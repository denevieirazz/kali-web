#include "native_files_window.h"
#include "native_files_internal.h"

#include "native_cloudos_drive.h"
#include "native_cloudos_trash_window.h"
#include "native_files_style.h"
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

CloudOSNativeFilesWindow::CloudOSNativeFilesWindow(HINSTANCE instance, std::wstring initial_path)
    : instance_(instance),
      initial_path_explicit_(!initial_path.empty()),
      current_path_(std::move(initial_path))
{
    if (current_path_.empty())
    {
        current_path_ = KnownFolderPath(FOLDERID_Profile);
        if (current_path_.empty()) current_path_ = CloudOS::NativeShellPlatform::WindowsVolumeRoot();
        if (current_path_.empty()) current_path_ = L"C:\\";
    }
}

void CloudOSNativeFilesWindow::Open(HINSTANCE instance, const std::wstring& initial_path)
{
    auto* self = new (std::nothrow) CloudOSNativeFilesWindow(instance, initial_path);
    if (self == nullptr || !self->Create())
    {
        delete self;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Arquivos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeFilesWindow::Create()
{
    if (!RegisterWindowClass(instance_)) return false;

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Arquivos - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1380,
        840,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr) return false;

    CloudOS::FilesStyle::ApplyWindowChrome(window_);
    dpi_ = GetDpiForWindow(window_);
    if (dpi_ == 0) dpi_ = 96;

    CreateUiResources();
    if (!CreateControls())
    {
        DestroyWindow(window_);
        return false;
    }

    ConfigureLists();
    LoadV5State();
    BuildSidebar();
    SyncTabStrip();

    RECT initial_shell_bounds{0, 0, 100, 100};
    shell_available_ = shell_view_.Create(
        shell_host_,
        initial_shell_bounds,
        [this](const std::wstring& path)
        {
            OnShellNavigationComplete(path);
        });

    if (!preview_.Create(instance_, window_))
    {
        preview_visible_ = false;
        persisted_state_.preview_visible = false;
    }
    preview_.Show(preview_visible_);

    Layout();
    if (!tab_states_.empty())
    {
        active_tab_ = std::min(active_tab_, tab_states_.size() - 1);
        current_path_ = tab_states_[active_tab_].path;
        suppressed_history_target_ = current_path_;
    }
    Navigate(current_path_);

    preview_timer_ = SetTimer(window_, kPreviewTimerId, 300, nullptr);
    destroy_deletes_self_ = true;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeFilesWindow::CreateFonts()
{
    ui_font_ = CreateFontW(
        -CloudOS::Scale(14, dpi_), 0, 0, 0, FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -CloudOS::Scale(21, dpi_), 0, 0, 0, FW_SEMIBOLD,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    caption_font_ = CreateFontW(
        -CloudOS::Scale(11, dpi_), 0, 0, 0, FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    glyph_font_ = CreateFontW(
        -CloudOS::Scale(18, dpi_), 0, 0, 0, FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Symbol");
}

void CloudOSNativeFilesWindow::ApplyFonts()
{
    const std::array<HWND, 22> controls{
        sidebar_, tab_strip_, new_tab_button_, close_tab_button_,
        back_button_, forward_button_, up_button_, path_edit_, go_button_,
        refresh_button_, favorite_button_, search_edit_, search_button_, preview_button_,
        new_folder_button_, rename_button_, delete_button_, operations_button_,
        list_, status_, shell_host_, preview_.Window()};
    for (HWND control : controls)
    {
        if (control != nullptr && ui_font_ != nullptr)
            SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(ui_font_), TRUE);
    }
}

void CloudOSNativeFilesWindow::DestroyFonts() noexcept
{
    if (ui_font_ != nullptr) DeleteObject(ui_font_);
    if (title_font_ != nullptr) DeleteObject(title_font_);
    if (caption_font_ != nullptr) DeleteObject(caption_font_);
    if (glyph_font_ != nullptr) DeleteObject(glyph_font_);
    ui_font_ = nullptr;
    title_font_ = nullptr;
    caption_font_ = nullptr;
    glyph_font_ = nullptr;
}

void CloudOSNativeFilesWindow::CreateUiResources()
{
    CreateFonts();
    background_brush_ = CreateSolidBrush(kBg);
    panel_brush_ = CreateSolidBrush(kPanel);
    surface_brush_ = CreateSolidBrush(kSurface);
    address_brush_ = CreateSolidBrush(kAddress);
}

void CloudOSNativeFilesWindow::DestroyUiResources() noexcept
{
    DestroyFonts();
    if (background_brush_ != nullptr) DeleteObject(background_brush_);
    if (panel_brush_ != nullptr) DeleteObject(panel_brush_);
    if (surface_brush_ != nullptr) DeleteObject(surface_brush_);
    if (address_brush_ != nullptr) DeleteObject(address_brush_);
    if (sidebar_image_list_ != nullptr) ImageList_Destroy(sidebar_image_list_);
    background_brush_ = nullptr;
    panel_brush_ = nullptr;
    surface_brush_ = nullptr;
    address_brush_ = nullptr;
    sidebar_image_list_ = nullptr;
    system_large_image_list_ = nullptr;
}

bool CloudOSNativeFilesWindow::CreateControls()
{
    sidebar_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_NOCOLUMNHEADER | LVS_SHOWSELALWAYS,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSidebarId)), instance_, nullptr);

    tab_strip_ = CreateWindowExW(
        0, WC_TABCONTROLW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | TCS_SINGLELINE | TCS_TOOLTIPS,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTabsId)), instance_, nullptr);
    new_tab_button_ = CreateButton(instance_, window_, L"＋", kNewTabId);
    close_tab_button_ = CreateButton(instance_, window_, L"×", kCloseTabId);

    back_button_ = CreateButton(instance_, window_, L"←", kBackId);
    forward_button_ = CreateButton(instance_, window_, L"→", kForwardId);
    up_button_ = CreateButton(instance_, window_, L"↑", kUpId);

    path_edit_ = CreateWindowExW(
        0, L"EDIT", current_path_.c_str(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | ES_NOHIDESEL,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPathId)), instance_, nullptr);
    go_button_ = CreateButton(instance_, window_, L"Ir", kGoId);
    favorite_button_ = CreateButton(instance_, window_, L"☆", kFavoriteId);
    refresh_button_ = CreateButton(instance_, window_, L"↻", kRefreshId);

    new_folder_button_ = CreateButton(instance_, window_, L"＋  Nova pasta", kNewFolderId);
    rename_button_ = CreateButton(instance_, window_, L"Renomear", kRenameId);
    delete_button_ = CreateButton(instance_, window_, L"Excluir", kDeleteId);
    operations_button_ = CreateButton(instance_, window_, L"Operações", kOperationsId);
    preview_button_ = CreateButton(instance_, window_, L"Preview", kPreviewId);

    search_edit_ = CreateWindowExW(
        0, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSearchEditId)), instance_, nullptr);
    search_button_ = CreateButton(instance_, window_, L"Buscar", kSearchId);

    shell_host_ = CreateWindowExW(
        0, L"STATIC", L"",
        WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kShellHostId)), instance_, nullptr);
    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_ICON | LVS_SINGLESEL | LVS_EDITLABELS |
            LVS_SHOWSELALWAYS | LVS_AUTOARRANGE,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)), instance_, nullptr);
    status_ = CreateWindowExW(
        0, L"STATIC", L"",
        WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStatusId)), instance_, nullptr);

    const std::array<HWND, 21> required{
        sidebar_, tab_strip_, new_tab_button_, close_tab_button_,
        back_button_, forward_button_, up_button_, path_edit_, go_button_,
        favorite_button_, refresh_button_, new_folder_button_, rename_button_,
        delete_button_, operations_button_, preview_button_, search_edit_, search_button_,
        shell_host_, list_, status_};
    for (HWND control : required)
        if (control == nullptr) return false;

    ApplyFonts();
    SendMessageW(path_edit_, EM_SETCUEBANNER, TRUE,
        reinterpret_cast<LPARAM>(L"Digite ou cole um caminho"));
    SendMessageW(search_edit_, EM_SETCUEBANNER, TRUE,
        reinterpret_cast<LPARAM>(L"Pesquisar nesta pasta"));

    if (!SetWindowSubclass(path_edit_, AddressEditSubclass, kAddressSubclassId, 0)) return false;
    if (!SetWindowSubclass(search_edit_, SearchEditSubclass, kSearchSubclassId, 0)) return false;
    return true;
}

void CloudOSNativeFilesWindow::ConfigureLists()
{
    ListView_SetExtendedListViewStyle(
        sidebar_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(sidebar_, kPanel);
    ListView_SetTextBkColor(sidebar_, kPanel);
    ListView_SetTextColor(sidebar_, kText);

    LVCOLUMNW side_column{};
    side_column.mask = LVCF_WIDTH;
    side_column.cx = CloudOS::Scale(220, dpi_);
    ListView_InsertColumn(sidebar_, 0, &side_column);

    sidebar_image_list_ = ImageList_Create(
        CloudOS::Scale(20, dpi_), CloudOS::Scale(20, dpi_),
        ILC_COLOR32 | ILC_MASK, 24, 8);
    if (sidebar_image_list_ != nullptr)
        ListView_SetImageList(sidebar_, sidebar_image_list_, LVSIL_SMALL);

    ListView_SetExtendedListViewStyle(list_, LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(list_, kSurface);
    ListView_SetTextBkColor(list_, kSurface);
    ListView_SetTextColor(list_, kText);
    ListView_SetIconSpacing(list_, CloudOS::Scale(136, dpi_), CloudOS::Scale(98, dpi_));

    SHFILEINFOW info{};
    const DWORD_PTR shared_large = SHGetFileInfoW(
        L"folder", FILE_ATTRIBUTE_DIRECTORY, &info, sizeof(info),
        SHGFI_SYSICONINDEX | SHGFI_LARGEICON | SHGFI_USEFILEATTRIBUTES);
    if (shared_large != 0)
    {
        system_large_image_list_ = reinterpret_cast<HIMAGELIST>(shared_large);
        ListView_SetImageList(list_, system_large_image_list_, LVSIL_NORMAL);
    }
}

void CloudOSNativeFilesWindow::BuildSidebar()
{
    sidebar_items_.clear();
    ListView_DeleteAllItems(sidebar_);
    if (sidebar_image_list_ != nullptr) ImageList_RemoveAll(sidebar_image_list_);

    std::wstring ignored;
    (void)CloudOS::NativeCloudOSDrive::EnsureReady(&ignored);

    const auto add = [this](
        std::wstring label,
        std::wstring path,
        SHSTOCKICONID fallback_icon,
        bool favorite = false)
    {
        if (path.empty()) return;
        SidebarItem item{};
        item.label = std::move(label);
        item.image_index = AddSidebarIcon(path, fallback_icon);
        item.path = std::move(path);
        item.favorite = favorite;
        sidebar_items_.push_back(std::move(item));
    };

    add(L"Início", KnownFolderPath(FOLDERID_Profile), SIID_FOLDER);
    add(L"Área de Trabalho", KnownFolderPath(FOLDERID_Desktop), SIID_FOLDER);
    add(L"Documentos", KnownFolderPath(FOLDERID_Documents), SIID_FOLDER);
    add(L"Downloads", KnownFolderPath(FOLDERID_Downloads), SIID_FOLDER);

    for (const auto& path : persisted_state_.favorites)
    {
        std::wstring label = L"★ ";
        label += LeafName(path);
        if (label.size() == 2) label += path;
        add(std::move(label), path, SIID_FOLDER, true);
    }

    add(L"CloudOS Drive", CloudOS::NativeCloudOSDrive::Root(), SIID_FOLDER);
    add(L"Projetos", CloudOS::NativeCloudOSDrive::ProjectsRoot(), SIID_FOLDER);
    add(L"WSL / Linux", L"\\\\wsl.localhost\\", SIID_APPLICATION);
    add(L"Disco do Sistema", CloudOS::NativeShellPlatform::WindowsVolumeRoot(), SIID_DRIVEFIXED);

    SidebarItem trash{};
    trash.label = L"Lixeira do CloudOS";
    trash.opens_trash = true;
    trash.image_index = AddSidebarIcon({}, SIID_RECYCLER);
    sidebar_items_.push_back(std::move(trash));

    for (std::size_t index = 0; index < sidebar_items_.size(); ++index)
    {
        LVITEMW item{};
        item.mask = LVIF_TEXT | LVIF_PARAM;
        if (sidebar_items_[index].image_index >= 0)
        {
            item.mask |= LVIF_IMAGE;
            item.iImage = sidebar_items_[index].image_index;
        }
        item.iItem = static_cast<int>(index);
        item.lParam = static_cast<LPARAM>(index);
        item.pszText = sidebar_items_[index].label.data();
        ListView_InsertItem(sidebar_, &item);
    }
    SelectSidebarForCurrentPath();
}

void CloudOSNativeFilesWindow::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    if (!GetClientRect(window_, &client)) return;

    const int width = std::max<LONG>(1, client.right - client.left);
    const int height = std::max<LONG>(1, client.bottom - client.top);
    const int side = CloudOS::Scale(252, dpi_);
    const int side_padding = CloudOS::Scale(12, dpi_);
    const int side_header = CloudOS::Scale(78, dpi_);
    const int right_margin = CloudOS::Scale(18, dpi_);
    const int gap = CloudOS::Scale(8, dpi_);
    const int right_start = side + CloudOS::Scale(18, dpi_);
    const int right_width = std::max(1, width - right_start - right_margin);
    const int status_height = CloudOS::Scale(28, dpi_);

    MoveWindow(
        sidebar_, side_padding, side_header,
        std::max(1, side - side_padding * 2),
        std::max(1, height - side_header - side_padding), TRUE);

    const int tab_y = CloudOS::Scale(12, dpi_);
    const int tab_height = CloudOS::Scale(36, dpi_);
    const int tab_button = CloudOS::Scale(38, dpi_);
    const int tab_strip_width = std::max(
        CloudOS::Scale(240, dpi_), right_width - tab_button * 2 - gap * 2);
    MoveWindow(tab_strip_, right_start, tab_y, tab_strip_width, tab_height, TRUE);
    MoveWindow(new_tab_button_, right_start + tab_strip_width + gap, tab_y, tab_button, tab_height, TRUE);
    MoveWindow(close_tab_button_, right_start + tab_strip_width + gap * 2 + tab_button,
        tab_y, tab_button, tab_height, TRUE);

    int x = right_start;
    const int nav_y = tab_y + tab_height + CloudOS::Scale(8, dpi_);
    const int nav_height = CloudOS::Scale(40, dpi_);
    const int nav_button = CloudOS::Scale(40, dpi_);
    MoveWindow(back_button_, x, nav_y, nav_button, nav_height, TRUE); x += nav_button + gap;
    MoveWindow(forward_button_, x, nav_y, nav_button, nav_height, TRUE); x += nav_button + gap;
    MoveWindow(up_button_, x, nav_y, nav_button, nav_height, TRUE); x += nav_button + gap;

    const int go_width = CloudOS::Scale(50, dpi_);
    const int favorite_width = CloudOS::Scale(42, dpi_);
    const int refresh_width = CloudOS::Scale(42, dpi_);
    const int path_width = std::max(
        CloudOS::Scale(220, dpi_),
        right_start + right_width - x - go_width - favorite_width - refresh_width - gap * 5);
    address_rect_ = RECT{x, nav_y, x + path_width, nav_y + nav_height};
    const int edit_inset_x = CloudOS::Scale(12, dpi_);
    const int edit_inset_y = CloudOS::Scale(7, dpi_);
    MoveWindow(path_edit_, address_rect_.left + edit_inset_x, address_rect_.top + edit_inset_y,
        std::max(1, path_width - edit_inset_x * 2),
        std::max(1, nav_height - edit_inset_y * 2), TRUE);
    x += path_width + gap;
    MoveWindow(go_button_, x, nav_y, go_width, nav_height, TRUE); x += go_width + gap;
    MoveWindow(favorite_button_, x, nav_y, favorite_width, nav_height, TRUE); x += favorite_width + gap;
    MoveWindow(refresh_button_, x, nav_y, refresh_width, nav_height, TRUE);

    x = right_start;
    const int actions_y = nav_y + nav_height + CloudOS::Scale(9, dpi_);
    const int action_height = CloudOS::Scale(34, dpi_);
    const int new_width = CloudOS::Scale(126, dpi_);
    const int rename_width = CloudOS::Scale(94, dpi_);
    const int delete_width = CloudOS::Scale(78, dpi_);
    const int operations_width = CloudOS::Scale(98, dpi_);
    const int preview_width = CloudOS::Scale(82, dpi_);
    MoveWindow(new_folder_button_, x, actions_y, new_width, action_height, TRUE); x += new_width + gap;
    MoveWindow(rename_button_, x, actions_y, rename_width, action_height, TRUE); x += rename_width + gap;
    MoveWindow(delete_button_, x, actions_y, delete_width, action_height, TRUE); x += delete_width + gap;
    MoveWindow(operations_button_, x, actions_y, operations_width, action_height, TRUE); x += operations_width + gap;
    MoveWindow(preview_button_, x, actions_y, preview_width, action_height, TRUE);

    const int search_button_width = CloudOS::Scale(72, dpi_);
    const int search_width = CloudOS::Scale(230, dpi_);
    const int search_x = right_start + right_width - search_width - search_button_width - gap;
    MoveWindow(search_edit_, search_x, actions_y, search_width, action_height, TRUE);
    MoveWindow(search_button_, search_x + search_width + gap, actions_y,
        search_button_width, action_height, TRUE);

    const int content_y = actions_y + action_height + CloudOS::Scale(12, dpi_);
    const int content_bottom = std::max(
        content_y + 1, height - status_height - CloudOS::Scale(8, dpi_));
    const int available_content_width = right_width;
    const int preview_gap = preview_visible_ ? CloudOS::Scale(10, dpi_) : 0;
    const int requested_preview = preview_visible_ ? CloudOS::Scale(320, dpi_) : 0;
    const int actual_preview = preview_visible_
        ? std::min(requested_preview, std::max(CloudOS::Scale(250, dpi_), available_content_width / 3))
        : 0;
    const int main_width = std::max(
        CloudOS::Scale(300, dpi_), available_content_width - actual_preview - preview_gap);

    content_rect_ = RECT{
        right_start,
        content_y,
        right_start + main_width,
        content_bottom};
    preview_rect_ = RECT{
        content_rect_.right + preview_gap,
        content_y,
        right_start + available_content_width,
        content_bottom};

    const int content_width = std::max<LONG>(1, content_rect_.right - content_rect_.left);
    const int content_height = std::max<LONG>(1, content_rect_.bottom - content_rect_.top);
    const int content_inset = 1;
    MoveWindow(shell_host_, content_rect_.left + content_inset, content_rect_.top + content_inset,
        std::max(1, content_width - content_inset * 2),
        std::max(1, content_height - content_inset * 2), TRUE);
    MoveWindow(list_, content_rect_.left + content_inset, content_rect_.top + content_inset,
        std::max(1, content_width - content_inset * 2),
        std::max(1, content_height - content_inset * 2), TRUE);

    if (preview_.Window() != nullptr)
    {
        preview_.Resize(preview_rect_);
        preview_.Show(preview_visible_);
    }

    MoveWindow(status_, right_start + CloudOS::Scale(4, dpi_), height - status_height,
        std::max(1, right_width), status_height, TRUE);

    if (shell_available_)
    {
        RECT bounds{0, 0,
            std::max(1, content_width - content_inset * 2),
            std::max(1, content_height - content_inset * 2)};
        shell_view_.Resize(bounds);
    }

    ListView_SetColumnWidth(sidebar_, 0,
        std::max(1, side - side_padding * 2 - CloudOS::Scale(4, dpi_)));
    ListView_SetIconSpacing(list_, CloudOS::Scale(136, dpi_), CloudOS::Scale(98, dpi_));
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeFilesWindow::PaintChrome(HDC dc, const RECT& client)
{
    if (dc == nullptr) return;
    FillRect(dc, &client, background_brush_);

    const int side = CloudOS::Scale(252, dpi_);
    RECT sidebar_background{0, 0, std::min<LONG>(client.right, side), client.bottom};
    FillRect(dc, &sidebar_background, panel_brush_);
    CloudOS::FilesStyle::PaintSeparator(dc, side - 1, 0, side - 1, client.bottom, kBorder);

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, kText);
    HGDIOBJ old_font = title_font_ != nullptr ? SelectObject(dc, title_font_) : nullptr;
    RECT title_rect{
        CloudOS::Scale(20, dpi_), CloudOS::Scale(14, dpi_),
        side - CloudOS::Scale(18, dpi_), CloudOS::Scale(43, dpi_)};
    DrawTextW(dc, L"Arquivos", -1, &title_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(dc, old_font);

    SetTextColor(dc, kMuted);
    old_font = caption_font_ != nullptr ? SelectObject(dc, caption_font_) : nullptr;
    RECT caption_rect{
        CloudOS::Scale(21, dpi_), CloudOS::Scale(43, dpi_),
        side - CloudOS::Scale(18, dpi_), CloudOS::Scale(67, dpi_)};
    DrawTextW(dc, L"Tabs  •  Quick Access  •  Windows Shell  •  Drive  •  WSL", -1,
        &caption_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(dc, old_font);

    if (address_rect_.right > address_rect_.left)
        CloudOS::FilesStyle::PaintRoundedSurface(
            dc, address_rect_, kAddress, kBorder, CloudOS::Scale(10, dpi_));
    if (content_rect_.right > content_rect_.left)
        CloudOS::FilesStyle::PaintRoundedSurface(
            dc, content_rect_, kSurface, kBorder, CloudOS::Scale(10, dpi_));
    if (preview_visible_ && preview_rect_.right > preview_rect_.left)
        CloudOS::FilesStyle::PaintRoundedSurface(
            dc, preview_rect_, CloudOS::WebSkin::BgSecondary, kBorder, CloudOS::Scale(10, dpi_));

    const int status_y = client.bottom - CloudOS::Scale(30, dpi_);
    CloudOS::FilesStyle::PaintSeparator(
        dc, side + CloudOS::Scale(18, dpi_), status_y,
        client.right - CloudOS::Scale(18, dpi_), status_y, kBorder);
}

void CloudOSNativeFilesWindow::UpdateStatus()
{
    std::wstring text;
    if (content_mode_ == ContentMode::CloudOSDrive)
        text = L"CloudOS Drive   •   " + std::to_wstring(entries_.size()) + L" itens";
    else if (content_mode_ == ContentMode::Shell)
        text = L"Windows Shell   •   " + current_path_;
    else
        text = std::to_wstring(entries_.size()) + L" itens   •   " + current_path_;

    text += L"   •   aba ";
    text += std::to_wstring(tab_states_.empty() ? 0 : active_tab_ + 1);
    text += L"/" + std::to_wstring(tab_states_.size());
    if (preview_visible_) text += L"   •   preview ativo";
    SetWindowTextW(status_, text.c_str());
}
