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

CloudOSNativeFilesWindow::CloudOSNativeFilesWindow(HINSTANCE instance, std::wstring initial_path)
    : instance_(instance), current_path_(std::move(initial_path))
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
        MessageBoxW(nullptr, L"Nao foi possivel abrir Arquivos.", L"CloudOS", MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeFilesWindow::Create()
{
    if (!RegisterWindowClass(instance_)) return false;
    window_ = CreateWindowExW(
        WS_EX_APPWINDOW, kClassName, L"Arquivos - CloudOS",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 1240, 790,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    CloudOS::DarkWindow(window_);
    dpi_ = GetDpiForWindow(window_);
    if (dpi_ == 0) dpi_ = 96;
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
        shell_host_, initial_shell_bounds,
        [this](const std::wstring& path) { OnShellNavigationComplete(path); });

    Layout();
    Navigate(current_path_);
    destroy_deletes_self_ = true;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeFilesWindow::CreateUiResources()
{
    ui_font_ = CreateFontW(
        -CloudOS::Scale(14, dpi_), 0, 0, 0, FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    background_brush_ = CreateSolidBrush(kBg);
    panel_brush_ = CreateSolidBrush(kPanel);
    surface_brush_ = CreateSolidBrush(kSurface);
}

void CloudOSNativeFilesWindow::DestroyUiResources() noexcept
{
    if (ui_font_ != nullptr) DeleteObject(ui_font_);
    if (background_brush_ != nullptr) DeleteObject(background_brush_);
    if (panel_brush_ != nullptr) DeleteObject(panel_brush_);
    if (surface_brush_ != nullptr) DeleteObject(surface_brush_);
    ui_font_ = nullptr;
    background_brush_ = nullptr;
    panel_brush_ = nullptr;
    surface_brush_ = nullptr;
    system_small_image_list_ = nullptr;
    system_large_image_list_ = nullptr;
}

bool CloudOSNativeFilesWindow::CreateControls()
{
    sidebar_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL | LVS_NOCOLUMNHEADER | LVS_SHOWSELALWAYS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSidebarId)), instance_, nullptr);
    back_button_ = CreateButton(instance_, window_, L"←", kBackId);
    forward_button_ = CreateButton(instance_, window_, L"→", kForwardId);
    up_button_ = CreateButton(instance_, window_, L"↑", kUpId);
    path_edit_ = CreateWindowExW(
        0, L"EDIT", current_path_.c_str(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPathId)), instance_, nullptr);
    go_button_ = CreateButton(instance_, window_, L"Ir", kGoId);
    refresh_button_ = CreateButton(instance_, window_, L"Atualizar", kRefreshId);
    new_folder_button_ = CreateButton(instance_, window_, L"+ Nova pasta", kNewFolderId);
    rename_button_ = CreateButton(instance_, window_, L"Renomear", kRenameId);
    delete_button_ = CreateButton(instance_, window_, L"Excluir", kDeleteId);
    shell_host_ = CreateWindowExW(
        0, L"STATIC", L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kShellHostId)), instance_, nullptr);
    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_ICON | LVS_SINGLESEL | LVS_EDITLABELS | LVS_SHOWSELALWAYS | LVS_AUTOARRANGE,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)), instance_, nullptr);
    status_ = CreateWindowExW(
        0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStatusId)), instance_, nullptr);

    const std::array<HWND, 12> controls{
        sidebar_, back_button_, forward_button_, up_button_, path_edit_, go_button_,
        refresh_button_, new_folder_button_, rename_button_, delete_button_, list_, status_};
    for (HWND control : controls)
    {
        if (control == nullptr) return false;
        if (ui_font_ != nullptr) SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(ui_font_), TRUE);
    }
    if (shell_host_ == nullptr) return false;
    return SetWindowSubclass(path_edit_, AddressEditSubclass, kAddressSubclassId, 0) != FALSE;
}

void CloudOSNativeFilesWindow::ConfigureLists()
{
    ListView_SetExtendedListViewStyle(sidebar_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    ListView_SetBkColor(sidebar_, kPanel);
    ListView_SetTextBkColor(sidebar_, kPanel);
    ListView_SetTextColor(sidebar_, kText);
    LVCOLUMNW side_column{};
    side_column.mask = LVCF_WIDTH;
    side_column.cx = CloudOS::Scale(210, dpi_);
    ListView_InsertColumn(sidebar_, 0, &side_column);

    ListView_SetExtendedListViewStyle(list_, LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP | LVS_EX_BORDERSELECT);
    ListView_SetBkColor(list_, kSurface);
    ListView_SetTextBkColor(list_, kSurface);
    ListView_SetTextColor(list_, kText);
    ListView_SetIconSpacing(list_, CloudOS::Scale(136, dpi_), CloudOS::Scale(98, dpi_));

    SHFILEINFOW info{};
    const DWORD_PTR shared_small = SHGetFileInfoW(
        L"C:\\", FILE_ATTRIBUTE_DIRECTORY, &info, sizeof(info),
        SHGFI_SYSICONINDEX | SHGFI_SMALLICON | SHGFI_USEFILEATTRIBUTES);
    if (shared_small != 0)
    {
        system_small_image_list_ = reinterpret_cast<HIMAGELIST>(shared_small);
        ListView_SetImageList(sidebar_, system_small_image_list_, LVSIL_SMALL);
    }
    const DWORD_PTR shared_large = SHGetFileInfoW(
        L"C:\\", FILE_ATTRIBUTE_DIRECTORY, &info, sizeof(info),
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
    std::wstring ignored;
    (void)CloudOS::NativeCloudOSDrive::EnsureReady(&ignored);

    const auto add = [this](const wchar_t* label, std::wstring path, SHSTOCKICONID icon)
    {
        if (path.empty()) return;
        SidebarItem item{};
        item.label = label;
        item.path = std::move(path);
        item.image_index = StockIconIndex(icon);
        sidebar_items_.push_back(std::move(item));
    };
    add(L"Início", KnownFolderPath(FOLDERID_Profile), SIID_FOLDER);
    add(L"Área de Trabalho", KnownFolderPath(FOLDERID_Desktop), SIID_FOLDER);
    add(L"Documentos", KnownFolderPath(FOLDERID_Documents), SIID_FOLDER);
    add(L"Downloads", KnownFolderPath(FOLDERID_Downloads), SIID_FOLDER);
    add(L"CloudOS Drive", CloudOS::NativeCloudOSDrive::Root(), SIID_FOLDER);
    add(L"Projetos", CloudOS::NativeCloudOSDrive::ProjectsRoot(), SIID_FOLDER);
    add(L"WSL / Linux", L"\\\\wsl.localhost\\", SIID_APPLICATION);
    add(L"Disco do Sistema", CloudOS::NativeShellPlatform::WindowsVolumeRoot(), SIID_DRIVEFIXED);
    SidebarItem trash{};
    trash.label = L"Lixeira do CloudOS";
    trash.opens_trash = true;
    trash.image_index = StockIconIndex(SIID_RECYCLER);
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
    if (window_ == nullptr) return;
    RECT client{};
    if (!GetClientRect(window_, &client)) return;

    const int width = std::max(1, static_cast<int>(client.right - client.left));
    const int height = std::max(1, static_cast<int>(client.bottom - client.top));
    const int side = CloudOS::Scale(225, dpi_);
    const int margin = CloudOS::Scale(12, dpi_);
    const int gap = CloudOS::Scale(8, dpi_);
    const int row = CloudOS::Scale(36, dpi_);
    const int nav_button_width = CloudOS::Scale(36, dpi_);
    const int status_height = CloudOS::Scale(28, dpi_);

    MoveWindow(sidebar_, 0, 0, side, height, TRUE);
    int x = side + margin;
    const int top = margin;
    MoveWindow(back_button_, x, top, nav_button_width, row, TRUE); x += nav_button_width + gap;
    MoveWindow(forward_button_, x, top, nav_button_width, row, TRUE); x += nav_button_width + gap;
    MoveWindow(up_button_, x, top, nav_button_width, row, TRUE); x += nav_button_width + gap;
    const int go_width = CloudOS::Scale(48, dpi_);
    const int refresh_width = CloudOS::Scale(88, dpi_);
    const int path_width = std::max(CloudOS::Scale(180, dpi_), width - margin - x - go_width - refresh_width - gap * 2);
    MoveWindow(path_edit_, x, top, path_width, row, TRUE); x += path_width + gap;
    MoveWindow(go_button_, x, top, go_width, row, TRUE); x += go_width + gap;
    MoveWindow(refresh_button_, x, top, refresh_width, row, TRUE);

    x = side + margin;
    const int actions_y = top + row + gap;
    MoveWindow(new_folder_button_, x, actions_y, CloudOS::Scale(118, dpi_), row, TRUE); x += CloudOS::Scale(118, dpi_) + gap;
    MoveWindow(rename_button_, x, actions_y, CloudOS::Scale(96, dpi_), row, TRUE); x += CloudOS::Scale(96, dpi_) + gap;
    MoveWindow(delete_button_, x, actions_y, CloudOS::Scale(86, dpi_), row, TRUE);

    const int content_x = side + margin;
    const int content_y = actions_y + row + gap;
    const int content_width = std::max(1, width - content_x - margin);
    const int content_height = std::max(1, height - content_y - status_height - margin);
    MoveWindow(shell_host_, content_x, content_y, content_width, content_height, TRUE);
    MoveWindow(list_, content_x, content_y, content_width, content_height, TRUE);
    MoveWindow(status_, content_x + 4, height - status_height, content_width - 8, status_height, TRUE);
    if (shell_available_)
    {
        RECT bounds{0, 0, content_width, content_height};
        shell_view_.Resize(bounds);
    }
    ListView_SetColumnWidth(sidebar_, 0, std::max(1, side - 8));
    ListView_SetIconSpacing(list_, CloudOS::Scale(136, dpi_), CloudOS::Scale(98, dpi_));
}

void CloudOSNativeFilesWindow::UpdateStatus()
{
    std::wstring text;
    if (content_mode_ == ContentMode::CloudOSDrive)
        text = L"CloudOS Drive protegido  •  " + std::to_wstring(entries_.size()) + L" itens  •  " + current_path_;
    else if (content_mode_ == ContentMode::Shell)
        text = L"Windows Shell nativo  •  contexto, drag-and-drop e visualizações do sistema  •  " + current_path_;
    else
        text = L"Compatibilidade Win32  •  " + std::to_wstring(entries_.size()) + L" itens  •  " + current_path_;
    SetWindowTextW(status_, text.c_str());
}
