#include "native_web_desktop_window.h"

#include "native_system_stats.h"
#include "native_theme.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cwchar>
#include <string_view>

namespace CloudOS
{
namespace
{
constexpr wchar_t kWebDesktopClass[] = L"CloudOS.NativeShell.WebDesktop.v1";

int FindAppIndex(std::wstring_view id)
{
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
    {
        if (id == kAllApps[index].id)
        {
            return static_cast<int>(index);
        }
    }
    return -1;
}

const wchar_t* JsonBool(bool value) noexcept
{
    return value ? L"true" : L"false";
}
}

CloudOSNativeWebDesktopWindow::~CloudOSNativeWebDesktopWindow()
{
    Destroy();
}

bool CloudOSNativeWebDesktopWindow::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    Destroy();
    instance_ = instance;
    window_manager_ = window_manager;

    const std::wstring ui_directory = NativeWebViewHost::DefaultContentDirectory();
    std::wstring runtime_version;
    if (ui_directory.empty() || !NativeWebViewHost::RuntimeAvailable(&runtime_version))
    {
        return false;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeWebDesktopWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    window_class.lpszClassName = kWebDesktopClass;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        kWebDesktopClass,
        L"CloudOS Native Web UI",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        0,
        0,
        0,
        0,
        nullptr,
        nullptr,
        instance_,
        this);
    if (hwnd_ == nullptr)
    {
        return false;
    }

    DarkWindow(hwnd_, false);

    const bool requested = web_host_.Create(
        hwnd_,
        ui_directory,
        [this](const std::wstring& message)
        {
            HandleWebMessage(message);
        },
        [this](bool success, const std::wstring& detail)
        {
            if (!success)
            {
                web_failure_detail_ = detail;
                if (hwnd_ != nullptr) InvalidateRect(hwnd_, nullptr, TRUE);
            }
            else
            {
                web_failure_detail_.clear();
                Redraw();
            }
        });

    if (!requested)
    {
        Destroy();
        return false;
    }
    return true;
}

void CloudOSNativeWebDesktopWindow::Destroy()
{
    web_host_.Destroy();
    if (hwnd_ != nullptr && IsWindow(hwnd_))
    {
        DestroyWindow(hwnd_);
    }
    hwnd_ = nullptr;
    instance_ = nullptr;
    window_manager_ = nullptr;
    web_failure_detail_.clear();
}

void CloudOSNativeWebDesktopWindow::UpdateLayout(const RECT& work_area)
{
    if (hwnd_ == nullptr)
    {
        return;
    }

    const int width = std::max(1, static_cast<int>(work_area.right - work_area.left));
    const int height = std::max(1, static_cast<int>(work_area.bottom - work_area.top));
    SetWindowPos(
        hwnd_,
        HWND_BOTTOM,
        work_area.left,
        work_area.top,
        width,
        height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    web_host_.Resize();
}

void CloudOSNativeWebDesktopWindow::Redraw()
{
    if (web_host_.Ready())
    {
        web_host_.PostJson(BuildStateJson());
    }
    else if (hwnd_ != nullptr)
    {
        InvalidateRect(hwnd_, nullptr, FALSE);
    }
}

void CloudOSNativeWebDesktopWindow::FocusSearch()
{
    if (hwnd_ == nullptr)
    {
        return;
    }
    (void)SetForegroundWindow(hwnd_);
    web_host_.PostJson(L"{\"type\":\"cloudos.event\",\"event\":\"focus-search\"}");
}

bool CloudOSNativeWebDesktopWindow::StartsWith(
    const std::wstring& value,
    const wchar_t* prefix) noexcept
{
    if (prefix == nullptr)
    {
        return false;
    }
    const std::size_t length = wcslen(prefix);
    return value.size() >= length && value.compare(0, length, prefix) == 0;
}

void CloudOSNativeWebDesktopWindow::HandleWebMessage(const std::wstring& message)
{
    if (message == L"ready" || message == L"state.request")
    {
        Redraw();
        return;
    }

    if (StartsWith(message, L"app.launch:"))
    {
        const std::wstring id = message.substr(wcslen(L"app.launch:"));
        const int index = FindAppIndex(id);
        if (index >= 0 && on_action_)
        {
            on_action_(index + 1);
        }
        return;
    }

    if (StartsWith(message, L"window.focus:") && window_manager_ != nullptr)
    {
        const wchar_t* value = message.c_str() + wcslen(L"window.focus:");
        wchar_t* end = nullptr;
        const unsigned long long raw = _wcstoui64(value, &end, 10);
        if (end != value && *end == L'\0' && raw != 0)
        {
            window_manager_->FocusWindow(
                reinterpret_cast<HWND>(static_cast<std::uintptr_t>(raw)));
            Redraw();
        }
        return;
    }

    if (StartsWith(message, L"workspace.switch:"))
    {
        const int workspace = _wtoi(message.c_str() + wcslen(L"workspace.switch:"));
        if (workspace >= 1 && workspace <= 4 && on_hotkey_)
        {
            on_hotkey_(HotWorkspace1 + workspace - 1);
        }
        return;
    }

    if (message == L"tiling.toggle")
    {
        if (on_hotkey_) on_hotkey_(HotTiling);
        return;
    }
    if (message == L"window.minimize")
    {
        if (on_hotkey_) on_hotkey_(HotMinimize);
        return;
    }
    if (message == L"window.maximize")
    {
        if (on_hotkey_) on_hotkey_(HotMaximize);
        return;
    }
    if (message == L"window.close")
    {
        if (on_hotkey_) on_hotkey_(HotClose);
        return;
    }
    if (message == L"window.next")
    {
        if (on_hotkey_) on_hotkey_(HotFocusNext);
        return;
    }
    if (message == L"window.snap:left")
    {
        if (on_hotkey_) on_hotkey_(HotSnapLeft);
        return;
    }
    if (message == L"window.snap:right")
    {
        if (on_hotkey_) on_hotkey_(HotSnapRight);
        return;
    }
    if (message == L"shell.exit")
    {
        PostQuitMessage(0);
    }
}

std::wstring CloudOSNativeWebDesktopWindow::JsonEscape(const std::wstring& value)
{
    std::wstring result;
    result.reserve(value.size() + 16);
    constexpr wchar_t digits[] = L"0123456789abcdef";
    for (const wchar_t character : value)
    {
        switch (character)
        {
        case L'\\': result += L"\\\\"; break;
        case L'\"': result += L"\\\""; break;
        case L'\b': result += L"\\b"; break;
        case L'\f': result += L"\\f"; break;
        case L'\n': result += L"\\n"; break;
        case L'\r': result += L"\\r"; break;
        case L'\t': result += L"\\t"; break;
        default:
            if (character < 0x20)
            {
                result += L"\\u00";
                result.push_back(digits[(character >> 4) & 0x0f]);
                result.push_back(digits[character & 0x0f]);
            }
            else
            {
                result.push_back(character);
            }
            break;
        }
    }
    return result;
}

std::wstring CloudOSNativeWebDesktopWindow::BuildStateJson() const
{
    const int workspace = window_manager_ != nullptr
        ? window_manager_->CurrentWorkspace() + 1
        : 1;
    const bool tiling = window_manager_ != nullptr && window_manager_->TilingEnabled();
    const HWND active = window_manager_ != nullptr
        ? window_manager_->ActiveManagedWindow()
        : nullptr;
    const SystemStats stats = NativeSystemStats::Query();

    std::wstring json =
        L"{\"type\":\"cloudos.state\",\"native\":true,\"workspace\":" +
        std::to_wstring(workspace) +
        L",\"tiling\":" + JsonBool(tiling) +
        L",\"managedWindowCount\":" +
        std::to_wstring(window_manager_ != nullptr ? window_manager_->ManagedWindowCount() : 0) +
        L",\"stats\":{";

    json += L"\"cpuAvailable\":";
    json += JsonBool(stats.cpu_available);
    json += L",\"cpuPercent\":" + std::to_wstring(stats.cpu_percent);
    json += L",\"ramAvailable\":";
    json += JsonBool(stats.ram_available);
    json += L",\"ramPercent\":" + std::to_wstring(stats.ram_percent);
    json += L",\"ramUsedMb\":" + std::to_wstring(stats.ram_used_mb);
    json += L",\"ramTotalMb\":" + std::to_wstring(stats.ram_total_mb);
    json += L",\"diskAvailable\":";
    json += JsonBool(stats.disk_available);
    json += L",\"diskFreeGb\":" + std::to_wstring(stats.disk_free_gb);
    json += L",\"diskTotalGb\":" + std::to_wstring(stats.disk_total_gb);
    json += L",\"uptime\":\"" + JsonEscape(stats.uptime_str) + L"\"}";

    json += L",\"apps\":[";
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
    {
        if (index != 0) json += L",";
        const AppItem& app = kAllApps[index];
        json += L"{\"id\":\"" + JsonEscape(app.id) +
            L"\",\"name\":\"" + JsonEscape(app.name) +
            L"\",\"description\":\"" + JsonEscape(app.desc) +
            L"\",\"category\":" +
            std::to_wstring(static_cast<int>(app.category)) + L"}";
    }
    json += L"]";

    json += L",\"windows\":[";
    if (window_manager_ != nullptr)
    {
        const auto windows = window_manager_->CurrentWorkspaceWindows();
        for (std::size_t index = 0; index < windows.size(); ++index)
        {
            if (index != 0) json += L",";
            const CloudOSManagedWindow& item = windows[index];
            const auto raw_hwnd = static_cast<unsigned long long>(
                reinterpret_cast<std::uintptr_t>(item.hwnd));
            json += L"{\"hwnd\":\"" + std::to_wstring(raw_hwnd) +
                L"\",\"pid\":" + std::to_wstring(item.process_id) +
                L",\"title\":\"" + JsonEscape(item.title) +
                L"\",\"floating\":" + JsonBool(item.floating) +
                L",\"active\":" + JsonBool(item.hwnd == active) + L"}";
        }
    }
    json += L"]}";
    return json;
}

LRESULT CloudOSNativeWebDesktopWindow::HandleMessage(
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        web_host_.Resize();
        return 0;

    case WM_HOTKEY:
        if (on_hotkey_)
        {
            on_hotkey_(static_cast<int>(w_param));
        }
        Redraw();
        return 0;

    case WM_TIMER:
        if ((w_param == kReconcileTimer || w_param == kMetricsTimer) && on_timer_)
        {
            on_timer_();
        }
        Redraw();
        return 0;

    case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
        if (window_manager_ != nullptr)
        {
            window_manager_->HandleRuntimeEvent(
                static_cast<cloudos_native_window_event_kind>(w_param),
                reinterpret_cast<HWND>(l_param));
        }
        Redraw();
        return 0;

    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
        if (on_timer_)
        {
            on_timer_();
        }
        Redraw();
        return 0;

    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(hwnd_, &client);
        FillRect(
            reinterpret_cast<HDC>(w_param),
            &client,
            reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
        return 1;
    }

    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(hwnd_, &paint);
        RECT client{};
        GetClientRect(hwnd_, &client);
        FillRect(dc, &client, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
        if (!web_failure_detail_.empty())
        {
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, RGB(235, 238, 245));
            RECT text = client;
            text.left += 48;
            text.right -= 48;
            DrawTextW(
                dc,
                web_failure_detail_.c_str(),
                -1,
                &text,
                DT_CENTER | DT_VCENTER | DT_WORDBREAK | DT_NOPREFIX);
        }
        EndPaint(hwnd_, &paint);
        return 0;
    }

    case WM_CLOSE:
        PostQuitMessage(0);
        return 0;

    case WM_NCDESTROY:
    {
        const HWND destroyed = hwnd_;
        if (destroyed != nullptr)
        {
            SetWindowLongPtrW(destroyed, GWLP_USERDATA, 0);
        }
        hwnd_ = nullptr;
        return DefWindowProcW(destroyed, message, w_param, l_param);
    }

    default:
        break;
    }
    return DefWindowProcW(hwnd_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeWebDesktopWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeWebDesktopWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeWebDesktopWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->hwnd_ = window;
            SetWindowLongPtrW(
                window,
                GWLP_USERDATA,
                reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeWebDesktopWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    if (self == nullptr)
    {
        return DefWindowProcW(window, message, w_param, l_param);
    }
    return self->HandleMessage(message, w_param, l_param);
}
} // namespace CloudOS
