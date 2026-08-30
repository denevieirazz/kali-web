#include "native_files_window.h"
#include "native_files_internal.h"

#include "native_cloudos_drive.h"
#include "native_files_style.h"
#include "native_theme.h"

#include <ShlObj.h>
#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <string_view>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

int CloudOSNativeFilesWindow::ShellIconIndex(
    const std::wstring& path,
    bool directory,
    bool use_attributes) const
{
    SHFILEINFOW info{};
    UINT flags = SHGFI_SYSICONINDEX | SHGFI_LARGEICON;
    if (use_attributes) flags |= SHGFI_USEFILEATTRIBUTES;
    const DWORD attributes = directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    return SHGetFileInfoW(path.c_str(), attributes, &info, sizeof(info), flags) == 0
        ? -1
        : info.iIcon;
}

int CloudOSNativeFilesWindow::AddSidebarIcon(
    const std::wstring& path,
    SHSTOCKICONID fallback_icon)
{
    if (sidebar_image_list_ == nullptr) return -1;
    HICON icon = nullptr;
    if (!path.empty() && !IsWslRootPath(path))
    {
        SHFILEINFOW info{};
        if (SHGetFileInfoW(path.c_str(), 0, &info, sizeof(info), SHGFI_ICON | SHGFI_SMALLICON) != 0)
            icon = info.hIcon;
    }
    if (icon == nullptr)
    {
        SHSTOCKICONINFO info{};
        info.cbSize = sizeof(info);
        if (SUCCEEDED(SHGetStockIconInfo(fallback_icon, SHGSI_ICON | SHGSI_SMALLICON, &info)))
            icon = info.hIcon;
    }
    if (icon == nullptr) return -1;
    const int index = ImageList_AddIcon(sidebar_image_list_, icon);
    DestroyIcon(icon);
    return index;
}

std::wstring CloudOSNativeFilesWindow::KnownFolderPath(REFKNOWNFOLDERID folder_id)
{
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &value)) || value == nullptr)
        return {};
    std::wstring result(value);
    CoTaskMemFree(value);
    return result;
}

std::wstring CloudOSNativeFilesWindow::JoinPath(
    const std::wstring& directory,
    const std::wstring& name)
{
    if (directory.empty()) return name;
    return (directory.back() == L'\\' || directory.back() == L'/')
        ? directory + name
        : directory + L"\\" + name;
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
    if (size >= 1024ull * 1024ull * 1024ull)
        swprintf_s(buffer, L"%.2f GB", static_cast<double>(size) / (1024.0 * 1024.0 * 1024.0));
    else if (size >= 1024ull * 1024ull)
        swprintf_s(buffer, L"%.1f MB", static_cast<double>(size) / (1024.0 * 1024.0));
    else if (size >= 1024ull)
        swprintf_s(buffer, L"%.1f KB", static_cast<double>(size) / 1024.0);
    else
        swprintf_s(buffer, L"%llu B", static_cast<unsigned long long>(size));
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
    if (GetDateFormatEx(
            LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &system, nullptr,
            date, static_cast<int>(std::size(date)), nullptr) == 0)
        return {};
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &system, nullptr,
            time, static_cast<int>(std::size(time))) == 0)
        return date;
    return std::wstring(date) + L" " + time;
}

std::wstring CloudOSNativeFilesWindow::LeafName(const std::wstring& path)
{
    if (path.empty()) return {};
    std::wstring value = path;
    while (value.size() > 3 && (value.back() == L'\\' || value.back() == L'/')) value.pop_back();
    const std::size_t separator = value.find_last_of(L"\\/");
    if (separator == std::wstring::npos || separator + 1 >= value.size()) return value;
    return value.substr(separator + 1);
}

bool CloudOSNativeFilesWindow::PathsEqual(
    const std::wstring& left,
    const std::wstring& right) noexcept
{
    return left.size() == right.size() && _wcsicmp(left.c_str(), right.c_str()) == 0;
}

bool CloudOSNativeFilesWindow::IsWslRootPath(const std::wstring& path)
{
    return _wcsicmp(path.c_str(), L"\\\\wsl.localhost") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl.localhost\\") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl$") == 0 ||
        _wcsicmp(path.c_str(), L"\\\\wsl$\\") == 0;
}

bool CloudOSNativeFilesWindow::IsRootPath(const std::wstring& path)
{
    return (path.size() == 3 && path[1] == L':' &&
            (path[2] == L'\\' || path[2] == L'/')) ||
        IsWslRootPath(path);
}

bool CloudOSNativeFilesWindow::IsSafeLeafName(const wchar_t* text)
{
    if (text == nullptr || *text == L'\0') return false;
    const std::wstring_view name(text);
    return name != L"." && name != L".." && name.size() <= 255 &&
        name.find_first_of(L"\\/:*?\"<>|") == std::wstring_view::npos;
}

void CloudOSNativeFilesWindow::ShowContentContextMenu(POINT screen_point)
{
    // IExplorerBrowser owns the standard Shell view context menu while in Shell
    // mode. For the V5 fallback filesystem view, however, CloudOS owns the
    // list HWND, so route real filesystem selections through IContextMenu3 and
    // preserve installed Shell extensions (7-Zip, Git, VS Code, Properties,
    // Share, Open With, etc.). CloudOS Drive deliberately keeps its safer
    // first-party menu because its virtual paths are not Windows Shell items.
    if (content_mode_ == ContentMode::Shell) return;

    const auto selected = SelectedPaths();
    if (content_mode_ == ContentMode::FallbackFileSystem && !selected.empty())
    {
        if (CloudOS::NativeShellContextMenuV7::Show(window_, selected, screen_point))
        {
            Refresh();
            return;
        }
    }

    enum : UINT
    {
        kOpen = 1,
        kRename = 2,
        kDelete = 3,
        kOperations = 4,
        kFavorite = 5,
        kRefresh = 6,
    };

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr) return;
    const bool has_selection = !selected.empty();
    AppendMenuW(menu, MF_STRING | (has_selection ? 0 : MF_GRAYED), kOpen, L"Abrir");
    AppendMenuW(menu, MF_STRING | (has_selection ? 0 : MF_GRAYED), kRename, L"Renomear");
    AppendMenuW(menu, MF_STRING | (has_selection ? 0 : MF_GRAYED), kDelete, L"Excluir");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kOperations, L"Copiar / mover / ZIP / extrair…");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    const bool favorite = CloudOS::NativeFilesStateStore::ContainsFavorite(persisted_state_, current_path_);
    AppendMenuW(menu, MF_STRING, kFavorite,
        favorite ? L"Remover do Quick Access" : L"Adicionar ao Quick Access");
    AppendMenuW(menu, MF_STRING, kRefresh, L"Atualizar");

    SetForegroundWindow(window_);
    const UINT command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_LEFTALIGN,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case kOpen: ActivateCustomSelection(); break;
    case kRename: BeginRename(); break;
    case kDelete: DeleteSelection(); break;
    case kOperations: OpenOperations(); break;
    case kFavorite: ToggleFavorite(); break;
    case kRefresh: Refresh(); break;
    default: break;
    }
}

LRESULT CloudOSNativeFilesWindow::DrawOwnerButton(const DRAWITEMSTRUCT& item)
{
    if (item.hDC == nullptr) return FALSE;
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool focused = (item.itemState & ODS_FOCUS) != 0;
    const bool hot = (item.itemState & ODS_HOTLIGHT) != 0;
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool primary = item.hwndItem == new_folder_button_;
    const bool danger = item.hwndItem == delete_button_;
    const bool glyph =
        item.hwndItem == back_button_ || item.hwndItem == forward_button_ ||
        item.hwndItem == up_button_ || item.hwndItem == refresh_button_ ||
        item.hwndItem == favorite_button_ || item.hwndItem == new_tab_button_ ||
        item.hwndItem == close_tab_button_;

    COLORREF fill = primary ? kAccent : kButton;
    COLORREF border = primary ? kAccent : kButton;
    COLORREF text_color = primary ? RGB(255, 255, 255) : kText;
    if (disabled)
    {
        fill = kButton;
        border = kButton;
        text_color = kMuted;
    }
    else if (primary && pressed)
    {
        fill = kAccentPressed;
        border = kAccentPressed;
    }
    else if (!primary && pressed)
    {
        fill = kPressed;
        border = kPressed;
    }
    else if (!primary && hot)
    {
        fill = kHot;
        border = kHot;
    }
    if (danger && !disabled) text_color = kDanger;
    if (focused && !primary) border = kAccent;

    CloudOS::FilesStyle::PaintRoundedSurface(
        item.hDC, item.rcItem, fill, border, CloudOS::Scale(9, dpi_), focused ? 1 : 0);
    wchar_t text[128]{};
    GetWindowTextW(item.hwndItem, text, static_cast<int>(std::size(text)));
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, text_color);
    HFONT font = glyph && glyph_font_ != nullptr ? glyph_font_ : ui_font_;
    HGDIOBJ old_font = font != nullptr ? SelectObject(item.hDC, font) : nullptr;
    RECT rect = item.rcItem;
    DrawTextW(item.hDC, text, -1, &rect,
        DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(item.hDC, old_font);
    return TRUE;
}

LRESULT CloudOSNativeFilesWindow::CustomDrawSidebar(const NMLVCUSTOMDRAW& draw)
{
    if (draw.nmcd.dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
    if (draw.nmcd.dwDrawStage != CDDS_ITEMPREPAINT) return CDRF_DODEFAULT;
    const int row = static_cast<int>(draw.nmcd.dwItemSpec);
    if (row < 0 || static_cast<std::size_t>(row) >= sidebar_items_.size()) return CDRF_DODEFAULT;

    RECT bounds{};
    if (!ListView_GetItemRect(sidebar_, row, &bounds, LVIR_BOUNDS)) return CDRF_DODEFAULT;
    FillRect(draw.nmcd.hdc, &bounds, panel_brush_);
    RECT pill = bounds;
    pill.left += CloudOS::Scale(4, dpi_);
    pill.right -= CloudOS::Scale(4, dpi_);
    pill.top += CloudOS::Scale(1, dpi_);
    pill.bottom -= CloudOS::Scale(1, dpi_);
    const bool selected = (draw.nmcd.uItemState & CDIS_SELECTED) != 0;
    const bool hot = (draw.nmcd.uItemState & CDIS_HOT) != 0;
    if (selected || hot)
        CloudOS::FilesStyle::PaintRoundedSurface(
            draw.nmcd.hdc, pill, selected ? kSelection : kHot,
            selected ? kSelection : kHot, CloudOS::Scale(8, dpi_), 0);
    if (selected)
    {
        RECT accent_bar{
            pill.left + CloudOS::Scale(3, dpi_), pill.top + CloudOS::Scale(6, dpi_),
            pill.left + CloudOS::Scale(6, dpi_), pill.bottom - CloudOS::Scale(6, dpi_)};
        HBRUSH accent = CreateSolidBrush(kAccent);
        if (accent != nullptr)
        {
            FillRect(draw.nmcd.hdc, &accent_bar, accent);
            DeleteObject(accent);
        }
    }

    const SidebarItem& item = sidebar_items_[static_cast<std::size_t>(row)];
    int icon_width = 0;
    int icon_height = 0;
    if (sidebar_image_list_ != nullptr &&
        ImageList_GetIconSize(sidebar_image_list_, &icon_width, &icon_height) &&
        item.image_index >= 0)
    {
        const int icon_x = pill.left + CloudOS::Scale(12, dpi_);
        const int icon_y = bounds.top + std::max<LONG>(
            0, static_cast<LONG>((bounds.bottom - bounds.top - icon_height) / 2));
        ImageList_Draw(sidebar_image_list_, item.image_index, draw.nmcd.hdc,
            icon_x, icon_y, ILD_TRANSPARENT);
    }

    RECT text_rect = bounds;
    text_rect.left = pill.left + CloudOS::Scale(42, dpi_);
    text_rect.right = pill.right - CloudOS::Scale(8, dpi_);
    SetBkMode(draw.nmcd.hdc, TRANSPARENT);
    SetTextColor(draw.nmcd.hdc, item.favorite ? CloudOS::WebSkin::AccentHover : kText);
    HGDIOBJ old_font = ui_font_ != nullptr ? SelectObject(draw.nmcd.hdc, ui_font_) : nullptr;
    DrawTextW(draw.nmcd.hdc, item.label.c_str(), -1, &text_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(draw.nmcd.hdc, old_font);
    return CDRF_SKIPDEFAULT;
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
            info->ptMinTrackSize.x = CloudOS::Scale(1080, dpi_);
            info->ptMinTrackSize.y = CloudOS::Scale(620, dpi_);
        }
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
    case WM_TIMER:
        if (w_param == kPreviewTimerId)
        {
            RefreshPreview();
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            if (w_param == 'T') { NewTab(); return 0; }
            if (w_param == 'W') { CloseActiveTab(); return 0; }
            if (w_param == 'F') { SetFocus(search_edit_); return 0; }
        }
        if ((GetKeyState(VK_MENU) & 0x8000) != 0)
        {
            if (w_param == VK_LEFT) { NavigateBack(); return 0; }
            if (w_param == VK_RIGHT) { NavigateForward(); return 0; }
        }
        break;
    case WM_DPICHANGED:
    {
        const UINT new_dpi = HIWORD(w_param);
        if (new_dpi != 0 && new_dpi != dpi_)
        {
            dpi_ = new_dpi;
            DestroyFonts();
            CreateFonts();
            ApplyFonts();
            if (sidebar_image_list_ != nullptr)
            {
                ImageList_Destroy(sidebar_image_list_);
                sidebar_image_list_ = nullptr;
            }
            sidebar_image_list_ = ImageList_Create(
                CloudOS::Scale(20, dpi_), CloudOS::Scale(20, dpi_),
                ILC_COLOR32 | ILC_MASK, 24, 8);
            if (sidebar_image_list_ != nullptr)
                ListView_SetImageList(sidebar_, sidebar_image_list_, LVSIL_SMALL);
            BuildSidebar();
        }
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        if (suggested != nullptr)
        {
            SetWindowPos(window_, nullptr, suggested->left, suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOZORDER | SWP_NOACTIVATE);
        }
        Layout();
        InvalidateRect(window_, nullptr, TRUE);
        return 0;
    }
    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kNewTabId: NewTab(); return 0;
        case kCloseTabId: CloseActiveTab(); return 0;
        case kBackId: NavigateBack(); return 0;
        case kForwardId: NavigateForward(); return 0;
        case kUpId: NavigateParent(); return 0;
        case kGoId: Navigate(ReadEditText(path_edit_)); return 0;
        case kFavoriteId: ToggleFavorite(); return 0;
        case kRefreshId: Refresh(); return 0;
        case kSearchId: OpenSearch(); return 0;
        case kPreviewId: TogglePreview(); return 0;
        case kOperationsId: OpenOperations(); return 0;
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
        if (header->hwndFrom == tab_strip_ && header->code == TCN_SELCHANGE)
        {
            const int selection = TabCtrl_GetCurSel(tab_strip_);
            if (selection >= 0) SelectTab(static_cast<std::size_t>(selection));
            return 0;
        }
        if (header->hwndFrom == sidebar_ && header->code == NM_CUSTOMDRAW)
            return CustomDrawSidebar(*reinterpret_cast<const NMLVCUSTOMDRAW*>(l_param));
        if (header->hwndFrom == sidebar_ && header->code == LVN_ITEMCHANGED)
        {
            const auto* changed = reinterpret_cast<const NMLISTVIEW*>(l_param);
            if ((changed->uNewState & LVIS_SELECTED) != 0 &&
                (changed->uOldState & LVIS_SELECTED) == 0)
                ActivateSidebarSelection();
            return 0;
        }
        if (header->hwndFrom == list_)
        {
            if (header->code == NM_DBLCLK)
            {
                ActivateCustomSelection();
                return 0;
            }
            if (header->code == NM_RCLICK)
            {
                const LPARAM packed = static_cast<LPARAM>(GetMessagePos());
                POINT point{GET_X_LPARAM(packed), GET_Y_LPARAM(packed)};
                ShowContentContextMenu(point);
                return 0;
            }
            if (header->code == LVN_ITEMCHANGED)
            {
                RefreshPreview();
                return 0;
            }
            if (header->code == LVN_ENDLABELEDITW)
            {
                auto* edit = reinterpret_cast<NMLVDISPINFOW*>(l_param);
                return edit != nullptr && CommitRename(edit->item.iItem, edit->item.pszText)
                    ? TRUE
                    : FALSE;
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
    case WM_CONTEXTMENU:
        if (reinterpret_cast<HWND>(w_param) == list_)
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            if (point.x == -1 && point.y == -1)
            {
                RECT bounds{};
                GetWindowRect(list_, &bounds);
                point = POINT{bounds.left + CloudOS::Scale(40, dpi_), bounds.top + CloudOS::Scale(40, dpi_)};
            }
            ShowContentContextMenu(point);
            return 0;
        }
        break;
    case WM_DRAWITEM:
        if (l_param != 0 && reinterpret_cast<const DRAWITEMSTRUCT*>(l_param)->CtlType == ODT_BUTTON)
            return DrawOwnerButton(*reinterpret_cast<const DRAWITEMSTRUCT*>(l_param));
        break;
    case WM_CTLCOLOREDIT:
        SetTextColor(reinterpret_cast<HDC>(w_param), kText);
        SetBkColor(reinterpret_cast<HDC>(w_param), kAddress);
        return reinterpret_cast<LRESULT>(address_brush_);
    case WM_CTLCOLORSTATIC:
        SetTextColor(reinterpret_cast<HDC>(w_param), kMuted);
        SetBkColor(reinterpret_cast<HDC>(w_param), kBg);
        return reinterpret_cast<LRESULT>(background_brush_);
    case WM_ERASEBKGND:
        if (background_brush_ != nullptr && panel_brush_ != nullptr)
        {
            RECT client{};
            GetClientRect(window_, &client);
            FillRect(reinterpret_cast<HDC>(w_param), &client, background_brush_);
            RECT sidebar_rect{
                0, 0,
                std::min<LONG>(client.right, static_cast<LONG>(CloudOS::Scale(252, dpi_))),
                client.bottom};
            FillRect(reinterpret_cast<HDC>(w_param), &sidebar_rect, panel_brush_);
            return 1;
        }
        break;
    case WM_PAINT:
    {
        PAINTSTRUCT ps{};
        HDC dc = BeginPaint(window_, &ps);
        if (dc != nullptr)
        {
            RECT client{};
            GetClientRect(window_, &client);
            PaintChrome(dc, client);
        }
        EndPaint(window_, &ps);
        return 0;
    }
    case WM_CLOSE:
        PersistV5State();
        DestroyWindow(window_);
        return 0;
    case WM_DESTROY:
        if (preview_timer_ != 0)
        {
            KillTimer(window_, preview_timer_);
            preview_timer_ = 0;
        }
        PersistV5State();
        preview_.Destroy();
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
        if (delete_self) delete this;
        return result;
    }
    default:
        break;
    }
    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeFilesWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeFilesWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFilesWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeFilesWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }
    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
