#include "native_files_window.h"
#include "native_files_internal.h"

#include "native_cloudos_drive.h"
#include "native_cloudos_trash_window.h"
#include "native_shell_platform.h"
#include "native_theme.h"

#include <ShlObj.h>
#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <new>
#include <string_view>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

int CloudOSNativeFilesWindow::ShellIconIndex(const std::wstring& path, bool directory, bool use_attributes) const
{
    SHFILEINFOW info{};
    UINT flags = SHGFI_SYSICONINDEX | SHGFI_LARGEICON;
    if (use_attributes) flags |= SHGFI_USEFILEATTRIBUTES;
    const DWORD attributes = directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    return SHGetFileInfoW(path.c_str(), attributes, &info, sizeof(info), flags) == 0 ? -1 : info.iIcon;
}

int CloudOSNativeFilesWindow::StockIconIndex(SHSTOCKICONID icon_id) const
{
    SHSTOCKICONINFO info{};
    info.cbSize = sizeof(info);
    return SUCCEEDED(SHGetStockIconInfo(icon_id, SHGSI_SYSICONINDEX | SHGSI_SMALLICON, &info)) ? info.iSysImageIndex : -1;
}

std::wstring CloudOSNativeFilesWindow::KnownFolderPath(REFKNOWNFOLDERID folder_id)
{
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &value)) || value == nullptr) return {};
    std::wstring result(value);
    CoTaskMemFree(value);
    return result;
}

std::wstring CloudOSNativeFilesWindow::JoinPath(const std::wstring& directory, const std::wstring& name)
{
    if (directory.empty()) return name;
    return (directory.back() == L'\\' || directory.back() == L'/') ? directory + name : directory + L"\\" + name;
}

std::wstring CloudOSNativeFilesWindow::ParentPath(const std::wstring& path)
{
    if (IsRootPath(path)) return path;
    std::wstring value = path;
    while (value.size() > 3 && (value.back() == L'\\' || value.back() == L'/')) value.pop_back();
    const std::size_t pos = value.find_last_of(L"\\/");
    if (pos == std::wstring::npos) return value;
    if (pos == 2 && value.size() > 2 && value[1] == L':') return value.substr(0, 3);
    return pos == 0 ? L"\\" : value.substr(0, pos);
}

std::wstring CloudOSNativeFilesWindow::ReadEditText(HWND edit)
{
    const int length = GetWindowTextLengthW(edit);
    if (length <= 0) return {};
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    GetWindowTextW(edit, text.data(), length + 1);
    text.resize(static_cast<std::size_t>(length));
    return text;
}

std::wstring CloudOSNativeFilesWindow::FormatSize(ULONGLONG size)
{
    wchar_t buffer[64]{};
    if (size >= 1024ull * 1024ull * 1024ull) swprintf_s(buffer, L"%.2f GB", static_cast<double>(size) / (1024.0 * 1024.0 * 1024.0));
    else if (size >= 1024ull * 1024ull) swprintf_s(buffer, L"%.1f MB", static_cast<double>(size) / (1024.0 * 1024.0));
    else if (size >= 1024ull) swprintf_s(buffer, L"%.1f KB", static_cast<double>(size) / 1024.0);
    else swprintf_s(buffer, L"%llu B", static_cast<unsigned long long>(size));
    return buffer;
}

std::wstring CloudOSNativeFilesWindow::FormatModified(const FILETIME& value)
{
    if (value.dwLowDateTime == 0 && value.dwHighDateTime == 0) return {};
    FILETIME local{};
    SYSTEMTIME system{};
    if (!FileTimeToLocalFileTime(&value, &local) || !FileTimeToSystemTime(&local, &system)) return {};
    wchar_t date[64]{};
    wchar_t time[64]{};
    if (GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &system, nullptr, date, static_cast<int>(std::size(date)), nullptr) == 0) return {};
    if (GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &system, nullptr, time, static_cast<int>(std::size(time))) == 0) return date;
    return std::wstring(date) + L" " + time;
}

bool CloudOSNativeFilesWindow::IsWslRootPath(const std::wstring& path)
{
    return _wcsicmp(path.c_str(), L"\\\\wsl.localhost") == 0 || _wcsicmp(path.c_str(), L"\\\\wsl.localhost\\") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl$") == 0 || _wcsicmp(path.c_str(), L"\\\\wsl$\\") == 0;
}

bool CloudOSNativeFilesWindow::IsRootPath(const std::wstring& path)
{
    return (path.size() == 3 && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) || IsWslRootPath(path);
}

bool CloudOSNativeFilesWindow::IsSafeLeafName(const wchar_t* text)
{
    if (text == nullptr || *text == L'\0') return false;
    const std::wstring_view name(text);
    return name != L"." && name != L".." && name.size() <= 255 && name.find_first_of(L"\\/:*?\"<>|") == std::wstring_view::npos;
}

LRESULT CloudOSNativeFilesWindow::DrawOwnerButton(const DRAWITEMSTRUCT& item)
{
    if (item.hDC == nullptr) return FALSE;
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool focused = (item.itemState & ODS_FOCUS) != 0;
    HBRUSH brush = CreateSolidBrush(pressed ? kHot : kSurface);
    HPEN pen = CreatePen(PS_SOLID, focused ? 2 : 1, focused ? kAccent : kBorder);
    HGDIOBJ old_brush = SelectObject(item.hDC, brush);
    HGDIOBJ old_pen = SelectObject(item.hDC, pen);
    const int radius = CloudOS::Scale(7, dpi_);
    RoundRect(item.hDC, item.rcItem.left, item.rcItem.top, item.rcItem.right, item.rcItem.bottom, radius, radius);
    SelectObject(item.hDC, old_pen);
    SelectObject(item.hDC, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);

    wchar_t text[128]{};
    GetWindowTextW(item.hwndItem, text, static_cast<int>(std::size(text)));
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, kText);
    HGDIOBJ old_font = ui_font_ != nullptr ? SelectObject(item.hDC, ui_font_) : nullptr;
    RECT rect = item.rcItem;
    DrawTextW(item.hDC, text, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(item.hDC, old_font);
    return TRUE;
}

LRESULT CloudOSNativeFilesWindow::HandleMessage(UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_GETMINMAXINFO:
    {
        auto* info = reinterpret_cast<MINMAXINFO*>(l_param);
        if (info != nullptr)
        {
            info->ptMinTrackSize.x = CloudOS::Scale(900, dpi_);
            info->ptMinTrackSize.y = CloudOS::Scale(560, dpi_);
        }
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
    case WM_DPICHANGED:
    {
        const UINT new_dpi = HIWORD(w_param);
        if (new_dpi != 0 && new_dpi != dpi_)
        {
            dpi_ = new_dpi;
            if (ui_font_ != nullptr) DeleteObject(ui_font_);
            ui_font_ = CreateFontW(
                -CloudOS::Scale(14, dpi_), 0, 0, 0, FW_NORMAL,
                FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            const std::array<HWND, 12> controls{
                sidebar_, back_button_, forward_button_, up_button_, path_edit_, go_button_,
                refresh_button_, new_folder_button_, rename_button_, delete_button_, list_, status_};
            for (HWND control : controls)
            {
                if (control != nullptr && ui_font_ != nullptr)
                {
                    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(ui_font_), TRUE);
                }
            }
        }
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        if (suggested != nullptr)
        {
            SetWindowPos(
                window_, nullptr,
                suggested->left, suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOZORDER | SWP_NOACTIVATE);
        }
        ListView_SetIconSpacing(
            list_,
            CloudOS::Scale(136, dpi_),
            CloudOS::Scale(98, dpi_));
        Layout();
        return 0;
    }
    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kBackId: NavigateBack(); return 0;
        case kForwardId: NavigateForward(); return 0;
        case kUpId: NavigateParent(); return 0;
        case kGoId: Navigate(ReadEditText(path_edit_)); return 0;
        case kRefreshId: Refresh(); return 0;
        case kNewFolderId: CreateNewFolder(); return 0;
        case kRenameId: BeginRename(); return 0;
        case kDeleteId: DeleteSelection(); return 0;
        default: break;
        }
        break;
    case WM_NOTIFY:
    {
        auto* header = reinterpret_cast<NMHDR*>(l_param);
        if (header == nullptr) break;
        if (header->hwndFrom == sidebar_ && header->code == LVN_ITEMCHANGED)
        {
            const auto* changed = reinterpret_cast<const NMLISTVIEW*>(l_param);
            if ((changed->uNewState & LVIS_SELECTED) != 0 && (changed->uOldState & LVIS_SELECTED) == 0)
            {
                ActivateSidebarSelection();
            }
            return 0;
        }
        if (header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK) { ActivateCustomSelection(); return 0; }
            if (header->code == LVN_ENDLABELEDITW)
            {
                auto* edit = reinterpret_cast<NMLVDISPINFOW*>(l_param);
                return edit != nullptr && CommitRename(edit->item.iItem, edit->item.pszText) ? TRUE : FALSE;
            }
            if (header->code == LVN_KEYDOWN)
            {
                const auto* key = reinterpret_cast<const NMLVKEYDOWN*>(l_param);
                if (key->wVKey == VK_F5) { Refresh(); return 0; }
                if (key->wVKey == VK_F2) { BeginRename(); return 0; }
                if (key->wVKey == VK_DELETE) { DeleteSelection(); return 0; }
                if (key->wVKey == VK_RETURN) { ActivateCustomSelection(); return 0; }
                if (key->wVKey == VK_BACK) { NavigateParent(); return 0; }
            }
        }
        break;
    }
    case WM_DRAWITEM:
        if (l_param != 0 && reinterpret_cast<const DRAWITEMSTRUCT*>(l_param)->CtlType == ODT_BUTTON)
        {
            return DrawOwnerButton(*reinterpret_cast<const DRAWITEMSTRUCT*>(l_param));
        }
        break;
    case WM_CTLCOLOREDIT:
        SetTextColor(reinterpret_cast<HDC>(w_param), kText);
        SetBkColor(reinterpret_cast<HDC>(w_param), kSurface);
        return reinterpret_cast<LRESULT>(surface_brush_);
    case WM_CTLCOLORSTATIC:
        SetTextColor(reinterpret_cast<HDC>(w_param), kMuted);
        SetBkMode(reinterpret_cast<HDC>(w_param), TRANSPARENT);
        return reinterpret_cast<LRESULT>(background_brush_);
    case WM_ERASEBKGND:
        if (background_brush_ != nullptr)
        {
            RECT client{};
            GetClientRect(window_, &client);
            FillRect(reinterpret_cast<HDC>(w_param), &client, background_brush_);
            return 1;
        }
        break;
    case WM_PAINT:
    {
        PAINTSTRUCT ps{};
        HDC dc = BeginPaint(window_, &ps);
        if (dc != nullptr && background_brush_ != nullptr)
        {
            RECT client{};
            GetClientRect(window_, &client);
            FillRect(dc, &client, background_brush_);
            RECT divider{CloudOS::Scale(225, dpi_), 0, CloudOS::Scale(225, dpi_) + 1, client.bottom};
            HBRUSH line = CreateSolidBrush(kBorder);
            FillRect(dc, &divider, line);
            DeleteObject(line);
        }
        EndPaint(window_, &ps);
        return 0;
    }
    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;
    case WM_DESTROY:
        shell_view_.Destroy();
        return 0;
    case WM_NCDESTROY:
    {
        const HWND hwnd = window_;
        const LRESULT result = DefWindowProcW(hwnd, message, w_param, l_param);
        if (hwnd != nullptr) SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        window_ = nullptr;
        DestroyUiResources();
        const bool delete_self = destroy_deletes_self_;
        destroy_deletes_self_ = false;
        if (delete_self)
        {
            delete this;
        }
        return result;
    }
    default:
        break;
    }
    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeFilesWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    CloudOSNativeFilesWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFilesWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeFilesWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }
    return self != nullptr ? self->HandleMessage(message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
}
