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
constexpr int kMediaPreviousId = 8813;
constexpr int kMediaToggleId = 8814;
constexpr int kMediaNextId = 8815;
constexpr int kMixerComboId = 8816;
constexpr int kMixerSliderId = 8817;
constexpr int kMixerMuteId = 8818;
constexpr int kBluetoothComboId = 8819;
constexpr int kBluetoothActionId = 8820;

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

std::wstring AudioSessionCaption(const NativeAudioSessionV7& session)
{
    std::wstring text = session.title.empty() ? L"Sessao de audio" : session.title;
    text += L"  ·  ";
    text += std::to_wstring(session.volume_percent);
    text += L"%";
    if (session.muted) text += L"  ·  mudo";
    if (session.active) text += L"  ·  ativo";
    return text;
}

std::wstring BluetoothCaption(const NativeBluetoothDeviceV7& device)
{
    std::wstring text = device.name.empty() ? L"Dispositivo Bluetooth" : device.name;
    text += device.low_energy ? L"  ·  BLE" : L"  ·  Bluetooth";
    if (device.paired) text += L"  ·  pareado";
    else if (device.can_pair) text += L"  ·  pronto para parear";
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
    NativeMediaControlV7::RefreshAsync();
    NativeBluetoothV7::RefreshAsync();

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
        0, 0, 560, 820,
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
    subtitle_ = CreateWindowW(L"STATIC", L"CloudOS Visual Platform V7 · controles reais do Windows",
        WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    media_label_ = CreateWindowW(L"STATIC", L"Midia · procurando sessao ativa", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    media_meta_ = CreateWindowW(L"STATIC", L"Spotify, navegadores e players via GSMTC",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_ENDELLIPSIS, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    media_previous_button_ = CreateWindowW(L"BUTTON", L"⏮", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaPreviousId)), instance_, nullptr);
    media_toggle_button_ = CreateWindowW(L"BUTTON", L"Reproduzir", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaToggleId)), instance_, nullptr);
    media_next_button_ = CreateWindowW(L"BUTTON", L"⏭", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaNextId)), instance_, nullptr);

    volume_label_ = CreateWindowW(L"STATIC", L"Volume", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kVolumeSliderId)), instance_, nullptr);
    mute_button_ = CreateWindowW(L"BUTTON", L"Mudo", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteId)), instance_, nullptr);

    mixer_label_ = CreateWindowW(L"STATIC", L"Mixer por aplicativo", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    mixer_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerComboId)), instance_, nullptr);
    mixer_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerSliderId)), instance_, nullptr);
    mixer_mute_button_ = CreateWindowW(L"BUTTON", L"Mudo app", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerMuteId)), instance_, nullptr);

    wifi_label_ = CreateWindowW(L"STATIC", L"Wi-Fi", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    wifi_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiComboId)), instance_, nullptr);
    wifi_action_button_ = CreateWindowW(L"BUTTON", L"Conectar", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiActionId)), instance_, nullptr);

    bluetooth_label_ = CreateWindowW(L"STATIC", L"Bluetooth", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    bluetooth_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothComboId)), instance_, nullptr);
    bluetooth_action_button_ = CreateWindowW(L"BUTTON", L"Parear", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothActionId)), instance_, nullptr);
    bluetooth_button_ = CreateWindowW(L"BUTTON", L"Abrir Bluetooth do Windows", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
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

    for (HWND control : {title_, subtitle_, media_label_, media_meta_, media_previous_button_, media_toggle_button_, media_next_button_,
             volume_label_, volume_slider_, mute_button_, mixer_label_, mixer_combo_, mixer_slider_, mixer_mute_button_,
             wifi_label_, wifi_combo_, wifi_action_button_, bluetooth_label_, bluetooth_combo_, bluetooth_action_button_, bluetooth_button_,
             brightness_label_, brightness_slider_, power_label_, balanced_button_, saver_button_, performance_button_,
             system_center_button_, appearance_button_})
    {
        if (control == nullptr) { Destroy(); return false; }
    }

    SetControlFont(title_, title_font_);
    SetControlFont(subtitle_, small_font_);
    SetControlFont(media_meta_, small_font_);
    for (HWND control : {media_label_, media_previous_button_, media_toggle_button_, media_next_button_,
             volume_label_, volume_slider_, mute_button_, mixer_label_, mixer_combo_, mixer_slider_, mixer_mute_button_,
             wifi_label_, wifi_combo_, wifi_action_button_, bluetooth_label_, bluetooth_combo_, bluetooth_action_button_, bluetooth_button_,
             brightness_label_, brightness_slider_, power_label_, balanced_button_, saver_button_, performance_button_,
             system_center_button_, appearance_button_})
        SetControlFont(control, font_);

    for (HWND slider : {volume_slider_, mixer_slider_, brightness_slider_})
    {
        SendMessageW(slider, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
        SendMessageW(slider, TBM_SETPAGESIZE, 0, 5);
        WebSkin::ApplyUxTheme(slider);
    }

    for (HWND button : {media_previous_button_, media_toggle_button_, media_next_button_, mute_button_, mixer_mute_button_,
             wifi_action_button_, bluetooth_action_button_, bluetooth_button_, balanced_button_, saver_button_,
             performance_button_, system_center_button_, appearance_button_})
        WebSkin::PrepareButton(button);
    for (HWND combo : {mixer_combo_, wifi_combo_, bluetooth_combo_}) WebSkin::ApplyUxTheme(combo);

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
    for (HWND* control : {&title_, &subtitle_, &media_label_, &media_meta_, &media_previous_button_, &media_toggle_button_, &media_next_button_,
             &volume_label_, &volume_slider_, &mute_button_, &mixer_label_, &mixer_combo_, &mixer_slider_, &mixer_mute_button_,
             &wifi_label_, &wifi_combo_, &wifi_action_button_, &bluetooth_label_, &bluetooth_combo_, &bluetooth_action_button_, &bluetooth_button_,
             &brightness_label_, &brightness_slider_, &power_label_, &balanced_button_, &saver_button_, &performance_button_,
             &system_center_button_, &appearance_button_})
        *control = nullptr;
    wifi_networks_.clear();
    audio_sessions_.clear();
    bluetooth_devices_.clear();
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
    const int margin = Scale(22, dpi);
    const int gap = Scale(10, dpi);
    const int inner = width - margin * 2;

    MoveWindow(title_, margin, Scale(16, dpi), inner, Scale(32, dpi), TRUE);
    MoveWindow(subtitle_, margin, Scale(48, dpi), inner, Scale(22, dpi), TRUE);

    MoveWindow(media_label_, margin, Scale(86, dpi), inner, Scale(24, dpi), TRUE);
    MoveWindow(media_meta_, margin, Scale(110, dpi), inner, Scale(20, dpi), TRUE);
    MoveWindow(media_previous_button_, margin, Scale(136, dpi), Scale(70, dpi), Scale(38, dpi), TRUE);
    MoveWindow(media_toggle_button_, margin + Scale(80, dpi), Scale(136, dpi), inner - Scale(160, dpi), Scale(38, dpi), TRUE);
    MoveWindow(media_next_button_, width - margin - Scale(70, dpi), Scale(136, dpi), Scale(70, dpi), Scale(38, dpi), TRUE);

    MoveWindow(volume_label_, margin, Scale(194, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(volume_slider_, margin, Scale(218, dpi), inner - Scale(96, dpi), Scale(30, dpi), TRUE);
    MoveWindow(mute_button_, width - margin - Scale(86, dpi), Scale(215, dpi), Scale(86, dpi), Scale(34, dpi), TRUE);

    MoveWindow(mixer_label_, margin, Scale(258, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(mixer_combo_, margin, Scale(282, dpi), inner, Scale(240, dpi), TRUE);
    MoveWindow(mixer_slider_, margin, Scale(322, dpi), inner - Scale(106, dpi), Scale(30, dpi), TRUE);
    MoveWindow(mixer_mute_button_, width - margin - Scale(96, dpi), Scale(319, dpi), Scale(96, dpi), Scale(34, dpi), TRUE);

    MoveWindow(wifi_label_, margin, Scale(366, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(wifi_combo_, margin, Scale(390, dpi), inner - Scale(108, dpi), Scale(260, dpi), TRUE);
    MoveWindow(wifi_action_button_, width - margin - Scale(98, dpi), Scale(388, dpi), Scale(98, dpi), Scale(36, dpi), TRUE);

    MoveWindow(bluetooth_label_, margin, Scale(434, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(bluetooth_combo_, margin, Scale(458, dpi), inner - Scale(108, dpi), Scale(230, dpi), TRUE);
    MoveWindow(bluetooth_action_button_, width - margin - Scale(98, dpi), Scale(456, dpi), Scale(98, dpi), Scale(36, dpi), TRUE);
    MoveWindow(bluetooth_button_, margin, Scale(498, dpi), inner, Scale(36, dpi), TRUE);

    MoveWindow(brightness_label_, margin, Scale(550, dpi), inner, Scale(22, dpi), TRUE);
    MoveWindow(brightness_slider_, margin, Scale(574, dpi), inner, Scale(30, dpi), TRUE);

    MoveWindow(power_label_, margin, Scale(616, dpi), inner, Scale(24, dpi), TRUE);
    const int third = (inner - gap * 2) / 3;
    MoveWindow(balanced_button_, margin, Scale(644, dpi), third, Scale(40, dpi), TRUE);
    MoveWindow(saver_button_, margin + third + gap, Scale(644, dpi), third, Scale(40, dpi), TRUE);
    MoveWindow(performance_button_, margin + (third + gap) * 2, Scale(644, dpi), third, Scale(40, dpi), TRUE);

    MoveWindow(system_center_button_, margin, Scale(704, dpi), inner, Scale(42, dpi), TRUE);
    MoveWindow(appearance_button_, margin, Scale(754, dpi), inner, Scale(38, dpi), TRUE);
}

int CloudOSNativeQuickSettingsWindow::SelectedWifiIndex() const noexcept
{
    if (wifi_combo_ == nullptr) return -1;
    const LRESULT selected = SendMessageW(wifi_combo_, CB_GETCURSEL, 0, 0);
    return selected == CB_ERR ? -1 : static_cast<int>(selected);
}

int CloudOSNativeQuickSettingsWindow::SelectedAudioSessionIndex() const noexcept
{
    if (mixer_combo_ == nullptr) return -1;
    const LRESULT selected = SendMessageW(mixer_combo_, CB_GETCURSEL, 0, 0);
    return selected == CB_ERR ? -1 : static_cast<int>(selected);
}

int CloudOSNativeQuickSettingsWindow::SelectedBluetoothIndex() const noexcept
{
    if (bluetooth_combo_ == nullptr) return -1;
    const LRESULT selected = SendMessageW(bluetooth_combo_, CB_GETCURSEL, 0, 0);
    return selected == CB_ERR ? -1 : static_cast<int>(selected);
}

void CloudOSNativeQuickSettingsWindow::RefreshMixerSelection()
{
    const int index = SelectedAudioSessionIndex();
    const bool valid = index >= 0 && index < static_cast<int>(audio_sessions_.size());
    EnableWindow(mixer_slider_, valid);
    EnableWindow(mixer_mute_button_, valid);
    if (!valid)
    {
        SetWindowTextW(mixer_mute_button_, L"Mudo app");
        return;
    }
    const NativeAudioSessionV7& session = audio_sessions_[static_cast<std::size_t>(index)];
    updating_slider_ = true;
    SendMessageW(mixer_slider_, TBM_SETPOS, TRUE, static_cast<LPARAM>(session.volume_percent));
    updating_slider_ = false;
    SetWindowTextW(mixer_mute_button_, session.muted ? L"Ativar app" : L"Mudo app");
}

void CloudOSNativeQuickSettingsWindow::RefreshBluetoothSelection()
{
    const int index = SelectedBluetoothIndex();
    const bool valid = index >= 0 && index < static_cast<int>(bluetooth_devices_.size());
    EnableWindow(bluetooth_action_button_, valid);
    if (!valid)
    {
        SetWindowTextW(bluetooth_action_button_, L"Parear");
        return;
    }
    const NativeBluetoothDeviceV7& device = bluetooth_devices_[static_cast<std::size_t>(index)];
    SetWindowTextW(bluetooth_action_button_, device.paired ? L"Remover" : L"Parear");
}

void CloudOSNativeQuickSettingsWindow::UpdateState(bool force_network)
{
    NativeMediaControlV7::RefreshAsync();
    const NativeMediaSnapshot media = NativeMediaControlV7::Snapshot();
    if (media.available)
    {
        std::wstring title = L"Midia  ·  ";
        title += media.title.empty() ? L"reproducao ativa" : media.title;
        SetWindowTextW(media_label_, title.c_str());
        std::wstring meta;
        if (!media.artist.empty()) meta += media.artist;
        if (!media.album.empty()) meta += (meta.empty() ? L"" : L"  ·  ") + media.album;
        if (!media.source_app_id.empty()) meta += (meta.empty() ? L"" : L"  ·  ") + media.source_app_id;
        SetWindowTextW(media_meta_, meta.empty() ? L"Sessao GSMTC ativa" : meta.c_str());
        SetWindowTextW(media_toggle_button_, media.playing ? L"Pausar" : L"Reproduzir");
        EnableWindow(media_toggle_button_, media.can_toggle);
        EnableWindow(media_next_button_, media.can_next);
        EnableWindow(media_previous_button_, media.can_previous);
    }
    else
    {
        SetWindowTextW(media_label_, L"Midia  ·  nenhuma sessao ativa");
        SetWindowTextW(media_meta_, L"Spotify, navegadores e players via GSMTC");
        SetWindowTextW(media_toggle_button_, L"Reproduzir");
        EnableWindow(media_toggle_button_, FALSE);
        EnableWindow(media_next_button_, FALSE);
        EnableWindow(media_previous_button_, FALSE);
    }

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

    ++mixer_refresh_tick_;
    if (force_network || audio_sessions_.empty() || (mixer_refresh_tick_ % 2u) == 0u)
    {
        DWORD previous_pid = 0;
        const int previous_index = SelectedAudioSessionIndex();
        if (previous_index >= 0 && previous_index < static_cast<int>(audio_sessions_.size()))
            previous_pid = audio_sessions_[static_cast<std::size_t>(previous_index)].process_id;
        audio_sessions_ = NativeAudioMixerV7::Enumerate();
        SendMessageW(mixer_combo_, CB_RESETCONTENT, 0, 0);
        int selection = -1;
        for (std::size_t index = 0; index < audio_sessions_.size(); ++index)
        {
            const std::wstring caption = AudioSessionCaption(audio_sessions_[index]);
            SendMessageW(mixer_combo_, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(caption.c_str()));
            if (selection < 0 && previous_pid != 0 && audio_sessions_[index].process_id == previous_pid)
                selection = static_cast<int>(index);
            if (selection < 0 && audio_sessions_[index].active) selection = static_cast<int>(index);
        }
        if (selection < 0 && !audio_sessions_.empty()) selection = 0;
        if (selection >= 0) SendMessageW(mixer_combo_, CB_SETCURSEL, selection, 0);
    }
    std::wstring mixer_text = L"Mixer por aplicativo";
    if (!audio_sessions_.empty()) mixer_text += L"  ·  " + std::to_wstring(audio_sessions_.size()) + L" sessoes";
    SetWindowTextW(mixer_label_, mixer_text.c_str());
    RefreshMixerSelection();

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
    if (force_network || wifi_networks_.empty() || (wifi_refresh_tick_ % 3u) == 0u)
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

    ++bluetooth_refresh_tick_;
    if (force_network || bluetooth_devices_.empty() || (bluetooth_refresh_tick_ % 3u) == 0u)
    {
        NativeBluetoothV7::RefreshAsync();
        const int previous = SelectedBluetoothIndex();
        bluetooth_devices_ = NativeBluetoothV7::Snapshot();
        SendMessageW(bluetooth_combo_, CB_RESETCONTENT, 0, 0);
        for (const auto& device : bluetooth_devices_)
        {
            const std::wstring caption = BluetoothCaption(device);
            SendMessageW(bluetooth_combo_, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(caption.c_str()));
        }
        int selection = previous;
        if (selection < 0 && !bluetooth_devices_.empty()) selection = 0;
        if (selection >= static_cast<int>(bluetooth_devices_.size())) selection = 0;
        if (selection >= 0) SendMessageW(bluetooth_combo_, CB_SETCURSEL, selection, 0);
    }
    std::wstring bluetooth_text = L"Bluetooth";
    if (!bluetooth_devices_.empty()) bluetooth_text += L"  ·  " + std::to_wstring(bluetooth_devices_.size()) + L" dispositivos";
    SetWindowTextW(bluetooth_label_, bluetooth_text.c_str());
    RefreshBluetoothSelection();

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

void CloudOSNativeQuickSettingsWindow::ApplyMixerFromSlider()
{
    if (updating_slider_ || mixer_slider_ == nullptr) return;
    const int index = SelectedAudioSessionIndex();
    if (index < 0 || index >= static_cast<int>(audio_sessions_.size())) return;
    const unsigned value = static_cast<unsigned>(std::clamp<int>(
        static_cast<int>(SendMessageW(mixer_slider_, TBM_GETPOS, 0, 0)), 0, 100));
    NativeAudioSessionV7& session = audio_sessions_[static_cast<std::size_t>(index)];
    if (NativeAudioMixerV7::SetVolume(session.process_id, value))
    {
        session.volume_percent = value;
        if (value > 0 && session.muted)
        {
            (void)NativeAudioMixerV7::SetMute(session.process_id, false);
            session.muted = false;
        }
    }
    RefreshMixerSelection();
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

void CloudOSNativeQuickSettingsWindow::ToggleMixerMute()
{
    const int index = SelectedAudioSessionIndex();
    if (index < 0 || index >= static_cast<int>(audio_sessions_.size())) return;
    NativeAudioSessionV7& session = audio_sessions_[static_cast<std::size_t>(index)];
    if (NativeAudioMixerV7::SetMute(session.process_id, !session.muted))
        session.muted = !session.muted;
    RefreshMixerSelection();
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

void CloudOSNativeQuickSettingsWindow::HandleBluetoothAction()
{
    const int index = SelectedBluetoothIndex();
    if (index < 0 || index >= static_cast<int>(bluetooth_devices_.size()))
    {
        (void)NativeSystemControlBackend::OpenWindowsTarget(window_, L"ms-settings:bluetooth");
        return;
    }
    const NativeBluetoothDeviceV7 device = bluetooth_devices_[static_cast<std::size_t>(index)];
    if (device.paired)
    {
        NativeBluetoothV7::UnpairAsync(device.id);
        NativeToastOverlay::Post(L"Bluetooth", L"Remocao solicitada ao Windows.", 0, 3200u);
    }
    else
    {
        NativeBluetoothV7::PairAsync(device.id);
        NativeToastOverlay::Post(L"Bluetooth", L"Pareamento solicitado ao Windows.", 0, 3200u);
    }
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
    NativeMediaControlV7::RefreshAsync();
    NativeBluetoothV7::RefreshAsync();
    UpdateState(true);
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(560, dpi);
    const int height = Scale(820, dpi);
    int x = anchor.right - width;
    int y = anchor.top - height - Scale(12, dpi);
    x = std::clamp<int>(x, static_cast<int>(info.rcWork.left),
        std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(y, static_cast<int>(info.rcWork.top),
        std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));
    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetTimer(window_, kRefreshTimer, 1800, nullptr);
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
        if (reinterpret_cast<HWND>(l_param) == mixer_slider_)
        {
            ApplyMixerFromSlider();
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
        case kMediaPreviousId: NativeMediaControlV7::PreviousAsync(); return 0;
        case kMediaToggleId: NativeMediaControlV7::TogglePlayPauseAsync(); return 0;
        case kMediaNextId: NativeMediaControlV7::NextAsync(); return 0;
        case kMuteId: ToggleMute(); return 0;
        case kMixerMuteId: ToggleMixerMute(); return 0;
        case kMixerComboId:
            if (HIWORD(w_param) == CBN_SELCHANGE) RefreshMixerSelection();
            return 0;
        case kWifiActionId: HandleWifiAction(); return 0;
        case kBluetoothComboId:
            if (HIWORD(w_param) == CBN_SELCHANGE) RefreshBluetoothSelection();
            return 0;
        case kBluetoothActionId: HandleBluetoothAction(); return 0;
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
    {
        const int control_id = LOWORD(w_param);
        const WebSkin::ButtonTone tone =
            (control_id == kSystemCenterId || control_id == kMediaToggleId)
                ? WebSkin::ButtonTone::Accent
                : WebSkin::ButtonTone::Neutral;
        if (WebSkin::PaintOwnerDrawButton(reinterpret_cast<DRAWITEMSTRUCT*>(l_param), tone)) return TRUE;
        break;
    }
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

        Gdiplus::Graphics graphics(dc);
        graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        const UINT dpi = GetDpiForWindow(window_);
        const int margin = Scale(14, dpi);
        const int width = std::max<LONG>(1, client.right - client.left);
        const auto card = [dpi, width, margin, &graphics](int top, int bottom)
        {
            WebSkin::DrawElevatedPanel(
                graphics,
                Gdiplus::RectF(
                    static_cast<Gdiplus::REAL>(margin),
                    static_cast<Gdiplus::REAL>(Scale(top, dpi)),
                    static_cast<Gdiplus::REAL>(width - margin * 2),
                    static_cast<Gdiplus::REAL>(Scale(bottom - top, dpi))),
                static_cast<Gdiplus::REAL>(Scale(WebSkin::RadiusLarge, dpi)),
                WebSkin::GdiColor(WebSkin::BgSecondary, 218),
                WebSkin::GdiColor(WebSkin::BorderDefault, 180));
        };
        card(76, 180);
        card(184, 352);
        card(356, 540);
        card(542, 692);

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