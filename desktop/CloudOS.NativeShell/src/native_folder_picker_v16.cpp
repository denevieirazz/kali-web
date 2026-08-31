#include "native_folder_picker_v16.h"

#include "native_integration_v16.h"
#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <filesystem>
#include <new>

#pragma comment(lib, "comctl32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.NativeShell.FolderPicker.v16";
constexpr int kAddressId = 16001;
constexpr int kGoId = 16002;
constexpr int kUpId = 16003;
constexpr int kDownloadsId = 16004;
constexpr int kDesktopId = 16005;
constexpr int kDocumentsId = 16006;
constexpr int kLinuxId = 16007;
constexpr int kListId = 16008;
constexpr int kSelectId = 16009;
constexpr int kCancelId = 16010;

bool DirectoryExists(const std::wstring& path)
{
    if (_wcsicmp(path.c_str(), NativeIntegrationV16::WslRoot().c_str()) == 0) return true;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

std::wstring ReadText(HWND control)
{
    const int length = GetWindowTextLengthW(control);
    if (length <= 0) return {};
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(control, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return value;
}

std::wstring ParentDirectory(const std::wstring& path)
{
    if (path.empty()) return {};
    const std::wstring wsl_root = NativeIntegrationV16::WslRoot();
    if (_wcsicmp(path.c_str(), wsl_root.c_str()) == 0) return path;

    std::filesystem::path value(path);
    const std::filesystem::path parent = value.parent_path();
    if (parent.empty()) return path;
    std::wstring result = parent.wstring();
    if (result.size() == 2u && result[1] == L':') result.push_back(L'\\');
    if (result.size() < wsl_root.size() && path.rfind(wsl_root, 0) == 0) return wsl_root;
    return result;
}

bool EnsureClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeFolderPickerV16::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = WebSkin::SharedBackgroundBrush();
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
} // namespace

CloudOSNativeFolderPickerV16::CloudOSNativeFolderPickerV16(
    HWND owner,
    std::wstring initial_directory)
    : owner_(owner),
      current_directory_(std::move(initial_directory))
{
}

CloudOSNativeFolderPickerV16::~CloudOSNativeFolderPickerV16()
{
    if (body_font_ != nullptr) DeleteObject(body_font_);
    if (title_font_ != nullptr) DeleteObject(title_font_);
}

bool CloudOSNativeFolderPickerV16::Pick(
    HWND owner,
    const std::wstring& initial_directory,
    std::wstring* selected_directory)
{
    if (selected_directory == nullptr) return false;
    selected_directory->clear();
    CloudOSNativeFolderPickerV16 picker(owner, initial_directory);
    if (!picker.Create()) return false;
    if (!picker.RunModal()) return false;
    *selected_directory = picker.selected_directory_;
    return true;
}

bool CloudOSNativeFolderPickerV16::Create()
{
    HINSTANCE instance = reinterpret_cast<HINSTANCE>(GetModuleHandleW(nullptr));
    if (!EnsureClass(instance)) return false;

    if (!DirectoryExists(current_directory_))
        current_directory_ = NativeIntegrationV16::DownloadsFolder();
    if (!DirectoryExists(current_directory_))
        current_directory_ = NativeIntegrationV16::DesktopFolder();
    if (!DirectoryExists(current_directory_))
    {
        wchar_t windows_directory[MAX_PATH]{};
        if (GetWindowsDirectoryW(windows_directory, static_cast<UINT>(std::size(windows_directory))) != 0)
            current_directory_ = windows_directory;
    }

    window_ = CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT,
        kClassName,
        L"Escolher pasta - CloudOS",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_SIZEBOX | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        820,
        610,
        owner_,
        nullptr,
        instance,
        this);
    if (window_ == nullptr) return false;

    address_edit_ = CreateWindowExW(
        0, L"EDIT", current_directory_.c_str(),
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kAddressId), instance, nullptr);
    go_button_ = CreateWindowExW(0, L"BUTTON", L"Ir",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kGoId), instance, nullptr);
    up_button_ = CreateWindowExW(0, L"BUTTON", L"Subir",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kUpId), instance, nullptr);
    downloads_button_ = CreateWindowExW(0, L"BUTTON", L"Downloads",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kDownloadsId), instance, nullptr);
    desktop_button_ = CreateWindowExW(0, L"BUTTON", L"Desktop",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kDesktopId), instance, nullptr);
    documents_button_ = CreateWindowExW(0, L"BUTTON", L"Documentos",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kDocumentsId), instance, nullptr);
    linux_button_ = CreateWindowExW(0, L"BUTTON", L"Linux / WSL",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kLinuxId), instance, nullptr);

    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kListId), instance, nullptr);
    select_button_ = CreateWindowExW(0, L"BUTTON", L"Selecionar esta pasta",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kSelectId), instance, nullptr);
    cancel_button_ = CreateWindowExW(0, L"BUTTON", L"Cancelar",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kCancelId), instance, nullptr);

    if (address_edit_ == nullptr || go_button_ == nullptr || up_button_ == nullptr ||
        downloads_button_ == nullptr || desktop_button_ == nullptr || documents_button_ == nullptr ||
        linux_button_ == nullptr || list_ == nullptr || select_button_ == nullptr || cancel_button_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    ListView_SetExtendedListViewStyle(list_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.cx = 260;
    column.pszText = const_cast<wchar_t*>(L"Pasta");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 480;
    column.pszText = const_cast<wchar_t*>(L"Caminho");
    ListView_InsertColumn(list_, 1, &column);

    ApplyWebWindowMaterial(window_);
    WebSkin::PrepareEdit(address_edit_);
    for (HWND button : {go_button_, up_button_, downloads_button_, desktop_button_, documents_button_,
             linux_button_, select_button_, cancel_button_})
        WebSkin::PrepareButton(button);

    ApplyFonts();
    Populate();
    Layout();
    return true;
}

void CloudOSNativeFolderPickerV16::ApplyFonts()
{
    const UINT dpi = GetDpiForWindow(window_);
    body_font_ = CreateFontW(
        -Scale(13, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(14, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    if (body_font_ == nullptr) return;
    for (HWND control : {address_edit_, go_button_, up_button_, downloads_button_, desktop_button_,
             documents_button_, linux_button_, list_, cancel_button_})
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(body_font_), TRUE);
    SendMessageW(select_button_, WM_SETFONT,
        reinterpret_cast<WPARAM>(title_font_ != nullptr ? title_font_ : body_font_), TRUE);
}

bool CloudOSNativeFolderPickerV16::RunModal()
{
    if (window_ == nullptr) return false;
    const bool owner_enabled = owner_ != nullptr && IsWindow(owner_) && IsWindowEnabled(owner_) != FALSE;
    if (owner_enabled) EnableWindow(owner_, FALSE);

    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetForegroundWindow(window_);

    MSG message{};
    while (window_ != nullptr && GetMessageW(&message, nullptr, 0, 0) > 0)
    {
        if (!IsDialogMessageW(window_, &message))
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }

    if (owner_enabled && owner_ != nullptr && IsWindow(owner_))
    {
        EnableWindow(owner_, TRUE);
        SetForegroundWindow(owner_);
    }
    return accepted_ && !selected_directory_.empty();
}

void CloudOSNativeFolderPickerV16::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(16, dpi);
    const int gap = Scale(8, dpi);
    const int row = Scale(34, dpi);
    const int shortcut_width = Scale(112, dpi);
    const int button_width = Scale(158, dpi);
    const int width = std::max(1, static_cast<int>(client.right - client.left));
    const int height = std::max(1, static_cast<int>(client.bottom - client.top));

    int x = margin;
    const int top = margin;
    const int up_width = Scale(70, dpi);
    MoveWindow(up_button_, x, top, up_width, row, TRUE);
    x += up_width + gap;
    const int go_width = Scale(52, dpi);
    const int address_width = std::max(120, width - x - go_width - margin - gap);
    MoveWindow(address_edit_, x, top, address_width, row, TRUE);
    x += address_width + gap;
    MoveWindow(go_button_, x, top, go_width, row, TRUE);

    x = margin;
    const int shortcut_top = top + row + gap;
    for (HWND button : {downloads_button_, desktop_button_, documents_button_, linux_button_})
    {
        MoveWindow(button, x, shortcut_top, shortcut_width, row, TRUE);
        x += shortcut_width + gap;
    }

    const int actions_height = row;
    const int actions_top = height - margin - actions_height;
    const int list_top = shortcut_top + row + gap;
    const int list_height = std::max(80, actions_top - gap - list_top);
    MoveWindow(list_, margin, list_top, std::max(100, width - margin * 2), list_height, TRUE);
    MoveWindow(cancel_button_, width - margin - Scale(100, dpi), actions_top, Scale(100, dpi), row, TRUE);
    MoveWindow(select_button_, width - margin - Scale(100, dpi) - gap - button_width,
        actions_top, button_width, row, TRUE);
}

void CloudOSNativeFolderPickerV16::Navigate(const std::wstring& directory)
{
    if (!DirectoryExists(directory))
    {
        MessageBoxW(window_, L"A pasta nao existe ou nao esta acessivel.", L"CloudOS", MB_OK | MB_ICONWARNING);
        return;
    }
    current_directory_ = directory;
    SetWindowTextW(address_edit_, current_directory_.c_str());
    Populate();
}

void CloudOSNativeFolderPickerV16::NavigateFromAddress()
{
    Navigate(ReadText(address_edit_));
}

void CloudOSNativeFolderPickerV16::NavigateSelected()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= visible_directories_.size()) return;
    Navigate(visible_directories_[static_cast<std::size_t>(row)]);
}

void CloudOSNativeFolderPickerV16::NavigateParent()
{
    const std::wstring parent = ParentDirectory(current_directory_);
    if (!parent.empty() && _wcsicmp(parent.c_str(), current_directory_.c_str()) != 0)
        Navigate(parent);
}

void CloudOSNativeFolderPickerV16::Accept()
{
    if (!DirectoryExists(current_directory_)) return;
    selected_directory_ = current_directory_;
    Close(true);
}

void CloudOSNativeFolderPickerV16::Close(bool accepted)
{
    accepted_ = accepted;
    if (window_ != nullptr) DestroyWindow(window_);
}

void CloudOSNativeFolderPickerV16::Populate()
{
    visible_directories_.clear();
    ListView_DeleteAllItems(list_);
    if (current_directory_.empty()) return;

    std::wstring pattern = current_directory_;
    if (!pattern.empty() && pattern.back() != L'\\' && pattern.back() != L'/') pattern += L'\\';
    pattern += L"*";

    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileExW(
        pattern.c_str(),
        FindExInfoBasic,
        &data,
        FindExSearchNameMatch,
        nullptr,
        FIND_FIRST_EX_LARGE_FETCH);
    if (find == INVALID_HANDLE_VALUE) return;

    do
    {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) continue;
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) continue;
        std::wstring full = current_directory_;
        if (!full.empty() && full.back() != L'\\' && full.back() != L'/') full += L'\\';
        full += data.cFileName;
        visible_directories_.push_back(std::move(full));
    }
    while (FindNextFileW(find, &data));
    FindClose(find);

    std::sort(visible_directories_.begin(), visible_directories_.end(), [](const std::wstring& left, const std::wstring& right)
    {
        return _wcsicmp(left.c_str(), right.c_str()) < 0;
    });

    for (std::size_t index = 0; index < visible_directories_.size(); ++index)
    {
        const std::filesystem::path path(visible_directories_[index]);
        std::wstring name = path.filename().wstring();
        if (name.empty()) name = visible_directories_[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = name.data();
        ListView_InsertItem(list_, &item);
        ListView_SetItemText(list_, static_cast<int>(index), 1, visible_directories_[index].data());
    }
}

LRESULT CloudOSNativeFolderPickerV16::HandleMessage(UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kAddressId && HIWORD(w_param) == EN_KILLFOCUS) return 0;
        if (HIWORD(w_param) == BN_CLICKED)
        {
            switch (LOWORD(w_param))
            {
            case kGoId: NavigateFromAddress(); return 0;
            case kUpId: NavigateParent(); return 0;
            case kDownloadsId: Navigate(NativeIntegrationV16::DownloadsFolder()); return 0;
            case kDesktopId: Navigate(NativeIntegrationV16::DesktopFolder()); return 0;
            case kDocumentsId: Navigate(NativeIntegrationV16::DocumentsFolder()); return 0;
            case kLinuxId: Navigate(NativeIntegrationV16::WslRoot()); return 0;
            case kSelectId: Accept(); return 0;
            case kCancelId: Close(false); return 0;
            default: break;
            }
        }
        break;
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_ && header->code == NM_DBLCLK)
        {
            NavigateSelected();
            return 0;
        }
        break;
    }
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE) { Close(false); return 0; }
        if (w_param == VK_RETURN)
        {
            if (GetFocus() == list_) NavigateSelected(); else NavigateFromAddress();
            return 0;
        }
        break;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr && draw->CtlType == ODT_BUTTON)
        {
            const ButtonTone tone = draw->CtlID == kSelectId ? ButtonTone::Accent : ButtonTone::Neutral;
            if (WebSkin::PaintOwnerDrawButton(draw, tone)) return TRUE;
        }
        break;
    }
    case WM_CLOSE:
        Close(false);
        return 0;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeFolderPickerV16::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeFolderPickerV16* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFolderPickerV16*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeFolderPickerV16*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }
    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
