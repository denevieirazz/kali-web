#include "native_workspace_studio_window.h"

#include "native_theme.h"
#include "native_workspace_studio_service.h"
#include "native_window_manager.h"

#include <commdlg.h>

#include <algorithm>
#include <array>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kWindowClass[] = L"CloudOS.NativeShell.WorkspaceStudio.v2";
constexpr int kIdTabs = 2100;
constexpr int kIdWorkspace = 2101;
constexpr int kIdProfileSave = 2110;
constexpr int kIdProfileApply = 2111;
constexpr int kIdWallpaperChoose = 2112;
constexpr int kIdRuleAdd = 2120;
constexpr int kIdRuleDelete = 2121;
constexpr int kIdRuleToggle = 2122;
constexpr int kIdRuleReapply = 2123;
constexpr int kIdLayoutCapture = 2130;
constexpr int kIdLayoutRestore = 2131;
constexpr int kIdLayoutDelete = 2132;
constexpr int kIdLayoutApplyPreset = 2133;
constexpr int kIdStartupAdd = 2140;
constexpr int kIdStartupDelete = 2141;
constexpr int kIdStartupRun = 2142;
constexpr int kIdActivityFocus = 2150;
constexpr int kIdActivityClear = 2151;
constexpr int kIdRefresh = 2160;

HWND MakeControl(
    HWND parent,
    const wchar_t* class_name,
    const wchar_t* text,
    DWORD style,
    DWORD ex_style = 0,
    int id = 0)
{
    return CreateWindowExW(
        ex_style,
        class_name,
        text,
        WS_CHILD | WS_VISIBLE | style,
        0,
        0,
        100,
        28,
        parent,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        GetModuleHandleW(nullptr),
        nullptr);
}

void AddComboItem(HWND combo, const std::wstring& text)
{
    SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text.c_str()));
}

void SetupList(HWND list, std::initializer_list<std::pair<const wchar_t*, int>> columns)
{
    if (list == nullptr)
    {
        return;
    }
    ListView_SetExtendedListViewStyle(
        list,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_GRIDLINES | LVS_EX_LABELTIP);
    int index = 0;
    for (const auto& column : columns)
    {
        LVCOLUMNW value{};
        value.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
        value.pszText = const_cast<wchar_t*>(column.first);
        value.cx = column.second;
        value.iSubItem = index;
        ListView_InsertColumn(list, index, &value);
        ++index;
    }
    WebSkin::PrepareListView(list);
}

void SetListCell(HWND list, int row, int column, const std::wstring& text)
{
    LVITEMW item{};
    item.mask = LVIF_TEXT;
    item.iItem = row;
    item.iSubItem = column;
    item.pszText = const_cast<wchar_t*>(text.c_str());
    if (column == 0)
    {
        ListView_InsertItem(list, &item);
    }
    else
    {
        ListView_SetItem(list, &item);
    }
}

void SetListId(HWND list, int row, LPARAM id)
{
    LVITEMW item{};
    item.mask = LVIF_PARAM;
    item.iItem = row;
    item.lParam = id;
    ListView_SetItem(list, &item);
}

LPARAM ListId(HWND list, int row)
{
    if (row < 0)
    {
        return 0;
    }
    LVITEMW item{};
    item.mask = LVIF_PARAM;
    item.iItem = row;
    return ListView_GetItem(list, &item) ? item.lParam : 0;
}

std::wstring BoolText(bool value)
{
    return value ? L"Sim" : L"Não";
}

std::wstring FormatTimestamp(std::uint64_t raw)
{
    if (raw == 0)
    {
        return L"-";
    }
    ULARGE_INTEGER value{};
    value.QuadPart = raw;
    FILETIME file_time{};
    file_time.dwLowDateTime = value.LowPart;
    file_time.dwHighDateTime = value.HighPart;
    FILETIME local{};
    SYSTEMTIME system{};
    if (!FileTimeToLocalFileTime(&file_time, &local) || !FileTimeToSystemTime(&local, &system))
    {
        return L"-";
    }
    wchar_t buffer[64]{};
    swprintf_s(
        buffer,
        L"%02u/%02u %02u:%02u",
        system.wDay,
        system.wMonth,
        system.wHour,
        system.wMinute);
    return buffer;
}
}

NativeWorkspaceStudioWindow::NativeWorkspaceStudioWindow(NativeWorkspaceStudioService* service) noexcept
    : service_(service)
{
}

NativeWorkspaceStudioWindow::~NativeWorkspaceStudioWindow()
{
    Destroy();
}

bool NativeWorkspaceStudioWindow::Create(HINSTANCE instance)
{
    if (window_ != nullptr)
    {
        return true;
    }
    instance_ = instance != nullptr ? instance : GetModuleHandleW(nullptr);

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeWorkspaceStudioWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = WebSkin::SharedBackgroundBrush();
    window_class.lpszClassName = kWindowClass;
    (void)RegisterClassExW(&window_class);

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kWindowClass,
        L"Workspace Studio - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1180,
        760,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    CreateControls();
    ApplyWebWindowMaterial(window_);
    Layout();
    RefreshAll();
    return true;
}

void NativeWorkspaceStudioWindow::Show(HWND owner)
{
    if (window_ == nullptr)
    {
        return;
    }
    if (owner != nullptr && IsWindow(owner))
    {
        SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
    }
    RefreshAll();
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
}

void NativeWorkspaceStudioWindow::Hide() noexcept
{
    if (window_ != nullptr)
    {
        ShowWindow(window_, SW_HIDE);
    }
}

void NativeWorkspaceStudioWindow::Destroy() noexcept
{
    if (window_ != nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
    }
    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (title_font_ != nullptr)
    {
        DeleteObject(title_font_);
        title_font_ = nullptr;
    }
}

void NativeWorkspaceStudioWindow::CreateControls()
{
    font_ = CreateFontW(
        -16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    title_font_ = CreateFontW(
        -28, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");

    HWND title = MakeControl(window_, L"STATIC", L"Workspace Studio", SS_LEFT);
    SendMessageW(title, WM_SETFONT, reinterpret_cast<WPARAM>(title_font_), TRUE);

    workspace_combo_ = MakeControl(window_, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL, 0, kIdWorkspace);
    MakeControl(window_, L"BUTTON", L"Atualizar", BS_PUSHBUTTON, 0, kIdRefresh);

    tabs_ = MakeControl(window_, WC_TABCONTROLW, L"", TCS_FIXEDWIDTH | TCS_FOCUSNEVER, 0, kIdTabs);
    SendMessageW(tabs_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
    const std::array<const wchar_t*, 5> tab_names{
        L"Perfis", L"Regras", L"Layouts", L"Inicialização", L"Atividade"};
    for (int index = 0; index < static_cast<int>(tab_names.size()); ++index)
    {
        TCITEMW item{};
        item.mask = TCIF_TEXT;
        item.pszText = const_cast<wchar_t*>(tab_names[static_cast<std::size_t>(index)]);
        TabCtrl_InsertItem(tabs_, index, &item);
    }

    for (auto& root : page_roots_)
    {
        root = MakeControl(window_, L"STATIC", L"", SS_NOTIFY);
    }

    HWND profiles = page_roots_[0];
    MakeControl(profiles, L"STATIC", L"Nome da área", SS_LEFT);
    profile_name_ = MakeControl(profiles, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    MakeControl(profiles, L"STATIC", L"Wallpaper deste workspace", SS_LEFT);
    profile_wallpaper_ = MakeControl(profiles, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    MakeControl(profiles, L"BUTTON", L"Escolher...", BS_PUSHBUTTON, 0, kIdWallpaperChoose);
    MakeControl(profiles, L"STATIC", L"Layout padrão", SS_LEFT);
    profile_layout_ = MakeControl(profiles, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    for (std::uint32_t value = 0; value <= static_cast<std::uint32_t>(WorkspaceLayoutPreset::Focus); ++value)
    {
        AddComboItem(profile_layout_, WorkspaceLayoutPresetName(static_cast<WorkspaceLayoutPreset>(value)));
    }
    profile_auto_tile_ = MakeControl(profiles, L"BUTTON", L"Aplicar layout automaticamente ao entrar", BS_AUTOCHECKBOX);
    profile_auto_launch_ = MakeControl(profiles, L"BUTTON", L"Executar itens de inicialização ao entrar", BS_AUTOCHECKBOX);
    profile_apply_wallpaper_ = MakeControl(profiles, L"BUTTON", L"Trocar wallpaper ao entrar", BS_AUTOCHECKBOX);
    MakeControl(profiles, L"BUTTON", L"Salvar perfil", BS_PUSHBUTTON, 0, kIdProfileSave);
    MakeControl(profiles, L"BUTTON", L"Aplicar agora", BS_PUSHBUTTON, 0, kIdProfileApply);

    HWND rules = page_roots_[1];
    rules_list_ = MakeControl(rules, WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, WS_EX_CLIENTEDGE);
    SetupList(rules_list_, {{L"On", 46}, {L"Campo", 100}, {L"Modo", 100}, {L"Padrão", 260}, {L"Área", 130}, {L"Flut.", 65}, {L"Max.", 65}});
    rule_field_ = MakeControl(rules, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    AddComboItem(rule_field_, L"Processo");
    AddComboItem(rule_field_, L"Título");
    AddComboItem(rule_field_, L"Classe Win32");
    SendMessageW(rule_field_, CB_SETCURSEL, 0, 0);
    rule_mode_ = MakeControl(rules, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    AddComboItem(rule_mode_, L"Contém");
    AddComboItem(rule_mode_, L"Exato");
    AddComboItem(rule_mode_, L"Prefixo");
    AddComboItem(rule_mode_, L"Wildcard");
    SendMessageW(rule_mode_, CB_SETCURSEL, 0, 0);
    rule_pattern_ = MakeControl(rules, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    rule_workspace_ = MakeControl(rules, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    rule_floating_ = MakeControl(rules, L"BUTTON", L"Flutuante", BS_AUTOCHECKBOX);
    rule_maximize_ = MakeControl(rules, L"BUTTON", L"Maximizar", BS_AUTOCHECKBOX);
    MakeControl(rules, L"BUTTON", L"Adicionar regra", BS_PUSHBUTTON, 0, kIdRuleAdd);
    MakeControl(rules, L"BUTTON", L"Ativar/desativar", BS_PUSHBUTTON, 0, kIdRuleToggle);
    MakeControl(rules, L"BUTTON", L"Excluir", BS_PUSHBUTTON, 0, kIdRuleDelete);
    MakeControl(rules, L"BUTTON", L"Reaplicar em todas as janelas", BS_PUSHBUTTON, 0, kIdRuleReapply);

    HWND layouts = page_roots_[2];
    layouts_list_ = MakeControl(layouts, WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, WS_EX_CLIENTEDGE);
    SetupList(layouts_list_, {{L"Nome", 260}, {L"Área", 160}, {L"Janelas", 90}, {L"Criado", 130}});
    MakeControl(layouts, L"STATIC", L"Nome do snapshot", SS_LEFT);
    layout_name_ = MakeControl(layouts, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    MakeControl(layouts, L"BUTTON", L"Capturar estado atual", BS_PUSHBUTTON, 0, kIdLayoutCapture);
    MakeControl(layouts, L"BUTTON", L"Restaurar selecionado", BS_PUSHBUTTON, 0, kIdLayoutRestore);
    MakeControl(layouts, L"BUTTON", L"Excluir snapshot", BS_PUSHBUTTON, 0, kIdLayoutDelete);
    MakeControl(layouts, L"STATIC", L"Preset instantâneo", SS_LEFT);
    layout_preset_ = MakeControl(layouts, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    for (std::uint32_t value = 0; value <= static_cast<std::uint32_t>(WorkspaceLayoutPreset::Focus); ++value)
    {
        AddComboItem(layout_preset_, WorkspaceLayoutPresetName(static_cast<WorkspaceLayoutPreset>(value)));
    }
    SendMessageW(layout_preset_, CB_SETCURSEL, 0, 0);
    MakeControl(layouts, L"BUTTON", L"Aplicar preset", BS_PUSHBUTTON, 0, kIdLayoutApplyPreset);

    HWND startup = page_roots_[3];
    startup_list_ = MakeControl(startup, WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, WS_EX_CLIENTEDGE);
    SetupList(startup_list_, {{L"On", 46}, {L"Tipo", 90}, {L"Destino", 260}, {L"Argumentos", 220}, {L"Área", 140}});
    startup_type_ = MakeControl(startup, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    AddComboItem(startup_type_, L"App CloudOS");
    AddComboItem(startup_type_, L"Programa Windows");
    SendMessageW(startup_type_, CB_SETCURSEL, 0, 0);
    startup_target_ = MakeControl(startup, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    startup_arguments_ = MakeControl(startup, L"EDIT", L"", ES_AUTOHSCROLL, WS_EX_CLIENTEDGE);
    startup_workspace_ = MakeControl(startup, L"COMBOBOX", L"", CBS_DROPDOWNLIST);
    MakeControl(startup, L"BUTTON", L"Adicionar", BS_PUSHBUTTON, 0, kIdStartupAdd);
    MakeControl(startup, L"BUTTON", L"Excluir", BS_PUSHBUTTON, 0, kIdStartupDelete);
    MakeControl(startup, L"BUTTON", L"Executar área agora", BS_PUSHBUTTON, 0, kIdStartupRun);

    HWND activity = page_roots_[4];
    activity_list_ = MakeControl(activity, WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, WS_EX_CLIENTEDGE);
    SetupList(activity_list_, {{L"Janela", 420}, {L"Processo", 160}, {L"Área", 150}, {L"Último foco", 130}});
    MakeControl(activity, L"BUTTON", L"Focar selecionada", BS_PUSHBUTTON, 0, kIdActivityFocus);
    MakeControl(activity, L"BUTTON", L"Limpar histórico", BS_PUSHBUTTON, 0, kIdActivityClear);

    status_ = MakeControl(window_, L"STATIC", L"Pronto", SS_LEFT | SS_CENTERIMAGE);

    EnumChildWindows(
        window_,
        [](HWND child, LPARAM font)
        {
            SendMessageW(child, WM_SETFONT, static_cast<WPARAM>(font), TRUE);
            return TRUE;
        },
        reinterpret_cast<LPARAM>(font_));
    SendMessageW(title, WM_SETFONT, reinterpret_cast<WPARAM>(title_font_), TRUE);

    RefreshWorkspaceCombos();
    ShowPage(Page::Profiles);
}

void NativeWorkspaceStudioWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(720L, client.right - client.left);
    const int height = std::max(520L, client.bottom - client.top);
    const int margin = 24;

    HWND title = FindWindowExW(window_, nullptr, L"STATIC", L"Workspace Studio");
    if (title != nullptr) MoveWindow(title, margin, 18, 340, 40, TRUE);
    MoveWindow(workspace_combo_, width - 330, 24, 190, 34, TRUE);
    HWND refresh = GetDlgItem(window_, kIdRefresh);
    if (refresh != nullptr) MoveWindow(refresh, width - 128, 24, 104, 34, TRUE);
    MoveWindow(tabs_, margin, 76, width - margin * 2, 38, TRUE);

    const int page_top = 122;
    const int page_height = height - page_top - 62;
    for (HWND root : page_roots_)
    {
        MoveWindow(root, margin, page_top, width - margin * 2, page_height, TRUE);
    }

    const int page_width = width - margin * 2;
    MoveWindow(profile_name_, 24, 48, page_width - 48, 32, TRUE);
    MoveWindow(profile_wallpaper_, 24, 118, page_width - 190, 32, TRUE);
    if (HWND choose = GetDlgItem(page_roots_[0], kIdWallpaperChoose)) MoveWindow(choose, page_width - 150, 118, 126, 32, TRUE);
    MoveWindow(profile_layout_, 24, 190, 260, 160, TRUE);
    MoveWindow(profile_auto_tile_, 24, 244, 350, 28, TRUE);
    MoveWindow(profile_auto_launch_, 24, 282, 380, 28, TRUE);
    MoveWindow(profile_apply_wallpaper_, 24, 320, 330, 28, TRUE);
    if (HWND save = GetDlgItem(page_roots_[0], kIdProfileSave)) MoveWindow(save, 24, 380, 140, 34, TRUE);
    if (HWND apply = GetDlgItem(page_roots_[0], kIdProfileApply)) MoveWindow(apply, 176, 380, 140, 34, TRUE);

    MoveWindow(rules_list_, 12, 12, page_width - 24, page_height - 180, TRUE);
    const int rules_y = page_height - 152;
    MoveWindow(rule_field_, 12, rules_y, 130, 140, TRUE);
    MoveWindow(rule_mode_, 152, rules_y, 120, 140, TRUE);
    MoveWindow(rule_pattern_, 282, rules_y, 260, 32, TRUE);
    MoveWindow(rule_workspace_, 552, rules_y, 150, 140, TRUE);
    MoveWindow(rule_floating_, 712, rules_y, 100, 28, TRUE);
    MoveWindow(rule_maximize_, 818, rules_y, 110, 28, TRUE);
    if (HWND add = GetDlgItem(page_roots_[1], kIdRuleAdd)) MoveWindow(add, 12, rules_y + 48, 132, 34, TRUE);
    if (HWND toggle = GetDlgItem(page_roots_[1], kIdRuleToggle)) MoveWindow(toggle, 154, rules_y + 48, 150, 34, TRUE);
    if (HWND del = GetDlgItem(page_roots_[1], kIdRuleDelete)) MoveWindow(del, 314, rules_y + 48, 100, 34, TRUE);
    if (HWND reapply = GetDlgItem(page_roots_[1], kIdRuleReapply)) MoveWindow(reapply, 424, rules_y + 48, 240, 34, TRUE);

    MoveWindow(layouts_list_, 12, 12, page_width - 24, page_height - 176, TRUE);
    const int layout_y = page_height - 148;
    MoveWindow(layout_name_, 12, layout_y + 26, 260, 32, TRUE);
    if (HWND capture = GetDlgItem(page_roots_[2], kIdLayoutCapture)) MoveWindow(capture, 286, layout_y + 26, 170, 34, TRUE);
    if (HWND restore = GetDlgItem(page_roots_[2], kIdLayoutRestore)) MoveWindow(restore, 468, layout_y + 26, 180, 34, TRUE);
    if (HWND del = GetDlgItem(page_roots_[2], kIdLayoutDelete)) MoveWindow(del, 660, layout_y + 26, 150, 34, TRUE);
    MoveWindow(layout_preset_, 12, layout_y + 92, 240, 140, TRUE);
    if (HWND apply = GetDlgItem(page_roots_[2], kIdLayoutApplyPreset)) MoveWindow(apply, 264, layout_y + 92, 140, 34, TRUE);

    MoveWindow(startup_list_, 12, 12, page_width - 24, page_height - 176, TRUE);
    const int startup_y = page_height - 150;
    MoveWindow(startup_type_, 12, startup_y, 160, 140, TRUE);
    MoveWindow(startup_target_, 184, startup_y, 260, 32, TRUE);
    MoveWindow(startup_arguments_, 456, startup_y, 230, 32, TRUE);
    MoveWindow(startup_workspace_, 698, startup_y, 150, 140, TRUE);
    if (HWND add = GetDlgItem(page_roots_[3], kIdStartupAdd)) MoveWindow(add, 12, startup_y + 50, 110, 34, TRUE);
    if (HWND del = GetDlgItem(page_roots_[3], kIdStartupDelete)) MoveWindow(del, 132, startup_y + 50, 110, 34, TRUE);
    if (HWND run = GetDlgItem(page_roots_[3], kIdStartupRun)) MoveWindow(run, 252, startup_y + 50, 180, 34, TRUE);

    MoveWindow(activity_list_, 12, 12, page_width - 24, page_height - 78, TRUE);
    if (HWND focus = GetDlgItem(page_roots_[4], kIdActivityFocus)) MoveWindow(focus, 12, page_height - 52, 160, 34, TRUE);
    if (HWND clear = GetDlgItem(page_roots_[4], kIdActivityClear)) MoveWindow(clear, 184, page_height - 52, 150, 34, TRUE);

    MoveWindow(status_, margin, height - 44, width - margin * 2, 28, TRUE);
}

void NativeWorkspaceStudioWindow::ShowPage(Page page)
{
    current_page_ = page;
    for (std::size_t index = 0; index < page_roots_.size(); ++index)
    {
        ShowWindow(page_roots_[index], static_cast<int>(index) == static_cast<int>(page) ? SW_SHOW : SW_HIDE);
    }
}

void NativeWorkspaceStudioWindow::RefreshWorkspaceCombos()
{
    if (service_ == nullptr)
    {
        return;
    }
    const int old_selection = SelectedWorkspace();
    const auto& store = service_->Store();
    const std::array<HWND, 3> combos{workspace_combo_, rule_workspace_, startup_workspace_};
    for (HWND combo : combos)
    {
        SendMessageW(combo, CB_RESETCONTENT, 0, 0);
        for (int workspace = 0; workspace < kWorkspaceStudioCount; ++workspace)
        {
            AddComboItem(combo, store.WorkspaceName(workspace));
        }
        SendMessageW(combo, CB_SETCURSEL, std::clamp(old_selection, 0, kWorkspaceStudioCount - 1), 0);
    }
}

void NativeWorkspaceStudioWindow::RefreshAll()
{
    RefreshWorkspaceCombos();
    RefreshProfilePage();
    RefreshRules();
    RefreshLayouts();
    RefreshStartup();
    RefreshActivity();
}

void NativeWorkspaceStudioWindow::RefreshProfilePage()
{
    if (service_ == nullptr)
    {
        return;
    }
    const int workspace = SelectedWorkspace();
    const auto& profile = service_->Store().Profiles()[static_cast<std::size_t>(workspace)];
    SetControlText(profile_name_, profile.name);
    SetControlText(profile_wallpaper_, profile.wallpaper_path);
    SendMessageW(profile_layout_, CB_SETCURSEL, static_cast<WPARAM>(profile.layout), 0);
    Button_SetCheck(profile_auto_tile_, profile.auto_tile ? BST_CHECKED : BST_UNCHECKED);
    Button_SetCheck(profile_auto_launch_, profile.auto_launch ? BST_CHECKED : BST_UNCHECKED);
    Button_SetCheck(profile_apply_wallpaper_, profile.apply_wallpaper ? BST_CHECKED : BST_UNCHECKED);
}

void NativeWorkspaceStudioWindow::RefreshRules()
{
    if (service_ == nullptr || rules_list_ == nullptr)
    {
        return;
    }
    ListView_DeleteAllItems(rules_list_);
    int row = 0;
    for (const auto& rule : service_->Store().Rules())
    {
        SetListCell(rules_list_, row, 0, rule.enabled ? L"✓" : L"-");
        SetListCell(rules_list_, row, 1, WorkspaceMatchFieldName(rule.field));
        SetListCell(rules_list_, row, 2, WorkspaceMatchModeName(rule.mode));
        SetListCell(rules_list_, row, 3, rule.pattern);
        SetListCell(rules_list_, row, 4, service_->Store().WorkspaceName(rule.workspace));
        SetListCell(rules_list_, row, 5, BoolText(rule.floating));
        SetListCell(rules_list_, row, 6, BoolText(rule.maximize));
        SetListId(rules_list_, row, static_cast<LPARAM>(rule.id));
        ++row;
    }
}

void NativeWorkspaceStudioWindow::RefreshLayouts()
{
    if (service_ == nullptr || layouts_list_ == nullptr)
    {
        return;
    }
    ListView_DeleteAllItems(layouts_list_);
    int row = 0;
    for (const auto& snapshot : service_->Store().Snapshots())
    {
        SetListCell(layouts_list_, row, 0, snapshot.name);
        SetListCell(layouts_list_, row, 1, service_->Store().WorkspaceName(snapshot.workspace));
        SetListCell(layouts_list_, row, 2, std::to_wstring(snapshot.windows.size()));
        SetListCell(layouts_list_, row, 3, FormatTimestamp(snapshot.created_filetime));
        SetListId(layouts_list_, row, static_cast<LPARAM>(snapshot.id));
        ++row;
    }
}

void NativeWorkspaceStudioWindow::RefreshStartup()
{
    if (service_ == nullptr || startup_list_ == nullptr)
    {
        return;
    }
    ListView_DeleteAllItems(startup_list_);
    int row = 0;
    for (const auto& entry : service_->Store().LaunchEntries())
    {
        SetListCell(startup_list_, row, 0, entry.enabled ? L"✓" : L"-");
        SetListCell(startup_list_, row, 1, entry.cloudos_app ? L"CloudOS" : L"Windows");
        SetListCell(startup_list_, row, 2, entry.target);
        SetListCell(startup_list_, row, 3, entry.arguments);
        SetListCell(startup_list_, row, 4, service_->Store().WorkspaceName(entry.workspace));
        SetListId(startup_list_, row, static_cast<LPARAM>(entry.id));
        ++row;
    }
}

void NativeWorkspaceStudioWindow::RefreshActivity()
{
    if (service_ == nullptr || activity_list_ == nullptr)
    {
        return;
    }
    ListView_DeleteAllItems(activity_list_);
    int row = 0;
    for (const auto& record : service_->Automation().FocusHistory())
    {
        SetListCell(activity_list_, row, 0, record.title.empty() ? L"(sem título)" : record.title);
        SetListCell(activity_list_, row, 1, record.process_name);
        SetListCell(activity_list_, row, 2, service_->Store().WorkspaceName(record.workspace));
        SetListCell(activity_list_, row, 3, FormatTimestamp(record.touched_filetime));
        SetListId(activity_list_, row, static_cast<LPARAM>(row));
        ++row;
    }
}

void NativeWorkspaceStudioWindow::SaveProfile()
{
    if (service_ == nullptr)
    {
        return;
    }
    const int workspace = SelectedWorkspace();
    auto& profile = service_->Store().Profiles()[static_cast<std::size_t>(workspace)];
    profile.name = ControlText(profile_name_);
    profile.wallpaper_path = ControlText(profile_wallpaper_);
    const LRESULT layout = SendMessageW(profile_layout_, CB_GETCURSEL, 0, 0);
    profile.layout = static_cast<WorkspaceLayoutPreset>(std::clamp<LRESULT>(layout, 0, 4));
    profile.auto_tile = Button_GetCheck(profile_auto_tile_) == BST_CHECKED;
    profile.auto_launch = Button_GetCheck(profile_auto_launch_) == BST_CHECKED;
    profile.apply_wallpaper = Button_GetCheck(profile_apply_wallpaper_) == BST_CHECKED;
    if (service_->Save())
    {
        SetStatus(L"Perfil salvo e persistido.");
        RefreshWorkspaceCombos();
    }
    else
    {
        SetStatus(L"Falha ao persistir o perfil.");
    }
}

void NativeWorkspaceStudioWindow::ApplyProfileNow()
{
    SaveProfile();
    if (service_ != nullptr)
    {
        service_->ApplyCurrentProfile();
        SetStatus(L"Perfil aplicado no workspace atual.");
    }
}

void NativeWorkspaceStudioWindow::ChooseWallpaper()
{
    wchar_t path[MAX_PATH * 4]{};
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = window_;
    dialog.lpstrFile = path;
    dialog.nMaxFile = static_cast<DWORD>(std::size(path));
    dialog.lpstrFilter = L"Imagens\0*.jpg;*.jpeg;*.png;*.bmp\0Todos os arquivos\0*.*\0";
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_EXPLORER;
    if (GetOpenFileNameW(&dialog))
    {
        SetControlText(profile_wallpaper_, path);
        Button_SetCheck(profile_apply_wallpaper_, BST_CHECKED);
    }
}

void NativeWorkspaceStudioWindow::AddRule()
{
    if (service_ == nullptr)
    {
        return;
    }
    WorkspaceRule rule{};
    rule.id = service_->Store().NextRuleId();
    rule.enabled = true;
    rule.field = static_cast<WorkspaceMatchField>(std::clamp<LRESULT>(SendMessageW(rule_field_, CB_GETCURSEL, 0, 0), 0, 2));
    rule.mode = static_cast<WorkspaceMatchMode>(std::clamp<LRESULT>(SendMessageW(rule_mode_, CB_GETCURSEL, 0, 0), 0, 3));
    rule.pattern = ControlText(rule_pattern_);
    rule.workspace = static_cast<int>(std::clamp<LRESULT>(SendMessageW(rule_workspace_, CB_GETCURSEL, 0, 0), 0, 3));
    rule.floating = Button_GetCheck(rule_floating_) == BST_CHECKED;
    rule.maximize = Button_GetCheck(rule_maximize_) == BST_CHECKED;
    if (rule.pattern.empty())
    {
        SetStatus(L"Informe um padrão para a regra.");
        return;
    }
    service_->Store().Rules().push_back(std::move(rule));
    (void)service_->Save();
    service_->ReapplyRules();
    RefreshRules();
    SetStatus(L"Regra adicionada e aplicada.");
}

void NativeWorkspaceStudioWindow::DeleteRule()
{
    if (service_ == nullptr)
    {
        return;
    }
    const int row = SelectedListIndex(rules_list_);
    const std::uint32_t id = static_cast<std::uint32_t>(ListId(rules_list_, row));
    auto& rules = service_->Store().Rules();
    const auto old_size = rules.size();
    std::erase_if(rules, [id](const WorkspaceRule& rule) { return rule.id == id; });
    if (rules.size() != old_size)
    {
        (void)service_->Save();
        service_->ReapplyRules();
        RefreshRules();
        SetStatus(L"Regra excluída.");
    }
}

void NativeWorkspaceStudioWindow::ToggleRule()
{
    if (service_ == nullptr)
    {
        return;
    }
    const std::uint32_t id = static_cast<std::uint32_t>(ListId(rules_list_, SelectedListIndex(rules_list_)));
    for (auto& rule : service_->Store().Rules())
    {
        if (rule.id == id)
        {
            rule.enabled = !rule.enabled;
            (void)service_->Save();
            service_->ReapplyRules();
            RefreshRules();
            SetStatus(rule.enabled ? L"Regra ativada." : L"Regra desativada.");
            return;
        }
    }
}

void NativeWorkspaceStudioWindow::ReapplyRules()
{
    if (service_ != nullptr)
    {
        service_->ReapplyRules();
        SetStatus(L"Todas as regras foram reavaliadas.");
    }
}

void NativeWorkspaceStudioWindow::CaptureLayout()
{
    if (service_ == nullptr || service_->Manager() == nullptr)
    {
        return;
    }
    const int workspace = SelectedWorkspace();
    auto snapshot = NativeWorkspaceLayoutEngine::Capture(
        *service_->Manager(),
        service_->Store(),
        workspace,
        ControlText(layout_name_));
    service_->Store().Snapshots().push_back(std::move(snapshot));
    (void)service_->Save();
    RefreshLayouts();
    SetStatus(L"Snapshot de layout capturado.");
}

void NativeWorkspaceStudioWindow::RestoreLayout()
{
    if (service_ == nullptr || service_->Manager() == nullptr)
    {
        return;
    }
    const std::uint32_t id = static_cast<std::uint32_t>(ListId(layouts_list_, SelectedListIndex(layouts_list_)));
    for (const auto& snapshot : service_->Store().Snapshots())
    {
        if (snapshot.id == id)
        {
            if (service_->Manager()->CurrentWorkspace() != snapshot.workspace)
            {
                service_->Manager()->SwitchWorkspace(snapshot.workspace);
            }
            const bool ok = NativeWorkspaceLayoutEngine::Restore(*service_->Manager(), snapshot);
            SetStatus(ok ? L"Layout restaurado." : L"Nenhuma janela compatível encontrada para restaurar.");
            return;
        }
    }
}

void NativeWorkspaceStudioWindow::DeleteLayout()
{
    if (service_ == nullptr)
    {
        return;
    }
    const std::uint32_t id = static_cast<std::uint32_t>(ListId(layouts_list_, SelectedListIndex(layouts_list_)));
    auto& snapshots = service_->Store().Snapshots();
    std::erase_if(snapshots, [id](const WorkspaceSnapshot& value) { return value.id == id; });
    (void)service_->Save();
    RefreshLayouts();
    SetStatus(L"Snapshot removido.");
}

void NativeWorkspaceStudioWindow::ApplyLayoutPreset()
{
    if (service_ == nullptr || service_->Manager() == nullptr)
    {
        return;
    }
    const auto preset = static_cast<WorkspaceLayoutPreset>(
        std::clamp<LRESULT>(SendMessageW(layout_preset_, CB_GETCURSEL, 0, 0), 0, 4));
    NativeWorkspaceLayoutEngine::ApplyPreset(*service_->Manager(), SelectedWorkspace(), preset);
    SetStatus(L"Preset aplicado.");
}

void NativeWorkspaceStudioWindow::AddStartupEntry()
{
    if (service_ == nullptr)
    {
        return;
    }
    WorkspaceLaunchEntry entry{};
    entry.id = service_->Store().NextLaunchId();
    entry.enabled = true;
    entry.cloudos_app = SendMessageW(startup_type_, CB_GETCURSEL, 0, 0) == 0;
    entry.target = ControlText(startup_target_);
    entry.arguments = ControlText(startup_arguments_);
    entry.workspace = static_cast<int>(std::clamp<LRESULT>(SendMessageW(startup_workspace_, CB_GETCURSEL, 0, 0), 0, 3));
    if (entry.target.empty())
    {
        SetStatus(L"Informe o ID do app CloudOS ou executável do Windows.");
        return;
    }
    service_->Store().LaunchEntries().push_back(std::move(entry));
    (void)service_->Save();
    RefreshStartup();
    SetStatus(L"Item de inicialização adicionado.");
}

void NativeWorkspaceStudioWindow::DeleteStartupEntry()
{
    if (service_ == nullptr)
    {
        return;
    }
    const std::uint32_t id = static_cast<std::uint32_t>(ListId(startup_list_, SelectedListIndex(startup_list_)));
    auto& values = service_->Store().LaunchEntries();
    std::erase_if(values, [id](const WorkspaceLaunchEntry& entry) { return entry.id == id; });
    (void)service_->Save();
    RefreshStartup();
    SetStatus(L"Item de inicialização removido.");
}

void NativeWorkspaceStudioWindow::RunStartupNow()
{
    if (service_ != nullptr)
    {
        service_->Automation().LaunchWorkspaceEntries(
            instance_,
            window_,
            SelectedWorkspace(),
            service_->Store());
        SetStatus(L"Itens habilitados da área foram executados.");
    }
}

void NativeWorkspaceStudioWindow::FocusHistorySelection()
{
    if (service_ == nullptr || service_->Manager() == nullptr)
    {
        return;
    }
    const int row = SelectedListIndex(activity_list_);
    if (row >= 0 && service_->Automation().FocusHistoryItem(*service_->Manager(), static_cast<std::size_t>(row)))
    {
        SetStatus(L"Janela focada a partir do histórico.");
    }
}

void NativeWorkspaceStudioWindow::ClearHistory()
{
    if (service_ != nullptr)
    {
        service_->Automation().ClearFocusHistory();
        RefreshActivity();
        SetStatus(L"Histórico de foco limpo.");
    }
}

int NativeWorkspaceStudioWindow::SelectedWorkspace() const noexcept
{
    if (workspace_combo_ == nullptr)
    {
        return 0;
    }
    const LRESULT value = SendMessageW(workspace_combo_, CB_GETCURSEL, 0, 0);
    return static_cast<int>(std::clamp<LRESULT>(value, 0, kWorkspaceStudioCount - 1));
}

int NativeWorkspaceStudioWindow::SelectedListIndex(HWND list) const noexcept
{
    return list == nullptr ? -1 : ListView_GetNextItem(list, -1, LVNI_SELECTED);
}

std::wstring NativeWorkspaceStudioWindow::ControlText(HWND control) const
{
    if (control == nullptr)
    {
        return {};
    }
    const int length = GetWindowTextLengthW(control);
    std::wstring text(static_cast<std::size_t>(std::max(0, length)) + 1u, L'\0');
    const int copied = GetWindowTextW(control, text.data(), static_cast<int>(text.size()));
    text.resize(static_cast<std::size_t>(std::max(0, copied)));
    return text;
}

void NativeWorkspaceStudioWindow::SetControlText(HWND control, const std::wstring& text)
{
    if (control != nullptr)
    {
        SetWindowTextW(control, text.c_str());
    }
}

void NativeWorkspaceStudioWindow::SetStatus(const std::wstring& text)
{
    SetControlText(status_, text);
}

LRESULT NativeWorkspaceStudioWindow::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_CLOSE:
        Hide();
        return 0;
    case WM_COMMAND:
    {
        const int id = LOWORD(w_param);
        const int notification = HIWORD(w_param);
        if (reinterpret_cast<HWND>(l_param) == workspace_combo_ && notification == CBN_SELCHANGE)
        {
            RefreshProfilePage();
            return 0;
        }
        switch (id)
        {
        case kIdRefresh: RefreshAll(); SetStatus(L"Dados atualizados."); break;
        case kIdProfileSave: SaveProfile(); break;
        case kIdProfileApply: ApplyProfileNow(); break;
        case kIdWallpaperChoose: ChooseWallpaper(); break;
        case kIdRuleAdd: AddRule(); break;
        case kIdRuleDelete: DeleteRule(); break;
        case kIdRuleToggle: ToggleRule(); break;
        case kIdRuleReapply: ReapplyRules(); break;
        case kIdLayoutCapture: CaptureLayout(); break;
        case kIdLayoutRestore: RestoreLayout(); break;
        case kIdLayoutDelete: DeleteLayout(); break;
        case kIdLayoutApplyPreset: ApplyLayoutPreset(); break;
        case kIdStartupAdd: AddStartupEntry(); break;
        case kIdStartupDelete: DeleteStartupEntry(); break;
        case kIdStartupRun: RunStartupNow(); break;
        case kIdActivityFocus: FocusHistorySelection(); break;
        case kIdActivityClear: ClearHistory(); break;
        default: break;
        }
        return 0;
    }
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == tabs_ && header->code == TCN_SELCHANGE)
        {
            const int selected = TabCtrl_GetCurSel(tabs_);
            ShowPage(static_cast<Page>(std::clamp(selected, 0, 4)));
            RefreshAll();
            return 0;
        }
        if (header != nullptr && header->code == NM_DBLCLK)
        {
            if (header->hwndFrom == layouts_list_) RestoreLayout();
            else if (header->hwndFrom == activity_list_) FocusHistorySelection();
            return 0;
        }
        if (header != nullptr && header->code == NM_CUSTOMDRAW)
        {
            return WebSkin::HandleListViewCustomDraw(reinterpret_cast<LPNMLVCUSTOMDRAW>(l_param));
        }
        break;
    }
    case WM_DRAWITEM:
        if (WebSkin::PaintOwnerDrawButton(reinterpret_cast<const DRAWITEMSTRUCT*>(l_param)))
        {
            return TRUE;
        }
        break;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        if (window_ == window)
        {
            window_ = nullptr;
        }
        break;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK NativeWorkspaceStudioWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeWorkspaceStudioWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<NativeWorkspaceStudioWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
