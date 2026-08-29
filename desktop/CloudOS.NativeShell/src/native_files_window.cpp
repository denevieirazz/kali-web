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
    : instance_(instance), current_path_(std::move(initial_path))
{
    if (current_path_.empty())
    {
        current_path_ = KnownFolderPath(FOLDERID_Profile);
        if (current_path_.empty())
        {
            current_path_ = CloudOS::NativeShellPlatform::WindowsVolumeRoot();
        }
        if (current_path_.empty())
        {
            current_path_ = L"C:\\";
        }
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
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Arquivos - CloudOS",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1240,
        790,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    CloudOS::FilesStyle::ApplyWindowChrome(window_);
    dpi_ = GetDpiForWindow(window_);
    if (dpi_ == 0)
    {
        dpi_ = 96;
    }

    CreateUiResources();
    if (!CreateControls())
    {
        DestroyWindow(window_);
        return false;
    }

    ConfigureLists();
    BuildSidebar();

    RECT initial_shell_bounds{0, 0, 100, 100};
    shell_available_ = shell_view_.Create(
        shell_host_,
        initial_shell_bounds,
        [this](const std::wstring& path)
        {
            OnShellNavigationComplete(path);
        });

    Layout();
    Navigate(current_path_);
    destroy_deletes_self_ = true;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeFilesWindow::CreateFonts()
{
    ui_font_ = CreateFontW(
        -CloudOS::Scale(14, dpi_),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Variable Text");

    title_font_ = CreateFontW(
        -CloudOS::Scale(21, dpi_),
        0,
        0,
        0,
        FW_SEMIBOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Variable Display");

    caption_font_ = CreateFontW(
        -CloudOS::Scale(11, dpi_),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Variable Text");

    glyph_font_ = CreateFontW(
        -CloudOS::Scale(18, dpi_),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Symbol");
}

void CloudOSNativeFilesWindow::ApplyFonts()
{
    const std::array<HWND, 12> controls{
        sidebar_,
        back_button_,
        forward_button_,
        up_button_,
        path_edit_,
        go_button_,
        refresh_button_,
        new_folder_button_,
        rename_button_,
        delete_button_,
        list_,
        status_};

    for (HWND control : controls)
    {
        if (control != nullptr && ui_font_ != nullptr)
        {
            SendMessageW(
                control,
                WM_SETFONT,
                reinterpret_cast<WPARAM>(ui_font_),
                TRUE);
        }
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
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_NOCOLUMNHEADER | LVS_SHOWSELALWAYS,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSidebarId)),
        instance_,
        nullptr);

    back_button_ = CreateButton(instance_, window_, L"←", kBackId);
    forward_button_ = CreateButton(instance_, window_, L"→", kForwardId);
    up_button_ = CreateButton(instance_, window_, L"↑", kUpId);

    path_edit_ = CreateWindowExW(
        0,
        L"EDIT",
        current_path_.c_str(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | ES_NOHIDESEL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPathId)),
        instance_,
        nullptr);

    go_button_ = CreateButton(instance_, window_, L"Ir", kGoId);
    refresh_button_ = CreateButton(instance_, window_, L"↻", kRefreshId);
    new_folder_button_ = CreateButton(instance_, window_, L"＋  Nova pasta", kNewFolderId);
    rename_button_ = CreateButton(instance_, window_, L"Renomear", kRenameId);
    delete_button_ = CreateButton(instance_, window_, L"Excluir", kDeleteId);

    shell_host_ = CreateWindowExW(
        0,
        L"STATIC",
        L"",
        WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kShellHostId)),
        instance_,
        nullptr);

    list_ = CreateWindowExW(
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_ICON | LVS_SINGLESEL | LVS_EDITLABELS |
            LVS_SHOWSELALWAYS | LVS_AUTOARRANGE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);

    status_ = CreateWindowExW(
        0,
        L"STATIC",
        L"",
        WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStatusId)),
        instance_,
        nullptr);

    const std::array<HWND, 12> controls{
        sidebar_,
        back_button_,
        forward_button_,
        up_button_,
        path_edit_,
        go_button_,
        refresh_button_,
        new_folder_button_,
        rename_button_,
        delete_button_,
        list_,
        status_};
    for (HWND control : controls)
    {
        if (control == nullptr)
        {
            return false;
        }
    }
    if (shell_host_ == nullptr)
    {
        return false;
    }

    ApplyFonts();
    (void)SendMessageW(
        path_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(L"Digite ou cole um caminho"));

    return SetWindowSubclass(
        path_edit_,
        AddressEditSubclass,
        kAddressSubclassId,
        0) != FALSE;
}

void CloudOSNativeFilesWindow::ConfigureLists()
{
    ListView_SetExtendedListViewStyle(
        sidebar_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(sidebar_, kPanel);
    ListView_SetTextBkColor(sidebar_, kPanel);
    ListView_SetTextColor(sidebar_, kText);

    LVCOLUMNW side_column{};
    side_column.mask = LVCF_WIDTH;
    side_column.cx = CloudOS::Scale(220, dpi_);
    ListView_InsertColumn(sidebar_, 0, &side_column);

    sidebar_image_list_ = ImageList_Create(
        CloudOS::Scale(20, dpi_),
        CloudOS::Scale(20, dpi_),
        ILC_COLOR32 | ILC_MASK,
        16,
        8);
    if (sidebar_image_list_ != nullptr)
    {
        ListView_SetImageList(sidebar_, sidebar_image_list_, LVSIL_SMALL);
    }

    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(list_, kSurface);
    ListView_SetTextBkColor(list_, kSurface);
    ListView_SetTextColor(list_, kText);
    ListView_SetIconSpacing(
        list_,
        CloudOS::Scale(136, dpi_),
        CloudOS::Scale(98, dpi_));

    SHFILEINFOW info{};
    const DWORD_PTR shared_large = SHGetFileInfoW(
        L"folder",
        FILE_ATTRIBUTE_DIRECTORY,
        &info,
        sizeof(info),
        SHGFI_SYSICONINDEX |
            SHGFI_LARGEICON |
            SHGFI_USEFILEATTRIBUTES);
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
    if (sidebar_image_list_ != nullptr)
    {
        ImageList_RemoveAll(sidebar_image_list_);
    }

    std::wstring ignored;
    (void)CloudOS::NativeCloudOSDrive::EnsureReady(&ignored);

    const auto add = [this](
        const wchar_t* label,
        std::wstring path,
        SHSTOCKICONID fallback_icon)
    {
        if (path.empty())
        {
            return;
        }
        SidebarItem item{};
        item.label = label;
        item.image_index = AddSidebarIcon(path, fallback_icon);
        item.path = std::move(path);
        sidebar_items_.push_back(std::move(item));
    };

    add(L"Início", KnownFolderPath(FOLDERID_Profile), SIID_FOLDER);
    add(L"Área de Trabalho", KnownFolderPath(FOLDERID_Desktop), SIID_FOLDER);
    add(L"Documentos", KnownFolderPath(FOLDERID_Documents), SIID_FOLDER);
    add(L"Downloads", KnownFolderPath(FOLDERID_Downloads), SIID_FOLDER);
    add(L"CloudOS Drive", CloudOS::NativeCloudOSDrive::Root(), SIID_FOLDER);
    add(L"Projetos", CloudOS::NativeCloudOSDrive::ProjectsRoot(), SIID_FOLDER);
    add(L"WSL / Linux", L"\\\\wsl.localhost\\", SIID_APPLICATION);
    add(
        L"Disco do Sistema",
        CloudOS::NativeShellPlatform::WindowsVolumeRoot(),
        SIID_DRIVEFIXED);

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
}

void CloudOSNativeFilesWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int width = std::max(1, static_cast<int>(client.right - client.left));
    const int height = std::max(1, static_cast<int>(client.bottom - client.top));
    const int side = CloudOS::Scale(252, dpi_);
    const int side_padding = CloudOS::Scale(12, dpi_);
    const int side_header = CloudOS::Scale(78, dpi_);
    const int right_margin = CloudOS::Scale(18, dpi_);
    const int gap = CloudOS::Scale(8, dpi_);
    const int row = CloudOS::Scale(40, dpi_);
    const int nav_button_width = CloudOS::Scale(40, dpi_);
    const int status_height = CloudOS::Scale(28, dpi_);

    MoveWindow(
        sidebar_,
        side_padding,
        side_header,
        std::max(1, side - side_padding * 2),
        std::max(1, height - side_header - side_padding),
        TRUE);

    int x = side + CloudOS::Scale(18, dpi_);
    const int right_start = x;
    const int top = CloudOS::Scale(16, dpi_);

    MoveWindow(back_button_, x, top, nav_button_width, row, TRUE);
    x += nav_button_width + gap;
    MoveWindow(forward_button_, x, top, nav_button_width, row, TRUE);
    x += nav_button_width + gap;
    MoveWindow(up_button_, x, top, nav_button_width, row, TRUE);
    x += nav_button_width + gap;

    const int go_width = CloudOS::Scale(50, dpi_);
    const int refresh_width = CloudOS::Scale(40, dpi_);
    const int path_width = std::max(
        CloudOS::Scale(260, dpi_),
        width - right_margin - x - go_width - refresh_width - gap * 2);

    address_rect_ = RECT{x, top, x + path_width, top + row};
    const int edit_inset_x = CloudOS::Scale(12, dpi_);
    const int edit_inset_y = CloudOS::Scale(7, dpi_);
    MoveWindow(
        path_edit_,
        address_rect_.left + edit_inset_x,
        address_rect_.top + edit_inset_y,
        std::max(1, path_width - edit_inset_x * 2),
        std::max(1, row - edit_inset_y * 2),
        TRUE);
    x += path_width + gap;
    MoveWindow(go_button_, x, top, go_width, row, TRUE);
    x += go_width + gap;
    MoveWindow(refresh_button_, x, top, refresh_width, row, TRUE);

    x = right_start;
    const int actions_y = top + row + CloudOS::Scale(12, dpi_);
    const int action_height = CloudOS::Scale(34, dpi_);
    const int new_width = CloudOS::Scale(128, dpi_);
    const int rename_width = CloudOS::Scale(98, dpi_);
    const int delete_width = CloudOS::Scale(82, dpi_);
    MoveWindow(new_folder_button_, x, actions_y, new_width, action_height, TRUE);
    x += new_width + gap;
    MoveWindow(rename_button_, x, actions_y, rename_width, action_height, TRUE);
    x += rename_width + gap;
    MoveWindow(delete_button_, x, actions_y, delete_width, action_height, TRUE);

    const int content_y = actions_y + action_height + CloudOS::Scale(12, dpi_);
    const int content_bottom = std::max(
        content_y + 1,
        height - status_height - CloudOS::Scale(8, dpi_));
    content_rect_ = RECT{
        right_start,
        content_y,
        std::max(right_start + 1, width - right_margin),
        content_bottom};

    const int content_width = std::max(1, content_rect_.right - content_rect_.left);
    const int content_height = std::max(1, content_rect_.bottom - content_rect_.top);
    const int content_inset = 1;
    MoveWindow(
        shell_host_,
        content_rect_.left + content_inset,
        content_rect_.top + content_inset,
        std::max(1, content_width - content_inset * 2),
        std::max(1, content_height - content_inset * 2),
        TRUE);
    MoveWindow(
        list_,
        content_rect_.left + content_inset,
        content_rect_.top + content_inset,
        std::max(1, content_width - content_inset * 2),
        std::max(1, content_height - content_inset * 2),
        TRUE);
    MoveWindow(
        status_,
        right_start + CloudOS::Scale(4, dpi_),
        height - status_height,
        std::max(1, width - right_start - right_margin),
        status_height,
        TRUE);

    if (shell_available_)
    {
        RECT bounds{
            0,
            0,
            std::max(1, content_width - content_inset * 2),
            std::max(1, content_height - content_inset * 2)};
        shell_view_.Resize(bounds);
    }

    ListView_SetColumnWidth(
        sidebar_,
        0,
        std::max(1, side - side_padding * 2 - CloudOS::Scale(4, dpi_)));
    ListView_SetIconSpacing(
        list_,
        CloudOS::Scale(136, dpi_),
        CloudOS::Scale(98, dpi_));

    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeFilesWindow::PaintChrome(HDC dc, const RECT& client)
{
    if (dc == nullptr)
    {
        return;
    }

    FillRect(dc, &client, background_brush_);

    const int side = CloudOS::Scale(252, dpi_);
    RECT sidebar_background{0, 0, std::min(client.right, side), client.bottom};
    FillRect(dc, &sidebar_background, panel_brush_);

    CloudOS::FilesStyle::PaintSeparator(
        dc,
        side - 1,
        0,
        side - 1,
        client.bottom,
        kBorder);

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, kText);
    HGDIOBJ old_font = title_font_ != nullptr
        ? SelectObject(dc, title_font_)
        : nullptr;
    RECT title_rect{
        CloudOS::Scale(20, dpi_),
        CloudOS::Scale(14, dpi_),
        side - CloudOS::Scale(18, dpi_),
        CloudOS::Scale(43, dpi_)};
    DrawTextW(
        dc,
        L"Arquivos",
        -1,
        &title_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }

    SetTextColor(dc, kMuted);
    old_font = caption_font_ != nullptr
        ? SelectObject(dc, caption_font_)
        : nullptr;
    RECT caption_rect{
        CloudOS::Scale(21, dpi_),
        CloudOS::Scale(43, dpi_),
        side - CloudOS::Scale(18, dpi_),
        CloudOS::Scale(67, dpi_)};
    DrawTextW(
        dc,
        L"CloudOS Drive  •  Windows  •  WSL",
        -1,
        &caption_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }

    if (address_rect_.right > address_rect_.left)
    {
        CloudOS::FilesStyle::PaintRoundedSurface(
            dc,
            address_rect_,
            kAddress,
            kBorder,
            CloudOS::Scale(10, dpi_));
    }

    if (content_rect_.right > content_rect_.left)
    {
        CloudOS::FilesStyle::PaintRoundedSurface(
            dc,
            content_rect_,
            kSurface,
            kBorder,
            CloudOS::Scale(10, dpi_));
    }

    const int status_y = client.bottom - CloudOS::Scale(30, dpi_);
    CloudOS::FilesStyle::PaintSeparator(
        dc,
        side + CloudOS::Scale(18, dpi_),
        status_y,
        client.right - CloudOS::Scale(18, dpi_),
        status_y,
        kBorder);
}

void CloudOSNativeFilesWindow::UpdateStatus()
{
    std::wstring text;
    if (content_mode_ == ContentMode::CloudOSDrive)
    {
        text = L"CloudOS Drive   •   " +
            std::to_wstring(entries_.size()) +
            L" itens";
    }
    else if (content_mode_ == ContentMode::Shell)
    {
        text = L"Windows Shell   •   " + current_path_;
    }
    else
    {
        text = std::to_wstring(entries_.size()) + L" itens   •   " + current_path_;
    }
    SetWindowTextW(status_, text.c_str());
}
