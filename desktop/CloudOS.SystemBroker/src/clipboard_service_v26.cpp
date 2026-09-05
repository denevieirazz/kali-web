#include "clipboard_service_v26.h"
#include "event_bus_v21.h"

#include <shellapi.h>
#include <algorithm>

#include <chrono>
#include <iomanip>
#include <sstream>

namespace CloudOS
{

namespace
{

std::string WideToUtf8(const std::wstring& wide)
{
    if (wide.empty()) return {};
    const int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), nullptr, 0, nullptr, nullptr);
    if (len <= 0) return {};
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), out.data(), len, nullptr, nullptr);
    return out;
}

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return {};
    const int len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), nullptr, 0);
    if (len <= 0) return {};
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), out.data(), len);
    return out;
}

std::string CurrentIsoTime()
{
    SYSTEMTIME st{};
    GetLocalTime(&st);
    std::ostringstream oss;
    oss << std::setfill('0')
        << std::setw(4) << st.wYear << "-"
        << std::setw(2) << st.wMonth << "-"
        << std::setw(2) << st.wDay << "T"
        << std::setw(2) << st.wHour << ":"
        << std::setw(2) << st.wMinute << ":"
        << std::setw(2) << st.wSecond;
    return oss.str();
}

} // namespace

JsonObject ClipboardItemV26::ToJsonObject(bool include_full_text) const
{
    JsonObject obj;
    obj["id"] = JsonValue(static_cast<int64_t>(id));
    obj["timestamp"] = JsonValue(timestamp);
    obj["type"] = JsonValue(type);
    obj["preview"] = JsonValue(preview);
    if (include_full_text && !full_text.empty())
    {
        obj["full_text"] = JsonValue(full_text);
    }
    obj["data_bytes"] = JsonValue(static_cast<double>(data_bytes));
    if (type == "image")
    {
        obj["image_width"] = JsonValue(static_cast<double>(image_width));
        obj["image_height"] = JsonValue(static_cast<double>(image_height));
    }
    if (!files.empty())
    {
        JsonArray arr;
        for (const auto& f : files)
        {
            arr.push_back(JsonValue(f));
        }
        obj["files"] = JsonValue(std::move(arr));
    }
    return obj;
}

ClipboardServiceV26& ClipboardServiceV26::Instance()
{
    static ClipboardServiceV26 instance;
    return instance;
}

ClipboardServiceV26::ClipboardServiceV26()
{
    Start();
}

ClipboardServiceV26::~ClipboardServiceV26()
{
    Stop();
}

bool ClipboardServiceV26::Start()
{
    if (running_.exchange(true))
    {
        return true;
    }

    listener_thread_ = std::thread(&ClipboardServiceV26::ListenerThreadProc, this);
    return true;
}

void ClipboardServiceV26::Stop()
{
    if (!running_.exchange(false))
    {
        return;
    }

    if (listener_thread_id_ != 0)
    {
        PostThreadMessageW(listener_thread_id_, WM_QUIT, 0, 0);
    }

    if (listener_thread_.joinable())
    {
        listener_thread_.join();
    }
    listener_thread_id_ = 0;
    listener_hwnd_ = nullptr;
}

LRESULT CALLBACK ClipboardServiceV26::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_CLIPBOARDUPDATE)
    {
        Instance().CaptureCurrentClipboard();
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

void ClipboardServiceV26::ListenerThreadProc()
{
    listener_thread_id_ = GetCurrentThreadId();

    const wchar_t* kClassName = L"CloudOSClipboardListenerClass";
    WNDCLASSEXW wc{sizeof(WNDCLASSEXW)};
    wc.lpfnWndProc = ClipboardServiceV26::WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClassName;
    RegisterClassExW(&wc);

    listener_hwnd_ = CreateWindowExW(
        0,
        kClassName,
        L"CloudOSClipboardListenerWindow",
        0,
        0, 0, 0, 0,
        HWND_MESSAGE,
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr);

    if (!listener_hwnd_)
    {
        running_.store(false);
        return;
    }

    AddClipboardFormatListener(listener_hwnd_);

    MSG msg;
    while (running_.load() && GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (listener_hwnd_)
    {
        RemoveClipboardFormatListener(listener_hwnd_);
        DestroyWindow(listener_hwnd_);
        listener_hwnd_ = nullptr;
    }
    UnregisterClassW(kClassName, GetModuleHandleW(nullptr));
}

void ClipboardServiceV26::CaptureCurrentClipboard()
{
    // Try to open clipboard with retries
    bool opened = false;
    for (int i = 0; i < 5; ++i)
    {
        if (OpenClipboard(listener_hwnd_))
        {
            opened = true;
            break;
        }
        Sleep(10);
    }
    if (!opened) return;

    ClipboardItemV26 item;
    item.id = next_id_.fetch_add(1);
    item.timestamp = CurrentIsoTime();
    bool captured = false;

    if (IsClipboardFormatAvailable(CF_UNICODETEXT))
    {
        HANDLE hData = GetClipboardData(CF_UNICODETEXT);
        if (hData)
        {
            auto* pText = static_cast<const wchar_t*>(GlobalLock(hData));
            if (pText)
            {
                std::wstring ws(pText);
                GlobalUnlock(hData);

                if (!ws.empty())
                {
                    item.type = "text";
                    std::string u8 = WideToUtf8(ws);
                    item.data_bytes = u8.size();

                    if (u8.size() > kMaxItemTextLength)
                    {
                        u8.resize(kMaxItemTextLength);
                    }
                    item.full_text = u8;

                    std::string prev = u8.substr(0, std::min<size_t>(u8.size(), 120));
                    std::replace(prev.begin(), prev.end(), '\r', ' ');
                    std::replace(prev.begin(), prev.end(), '\n', ' ');
                    item.preview = std::move(prev);
                    captured = true;
                }
            }
        }
    }
    else if (IsClipboardFormatAvailable(CF_HDROP))
    {
        HANDLE hDrop = GetClipboardData(CF_HDROP);
        if (hDrop)
        {
            auto drop = reinterpret_cast<HDROP>(GlobalLock(hDrop));
            if (drop)
            {
                UINT fileCount = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
                std::vector<std::string> filesList;
                for (UINT i = 0; i < fileCount; ++i)
                {
                    WCHAR buf[MAX_PATH + 1] = {0};
                    if (DragQueryFileW(drop, i, buf, MAX_PATH) > 0)
                    {
                        filesList.push_back(WideToUtf8(buf));
                    }
                }
                GlobalUnlock(hDrop);

                if (!filesList.empty())
                {
                    item.type = "files";
                    item.files = filesList;
                    item.data_bytes = filesList.size();
                    item.preview = std::to_string(filesList.size()) + " arquivo(s) copiado(s): " + filesList[0];
                    captured = true;
                }
            }
        }
    }
    else if (IsClipboardFormatAvailable(CF_DIB))
    {
        HANDLE hDib = GetClipboardData(CF_DIB);
        if (hDib)
        {
            auto* pBmi = static_cast<const BITMAPINFOHEADER*>(GlobalLock(hDib));
            if (pBmi)
            {
                item.type = "image";
                item.image_width = static_cast<int>(pBmi->biWidth);
                item.image_height = static_cast<int>(std::abs(pBmi->biHeight));
                item.data_bytes = static_cast<size_t>(pBmi->biSizeImage);
                item.preview = "Imagem (" + std::to_string(item.image_width) + "x" + std::to_string(item.image_height) + ")";
                GlobalUnlock(hDib);
                captured = true;
            }
        }
    }

    CloseClipboard();

    if (captured)
    {
        JsonObject payload;
        payload["id"] = JsonValue(static_cast<int64_t>(item.id));
        payload["type"] = JsonValue(item.type);
        payload["preview"] = JsonValue(item.preview);

        {
            std::lock_guard<std::mutex> lock(mutex_);
            // Deduplicate if identical to top item
            if (!history_.empty() && history_.front().type == item.type && history_.front().preview == item.preview)
            {
                return;
            }
            history_.push_front(std::move(item));
            if (history_.size() > kMaxHistoryItems)
            {
                history_.pop_back();
            }
        }

        EventBusV21::Instance().Publish("clipboard.changed", payload);
    }
}

std::vector<ClipboardItemV26> ClipboardServiceV26::GetHistory(size_t limit) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<ClipboardItemV26> res;
    const size_t n = std::min(limit, history_.size());
    res.reserve(n);
    for (size_t i = 0; i < n; ++i)
    {
        res.push_back(history_[i]);
    }
    return res;
}

std::string ClipboardServiceV26::GetCurrentText() const
{
    std::string text;
    if (!OpenClipboard(nullptr)) return text;

    HANDLE hData = GetClipboardData(CF_UNICODETEXT);
    if (hData)
    {
        auto* pText = static_cast<const wchar_t*>(GlobalLock(hData));
        if (pText)
        {
            text = WideToUtf8(pText);
            GlobalUnlock(hData);
        }
    }
    CloseClipboard();
    return text;
}

bool ClipboardServiceV26::SetText(const std::string& text, std::string* error)
{
    std::wstring ws = Utf8ToWide(text);
    const size_t bytes = (ws.size() + 1) * sizeof(wchar_t);

    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!hMem)
    {
        if (error) *error = "GlobalAlloc failed";
        return false;
    }

    void* pMem = GlobalLock(hMem);
    if (!pMem)
    {
        GlobalFree(hMem);
        if (error) *error = "GlobalLock failed";
        return false;
    }
    memcpy(pMem, ws.c_str(), bytes);
    GlobalUnlock(hMem);

    if (!OpenClipboard(nullptr))
    {
        GlobalFree(hMem);
        if (error) *error = "OpenClipboard failed";
        return false;
    }

    EmptyClipboard();
    if (!SetClipboardData(CF_UNICODETEXT, hMem))
    {
        CloseClipboard();
        GlobalFree(hMem);
        if (error) *error = "SetClipboardData failed";
        return false;
    }

    CloseClipboard();
    return true;
}

bool ClipboardServiceV26::Clear(std::string* error)
{
    if (!OpenClipboard(nullptr))
    {
        if (error) *error = "OpenClipboard failed";
        return false;
    }
    EmptyClipboard();
    CloseClipboard();

    {
        std::lock_guard<std::mutex> lock(mutex_);
        history_.clear();
    }

    JsonObject payload;
    payload["cleared"] = JsonValue(true);
    EventBusV21::Instance().Publish("clipboard.changed", payload);
    return true;
}

} // namespace CloudOS
