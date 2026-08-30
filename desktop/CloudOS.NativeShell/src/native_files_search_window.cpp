#include "native_files_search_window.h"

#include "native_files_window.h"
#include "native_theme.h"

#include <CommCtrl.h>
#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <cwctype>
#include <new>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.NativeShell.FilesSearch.v5";
constexpr UINT kSearchCompleteMessage = WM_APP + 0x551;
constexpr int kListId = 15501;
constexpr int kOpenId = 15502;
constexpr int kLocationId = 15503;
constexpr int kCancelId = 15504;

void ApplyFont(HWND window, HFONT font)
{
    if (window != nullptr && font != nullptr)
        SendMessageW(window, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void InsertColumn(HWND list, int index, const wchar_t* title, int width)
{
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    column.iSubItem = index;
    column.cx = width;
    column.pszText = const_cast<LPWSTR>(title);
    ListView_InsertColumn(list, index, &column);
}
}

CloudOSNativeFilesSearchWindow::CloudOSNativeFilesSearchWindow(
    HINSTANCE instance, std::wstring root, std::wstring query) noexcept
    : instance_(instance), root_(std::move(root)), query_(std::move(query))
{
}

CloudOSNativeFilesSearchWindow::~CloudOSNativeFilesSearchWindow()
{
    cancel_requested_.store(true, std::memory_order_relaxed);
    JoinWorker();
    if (font_ != nullptr) DeleteObject(font_);
    if (title_font_ != nullptr) DeleteObject(title_font_);
    if (background_ != nullptr) DeleteObject(background_);
}

HWND CloudOSNativeFilesSearchWindow::Open(
    HINSTANCE instance,
    const std::wstring& root,
    const std::wstring& query,
    HWND owner)
{
    if (root.empty() || query.empty() || query.size() > MaximumQueryCharacters) return nullptr;
    auto* self = new (std::nothrow) CloudOSNativeFilesSearchWindow(instance, root, query);
    if (self == nullptr) return nullptr;
    if (!self->Create(owner))
    {
        delete self;
        return nullptr;
    }
    self->self_delete_ = true;
    return self->window_;
}

bool CloudOSNativeFilesSearchWindow::Create(HWND owner)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeFilesSearchWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Pesquisa - Arquivos CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT, CW_USEDEFAULT, 1040, 700,
        owner, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    const UINT dpi = GetDpiForWindow(window_);
    font_ = CreateFontW(
        -Scale(14, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(21, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    background_ = WebSkin::CreateBackgroundBrush();

    title_ = CreateWindowW(L"STATIC", L"Pesquisa de arquivos", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    std::wstring label = L"“" + query_ + L"” em " + root_;
    query_label_ = CreateWindowW(L"STATIC", label.c_str(), WS_CHILD | WS_VISIBLE | SS_LEFT | SS_ENDELLIPSIS,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)), instance_, nullptr);
    open_button_ = CreateWindowW(L"BUTTON", L"Abrir", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kOpenId)), instance_, nullptr);
    location_button_ = CreateWindowW(L"BUTTON", L"Abrir local", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kLocationId)), instance_, nullptr);
    cancel_button_ = CreateWindowW(L"BUTTON", L"Cancelar", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCancelId)), instance_, nullptr);
    status_ = CreateWindowW(L"STATIC", L"Preparando pesquisa…", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    if (title_ == nullptr || query_label_ == nullptr || list_ == nullptr || open_button_ == nullptr ||
        location_button_ == nullptr || cancel_button_ == nullptr || status_ == nullptr)
    {
        Destroy();
        return false;
    }

    ApplyFont(title_, title_font_);
    for (HWND control : {query_label_, list_, open_button_, location_button_, cancel_button_, status_})
        ApplyFont(control, font_);
    WebSkin::PrepareListView(list_);
    for (HWND button : {open_button_, location_button_, cancel_button_}) WebSkin::PrepareButton(button);
    ApplyWebWindowMaterial(window_);
    ListView_SetExtendedListViewStyle(list_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    InsertColumn(list_, 0, L"Nome", Scale(220, dpi));
    InsertColumn(list_, 1, L"Local", Scale(500, dpi));
    InsertColumn(list_, 2, L"Tamanho", Scale(100, dpi));
    InsertColumn(list_, 3, L"Modificado", Scale(150, dpi));

    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    StartSearch();
    return true;
}

void CloudOSNativeFilesSearchWindow::Destroy() noexcept
{
    cancel_requested_.store(true, std::memory_order_relaxed);
    JoinWorker();
    if (window_ != nullptr && IsWindow(window_)) DestroyWindow(window_);
    window_ = nullptr;
}

void CloudOSNativeFilesSearchWindow::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::max<LONG>(1, client.right - client.left);
    const int height = std::max<LONG>(1, client.bottom - client.top);
    const int margin = Scale(20, dpi);
    const int gap = Scale(10, dpi);
    const int button_width = Scale(108, dpi);
    const int button_height = Scale(38, dpi);

    MoveWindow(title_, margin, Scale(18, dpi), width - margin * 2, Scale(34, dpi), TRUE);
    MoveWindow(query_label_, margin, Scale(54, dpi), width - margin * 2, Scale(28, dpi), TRUE);
    MoveWindow(list_, margin, Scale(94, dpi), width - margin * 2,
        std::max(1, height - Scale(174, dpi)), TRUE);
    const int footer_y = height - margin - button_height;
    MoveWindow(status_, margin, footer_y + Scale(8, dpi),
        std::max(1, width - margin * 2 - (button_width + gap) * 3), Scale(28, dpi), TRUE);
    int x = width - margin - button_width * 3 - gap * 2;
    MoveWindow(open_button_, x, footer_y, button_width, button_height, TRUE);
    x += button_width + gap;
    MoveWindow(location_button_, x, footer_y, button_width, button_height, TRUE);
    x += button_width + gap;
    MoveWindow(cancel_button_, x, footer_y, button_width, button_height, TRUE);
}

void CloudOSNativeFilesSearchWindow::Paint(HDC dc)
{
    if (dc == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, background_);
}

void CloudOSNativeFilesSearchWindow::StartSearch()
{
    CancelSearch();
    JoinWorker();
    results_.clear();
    ListView_DeleteAllItems(list_);
    cancel_requested_.store(false, std::memory_order_relaxed);
    running_ = true;
    RefreshStatus();
    EnableWindow(cancel_button_, TRUE);
    const std::wstring root = root_;
    const std::wstring query = query_;
    worker_ = std::thread([this, root, query]() { WorkerMain(root, query); });
}

void CloudOSNativeFilesSearchWindow::CancelSearch() noexcept
{
    cancel_requested_.store(true, std::memory_order_relaxed);
}

void CloudOSNativeFilesSearchWindow::JoinWorker() noexcept
{
    if (worker_.joinable() && worker_.get_id() != std::this_thread::get_id()) worker_.join();
}

void CloudOSNativeFilesSearchWindow::WorkerMain(std::wstring root, std::wstring query)
{
    auto* completion = new (std::nothrow) SearchCompletion();
    if (completion == nullptr) return;
    const DWORD attributes = GetFileAttributesW(root.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        completion->error = L"A pasta raiz não existe ou não pode ser lida.";
    }
    else
    {
        SearchDirectory(root, Lower(std::move(query)), 0, completion);
    }
    completion->canceled = cancel_requested_.load(std::memory_order_relaxed);
    HWND target = window_;
    if (target == nullptr || !IsWindow(target) ||
        !PostMessageW(target, kSearchCompleteMessage, 0, reinterpret_cast<LPARAM>(completion)))
    {
        delete completion;
    }
}

void CloudOSNativeFilesSearchWindow::SearchDirectory(
    const std::wstring& directory,
    const std::wstring& lowered_query,
    std::size_t depth,
    SearchCompletion* completion)
{
    if (completion == nullptr || depth > MaximumDepth || cancel_requested_.load(std::memory_order_relaxed)) return;
    const std::wstring pattern = JoinPath(directory, L"*");
    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileExW(
        pattern.c_str(), FindExInfoBasic, &data, FindExSearchNameMatch, nullptr,
        FIND_FIRST_EX_LARGE_FETCH);
    if (find == INVALID_HANDLE_VALUE) return;

    do
    {
        if (cancel_requested_.load(std::memory_order_relaxed)) break;
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) continue;
        const bool directory_entry = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        const bool reparse = (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        const std::wstring full_path = JoinPath(directory, data.cFileName);
        if (Lower(data.cFileName).find(lowered_query) != std::wstring::npos)
        {
            Result result{};
            result.name = data.cFileName;
            result.path = full_path;
            result.directory = directory_entry;
            result.size = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32u) | data.nFileSizeLow;
            result.modified = data.ftLastWriteTime;
            completion->results.push_back(std::move(result));
            if (completion->results.size() >= MaximumResults)
            {
                completion->truncated = true;
                break;
            }
        }
        if (directory_entry && !reparse && depth < MaximumDepth &&
            completion->results.size() < MaximumResults)
        {
            SearchDirectory(full_path, lowered_query, depth + 1, completion);
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);
}

void CloudOSNativeFilesSearchWindow::ApplyCompletion(SearchCompletion* completion)
{
    running_ = false;
    EnableWindow(cancel_button_, FALSE);
    if (completion == nullptr)
    {
        RefreshStatus();
        return;
    }
    results_ = std::move(completion->results);
    const std::wstring error = std::move(completion->error);
    const bool canceled = completion->canceled;
    const bool truncated = completion->truncated;
    delete completion;

    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < results_.size(); ++index)
    {
        Result& result = results_[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = result.name.data();
        ListView_InsertItem(list_, &item);
        std::wstring location = ParentPath(result.path);
        std::wstring size = result.directory ? L"Pasta" : FormatBytes(result.size);
        std::wstring modified = FormatModified(result.modified);
        ListView_SetItemText(list_, static_cast<int>(index), 1, location.data());
        ListView_SetItemText(list_, static_cast<int>(index), 2, size.data());
        ListView_SetItemText(list_, static_cast<int>(index), 3, modified.data());
    }

    std::wstring status;
    if (!error.empty()) status = error;
    else if (canceled) status = L"Pesquisa cancelada · " + std::to_wstring(results_.size()) + L" resultados";
    else
    {
        status = std::to_wstring(results_.size()) + L" resultados";
        if (truncated) status += L" · limite de 500 atingido";
    }
    SetWindowTextW(status_, status.c_str());
}

void CloudOSNativeFilesSearchWindow::RefreshStatus()
{
    if (status_ == nullptr) return;
    if (running_) SetWindowTextW(status_, L"Pesquisando… Escaneamento limitado e cancelável.");
    else SetWindowTextW(status_, (std::to_wstring(results_.size()) + L" resultados").c_str());
}

void CloudOSNativeFilesSearchWindow::OpenSelected(bool parent_only)
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= results_.size()) return;
    const Result& result = results_[static_cast<std::size_t>(row)];
    if (parent_only)
    {
        CloudOSNativeFilesWindow::Open(instance_, ParentPath(result.path));
        return;
    }
    if (result.directory)
    {
        CloudOSNativeFilesWindow::Open(instance_, result.path);
        return;
    }
    (void)ShellExecuteW(window_, L"open", result.path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

std::wstring CloudOSNativeFilesSearchWindow::Lower(std::wstring value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t character)
    {
        return static_cast<wchar_t>(std::towlower(character));
    });
    return value;
}

std::wstring CloudOSNativeFilesSearchWindow::JoinPath(const std::wstring& left, const std::wstring& right)
{
    if (left.empty()) return right;
    if (left.back() == L'\\' || left.back() == L'/') return left + right;
    return left + L"\\" + right;
}

std::wstring CloudOSNativeFilesSearchWindow::ParentPath(const std::wstring& path)
{
    if (path.empty()) return {};
    std::wstring value = path;
    while (value.size() > 3 && (value.back() == L'\\' || value.back() == L'/')) value.pop_back();
    const std::size_t separator = value.find_last_of(L"\\/");
    if (separator == std::wstring::npos) return value;
    if (separator == 2 && value.size() > 2 && value[1] == L':') return value.substr(0, 3);
    return separator == 0 ? L"\\" : value.substr(0, separator);
}

std::wstring CloudOSNativeFilesSearchWindow::FormatBytes(ULONGLONG value)
{
    wchar_t buffer[64]{};
    if (value >= 1024ull * 1024ull * 1024ull)
        swprintf_s(buffer, L"%.2f GB", static_cast<double>(value) / (1024.0 * 1024.0 * 1024.0));
    else if (value >= 1024ull * 1024ull)
        swprintf_s(buffer, L"%.1f MB", static_cast<double>(value) / (1024.0 * 1024.0));
    else if (value >= 1024ull)
        swprintf_s(buffer, L"%.1f KB", static_cast<double>(value) / 1024.0);
    else
        swprintf_s(buffer, L"%llu B", static_cast<unsigned long long>(value));
    return buffer;
}

std::wstring CloudOSNativeFilesSearchWindow::FormatModified(const FILETIME& value)
{
    FILETIME local{};
    SYSTEMTIME time{};
    if (!FileTimeToLocalFileTime(&value, &local) || !FileTimeToSystemTime(&local, &time)) return {};
    wchar_t date[64]{};
    wchar_t clock[64]{};
    if (GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &time, nullptr,
            date, static_cast<int>(std::size(date)), nullptr) == 0) return {};
    if (GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &time, nullptr,
            clock, static_cast<int>(std::size(clock))) == 0) return date;
    return std::wstring(date) + L" " + clock;
}

LRESULT CloudOSNativeFilesSearchWindow::HandleMessage(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_GETMINMAXINFO:
    {
        auto* info = reinterpret_cast<MINMAXINFO*>(l_param);
        if (info != nullptr)
        {
            info->ptMinTrackSize.x = 760;
            info->ptMinTrackSize.y = 500;
        }
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kOpenId) { OpenSelected(false); return 0; }
        if (LOWORD(w_param) == kLocationId) { OpenSelected(true); return 0; }
        if (LOWORD(w_param) == kCancelId) { CancelSearch(); return 0; }
        break;
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK || header->code == NM_RETURN)
            {
                OpenSelected(false);
                return 0;
            }
        }
        break;
    }
    case kSearchCompleteMessage:
        JoinWorker();
        ApplyCompletion(reinterpret_cast<SearchCompletion*>(l_param));
        return 0;
    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        Paint(dc);
        EndPaint(window, &paint);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_CLOSE:
        DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        cancel_requested_.store(true, std::memory_order_relaxed);
        JoinWorker();
        return 0;
    case WM_NCDESTROY:
    {
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        window_ = nullptr;
        const bool remove_self = self_delete_;
        self_delete_ = false;
        if (remove_self) delete this;
        return DefWindowProcW(window, message, w_param, l_param);
    }
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeFilesSearchWindow::WindowProcedure(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeFilesSearchWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFilesSearchWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
