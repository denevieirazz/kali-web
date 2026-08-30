#include "native_session_continuity_window.h"

#include "native_session_continuity_service.h"
#include "native_theme.h"
#include "native_window_manager.h"
#include "native_workspace_automation.h"
#include "native_workspace_labels.h"
#include "native_workspace_studio_service.h"

#include <commctrl.h>
#include <uxtheme.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <string>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "uxtheme.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kWindowClass[] = L"CloudOS.NativeShell.SessionContinuity.Center.v3";
constexpr int kWindowWidthDip = 1120;
constexpr int kWindowHeightDip = 760;
constexpr int kNavBase = 13100;
constexpr int kListId = 13110;
constexpr int kPrimaryId = 13111;
constexpr int kSecondaryId = 13112;
constexpr int kClearId = 13113;
constexpr int kEnabledId = 13120;
constexpr int kAutoCheckpointId = 13121;
constexpr int kRestoreUncleanId = 13122;
constexpr int kRestoreWorkspaceId = 13123;
constexpr int kFocusHistoryId = 13124;
constexpr int kIntervalId = 13125;
constexpr int kRetentionId = 13126;

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

std::wstring ReadText(HWND control)
{
    if (control == nullptr)
    {
        return {};
    }
    const int length = GetWindowTextLengthW(control);
    if (length <= 0)
    {
        return {};
    }
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(control, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return value;
}

void SetCheck(HWND control, bool checked)
{
    if (control != nullptr)
    {
        SendMessageW(control, BM_SETCHECK, checked ? BST_CHECKED : BST_UNCHECKED, 0);
    }
}

bool Checked(HWND control)
{
    return control != nullptr && SendMessageW(control, BM_GETCHECK, 0, 0) == BST_CHECKED;
}

std::uint32_t ReadUInt(HWND control, std::uint32_t fallback)
{
    const std::wstring text = ReadText(control);
    if (text.empty())
    {
        return fallback;
    }
    wchar_t* end = nullptr;
    const unsigned long value = std::wcstoul(text.c_str(), &end, 10);
    return end == text.c_str() ? fallback : static_cast<std::uint32_t>(value);
}

void ClearColumns(HWND list)
{
    if (list == nullptr)
    {
        return;
    }
    while (Header_GetItemCount(ListView_GetHeader(list)) > 0)
    {
        ListView_DeleteColumn(list, 0);
    }
}

void AddColumn(HWND list, int index, const wchar_t* title, int width)
{
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    column.iSubItem = index;
    column.cx = width;
    column.pszText = const_cast<LPWSTR>(title);
    ListView_InsertColumn(list, index, &column);
}

void SetItemText(HWND list, int row, int column, const std::wstring& text)
{
    ListView_SetItemText(
        list,
        row,
        column,
        const_cast<LPWSTR>(text.c_str()));
}

std::wstring ShowCommandText(UINT command)
{
    if (command == SW_SHOWMAXIMIZED || command == SW_MAXIMIZE)
    {
        return L"Maximizada";
    }
    if (command == SW_SHOWMINIMIZED || command == SW_MINIMIZE || command == SW_SHOWMINNOACTIVE)
    {
        return L"Minimizada";
    }
    return L"Normal";
}
}

NativeSessionContinuityWindow::~NativeSessionContinuityWindow()
{
    Destroy();
}

bool NativeSessionContinuityWindow::Create(
    HINSTANCE instance,
    NativeSessionContinuityService* service)
{
    Destroy();
    if (instance == nullptr || service == nullptr)
    {
        return false;
    }
    instance_ = instance;
    service_ = service;

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &NativeSessionContinuityWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kWindowClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kWindowClass,
        L"Central de Continuidade - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        kWindowWidthDip,
        kWindowHeightDip,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    const UINT dpi = GetDpiForWindow(window_);
    font_ = CreateFontW(
        -Scale(13, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    small_font_ = CreateFontW(
        -Scale(10, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(22, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    background_ = CreateSolidBrush(WebSkin::BgPrimary);

    CreateControls();
    ApplyWebWindowMaterial(window_);
    SetPage(Page::Session);
    ShowWindow(window_, SW_HIDE);
    return true;
}

void NativeSessionContinuityWindow::CreateControls()
{
    static constexpr std::array<const wchar_t*, 4> nav_titles{
        L"Sessão",
        L"Checkpoints",
        L"Journal",
        L"Preferências",
    };
    for (std::size_t index = 0; index < nav_buttons_.size(); ++index)
    {
        nav_buttons_[index] = CreateWindowW(
            L"BUTTON",
            nav_titles[index],
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
            0, 0, 0, 0,
            window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNavBase + static_cast<int>(index))),
            instance_,
            nullptr);
        WebSkin::PrepareButton(nav_buttons_[index]);
    }

    title_label_ = CreateWindowW(
        L"STATIC", L"Session Continuity V3",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    subtitle_label_ = CreateWindowW(
        L"STATIC", L"Checkpoints transacionais, recuperação e histórico do shell.",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    status_label_ = CreateWindowW(
        L"STATIC", L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    list_ = CreateWindowExW(
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP |
            LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP | LVS_EX_GRIDLINES);
    ListView_SetBkColor(list_, WebSkin::BgSecondary);
    ListView_SetTextBkColor(list_, WebSkin::BgSecondary);
    ListView_SetTextColor(list_, WebSkin::TextPrimary);
    SetWindowTheme(list_, L"DarkMode_Explorer", nullptr);

    primary_button_ = CreateWindowW(
        L"BUTTON", L"Salvar agora",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPrimaryId)), instance_, nullptr);
    secondary_button_ = CreateWindowW(
        L"BUTTON", L"Restaurar último",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSecondaryId)), instance_, nullptr);
    clear_button_ = CreateWindowW(
        L"BUTTON", L"Workspace Studio",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kClearId)), instance_, nullptr);
    for (HWND button : {primary_button_, secondary_button_, clear_button_})
    {
        WebSkin::PrepareButton(button);
    }

    enabled_check_ = CreateWindowW(
        L"BUTTON", L"Ativar Session Continuity",
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEnabledId)), instance_, nullptr);
    auto_checkpoint_check_ = CreateWindowW(
        L"BUTTON", L"Criar checkpoints automáticos quando o estado mudar",
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kAutoCheckpointId)), instance_, nullptr);
    restore_unclean_check_ = CreateWindowW(
        L"BUTTON", L"Reaplicar último checkpoint após sessão interrompida",
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRestoreUncleanId)), instance_, nullptr);
    restore_workspace_check_ = CreateWindowW(
        L"BUTTON", L"Retomar a última área de trabalho ativa",
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRestoreWorkspaceId)), instance_, nullptr);
    focus_history_check_ = CreateWindowW(
        L"BUTTON", L"Registrar mudanças de foco no journal",
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFocusHistoryId)), instance_, nullptr);

    interval_label_ = CreateWindowW(
        L"STATIC", L"Intervalo mínimo de autosave (segundos)",
        WS_CHILD | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    retention_label_ = CreateWindowW(
        L"STATIC", L"Checkpoints mantidos por área",
        WS_CHILD | SS_LEFT | SS_NOPREFIX,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    interval_edit_ = CreateWindowExW(
        0, L"EDIT", L"20",
        WS_CHILD | WS_TABSTOP | ES_NUMBER | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIntervalId)), instance_, nullptr);
    retention_edit_ = CreateWindowExW(
        0, L"EDIT", L"8",
        WS_CHILD | WS_TABSTOP | ES_NUMBER | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRetentionId)), instance_, nullptr);
    WebSkin::PrepareEdit(interval_edit_);
    WebSkin::PrepareEdit(retention_edit_);

    for (HWND control : {
             title_label_, subtitle_label_, status_label_, list_, primary_button_, secondary_button_, clear_button_,
             enabled_check_, auto_checkpoint_check_, restore_unclean_check_, restore_workspace_check_,
             focus_history_check_, interval_label_, retention_label_, interval_edit_, retention_edit_})
    {
        SetControlFont(control, font_);
    }
    for (HWND button : nav_buttons_)
    {
        SetControlFont(button, font_);
    }
    SetControlFont(title_label_, title_font_);
    SetControlFont(subtitle_label_, small_font_);
    SetControlFont(status_label_, small_font_);
}

void NativeSessionContinuityWindow::Destroy() noexcept
{
    if (window_ != nullptr && IsWindow(window_))
    {
        DestroyWindow(window_);
    }
    window_ = nullptr;
    nav_buttons_.fill(nullptr);
    title_label_ = nullptr;
    subtitle_label_ = nullptr;
    status_label_ = nullptr;
    list_ = nullptr;
    primary_button_ = nullptr;
    secondary_button_ = nullptr;
    clear_button_ = nullptr;
    enabled_check_ = nullptr;
    auto_checkpoint_check_ = nullptr;
    restore_unclean_check_ = nullptr;
    restore_workspace_check_ = nullptr;
    focus_history_check_ = nullptr;
    interval_edit_ = nullptr;
    retention_edit_ = nullptr;
    interval_label_ = nullptr;
    retention_label_ = nullptr;
    service_ = nullptr;

    for (HFONT* font : {&font_, &small_font_, &title_font_})
    {
        if (*font != nullptr)
        {
            DeleteObject(*font);
            *font = nullptr;
        }
    }
    if (background_ != nullptr)
    {
        DeleteObject(background_);
        background_ = nullptr;
    }
}

bool NativeSessionContinuityWindow::Visible() const noexcept
{
    return window_ != nullptr && IsWindow(window_) && IsWindowVisible(window_);
}

void NativeSessionContinuityWindow::Show(HWND owner)
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT work{};
    HMONITOR monitor = MonitorFromWindow(
        owner != nullptr ? owner : window_,
        MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        work = info.rcWork;
    }
    else
    {
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    }
    RECT bounds{};
    GetWindowRect(window_, &bounds);
    const int width = std::max<int>(720, bounds.right - bounds.left);
    const int height = std::max<int>(520, bounds.bottom - bounds.top);
    const int x = work.left + std::max<int>(0, (work.right - work.left - width) / 2);
    const int y = work.top + std::max<int>(0, (work.bottom - work.top - height) / 2);
    SetWindowPos(window_, HWND_TOP, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOW);
    SetForegroundWindow(window_);
    Refresh();
}

void NativeSessionContinuityWindow::Hide()
{
    if (window_ != nullptr)
    {
        ShowWindow(window_, SW_HIDE);
    }
}

void NativeSessionContinuityWindow::Toggle(HWND owner)
{
    Visible() ? Hide() : Show(owner);
}

void NativeSessionContinuityWindow::SetPage(Page page)
{
    page_ = page;
    const bool preferences = page_ == Page::Preferences;
    ShowWindow(list_, preferences ? SW_HIDE : SW_SHOW);
    for (HWND control : {
             enabled_check_, auto_checkpoint_check_, restore_unclean_check_, restore_workspace_check_,
             focus_history_check_, interval_label_, retention_label_, interval_edit_, retention_edit_})
    {
        ShowWindow(control, preferences ? SW_SHOW : SW_HIDE);
    }

    switch (page_)
    {
    case Page::Session:
        SetWindowTextW(primary_button_, L"Salvar agora");
        SetWindowTextW(secondary_button_, L"Restaurar último");
        SetWindowTextW(clear_button_, L"Workspace Studio");
        break;
    case Page::Checkpoints:
        SetWindowTextW(primary_button_, L"Restaurar selecionado");
        SetWindowTextW(secondary_button_, L"Capturar estado atual");
        SetWindowTextW(clear_button_, L"Excluir checkpoints");
        break;
    case Page::Journal:
        SetWindowTextW(primary_button_, L"Salvar agora");
        SetWindowTextW(secondary_button_, L"Checkpoint atual");
        SetWindowTextW(clear_button_, L"Limpar journal");
        break;
    case Page::Preferences:
        SetWindowTextW(primary_button_, L"Salvar preferências");
        SetWindowTextW(secondary_button_, L"Salvar + checkpoint");
        SetWindowTextW(clear_button_, L"Restaurar padrões");
        break;
    }
    Layout();
    Refresh();
    InvalidateRect(window_, nullptr, FALSE);
}

void NativeSessionContinuityWindow::Refresh()
{
    if (window_ == nullptr || service_ == nullptr)
    {
        return;
    }
    RefreshHeader();
    switch (page_)
    {
    case Page::Session: RefreshSession(); break;
    case Page::Checkpoints: RefreshCheckpoints(); break;
    case Page::Journal: RefreshJournal(); break;
    case Page::Preferences: RefreshPreferences(); break;
    }
}

void NativeSessionContinuityWindow::RefreshHeader()
{
    const auto& store = service_->Store();
    const int workspace = service_->Manager() != nullptr
        ? service_->Manager()->CurrentWorkspace()
        : store.LastWorkspace();
    std::wstring status = NativeWorkspaceLabels::StatusText(workspace);
    status += L"   •   ";
    status += std::to_wstring(store.Checkpoints().size()) + L" checkpoints";
    status += L"   •   ";
    status += std::to_wstring(store.Journal().size()) + L" eventos";
    if (service_->PreviousSessionUnclean())
    {
        status += L"   •   sessão anterior interrompida";
    }
    SetWindowTextW(status_label_, status.c_str());
}

void NativeSessionContinuityWindow::RefreshSession()
{
    ListView_DeleteAllItems(list_);
    ClearColumns(list_);
    const UINT dpi = GetDpiForWindow(window_);
    AddColumn(list_, 0, L"Área", Scale(160, dpi));
    AddColumn(list_, 1, L"Janela", Scale(390, dpi));
    AddColumn(list_, 2, L"Processo", Scale(180, dpi));
    AddColumn(list_, 3, L"Modo", Scale(110, dpi));
    AddColumn(list_, 4, L"Estado", Scale(110, dpi));

    CloudOSNativeWindowManager* manager = service_->Manager();
    if (manager == nullptr)
    {
        return;
    }
    manager->Reconcile();
    const auto windows = manager->AllManagedWindows();
    int row = 0;
    for (const auto& item : windows)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }
        const WorkspaceWindowIdentity identity =
            NativeWorkspaceAutomationEngine::IdentifyWindow(item.hwnd, item.process_id);
        LVITEMW entry{};
        entry.mask = LVIF_TEXT | LVIF_PARAM;
        entry.iItem = row;
        std::wstring workspace = NativeWorkspaceLabels::NumberedName(item.workspace);
        entry.pszText = const_cast<LPWSTR>(workspace.c_str());
        entry.lParam = reinterpret_cast<LPARAM>(item.hwnd);
        const int inserted = ListView_InsertItem(list_, &entry);
        if (inserted < 0)
        {
            continue;
        }
        SetItemText(list_, inserted, 1, item.title.empty() ? identity.window_title : item.title);
        SetItemText(list_, inserted, 2, identity.process_name.empty() ? L"CloudOS" : identity.process_name);
        SetItemText(list_, inserted, 3, item.floating ? L"Flutuante" : L"Gerenciada");
        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        const UINT show = GetWindowPlacement(item.hwnd, &placement) ? placement.showCmd : SW_SHOWNORMAL;
        SetItemText(list_, inserted, 4, ShowCommandText(show));
        ++row;
    }
}

void NativeSessionContinuityWindow::RefreshCheckpoints()
{
    const int selected = SelectedRow();
    std::uint32_t selected_id = selected >= 0 ? SelectedCheckpointId() : 0u;
    ListView_DeleteAllItems(list_);
    ClearColumns(list_);
    const UINT dpi = GetDpiForWindow(window_);
    AddColumn(list_, 0, L"ID", Scale(70, dpi));
    AddColumn(list_, 1, L"Criado", Scale(170, dpi));
    AddColumn(list_, 2, L"Área", Scale(180, dpi));
    AddColumn(list_, 3, L"Motivo", Scale(360, dpi));
    AddColumn(list_, 4, L"Janelas", Scale(90, dpi));

    int row = 0;
    for (auto iterator = service_->Store().Checkpoints().rbegin();
         iterator != service_->Store().Checkpoints().rend();
         ++iterator)
    {
        const ContinuityCheckpoint& checkpoint = *iterator;
        std::wstring id = L"#" + std::to_wstring(checkpoint.id);
        LVITEMW entry{};
        entry.mask = LVIF_TEXT | LVIF_PARAM;
        entry.iItem = row;
        entry.pszText = const_cast<LPWSTR>(id.c_str());
        entry.lParam = static_cast<LPARAM>(checkpoint.id);
        const int inserted = ListView_InsertItem(list_, &entry);
        if (inserted < 0)
        {
            continue;
        }
        SetItemText(list_, inserted, 1, ContinuityFileTimeText(checkpoint.created_filetime));
        SetItemText(list_, inserted, 2, NativeWorkspaceLabels::NumberedName(checkpoint.workspace));
        SetItemText(list_, inserted, 3, checkpoint.reason);
        SetItemText(list_, inserted, 4, std::to_wstring(checkpoint.windows.size()));
        if (checkpoint.id == selected_id)
        {
            ListView_SetItemState(list_, inserted, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
        }
        ++row;
    }
}

void NativeSessionContinuityWindow::RefreshJournal()
{
    ListView_DeleteAllItems(list_);
    ClearColumns(list_);
    const UINT dpi = GetDpiForWindow(window_);
    AddColumn(list_, 0, L"Quando", Scale(170, dpi));
    AddColumn(list_, 1, L"Evento", Scale(190, dpi));
    AddColumn(list_, 2, L"Área", Scale(150, dpi));
    AddColumn(list_, 3, L"Título", Scale(260, dpi));
    AddColumn(list_, 4, L"Detalhe", Scale(330, dpi));

    int row = 0;
    for (auto iterator = service_->Store().Journal().rbegin();
         iterator != service_->Store().Journal().rend() && row < 250;
         ++iterator, ++row)
    {
        const ContinuityJournalEvent& event = *iterator;
        std::wstring when = ContinuityFileTimeText(event.created_filetime);
        LVITEMW entry{};
        entry.mask = LVIF_TEXT | LVIF_PARAM;
        entry.iItem = row;
        entry.pszText = const_cast<LPWSTR>(when.c_str());
        entry.lParam = static_cast<LPARAM>(event.sequence);
        const int inserted = ListView_InsertItem(list_, &entry);
        if (inserted < 0)
        {
            continue;
        }
        SetItemText(list_, inserted, 1, ContinuityEventKindName(event.kind));
        SetItemText(list_, inserted, 2, NativeWorkspaceLabels::CompactName(event.workspace, 14u));
        SetItemText(list_, inserted, 3, event.title);
        SetItemText(list_, inserted, 4, event.detail);
    }
}

void NativeSessionContinuityWindow::RefreshPreferences()
{
    const ContinuityPreferences& preferences = service_->Store().Preferences();
    SetCheck(enabled_check_, preferences.enabled);
    SetCheck(auto_checkpoint_check_, preferences.auto_checkpoint);
    SetCheck(restore_unclean_check_, preferences.restore_after_unclean);
    SetCheck(restore_workspace_check_, preferences.restore_last_workspace);
    SetCheck(focus_history_check_, preferences.record_focus_history);
    SetWindowTextW(interval_edit_, std::to_wstring(preferences.checkpoint_interval_seconds).c_str());
    SetWindowTextW(retention_edit_, std::to_wstring(preferences.retention_per_workspace).c_str());
}

void NativeSessionContinuityWindow::SavePreferences()
{
    ContinuityPreferences& preferences = service_->Store().Preferences();
    preferences.enabled = Checked(enabled_check_);
    preferences.auto_checkpoint = Checked(auto_checkpoint_check_);
    preferences.restore_after_unclean = Checked(restore_unclean_check_);
    preferences.restore_last_workspace = Checked(restore_workspace_check_);
    preferences.record_focus_history = Checked(focus_history_check_);
    preferences.checkpoint_interval_seconds = std::clamp<std::uint32_t>(
        ReadUInt(interval_edit_, preferences.checkpoint_interval_seconds), 5u, 3600u);
    preferences.retention_per_workspace = std::clamp<std::uint32_t>(
        ReadUInt(retention_edit_, preferences.retention_per_workspace), 1u, 32u);
    service_->PreferencesChanged();
}

int NativeSessionContinuityWindow::SelectedRow() const
{
    return list_ != nullptr
        ? ListView_GetNextItem(list_, -1, LVNI_SELECTED)
        : -1;
}

std::uint32_t NativeSessionContinuityWindow::SelectedCheckpointId() const
{
    const int row = SelectedRow();
    if (row < 0)
    {
        return 0u;
    }
    LVITEMW item{};
    item.mask = LVIF_PARAM;
    item.iItem = row;
    return ListView_GetItem(list_, &item)
        ? static_cast<std::uint32_t>(item.lParam)
        : 0u;
}

void NativeSessionContinuityWindow::RestoreSelectedCheckpoint()
{
    const std::uint32_t id = SelectedCheckpointId();
    if (id != 0u)
    {
        (void)service_->RestoreCheckpoint(id);
    }
}

void NativeSessionContinuityWindow::CaptureCurrentCheckpoint()
{
    CloudOSNativeWindowManager* manager = service_->Manager();
    if (manager != nullptr)
    {
        (void)service_->CaptureCheckpoint(manager->CurrentWorkspace(), L"captura manual");
    }
}

void NativeSessionContinuityWindow::FocusSelectedWindow()
{
    if (page_ != Page::Session || service_->Manager() == nullptr)
    {
        return;
    }
    const int row = SelectedRow();
    if (row < 0)
    {
        return;
    }
    LVITEMW item{};
    item.mask = LVIF_PARAM;
    item.iItem = row;
    if (!ListView_GetItem(list_, &item))
    {
        return;
    }
    HWND target = reinterpret_cast<HWND>(item.lParam);
    const int workspace = service_->Manager()->WorkspaceFor(target);
    if (workspace >= 0 && workspace != service_->Manager()->CurrentWorkspace())
    {
        service_->Manager()->SwitchWorkspace(workspace);
    }
    service_->Manager()->FocusWindow(target);
}

void NativeSessionContinuityWindow::ClearCurrentPage()
{
    switch (page_)
    {
    case Page::Session:
        NativeWorkspaceStudioService::Open(instance_, window_);
        break;
    case Page::Checkpoints:
        if (MessageBoxW(
                window_,
                L"Excluir todos os checkpoints do Session Continuity?",
                L"CloudOS",
                MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES)
        {
            service_->ClearCheckpoints();
        }
        break;
    case Page::Journal:
        if (MessageBoxW(
                window_,
                L"Limpar o journal de continuidade?",
                L"CloudOS",
                MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES)
        {
            service_->ClearJournal();
        }
        break;
    case Page::Preferences:
        service_->Store().Preferences() = ContinuityPreferences{};
        service_->PreferencesChanged();
        RefreshPreferences();
        break;
    }
}

void NativeSessionContinuityWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(24, dpi);
    const int nav_width = Scale(156, dpi);
    const int nav_height = Scale(42, dpi);
    const int nav_gap = Scale(8, dpi);
    int nav_y = Scale(122, dpi);
    for (HWND button : nav_buttons_)
    {
        MoveWindow(button, margin, nav_y, nav_width, nav_height, TRUE);
        nav_y += nav_height + nav_gap;
    }

    const int content_left = margin + nav_width + Scale(28, dpi);
    const int content_right = std::max<int>(content_left + Scale(300, dpi), client.right - margin);
    const int content_width = std::max<int>(300, content_right - content_left);
    MoveWindow(title_label_, content_left, Scale(22, dpi), content_width, Scale(38, dpi), TRUE);
    MoveWindow(subtitle_label_, content_left, Scale(62, dpi), content_width, Scale(26, dpi), TRUE);
    MoveWindow(status_label_, content_left, Scale(92, dpi), content_width, Scale(24, dpi), TRUE);

    const int button_height = Scale(40, dpi);
    const int button_gap = Scale(10, dpi);
    const int button_width = Scale(174, dpi);
    const int actions_y = std::max<int>(Scale(510, dpi), client.bottom - margin - button_height);
    MoveWindow(primary_button_, content_left, actions_y, button_width, button_height, TRUE);
    MoveWindow(secondary_button_, content_left + button_width + button_gap, actions_y, button_width, button_height, TRUE);
    MoveWindow(clear_button_, content_left + (button_width + button_gap) * 2, actions_y, button_width, button_height, TRUE);

    const int body_top = Scale(126, dpi);
    const int body_bottom = actions_y - Scale(14, dpi);
    MoveWindow(list_, content_left, body_top, content_width, std::max<int>(120, body_bottom - body_top), TRUE);

    const int check_height = Scale(34, dpi);
    int pref_y = body_top + Scale(8, dpi);
    for (HWND check : {
             enabled_check_, auto_checkpoint_check_, restore_unclean_check_,
             restore_workspace_check_, focus_history_check_})
    {
        MoveWindow(check, content_left + Scale(4, dpi), pref_y, content_width - Scale(8, dpi), check_height, TRUE);
        pref_y += check_height + Scale(8, dpi);
    }
    pref_y += Scale(12, dpi);
    const int label_width = Scale(330, dpi);
    const int edit_width = Scale(120, dpi);
    MoveWindow(interval_label_, content_left + Scale(4, dpi), pref_y, label_width, check_height, TRUE);
    MoveWindow(interval_edit_, content_left + label_width + Scale(12, dpi), pref_y, edit_width, check_height, TRUE);
    pref_y += check_height + Scale(14, dpi);
    MoveWindow(retention_label_, content_left + Scale(4, dpi), pref_y, label_width, check_height, TRUE);
    MoveWindow(retention_edit_, content_left + label_width + Scale(12, dpi), pref_y, edit_width, check_height, TRUE);
}

void NativeSessionContinuityWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, background_);

    RECT sidebar = client;
    sidebar.right = Scale(204, GetDpiForWindow(window_));
    HBRUSH sidebar_brush = CreateSolidBrush(WebSkin::BgSecondary);
    FillRect(dc, &sidebar, sidebar_brush);
    DeleteObject(sidebar_brush);

    HPEN pen = CreatePen(PS_SOLID, 1, WebSkin::BorderDefault);
    HGDIOBJ old_pen = SelectObject(dc, pen);
    MoveToEx(dc, sidebar.right, 0, nullptr);
    LineTo(dc, sidebar.right, client.bottom);
    SelectObject(dc, old_pen);
    DeleteObject(pen);
    EndPaint(window_, &paint);
}

void NativeSessionContinuityWindow::DrawOwnerButton(const DRAWITEMSTRUCT& item)
{
    const bool selected_nav = item.CtlID >= kNavBase && item.CtlID < kNavBase + 4 &&
        static_cast<int>(page_) == static_cast<int>(item.CtlID - kNavBase);
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const COLORREF fill = selected_nav
        ? WebSkin::BgActive
        : pressed ? WebSkin::BgHover : WebSkin::BgTertiary;
    const COLORREF border = selected_nav ? WebSkin::Accent : WebSkin::BorderDefault;

    HBRUSH brush = CreateSolidBrush(fill);
    FillRect(item.hDC, &item.rcItem, brush);
    DeleteObject(brush);
    HPEN pen = CreatePen(PS_SOLID, selected_nav ? 2 : 1, border);
    HGDIOBJ old_pen = SelectObject(item.hDC, pen);
    HGDIOBJ old_brush = SelectObject(item.hDC, GetStockObject(NULL_BRUSH));
    Rectangle(item.hDC, item.rcItem.left, item.rcItem.top, item.rcItem.right, item.rcItem.bottom);
    SelectObject(item.hDC, old_brush);
    SelectObject(item.hDC, old_pen);
    DeleteObject(pen);

    wchar_t text[128]{};
    GetWindowTextW(item.hwndItem, text, static_cast<int>(std::size(text)));
    HFONT font = reinterpret_cast<HFONT>(SendMessageW(item.hwndItem, WM_GETFONT, 0, 0));
    HGDIOBJ old_font = font != nullptr ? SelectObject(item.hDC, font) : nullptr;
    SetBkMode(item.hDC, TRANSPARENT);
    SetTextColor(item.hDC, disabled ? WebSkin::TextTertiary : WebSkin::TextPrimary);
    RECT text_rect = item.rcItem;
    DrawTextW(item.hDC, text, -1, &text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    if (old_font != nullptr)
    {
        SelectObject(item.hDC, old_font);
    }
}

LRESULT CALLBACK NativeSessionContinuityWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeSessionContinuityWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(l_param);
        self = static_cast<NativeSessionContinuityWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}

LRESULT NativeSessionContinuityWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_COMMAND:
    {
        const int id = LOWORD(w_param);
        if (id >= kNavBase && id < kNavBase + 4)
        {
            SetPage(static_cast<Page>(id - kNavBase));
            return 0;
        }
        if (id == kPrimaryId)
        {
            switch (page_)
            {
            case Page::Session: (void)service_->SaveNow(L"Central de Continuidade"); break;
            case Page::Checkpoints: RestoreSelectedCheckpoint(); break;
            case Page::Journal: (void)service_->SaveNow(L"Central de Continuidade"); break;
            case Page::Preferences: SavePreferences(); break;
            }
            Refresh();
            return 0;
        }
        if (id == kSecondaryId)
        {
            switch (page_)
            {
            case Page::Session:
                if (service_->Manager() != nullptr)
                {
                    (void)service_->RestoreLatest(service_->Manager()->CurrentWorkspace());
                }
                break;
            case Page::Checkpoints: CaptureCurrentCheckpoint(); break;
            case Page::Journal: CaptureCurrentCheckpoint(); break;
            case Page::Preferences:
                SavePreferences();
                (void)service_->SaveNow(L"preferências + checkpoint");
                break;
            }
            Refresh();
            return 0;
        }
        if (id == kClearId)
        {
            ClearCurrentPage();
            Refresh();
            return 0;
        }
        break;
    }
    case WM_NOTIFY:
        if (reinterpret_cast<NMHDR*>(l_param)->hwndFrom == list_ &&
            reinterpret_cast<NMHDR*>(l_param)->code == NM_DBLCLK)
        {
            if (page_ == Page::Session)
            {
                FocusSelectedWindow();
            }
            else if (page_ == Page::Checkpoints)
            {
                RestoreSelectedCheckpoint();
            }
            return 0;
        }
        break;
    case WM_DRAWITEM:
        DrawOwnerButton(*reinterpret_cast<DRAWITEMSTRUCT*>(l_param));
        return TRUE;
    case WM_SIZE:
        Layout();
        return 0;
    case WM_PAINT:
        Paint();
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_CLOSE:
        Hide();
        return 0;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE)
        {
            Hide();
            return 0;
        }
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0 && w_param == 'S')
        {
            (void)service_->SaveNow(L"Ctrl+S");
            return 0;
        }
        break;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        window_ = nullptr;
        return DefWindowProcW(window, message, w_param, l_param);
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
