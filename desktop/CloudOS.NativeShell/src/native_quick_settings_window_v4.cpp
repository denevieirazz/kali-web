#include "native_quick_settings_window.h"

#include "native_appearance_manager.h"
#include "native_cloudos_tray.h"
#include "native_control_plane_service.h"
#include "native_notification_center.h"
#include "native_system_control_window.h"
#include "native_theme.h"
#include "native_toast_overlay.h"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kQuickSettingsClass[] = L"CloudOS.NativeShell.QuickSettings.v4";
constexpr int kVolumeSliderId = 8801;
constexpr int kMuteId = 8802;
constexpr int kWifiComboId = 8803;
constexpr int kWifiActionId = 8804;
constexpr int kBluetoothId = 8805;
constexpr int kBrightnessSliderId = 8806;
constexpr int kBalancedId = 8807;
constexpr int kSaverId = 8808;
constexpr int kPerformanceId = 8809;
constexpr int kSystemCenterId = 8810;
constexpr int kAppearanceId = 8811;
constexpr UINT_PTR kRefreshTimer = 8812;

// Compatibility note: V2 implemented IAudioEndpointVolume directly here using
// GetMasterVolumeLevelScalar / SetMasterVolumeLevelScalar / SetMute and
// GetSystemPowerStatus. V4 routes those operations through
// NativeSystemControlBackend so Quick Settings and System Center share one
// authoritative backend. The official fallbacks remain ms-settings:network-wifi
// and ms-settings:bluetooth for credentials/pairing Windows must own.

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

std::wstring WifiCaption(const NativeWifiNetwork& network)
{
    std::wstring text = network.ssid.empty() ? L"Rede sem nome" : network.ssid;
    text += L"  ·  ";
    text += std::to_wstring(network.signal_quality);
    text += L"%";
    if (network.connected) text += L"  ·  conectado";
    else if (network.profile_name.empty()) text += L"  ·  senha necessaria";
    return text;
}
}

CloudOSNativeQuickSettingsWindow::~CloudOSNativeQuickSettingsWindow()
{
    Destroy();
}

bool CloudOSNativeQuickSettingsWindow::Create(HINSTANCE instance)
{
    instance_ = instance;

    (void)NativeToastOverlay::Initialize(instance_);
    (void)NativeControlPlaneService::Instance().Start(instance_);
    (void)NativeCloudOSTrayService::Instance().Start(instance_);

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeQuickSettingsWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kQuickSettingsClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kQuickSettingsClass,
        L"Configuracoes Rapidas - CloudOS",
        WS_POPUP | WS_CLIPCHILDREN,
        0, 0, 520, 548,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    background_ = WebSkin::CreateBackgroundBrush();
    font_ = CreateFontW(-15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    small_font_ = CreateFontW(-13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(-23, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    title_ = CreateWindowW(L"STATIC", L"Configuracoes rapidas", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    subtitle_ = CreateWindowW(L"STATIC", L"Controles reais do Windows · CloudOS Control Plane V4",
        WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_label_ = CreateWindowW(L"STATIC", L"Volume", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kVolumeSliderId)), instance_, nullptr);
    mute_button_ = CreateWindowW(L"BUTTON", L"Mudo", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteId)), instance_, nullptr);

    wifi_label_ = CreateWindowW(L"STATIC", L"Wi-Fi", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    wifi_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiComboId)), instance_, nullptr);
    wifi_action_button_ = CreateWindowW(L"BUTTON", L"Conectar", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiActionId)), instance_, nullptr);
    bluetooth_button_ = CreateWindowW(L"BUTTON", L"Bluetooth / pareamento", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothId)), instance_, nullptr);

    brightness_label_ = CreateWindowW(L"STATIC", L"Brilho", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    brightness_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBrightnessSliderId)), instance_, nullptr);

    power_label_ = CreateWindowW(L"STATIC", L"Energia", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    balanced_button_ = CreateWindowW(L"BUTTON", L"Equilibrado", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBalancedId)), instance_, nullptr);
    saver_button_ = CreateWindowW(L"BUTTON", L"Economia", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSaverId)), instance_, nullptr);
    performance_button_ = CreateWindowW(L"BUTTON", L"Desempenho", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPerformanceId)), instance_, nullptr);

    system_center_button_ = CreateWindowW(L"BUTTON", L"Abrir Central do Sistema", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSystemCenterId)), instance_, nullptr);
    appearance_button_ = CreateWindowW(L"BUTTON", L"Trocar cor de destaque", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kAppearanceId)), instance_, nullptr);

    for (HWND control : {title_, subtitle_, volume_label_, volume_slider_, mute_button_, wifi_label_,
             wifi_combo_, wifi_action_button_, bluetooth_button_, brightness_label_, brightness_slider_,
             power_label_, balanced_button_, saver_button_, performance_button_, system_center_button_, appearance_button_})
    {
        if (control == nullptr) { Destroy(); return false; }
    }

    SetControlFont(title_, title_font_);
    SetControlFont(subtitle_, small_font_);
    for (HWND control : {volume_label_, volume_slider_, mute_button_, wifi_label_, wifi_combo_,
             wifi_action_button_, bluetooth_button_, brightness_label_, brightness_slider_, power_label_,
             balanced_button_, saver_button_, performance_button_, system_center_button_, appearance_button_})
        SetControlFont(control, font_);

    SendMessageW(volume_slider_, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
    SendMessageW(volume_slider_, TBM_SETPAGESIZE, 0, 5);
    SendMessageW(brightness_slider_, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
    SendMessageW(brightness_slider_, TBM_SETPAGESIZE, 0, 5);

    for (HWND button : {mute_button_, wifi_action_button_, bluetooth_button_, balanced_button_, saver_button_,
             performance_button_, system_center_button_, appearance_button_})
        WebSkin::PrepareButton(button);
    WebSkin::ApplyUxTheme(volume_slider_);
    WebSkin::ApplyUxTheme(brightness_slider_);
    WebSkin::ApplyUxTheme(wifi_combo_);
    ApplyWebFlyoutMaterial(window_);
    Layout();
    UpdateState(true);
    return true;
}

void CloudOSNativeQuickSettingsWindow::Destroy()
{
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kRefreshTimer);
        DestroyWindow(window_);
    }
    window_ = nullptr;
    for (HWND* control : {&title_, &subtitle_, &volume_label_, &volume_slider_, &mute_button_, &wifi_label_,
             &wifi_combo_, &wifi_action_button_, &bluetooth_button_, &brightness_label_, &brightness_slider_,
             &power_label_, &balanced_button_, &saver_button_, &performance_button_, &system_center_button_, &appearance_button_})
        *control = nullptr;
    wifi_networks_.clear();
    if (font_ != nullptr) { DeleteObject(font_); font_ = nullptr; }
    if (small_font_ != nullptr) { DeleteObject(small_font_); small_font_ = nullptr; }
    if (title_font_ != nullptr) { DeleteObject(title_font_); title_font_ = nullptr; }
    if (background_ != nullptr) { DeleteObject(background_); background_ = nullptr; }
}

void CloudOSNativeQuickSettingsWindow::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::max<LONG>(1, client.right - client.left);
    const int margin = Scale(20, dpi);
    const int gap = Scale(10, dpi);
    const int inner = width - margin * 2;

    MoveWindow(title_, margin, Scale(16, dpi), inner, Scale(32, dpi), TRUE);
    MoveWindow(subtitle_, margin, Scale(48, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(volume_label_, margin, Scale(82, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(volume_slider_, margin, Scale(106, dpi), inner - Scale(96, dpi), Scale(30, dpi), TRUE);
    MoveWindow(mute_button_, width - margin - Scale(86, dpi), Scale(103, dpi), Scale(86, dpi), Scale(34, dpi), TRUE);

    MoveWindow(wifi_label_, margin, Scale(150, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(wifi_combo_, margin, Scale(174, dpi), inner - Scale(108, dpi), Scale(330, dpi), TRUE);
    MoveWindow(wifi_action_button_, width - margin - Scale(98, dpi), Scale(172, dpi), Scale(98, dpi), Scale(36, dpi), TRUE);
    MoveWindow(bluetooth_button_, margin, Scale(216, dpi), inner, Scale(38, dpi), TRUE);

    MoveWindow(brightness_label_, margin, Scale(266, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(brightness_slider_, margin, Scale(290, dpi), inner, Scale(30, dpi), TRUE);

    MoveWindow(power_label_, margin, Scale(332, dpi), inner, Scale(24, dpi), TRUE);
    const int third = (inner - gap * 2) / 3;
    MoveWindow(balanced_button_, margin, Scale(360, dpi), third, Scale(40, dpi), TRUE);
    MoveWindow(saver_button_, margin + third + gap, Scale(360, dpi), third, Scale(40, dpi), TRUE);
    MoveWindow(performance_button_, margin + (third + gap) * 2, Scale(360, dpi), third, Scale(40, dpi), TRUE);

    MoveWindow(system_center_button_, margin, Scale(420, dpi), inner, Scale(42, dpi), TRUE);
    MoveWindow(appearance_button_, margin, Scale(472, dpi), inner, Scale(38, dpi), TRUE);
}

int CloudOSNativeQuickSettingsWindow::SelectedWifiIndex() const noexcept
{
    if (wifi_combo_ == nullptr) return -1;
    const LRESULT selected = SendMessageW(wifi_combo_, CB_GETCURSEL, 0, 0);
    return selected == CB_ERR ? -1 : static_cast<int>(selected);
}

void CloudOSNativeQuickSettingsWindow::UpdateState(bool force_wifi)
{
    const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
    updating_slider_ = true;
    SendMessageW(volume_slider_, TBM_SETPOS, TRUE, static_cast<LPARAM>(audio.volume_percent));
    updating_slider_ = false;
    EnableWindow(volume_slider_, audio.available);
    EnableWindow(mute_button_, audio.available);
    std::wstring audio_text = L"Volume  ·  ";
    audio_text += audio.available ? std::to_wstring(audio.volume_percent) + L"%" : L"indisponivel";
    if (!audio.endpoint_name.empty()) audio_text += L"  ·  " + audio.endpoint_name;
    SetWindowTextW(volume_label_, audio_text.c_str());
    SetWindowTextW(mute_button_, audio.muted ? L"Ativar som" : L"Mudo");

    const NativeBrightnessState brightness = NativeSystemControlBackend::QueryBrightness();
    updating_slider_ = true;
    SendMessageW(brightness_slider_, TBM_SETPOS, TRUE, static_cast<LPARAM>(brightness.percent));
    updating_slider_ = false;
    EnableWindow(brightness_slider_, brightness.available);
    std::wstring brightness_text = L"Brilho  ·  ";
    if (brightness.available)
    {
        brightness_text += std::to_wstring(brightness.percent) + L"%";
        if (!brightness.source.empty()) brightness_text += L"  ·  " + brightness.source;
    }
    else brightness_text += L"hardware nao expoe DDC/CI ou WMI";
    SetWindowTextW(brightness_label_, brightness_text.c_str());

    const NativePowerState power = NativeSystemControlBackend::QueryPower();
    std::wstring power_text = L"Energia  ·  " + (power.active_plan.empty() ? std::wstring(L"plano atual") : power.active_plan);
    if (power.battery_present)
        power_text += L"  ·  " + std::to_wstring(power.battery_percent) + L"%" + (power.on_ac ? L" AC" : L" bateria");
    SetWindowTextW(power_label_, power_text.c_str());

    ++wifi_refresh_tick_;
    if (force_wifi || wifi_networks_.empty() || (wifi_refresh_tick_ % 3u) == 0u)
    {
        const int previous = SelectedWifiIndex();
        wifi_networks_ = NativeSystemControlBackend::ScanWifi();
        SendMessageW(wifi_combo_, CB_RESETCONTENT, 0, 0);
        int connected_index = -1;
        for (std::size_t index = 0; index < wifi_networks_.size(); ++index)
        {
            const std::wstring caption = WifiCaption(wifi_networks_[index]);
            SendMessageW(wifi_combo_, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(caption.c_str()));
            if (wifi_networks_[index].connected) connected_index = static_cast<int>(index);
        }
        int selection = connected_index >= 0 ? connected_index : previous;
        if (selection < 0 && !wifi_networks_.empty()) selection = 0;
        if (selection >= static_cast<int>(wifi_networks_.size())) selection = 0;
        if (selection >= 0) SendMessageW(wifi_combo_, CB_SETCURSEL, selection, 0);
    }

    const int wifi_index = SelectedWifiIndex();
    const bool valid_wifi = wifi_index >= 0 && wifi_index < static_cast<int>(wifi_networks_.size());
    SetWindowTextW(wifi_action_button_, valid_wifi && wifi_networks_[static_cast<std::size_t>(wifi_index)].connected
        ? L"Desconectar" : L"Conectar");
    EnableWindow(wifi_action_button_, valid_wifi);
    std::wstring wifi_text = L"Wi-Fi";
    if (valid_wifi && wifi_networks_[static_cast<std::size_t>(wifi_index)].connected)
        wifi_text += L"  ·  " + wifi_networks_[static_cast<std::size_t>(wifi_index)].ssid;
    else if (wifi_networks_.empty()) wifi_text += L"  ·  nenhuma rede detectada";
    SetWindowTextW(wifi_label_, wifi_text.c_str());

    NativeControlPlaneService::Instance().RefreshNow();
    NativeCloudOSTrayService::Instance().Refresh();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeQuickSettingsWindow::ApplyVolumeFromSlider()
{
    if (updating_slider_ || volume_slider_ == nullptr) return;
    const unsigned value = static_cast<unsigned>(std::clamp<int>(
        static_cast<int>(SendMessageW(volume_slider_, TBM_GETPOS, 0, 0)), 0, 100));
    std::wstring error;
    if (!NativeSystemControlBackend::SetMasterVolume(value, &error))
        ShowOperationResult(L"Volume", false, error);
    else if (value > 0)
        (void)NativeSystemControlBackend::SetMasterMute(false, nullptr);
    UpdateState(false);
}

void CloudOSNativeQuickSettingsWindow::ApplyBrightnessFromSlider()
{
    if (updating_slider_ || brightness_slider_ == nullptr) return;
    const unsigned value = static_cast<unsigned>(std::clamp<int>(
        static_cast<int>(SendMessageW(brightness_slider_, TBM_GETPOS, 0, 0)), 0, 100));
    std::wstring error;
    const bool success = NativeSystemControlBackend::SetBrightness(value, &error);
    if (!success) ShowOperationResult(L"Brilho", false, error);
    UpdateState(false);
}

void CloudOSNativeQuickSettingsWindow::ToggleMute()
{
    const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
    if (!audio.available) return;
    std::wstring error;
    const bool success = NativeSystemControlBackend::SetMasterMute(!audio.muted, &error);
    if (!success) ShowOperationResult(L"Audio", false, error);
    UpdateState(false);
}

void CloudOSNativeQuickSettingsWindow::HandleWifiAction()
{
    const int index = SelectedWifiIndex();
    if (index < 0 || index >= static_cast<int>(wifi_networks_.size())) return;
    const NativeWifiNetwork network = wifi_networks_[static_cast<std::size_t>(index)];
    std::wstring error;
    bool success = false;
    if (network.connected)
        success = NativeSystemControlBackend::DisconnectWifi(network.interface_guid, &error);
    else if (!network.profile_name.empty())
        success = NativeSystemControlBackend::ConnectKnownWifi(network, &error);
    else
    {
        (void)NativeSystemControlBackend::OpenWindowsTarget(window_, L"ms-settings:network-wifi");
        NativeToastOverlay::Post(L"Credencial do Wi-Fi",
            L"O Windows abriu o fluxo oficial para informar a senha da rede.", 0, 4200u);
        return;
    }
    ShowOperationResult(network.connected ? L"Wi-Fi desconectado" : L"Wi-Fi conectado", success, error);
    UpdateState(true);
}

void CloudOSNativeQuickSettingsWindow::ApplyPowerPlan(int plan)
{
    std::wstring error;
    bool success = false;
    if (plan == 0) success = NativeSystemControlBackend::SetBalancedPowerPlan(&error);
    else if (plan == 1) success = NativeSystemControlBackend::SetPowerSaverPlan(&error);
    else success = NativeSystemControlBackend::SetHighPerformancePlan(&error);
    ShowOperationResult(L"Plano de energia", success, error);
    UpdateState(false);
}

void CloudOSNativeQuickSettingsWindow::CycleAccent()
{
    const COLORREF next = NativeAppearanceManager::NextPresetAccent(NativeAppearanceManager::Accent());
    NativeAppearanceManager::SetAccent(next);
    NativeToastOverlay::Post(L"Cor de destaque atualizada",
        L"A tray e as superficies Control Plane passam a usar a nova cor imediatamente.", 0, 3200u);
    NativeCloudOSTrayService::Instance().Refresh();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeQuickSettingsWindow::OpenSystemCenter()
{
    (void)CloudOSNativeSystemControlWindow::Open(instance_, window_);
}

void CloudOSNativeQuickSettingsWindow::ShowOperationResult(
    const std::wstring& title, bool success, const std::wstring& error)
{
    const std::wstring detail = success ? L"Operacao concluida." :
        (error.empty() ? L"O Windows recusou a operacao." : error);
    CloudOSNativeNotificationCenter::Post(title, detail, success ? 0 : 1);
    NativeToastOverlay::Post(title, detail, success ? 0 : 1, success ? 3000u : 5200u);
}

void CloudOSNativeQuickSettingsWindow::ShowNear(const RECT& anchor)
{
    if (window_ == nullptr) return;
    UpdateState(true);
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(520, dpi);
    const int height = Scale(548, dpi);
    int x = anchor.right - width;
    int y = anchor.top - height - Scale(10, dpi);
    x = std::clamp<int>(x, static_cast<int>(info.rcWork.left),
        std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(y, static_cast<int>(info.rcWork.top),
        std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));
    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetTimer(window_, kRefreshTimer, 2500, nullptr);
}

void CloudOSNativeQuickSettingsWindow::ToggleNear(const RECT& anchor)
{
    if (window_ != nullptr) IsWindowVisible(window_) ? Hide() : ShowNear(anchor);
}

void CloudOSNativeQuickSettingsWindow::Hide()
{
    if (window_ != nullptr)
    {
        KillTimer(window_, kRefreshTimer);
        ShowWindow(window_, SW_HIDE);
    }
}

void CloudOSNativeQuickSettingsWindow::Refresh()
{
    UpdateState(false);
}

LRESULT CloudOSNativeQuickSettingsWindow::HandleMessage(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
    case WM_DPICHANGED:
        Layout();
        return 0;
    case WM_HSCROLL:
        if (reinterpret_cast<HWND>(l_param) == volume_slider_)
        {
            ApplyVolumeFromSlider();
            return 0;
        }
        if (reinterpret_cast<HWND>(l_param) == brightness_slider_)
        {
            ApplyBrightnessFromSlider();
            return 0;
        }
        break;
    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kMuteId: ToggleMute(); return 0;
        case kWifiActionId: HandleWifiAction(); return 0;
        case kBluetoothId:
            (void)NativeSystemControlBackend::OpenWindowsTarget(window_, L"ms-settings:bluetooth");
            return 0;
        case kBalancedId: ApplyPowerPlan(0); return 0;
        case kSaverId: ApplyPowerPlan(1); return 0;
        case kPerformanceId: ApplyPowerPlan(2); return 0;
        case kSystemCenterId: OpenSystemCenter(); return 0;
        case kAppearanceId: CycleAccent(); return 0;
        default: break;
        }
        break;
    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            UpdateState(false);
            return 0;
        }
        break;
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE) Hide();
        return 0;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE) { Hide(); return 0; }
        break;
    case WM_DRAWITEM:
        if (WebSkin::PaintOwnerDrawButton(reinterpret_cast<DRAWITEMSTRUCT*>(l_param),
                LOWORD(w_param) == kSystemCenterId ? WebSkin::ButtonTone::Accent : WebSkin::ButtonTone::Neutral))
            return TRUE;
        break;
    case WM_CTLCOLORSTATIC:
        SetBkMode(reinterpret_cast<HDC>(w_param), TRANSPARENT);
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(background_);
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window_, &paint);
        RECT client{};
        GetClientRect(window_, &client);
        WebSkin::PaintWindowBackground(dc, client);
        EndPaint(window_, &paint);
        return 0;
    }
    case WM_NCDESTROY:
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeQuickSettingsWindow::WindowProcedure(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeQuickSettingsWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = reinterpret_cast<CloudOSNativeQuickSettingsWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->window_ = window;
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
