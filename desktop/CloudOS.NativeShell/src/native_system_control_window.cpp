#include "native_system_control_window.h"

#include "native_theme.h"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <utility>

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.SystemControl.v1";
constexpr UINT_PTR kRefreshTimer = 0x5C01;
constexpr int kNavBase = 100;
constexpr int kDetailBase = 200;
constexpr int kActionBase = 300;
constexpr int kListId = 400;
constexpr int kSliderId = 401;

constexpr std::array<const wchar_t*, 8> kPageNames{
    L"Visao Geral",
    L"Wi-Fi",
    L"Tela",
    L"Audio",
    L"Energia",
    L"Rede",
    L"Armazenamento",
    L"Processos",
};

constexpr std::array<const wchar_t*, 8> kPageDescriptions{
    L"Saude da sessao, memoria, monitores, servicos essenciais e atalhos administrativos.",
    L"Redes Wi-Fi detectadas pelo Native Wi-Fi API. Redes com perfil salvo podem conectar direto.",
    L"Brilho real via DDC/CI com fallback WMI para paineis integrados.",
    L"Volume master e mute do endpoint de audio padrao via Core Audio.",
    L"Bateria, alimentacao e troca direta entre planos de energia do Windows.",
    L"Adaptadores, enderecos IP, MAC, estado e velocidade de link.",
    L"Volumes montados, sistema de arquivos, capacidade e espaco livre.",
    L"Processos ordenados por memoria residente, com acesso ao Task Manager e encerramento confirmado.",
};

std::wstring PercentText(unsigned value)
{
    return std::to_wstring(value) + L"%";
}

std::wstring SecondsText(DWORD seconds)
{
    if (seconds == static_cast<DWORD>(-1))
    {
        return L"Estimativa indisponivel";
    }
    const DWORD hours = seconds / 3600;
    const DWORD minutes = (seconds % 3600) / 60;
    if (hours == 0)
    {
        return std::to_wstring(minutes) + L" min";
    }
    return std::to_wstring(hours) + L" h " + std::to_wstring(minutes) + L" min";
}

void SetFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

void SetText(HWND control, const std::wstring& text)
{
    if (control != nullptr)
    {
        SetWindowTextW(control, text.c_str());
    }
}

void Show(HWND control, bool visible)
{
    if (control != nullptr)
    {
        ShowWindow(control, visible ? SW_SHOW : SW_HIDE);
    }
}

void InsertColumn(HWND list, int index, const wchar_t* title, int width)
{
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    column.pszText = const_cast<LPWSTR>(title);
    column.cx = width;
    column.iSubItem = index;
    ListView_InsertColumn(list, index, &column);
}

int InsertRow(HWND list, const std::wstring& first, LPARAM data = 0)
{
    LVITEMW item{};
    item.mask = LVIF_TEXT | LVIF_PARAM;
    item.iItem = ListView_GetItemCount(list);
    item.iSubItem = 0;
    item.pszText = const_cast<LPWSTR>(first.c_str());
    item.lParam = data;
    return ListView_InsertItem(list, &item);
}

void SetCell(HWND list, int row, int column, const std::wstring& text)
{
    ListView_SetItemText(list, row, column, const_cast<LPWSTR>(text.c_str()));
}

std::wstring WindowClassTitle(HWND window)
{
    if (window == nullptr)
    {
        return {};
    }
    wchar_t title[256]{};
    GetWindowTextW(window, title, static_cast<int>(std::size(title)));
    return title;
}
}

CloudOSNativeSystemControlWindow::CloudOSNativeSystemControlWindow(HINSTANCE instance) noexcept
    : instance_(instance)
{
}

CloudOSNativeSystemControlWindow::~CloudOSNativeSystemControlWindow()
{
    Destroy();
}

HWND CloudOSNativeSystemControlWindow::Open(HINSTANCE instance, HWND owner)
{
    HWND existing = FindWindowW(kClassName, nullptr);
    if (existing != nullptr)
    {
        ShowWindow(existing, SW_RESTORE);
        SetForegroundWindow(existing);
        return existing;
    }

    auto* self = new (std::nothrow) CloudOSNativeSystemControlWindow(instance);
    if (self == nullptr)
    {
        return nullptr;
    }
    if (!self->Create(owner))
    {
        delete self;
        return nullptr;
    }
    return self->window_;
}

bool CloudOSNativeSystemControlWindow::Create(HWND owner)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.lpfnWndProc = &CloudOSNativeSystemControlWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hIconSm = window_class.hIcon;
    window_class.hbrBackground = WebSkin::SharedBackgroundBrush();
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    const int width = 1120;
    const int height = 760;
    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const int x = work.left + std::max(0, (static_cast<int>(work.right - work.left) - width) / 2);
    const int y = work.top + std::max(0, (static_cast<int>(work.bottom - work.top) - height) / 2);

    window_ = CreateWindowExW(
        0,
        kClassName,
        L"Central do Sistema - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        x,
        y,
        width,
        height,
        owner,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    font_ = CreateFontW(
        -18, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    small_font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    title_font_ = CreateFontW(
        -28, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    background_ = CreateSolidBrush(WebSkin::BgPrimary);
    panel_ = CreateSolidBrush(WebSkin::BgSecondary);

    title_ = CreateWindowExW(
        0, L"STATIC", L"Central do Sistema",
        WS_CHILD | WS_VISIBLE,
        0, 0, 0, 0,
        window_, nullptr, instance_, nullptr);
    subtitle_ = CreateWindowExW(
        0, L"STATIC", L"",
        WS_CHILD | WS_VISIBLE,
        0, 0, 0, 0,
        window_, nullptr, instance_, nullptr);

    for (std::size_t index = 0; index < nav_buttons_.size(); ++index)
    {
        nav_buttons_[index] = CreateWindowExW(
            0,
            L"BUTTON",
            kPageNames[index],
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
            0, 0, 0, 0,
            window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNavBase + static_cast<int>(index))),
            instance_,
            nullptr);
    }

    list_ = CreateWindowExW(
        0,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    ListView_SetExtendedListViewStyleEx(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    slider_ = CreateWindowExW(
        0,
        TRACKBAR_CLASSW,
        L"",
        WS_CHILD | WS_TABSTOP | TBS_HORZ | TBS_AUTOTICKS,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSliderId)),
        instance_,
        nullptr);
    SendMessageW(slider_, TBM_SETRANGE, TRUE, MAKELONG(0, 100));
    SendMessageW(slider_, TBM_SETTICFREQ, 10, 0);

    slider_value_ = CreateWindowExW(
        0, L"STATIC", L"",
        WS_CHILD,
        0, 0, 0, 0,
        window_, nullptr, instance_, nullptr);

    for (std::size_t index = 0; index < detail_labels_.size(); ++index)
    {
        detail_labels_[index] = CreateWindowExW(
            0,
            L"STATIC",
            L"",
            WS_CHILD,
            0, 0, 0, 0,
            window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDetailBase + static_cast<int>(index))),
            instance_,
            nullptr);
    }

    for (std::size_t index = 0; index < action_buttons_.size(); ++index)
    {
        action_buttons_[index] = CreateWindowExW(
            0,
            L"BUTTON",
            L"",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
            0, 0, 0, 0,
            window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kActionBase + static_cast<int>(index))),
            instance_,
            nullptr);
    }

    status_ = CreateWindowExW(
        0, L"STATIC", L"",
        WS_CHILD | WS_VISIBLE,
        0, 0, 0, 0,
        window_, nullptr, instance_, nullptr);

    SetFont(title_, title_font_);
    SetFont(subtitle_, small_font_);
    SetFont(list_, font_);
    SetFont(slider_value_, font_);
    SetFont(status_, small_font_);
    for (HWND button : nav_buttons_) SetFont(button, font_);
    for (HWND label : detail_labels_) SetFont(label, font_);
    for (HWND button : action_buttons_) SetFont(button, font_);

    ApplyWebWindowMaterial(window_);
    WebSkin::PrepareListView(list_);
    WebSkin::ApplyUxTheme(slider_);

    SetTimer(window_, kRefreshTimer, 2000, nullptr);
    SetPage(Page::Overview);
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    SetForegroundWindow(window_);
    return true;
}

void CloudOSNativeSystemControlWindow::Destroy() noexcept
{
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kRefreshTimer);
        DestroyWindow(window_);
        window_ = nullptr;
    }
    if (font_ != nullptr) { DeleteObject(font_); font_ = nullptr; }
    if (small_font_ != nullptr) { DeleteObject(small_font_); small_font_ = nullptr; }
    if (title_font_ != nullptr) { DeleteObject(title_font_); title_font_ = nullptr; }
    if (background_ != nullptr) { DeleteObject(background_); background_ = nullptr; }
    if (panel_ != nullptr) { DeleteObject(panel_); panel_ = nullptr; }
}

void CloudOSNativeSystemControlWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT client{};
    GetClientRect(window_, &client);
    const int width = static_cast<int>(client.right - client.left);
    const int height = static_cast<int>(client.bottom - client.top);
    const int nav_width = 190;
    const int margin = 20;
    const int content_left = nav_width + 28;
    const int content_width = std::max(300, width - content_left - margin);

    MoveWindow(title_, content_left, 18, content_width, 38, TRUE);
    MoveWindow(subtitle_, content_left, 58, content_width, 42, TRUE);

    int nav_y = 24;
    for (HWND button : nav_buttons_)
    {
        MoveWindow(button, 14, nav_y, nav_width - 28, 46, TRUE);
        nav_y += 52;
    }

    const int details_top = 108;
    for (std::size_t index = 0; index < detail_labels_.size(); ++index)
    {
        const int column = static_cast<int>(index % 2);
        const int row = static_cast<int>(index / 2);
        const int cell_width = (content_width - 12) / 2;
        MoveWindow(
            detail_labels_[index],
            content_left + column * (cell_width + 12),
            details_top + row * 38,
            cell_width,
            32,
            TRUE);
    }

    MoveWindow(slider_, content_left, 232, std::max(180, content_width - 110), 38, TRUE);
    MoveWindow(slider_value_, content_left + std::max(180, content_width - 100), 236, 90, 30, TRUE);

    const int list_top = 292;
    const int action_top = height - 96;
    MoveWindow(list_, content_left, list_top, content_width, std::max(100, action_top - list_top - 16), TRUE);

    const int button_gap = 10;
    const int button_width = std::max(120, (content_width - button_gap * 3) / 4);
    for (std::size_t index = 0; index < action_buttons_.size(); ++index)
    {
        MoveWindow(
            action_buttons_[index],
            content_left + static_cast<int>(index) * (button_width + button_gap),
            action_top,
            button_width,
            42,
            TRUE);
    }
    MoveWindow(status_, content_left, height - 42, content_width, 26, TRUE);
}

void CloudOSNativeSystemControlWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    WebSkin::PaintWindowBackground(dc, client);

    RECT sidebar{0, 0, 190, client.bottom};
    FillRect(dc, &sidebar, panel_ != nullptr ? panel_ : WebSkin::SharedSurfaceBrush());

    HPEN separator = CreatePen(PS_SOLID, 1, WebSkin::BorderDefault);
    HGDIOBJ previous = SelectObject(dc, separator);
    MoveToEx(dc, 190, 0, nullptr);
    LineTo(dc, 190, client.bottom);
    SelectObject(dc, previous);
    DeleteObject(separator);
    EndPaint(window_, &paint);
}

void CloudOSNativeSystemControlWindow::SetPage(Page page)
{
    page_ = page;
    refresh_tick_ = 0;
    SetText(subtitle_, kPageDescriptions[static_cast<std::size_t>(page_)]);
    ConfigurePageControls();
    Refresh(true);
    InvalidateRect(window_, nullptr, TRUE);
}

void CloudOSNativeSystemControlWindow::ClearDetails()
{
    for (HWND label : detail_labels_)
    {
        SetText(label, L"");
        Show(label, false);
    }
    Show(slider_, false);
    Show(slider_value_, false);
}

void CloudOSNativeSystemControlWindow::ConfigurePageControls()
{
    ClearDetails();
    ListView_DeleteAllItems(list_);
    ResetListColumns();
    Show(list_, true);

    std::array<std::wstring, 4> actions{};
    switch (page_)
    {
    case Page::Overview:
        actions = {L"Gerenciador de Tarefas", L"Configuracoes", L"Gerenciador de Dispositivos", L"Painel de Controle"};
        break;
    case Page::Wifi:
        actions = {L"Atualizar redes", L"Conectar perfil", L"Desconectar", L"Configuracoes Wi-Fi"};
        break;
    case Page::Display:
        actions = {L"Tela do Windows", L"Tela avancada", L"Calibrar cores", L"Propriedades de video"};
        Show(list_, false);
        break;
    case Page::Audio:
        actions = {L"Mute / Som", L"Configuracoes de Som", L"Mixer de Volume", L"Dispositivos de Audio"};
        Show(list_, false);
        break;
    case Page::Power:
        actions = {L"Equilibrado", L"Economia", L"Alto desempenho", L"Energia do Windows"};
        Show(list_, false);
        break;
    case Page::Network:
        actions = {L"Atualizar", L"Conexoes de Rede", L"Rede do Windows", L"ipconfig /all"};
        break;
    case Page::Storage:
        actions = {L"Abrir volume", L"Gerenciamento de Disco", L"Armazenamento", L"Limpeza de Disco"};
        break;
    case Page::Processes:
        actions = {L"Atualizar", L"Gerenciador de Tarefas", L"Monitor de Recursos", L"Finalizar selecionado"};
        break;
    }

    for (std::size_t index = 0; index < action_buttons_.size(); ++index)
    {
        SetText(action_buttons_[index], actions[index]);
        Show(action_buttons_[index], true);
    }
}

void CloudOSNativeSystemControlWindow::ResetListColumns()
{
    if (list_ == nullptr)
    {
        return;
    }
    while (Header_GetItemCount(ListView_GetHeader(list_)) > 0)
    {
        ListView_DeleteColumn(list_, 0);
    }
}

void CloudOSNativeSystemControlWindow::SetListColumns(
    const std::vector<std::pair<std::wstring, int>>& columns)
{
    ResetListColumns();
    for (std::size_t index = 0; index < columns.size(); ++index)
    {
        InsertColumn(
            list_,
            static_cast<int>(index),
            columns[index].first.c_str(),
            columns[index].second);
    }
}

void CloudOSNativeSystemControlWindow::Refresh(bool force)
{
    if (window_ == nullptr || (!IsWindowVisible(window_) && !force))
    {
        return;
    }
    ++refresh_tick_;
    switch (page_)
    {
    case Page::Overview: RefreshOverview(); break;
    case Page::Wifi:
        if (force || refresh_tick_ == 1 || (refresh_tick_ % 5) == 0) RefreshWifi();
        break;
    case Page::Display:
        if (force || (refresh_tick_ % 3) == 0) RefreshDisplay();
        break;
    case Page::Audio: RefreshAudio(); break;
    case Page::Power: RefreshPower(); break;
    case Page::Network:
        if (force || (refresh_tick_ % 3) == 0) RefreshNetwork();
        break;
    case Page::Storage:
        if (force || (refresh_tick_ % 5) == 0) RefreshStorage();
        break;
    case Page::Processes: RefreshProcesses(); break;
    }
    RefreshStatus();
}

void CloudOSNativeSystemControlWindow::RefreshOverview()
{
    const NativeSystemSummary summary = NativeSystemControlBackend::QuerySummary();
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], true);

    SetText(detail_labels_[0], L"Memoria: " + PercentText(summary.memory_load_percent));
    SetText(detail_labels_[1], L"RAM livre: " + NativeSystemControlBackend::FormatBytes(summary.available_memory_bytes));
    SetText(detail_labels_[2], L"Processos: " + std::to_wstring(summary.process_count));
    SetText(detail_labels_[3], L"Monitores: " + std::to_wstring(summary.monitor_count));
    SetText(detail_labels_[4], L"Adaptadores: " + std::to_wstring(summary.adapter_count));
    SetText(detail_labels_[5], L"Volumes: " + std::to_wstring(summary.drive_count));

    SetListColumns({{L"Servico", 340}, {L"Nome", 210}, {L"Estado", 180}});
    ListView_DeleteAllItems(list_);
    const auto services = NativeSystemControlBackend::QueryCoreServices();
    for (const auto& service : services)
    {
        const int row = InsertRow(list_, service.display_name);
        SetCell(list_, row, 1, service.name);
        SetCell(list_, row, 2, service.state);
    }
}

void CloudOSNativeSystemControlWindow::RefreshWifi()
{
    const int selected = SelectedListIndex();
    std::wstring selected_ssid;
    if (selected >= 0 && static_cast<std::size_t>(selected) < wifi_.size())
    {
        selected_ssid = wifi_[static_cast<std::size_t>(selected)].ssid;
    }

    wifi_ = NativeSystemControlBackend::ScanWifi();
    SetListColumns({{L"Rede", 280}, {L"Sinal", 90}, {L"Seguranca", 130}, {L"Estado", 120}, {L"Interface", 260}});
    ListView_DeleteAllItems(list_);
    int restore_selection = -1;
    for (std::size_t index = 0; index < wifi_.size(); ++index)
    {
        const auto& network = wifi_[index];
        const int row = InsertRow(list_, network.ssid, static_cast<LPARAM>(index));
        SetCell(list_, row, 1, PercentText(network.signal_quality));
        SetCell(list_, row, 2, network.secure ? L"Protegida" : L"Aberta");
        SetCell(list_, row, 3, network.connected ? L"Conectado" : (network.profile_name.empty() ? L"Sem perfil" : L"Perfil salvo"));
        SetCell(list_, row, 4, network.interface_name);
        if (!selected_ssid.empty() && _wcsicmp(network.ssid.c_str(), selected_ssid.c_str()) == 0)
        {
            restore_selection = row;
        }
    }
    if (restore_selection >= 0)
    {
        ListView_SetItemState(list_, restore_selection, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
        ListView_EnsureVisible(list_, restore_selection, FALSE);
    }

    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 4);
    const auto connected = std::find_if(wifi_.begin(), wifi_.end(), [](const NativeWifiNetwork& item) { return item.connected; });
    SetText(detail_labels_[0], L"Redes encontradas: " + std::to_wstring(wifi_.size()));
    SetText(detail_labels_[1], connected == wifi_.end() ? L"Conexao: nenhuma" : L"Conexao: " + connected->ssid);
    SetText(detail_labels_[2], connected == wifi_.end() ? L"Sinal: --" : L"Sinal: " + PercentText(connected->signal_quality));
    SetText(detail_labels_[3], connected == wifi_.end() ? L"Interface: --" : L"Interface: " + connected->interface_name);
}

void CloudOSNativeSystemControlWindow::RefreshDisplay()
{
    brightness_ = NativeSystemControlBackend::QueryBrightness();
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 4);
    SetText(detail_labels_[0], brightness_.available ? L"Brilho atual: " + PercentText(brightness_.percent) : L"Brilho: controle indisponivel");
    SetText(detail_labels_[1], L"Metodo: " + (brightness_.source.empty() ? std::wstring(L"nenhum") : brightness_.source));
    SetText(detail_labels_[2], L"Monitor: " + (brightness_.monitor_name.empty() ? std::wstring(L"nao identificado") : brightness_.monitor_name));
    SetText(detail_labels_[3], L"Fallback: DDC/CI -> WMI");

    Show(slider_, brightness_.available);
    Show(slider_value_, brightness_.available);
    if (brightness_.available)
    {
        slider_programmatic_ = true;
        SendMessageW(slider_, TBM_SETPOS, TRUE, brightness_.percent);
        slider_programmatic_ = false;
        SetText(slider_value_, PercentText(brightness_.percent));
    }
}

void CloudOSNativeSystemControlWindow::RefreshAudio()
{
    audio_ = NativeSystemControlBackend::QueryAudio();
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 4);
    SetText(detail_labels_[0], audio_.available ? L"Volume master: " + PercentText(audio_.volume_percent) : L"Audio: endpoint indisponivel");
    SetText(detail_labels_[1], L"Estado: " + std::wstring(audio_.muted ? L"Mudo" : L"Ativo"));
    SetText(detail_labels_[2], L"Saida: " + (audio_.endpoint_name.empty() ? std::wstring(L"Padrao do Windows") : audio_.endpoint_name));
    SetText(detail_labels_[3], L"API: IAudioEndpointVolume");

    Show(slider_, audio_.available);
    Show(slider_value_, audio_.available);
    if (audio_.available)
    {
        slider_programmatic_ = true;
        SendMessageW(slider_, TBM_SETPOS, TRUE, audio_.volume_percent);
        slider_programmatic_ = false;
        SetText(slider_value_, PercentText(audio_.volume_percent));
        SetText(action_buttons_[0], audio_.muted ? L"Ativar som" : L"Silenciar");
    }
}

void CloudOSNativeSystemControlWindow::RefreshPower()
{
    power_ = NativeSystemControlBackend::QueryPower();
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 5);
    SetText(detail_labels_[0], L"Fonte: " + std::wstring(power_.on_ac ? L"Tomada / AC" : L"Bateria"));
    SetText(detail_labels_[1], power_.battery_present ? L"Bateria: " + PercentText(power_.battery_percent) : L"Bateria: nao detectada");
    SetText(detail_labels_[2], L"Plano ativo: " + (power_.active_plan.empty() ? std::wstring(L"desconhecido") : power_.active_plan));
    SetText(detail_labels_[3], power_.battery_present ? L"Tempo estimado: " + SecondsText(power_.battery_life_seconds) : L"Tempo estimado: --");
    SetText(detail_labels_[4], L"API: GetSystemPowerStatus + PowerSetActiveScheme");
}

void CloudOSNativeSystemControlWindow::RefreshNetwork()
{
    adapters_ = NativeSystemControlBackend::QueryAdapters();
    SetListColumns({{L"Adaptador", 220}, {L"Estado", 130}, {L"IPv4", 145}, {L"IPv6", 210}, {L"MAC", 160}, {L"Link", 110}});
    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < adapters_.size(); ++index)
    {
        const auto& adapter = adapters_[index];
        const int row = InsertRow(list_, adapter.name, static_cast<LPARAM>(index));
        SetCell(list_, row, 1, adapter.status);
        SetCell(list_, row, 2, adapter.ipv4.empty() ? L"--" : adapter.ipv4);
        SetCell(list_, row, 3, adapter.ipv6.empty() ? L"--" : adapter.ipv6);
        SetCell(list_, row, 4, adapter.mac.empty() ? L"--" : adapter.mac);
        SetCell(list_, row, 5, std::to_wstring(std::max(adapter.transmit_mbps, adapter.receive_mbps)) + L" Mbps");
    }
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 3);
    const auto active = std::count_if(adapters_.begin(), adapters_.end(), [](const NativeNetworkAdapter& item) { return item.status == L"Conectado"; });
    SetText(detail_labels_[0], L"Adaptadores: " + std::to_wstring(adapters_.size()));
    SetText(detail_labels_[1], L"Ativos: " + std::to_wstring(active));
    SetText(detail_labels_[2], L"API: GetAdaptersAddresses");
}

void CloudOSNativeSystemControlWindow::RefreshStorage()
{
    drives_ = NativeSystemControlBackend::QueryDrives();
    SetListColumns({{L"Volume", 95}, {L"Rotulo", 190}, {L"Tipo", 150}, {L"Sistema", 110}, {L"Livre", 130}, {L"Total", 130}});
    ListView_DeleteAllItems(list_);
    std::uint64_t total = 0;
    std::uint64_t free = 0;
    for (std::size_t index = 0; index < drives_.size(); ++index)
    {
        const auto& drive = drives_[index];
        const int row = InsertRow(list_, drive.root, static_cast<LPARAM>(index));
        SetCell(list_, row, 1, drive.label.empty() ? L"--" : drive.label);
        SetCell(list_, row, 2, drive.type);
        SetCell(list_, row, 3, drive.file_system.empty() ? L"--" : drive.file_system);
        SetCell(list_, row, 4, NativeSystemControlBackend::FormatBytes(drive.free_bytes));
        SetCell(list_, row, 5, NativeSystemControlBackend::FormatBytes(drive.total_bytes));
        total += drive.total_bytes;
        free += drive.free_bytes;
    }
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 3);
    SetText(detail_labels_[0], L"Volumes montados: " + std::to_wstring(drives_.size()));
    SetText(detail_labels_[1], L"Capacidade somada: " + NativeSystemControlBackend::FormatBytes(total));
    SetText(detail_labels_[2], L"Livre somado: " + NativeSystemControlBackend::FormatBytes(free));
}

void CloudOSNativeSystemControlWindow::RefreshProcesses()
{
    DWORD selected_pid = 0;
    const int selected = SelectedListIndex();
    if (selected >= 0 && static_cast<std::size_t>(selected) < processes_.size())
    {
        selected_pid = processes_[static_cast<std::size_t>(selected)].process_id;
    }

    processes_ = NativeSystemControlBackend::QueryProcesses(60);
    SetListColumns({{L"Processo", 330}, {L"PID", 100}, {L"Memoria", 150}, {L"Privada", 150}});
    ListView_DeleteAllItems(list_);
    int restore = -1;
    for (std::size_t index = 0; index < processes_.size(); ++index)
    {
        const auto& process = processes_[index];
        const int row = InsertRow(list_, process.name, static_cast<LPARAM>(index));
        SetCell(list_, row, 1, std::to_wstring(process.process_id));
        SetCell(list_, row, 2, NativeSystemControlBackend::FormatBytes(process.working_set_bytes));
        SetCell(list_, row, 3, NativeSystemControlBackend::FormatBytes(process.private_bytes));
        if (selected_pid != 0 && process.process_id == selected_pid)
        {
            restore = row;
        }
    }
    if (restore >= 0)
    {
        ListView_SetItemState(list_, restore, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    }
    for (std::size_t index = 0; index < detail_labels_.size(); ++index) Show(detail_labels_[index], index < 3);
    SetText(detail_labels_[0], L"Top por memoria: " + std::to_wstring(processes_.size()) + L" processos");
    if (!processes_.empty())
    {
        SetText(detail_labels_[1], L"Maior consumo: " + processes_.front().name);
        SetText(detail_labels_[2], L"Working set: " + NativeSystemControlBackend::FormatBytes(processes_.front().working_set_bytes));
    }
}

void CloudOSNativeSystemControlWindow::RefreshStatus()
{
    SYSTEMTIME time{};
    GetLocalTime(&time);
    wchar_t buffer[256]{};
    swprintf_s(
        buffer,
        L"CloudOS System Center  |  %02u:%02u:%02u  |  Atualizacao automatica a cada 2 s",
        time.wHour,
        time.wMinute,
        time.wSecond);
    SetText(status_, buffer);
}

int CloudOSNativeSystemControlWindow::SelectedListIndex() const noexcept
{
    return list_ == nullptr ? -1 : ListView_GetNextItem(list_, -1, LVNI_SELECTED);
}

void CloudOSNativeSystemControlWindow::ConnectSelectedWifi()
{
    const int selected = SelectedListIndex();
    if (selected < 0 || static_cast<std::size_t>(selected) >= wifi_.size())
    {
        ShowError(L"Wi-Fi", L"Selecione uma rede primeiro.");
        return;
    }
    std::wstring error;
    if (!NativeSystemControlBackend::ConnectKnownWifi(wifi_[static_cast<std::size_t>(selected)], &error))
    {
        ShowError(L"Conectar Wi-Fi", error);
        if (wifi_[static_cast<std::size_t>(selected)].profile_name.empty())
        {
            OpenTarget(L"ms-settings:network-wifi");
        }
        return;
    }
    SetText(status_, L"Solicitacao de conexao enviada ao Windows WLAN AutoConfig...");
    RefreshWifi();
}

void CloudOSNativeSystemControlWindow::DisconnectSelectedWifi()
{
    const int selected = SelectedListIndex();
    if (selected < 0 || static_cast<std::size_t>(selected) >= wifi_.size())
    {
        const auto connected = std::find_if(wifi_.begin(), wifi_.end(), [](const NativeWifiNetwork& item) { return item.connected; });
        if (connected == wifi_.end())
        {
            ShowError(L"Wi-Fi", L"Nenhuma conexao Wi-Fi ativa foi encontrada.");
            return;
        }
        std::wstring error;
        if (!NativeSystemControlBackend::DisconnectWifi(connected->interface_guid, &error))
        {
            ShowError(L"Desconectar Wi-Fi", error);
        }
        RefreshWifi();
        return;
    }

    std::wstring error;
    if (!NativeSystemControlBackend::DisconnectWifi(wifi_[static_cast<std::size_t>(selected)].interface_guid, &error))
    {
        ShowError(L"Desconectar Wi-Fi", error);
    }
    RefreshWifi();
}

void CloudOSNativeSystemControlWindow::HandleSlider(HWND slider)
{
    if (slider != slider_ || slider_programmatic_)
    {
        return;
    }
    const unsigned value = static_cast<unsigned>(SendMessageW(slider_, TBM_GETPOS, 0, 0));
    SetText(slider_value_, PercentText(value));
    std::wstring error;
    if (page_ == Page::Audio)
    {
        if (!NativeSystemControlBackend::SetMasterVolume(value, &error))
        {
            ShowError(L"Volume", error);
        }
    }
    else if (page_ == Page::Display)
    {
        if (!NativeSystemControlBackend::SetBrightness(value, &error))
        {
            ShowError(L"Brilho", error);
            RefreshDisplay();
        }
    }
}

void CloudOSNativeSystemControlWindow::HandleAction(int control_id)
{
    const int action = control_id - kActionBase;
    if (action < 0 || action >= 4)
    {
        return;
    }

    std::wstring error;
    switch (page_)
    {
    case Page::Overview:
        if (action == 0) OpenTarget(L"taskmgr.exe");
        else if (action == 1) OpenTarget(L"ms-settings:");
        else if (action == 2) OpenTarget(L"devmgmt.msc");
        else OpenTarget(L"control.exe");
        break;

    case Page::Wifi:
        if (action == 0) RefreshWifi();
        else if (action == 1) ConnectSelectedWifi();
        else if (action == 2) DisconnectSelectedWifi();
        else OpenTarget(L"ms-settings:network-wifi");
        break;

    case Page::Display:
        if (action == 0) OpenTarget(L"ms-settings:display");
        else if (action == 1) OpenTarget(L"ms-settings:display-advanced");
        else if (action == 2) OpenTarget(L"dccw.exe");
        else OpenTarget(L"desk.cpl");
        break;

    case Page::Audio:
        if (action == 0)
        {
            if (!NativeSystemControlBackend::SetMasterMute(!audio_.muted, &error)) ShowError(L"Audio", error);
            RefreshAudio();
        }
        else if (action == 1) OpenTarget(L"ms-settings:sound");
        else if (action == 2) OpenTarget(L"sndvol.exe");
        else OpenTarget(L"mmsys.cpl");
        break;

    case Page::Power:
        if (action == 0)
        {
            if (!NativeSystemControlBackend::SetBalancedPowerPlan(&error)) ShowError(L"Energia", error);
        }
        else if (action == 1)
        {
            if (!NativeSystemControlBackend::SetPowerSaverPlan(&error)) ShowError(L"Energia", error);
        }
        else if (action == 2)
        {
            if (!NativeSystemControlBackend::SetHighPerformancePlan(&error)) ShowError(L"Energia", error);
        }
        else OpenTarget(L"ms-settings:powersleep");
        RefreshPower();
        break;

    case Page::Network:
        if (action == 0) RefreshNetwork();
        else if (action == 1) OpenTarget(L"ncpa.cpl");
        else if (action == 2) OpenTarget(L"ms-settings:network-status");
        else OpenTarget(L"cmd.exe", L"/k ipconfig /all");
        break;

    case Page::Storage:
        if (action == 0)
        {
            const int selected = SelectedListIndex();
            if (selected >= 0 && static_cast<std::size_t>(selected) < drives_.size())
            {
                OpenTarget(drives_[static_cast<std::size_t>(selected)].root.c_str());
            }
            else
            {
                OpenTarget(L"explorer.exe", L"shell:MyComputerFolder");
            }
        }
        else if (action == 1) OpenTarget(L"diskmgmt.msc");
        else if (action == 2) OpenTarget(L"ms-settings:storagesense");
        else OpenTarget(L"cleanmgr.exe");
        break;

    case Page::Processes:
        if (action == 0) RefreshProcesses();
        else if (action == 1) OpenTarget(L"taskmgr.exe");
        else if (action == 2) OpenTarget(L"resmon.exe");
        else
        {
            const int selected = SelectedListIndex();
            if (selected < 0 || static_cast<std::size_t>(selected) >= processes_.size())
            {
                ShowError(L"Processos", L"Selecione um processo para finalizar.");
                return;
            }
            const NativeProcessInfo& process = processes_[static_cast<std::size_t>(selected)];
            if (process.process_id == GetCurrentProcessId())
            {
                ShowError(L"Processos", L"A Central do Sistema nao finaliza o proprio CloudOS por este comando.");
                return;
            }
            std::wstring message = L"Finalizar ";
            message += process.name;
            message += L" (PID ";
            message += std::to_wstring(process.process_id);
            message += L")?\n\nDados nao salvos nesse processo podem ser perdidos.";
            if (MessageBoxW(window_, message.c_str(), L"CloudOS - Finalizar processo", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
            {
                return;
            }
            HANDLE handle = OpenProcess(PROCESS_TERMINATE, FALSE, process.process_id);
            if (handle == nullptr)
            {
                ShowError(L"Processos", L"O Windows negou permissao para finalizar esse processo.");
                return;
            }
            const BOOL terminated = TerminateProcess(handle, 1);
            CloseHandle(handle);
            if (!terminated)
            {
                ShowError(L"Processos", L"Nao foi possivel finalizar o processo selecionado.");
            }
            RefreshProcesses();
        }
        break;
    }
}

void CloudOSNativeSystemControlWindow::ShowError(const std::wstring& title, const std::wstring& error)
{
    MessageBoxW(
        window_,
        error.empty() ? L"A operacao nao pôde ser concluida." : error.c_str(),
        title.c_str(),
        MB_OK | MB_ICONWARNING);
}

void CloudOSNativeSystemControlWindow::OpenTarget(const wchar_t* target, const wchar_t* parameters)
{
    if (!NativeSystemControlBackend::OpenWindowsTarget(window_, target, parameters))
    {
        std::wstring message = L"Nao foi possivel abrir: ";
        message += target != nullptr ? target : L"destino";
        ShowError(L"CloudOS", message);
    }
}

LRESULT CloudOSNativeSystemControlWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_CREATE:
        return 0;

    case WM_SIZE:
        Layout();
        return 0;

    case WM_PAINT:
        Paint();
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            Refresh(false);
            return 0;
        }
        break;

    case WM_COMMAND:
    {
        const int id = LOWORD(w_param);
        if (id >= kNavBase && id < kNavBase + static_cast<int>(nav_buttons_.size()) && HIWORD(w_param) == BN_CLICKED)
        {
            SetPage(static_cast<Page>(id - kNavBase));
            return 0;
        }
        if (id >= kActionBase && id < kActionBase + static_cast<int>(action_buttons_.size()) && HIWORD(w_param) == BN_CLICKED)
        {
            HandleAction(id);
            return 0;
        }
        break;
    }

    case WM_HSCROLL:
        if (reinterpret_cast<HWND>(l_param) == slider_)
        {
            HandleSlider(slider_);
            return 0;
        }
        break;

    case WM_NOTIFY:
    {
        auto* header = reinterpret_cast<NMHDR*>(l_param);
        if (header != nullptr && header->hwndFrom == list_)
        {
            if (header->code == NM_CUSTOMDRAW)
            {
                return WebSkin::HandleListViewCustomDraw(
                    reinterpret_cast<LPNMLVCUSTOMDRAW>(l_param));
            }
            if (header->code == NM_DBLCLK)
            {
                if (page_ == Page::Wifi) ConnectSelectedWifi();
                else if (page_ == Page::Storage) HandleAction(kActionBase);
                return 0;
            }
        }
        break;
    }

    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw == nullptr)
        {
            break;
        }
        ButtonTone tone = ButtonTone::Neutral;
        const int id = static_cast<int>(draw->CtlID);
        if (id >= kNavBase && id < kNavBase + static_cast<int>(nav_buttons_.size()))
        {
            if ((id - kNavBase) == static_cast<int>(page_))
            {
                tone = ButtonTone::Accent;
            }
        }
        else if (id == kActionBase)
        {
            tone = ButtonTone::Accent;
        }
        else if (page_ == Page::Processes && id == kActionBase + 3)
        {
            tone = ButtonTone::Danger;
        }
        if (WebSkin::PaintOwnerDrawButton(draw, tone))
        {
            return TRUE;
        }
        break;
    }

    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetBkMode(dc, TRANSPARENT);
        HWND control = reinterpret_cast<HWND>(l_param);
        SetTextColor(dc, control == title_ ? WebSkin::TextPrimary : WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(background_ != nullptr ? background_ : WebSkin::SharedBackgroundBrush());
    }

    case WM_KEYDOWN:
        if (w_param == VK_F5)
        {
            Refresh(true);
            return 0;
        }
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            if (w_param >= L'1' && w_param <= L'8')
            {
                SetPage(static_cast<Page>(static_cast<int>(w_param - L'1')));
                return 0;
            }
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window);
        return 0;

    case WM_NCDESTROY:
    {
        KillTimer(window, kRefreshTimer);
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        window_ = nullptr;
        LRESULT result = DefWindowProcW(window, message, w_param, l_param);
        delete this;
        return result;
    }
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeSystemControlWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeSystemControlWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = create != nullptr
            ? static_cast<CloudOSNativeSystemControlWindow*>(create->lpCreateParams)
            : nullptr;
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    if (self != nullptr)
    {
        return self->HandleMessage(window, message, w_param, l_param);
    }
    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
