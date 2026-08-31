#include "native_performance_v12.h"
#include "native_controls_v12.h"
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
        WS_POPUP | WS_CLIPCHILDREN | WS_VSCROLL,
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
    media_meta_ = CreateWindowW(L"STATIC", L"Nenhuma reproducao ativa",
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_ENDELLIPSIS, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    media_previous_button_ = CreateWindowW(L"BUTTON", L"⏮", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaPreviousId)), instance_, nullptr);
    media_toggle_button_ = CreateWindowW(L"BUTTON", L"Reproduzir", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaToggleId)), instance_, nullptr);
    media_next_button_ = CreateWindowW(L"BUTTON", L"⏭", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMediaNextId)), instance_, nullptr);

    volume_label_ = CreateWindowW(L"STATIC", L"Volume", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kVolumeSliderId)), instance_, nullptr);
    mute_button_ = CreateWindowW(L"BUTTON", L"Mudo", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteId)), instance_, nullptr);

    mixer_label_ = CreateWindowW(L"STATIC", L"Mixer por aplicativo", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    mixer_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerComboId)), instance_, nullptr);
    mixer_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerSliderId)), instance_, nullptr);
    mixer_mute_button_ = CreateWindowW(L"BUTTON", L"Mudo app", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMixerMuteId)), instance_, nullptr);

    wifi_label_ = CreateWindowW(L"STATIC", L"Wi-Fi", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    wifi_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiComboId)), instance_, nullptr);
    wifi_action_button_ = CreateWindowW(L"BUTTON", L"Conectar", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiActionId)), instance_, nullptr);

    bluetooth_label_ = CreateWindowW(L"STATIC", L"Bluetooth", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    bluetooth_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothComboId)), instance_, nullptr);
    bluetooth_action_button_ = CreateWindowW(L"BUTTON", L"Parear", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothActionId)), instance_, nullptr);
    bluetooth_button_ = CreateWindowW(L"BUTTON", L"Abrir Bluetooth do Windows", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothId)), instance_, nullptr);

    brightness_label_ = CreateWindowW(L"STATIC", L"Brilho", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    brightness_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBrightnessSliderId)), instance_, nullptr);

    power_label_ = CreateWindowW(L"STATIC", L"Energia", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    balanced_button_ = CreateWindowW(L"BUTTON", L"Equilibrado", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBalancedId)), instance_, nullptr);
    saver_button_ = CreateWindowW(L"BUTTON", L"Economia", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSaverId)), instance_, nullptr);
    performance_button_ = CreateWindowW(L"BUTTON", L"Desempenho", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPerformanceId)), instance_, nullptr);

    system_center_button_ = CreateWindowW(L"BUTTON", L"Abrir Central do Sistema", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSystemCenterId)), instance_, nullptr);
    appearance_button_ = CreateWindowW(L"BUTTON", L"Trocar cor de destaque", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
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
        ControlsV12::Prepare(slider,true);
    }

    for (HWND button : {media_previous_button_, media_toggle_button_, media_next_button_, mute_button_, mixer_mute_button_,
             wifi_action_button_, bluetooth_action_button_, bluetooth_button_, balanced_button_, saver_button_,
             performance_button_, system_center_button_, appearance_button_})
        WebSkin::PrepareButton(button);
    for (HWND combo : {mixer_combo_, wifi_combo_, bluetooth_combo_}) { WebSkin::ApplyUxTheme(combo); ControlsV12::Prepare(combo,false); }

    advanced_button_ = CreateWindowW(L"BUTTON", L"Mais controles", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW, 0,0,0,0, window_, reinterpret_cast<HMENU>(8821), instance_, nullptr);
    SetControlFont(advanced_button_, font_);
    WebSkin::ApplyUxTheme(window_);
    ApplyWebFlyoutMaterial(window_);
    Layout();
    UpdateState(true);
    return true;
}

void CloudOSNativeQuickSettingsWindow::Destroy()
{
    model_v12_.Stop();
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
    if (title_ && font_dpi_v12_ != dpi)
    {
        font_dpi_v12_=dpi;
        if(font_) DeleteObject(font_); if(small_font_) DeleteObject(small_font_); if(title_font_) DeleteObject(title_font_);
        font_=CreateFontW(-Scale(14,dpi),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI Variable Text");
        small_font_=CreateFontW(-Scale(12,dpi),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI Variable Text");
        title_font_=CreateFontW(-Scale(22,dpi),0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI Variable Display");
        EnumChildWindows(window_,[](HWND child,LPARAM data)->BOOL { SendMessageW(child,WM_SETFONT,static_cast<WPARAM>(data),TRUE); return TRUE; },reinterpret_cast<LPARAM>(font_));
        SetControlFont(title_,title_font_); SetControlFont(media_meta_,small_font_);
    }

    const int width = std::max<LONG>(1, client.right - client.left);
    const int margin = Scale(20,dpi), inner = std::max(1,width-margin*2), gap=Scale(8,dpi);
    scroll_v12_.Update(window_, Scale(advanced_v12_ ? 1040 : 606,dpi), client.bottom);
    SetPropW(window_,L"CloudOS.QuickScroll.V12",reinterpret_cast<HANDLE>(static_cast<INT_PTR>(scroll_v12_.position)));
    if(advanced_v12_ && !QuickSettingsMediaV8::panel) QuickSettingsMediaV8::Attach(window_);
    if(QuickSettingsMediaV8::panel) { ShowWindow(QuickSettingsMediaV8::panel,advanced_v12_?SW_SHOWNA:SW_HIDE); QuickSettingsMediaV8::Layout(window_); }
    auto place = [&](HWND control, int x, int y, int w, int h) { if(control) MoveWindow(control,x,Scale(y,dpi)-scroll_v12_.position,w,Scale(h,dpi),TRUE); };
    auto row = [&](HWND label, HWND combo, HWND action, int y) { place(label,margin,y,inner,22); place(combo,margin,y+26,inner-Scale(104,dpi),230); place(action,width-margin-Scale(96,dpi),y+24,Scale(96,dpi),34); };
    place(title_,margin,16,inner,30); ShowWindow(subtitle_,SW_HIDE);
    row(wifi_label_,wifi_combo_,wifi_action_button_,60);
    row(bluetooth_label_,bluetooth_combo_,bluetooth_action_button_,134);
    place(volume_label_,margin,212,inner,22); place(volume_slider_,margin,238,inner-Scale(92,dpi),32); place(mute_button_,width-margin-Scale(84,dpi),236,Scale(84,dpi),34);
    place(brightness_label_,margin,282,inner,22); place(brightness_slider_,margin,306,inner,32);
    place(media_label_,margin,350,inner,22); place(media_meta_,margin,374,inner,20);
    place(media_previous_button_,margin,400,Scale(74,dpi),34); place(media_toggle_button_,margin+Scale(82,dpi),400,inner-Scale(164,dpi),34); place(media_next_button_,width-margin-Scale(74,dpi),400,Scale(74,dpi),34);
    place(power_label_,margin,452,inner,24); place(system_center_button_,margin,488,inner,38); place(advanced_button_,margin,536,inner,36);
    for (HWND c : {mixer_label_,mixer_combo_,mixer_slider_,mixer_mute_button_,bluetooth_button_,balanced_button_,saver_button_,performance_button_,appearance_button_}) ShowWindow(c,advanced_v12_?SW_SHOWNA:SW_HIDE);
    if (advanced_v12_)
    {
        place(mixer_label_,margin,590,inner,22); place(mixer_combo_,margin,616,inner,230); place(mixer_slider_,margin,652,inner-Scale(104,dpi),32); place(mixer_mute_button_,width-margin-Scale(96,dpi),650,Scale(96,dpi),34);
        place(bluetooth_button_,margin,704,inner,36);
        const int third=(inner-gap*2)/3;
        place(balanced_button_,margin,758,third,36); place(saver_button_,margin+third+gap,758,third,36); place(performance_button_,margin+(third+gap)*2,758,third,36);
        place(appearance_button_,margin,816,inner,36);
    }

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
    if (!window_ || !IsWindowVisible(window_)) return;
    QuickSettingsMediaV8::RefreshSnapshot();
    const auto cached = model_v12_.Snapshot();
    const NativeMediaSnapshot media = NativeMediaControlV7::Snapshot();
    if (media.available)
    {
        std::wstring title = L"Midia  ·  ";
        title += media.title.empty() ? L"reproducao ativa" : media.title;
        SetWindowTextW(media_label_, title.c_str());
        std::wstring meta;
        if (!media.artist.empty()) meta += media.artist;
        if (!media.album.empty()) meta += (meta.empty() ? L"" : L"  ·  ") + media.album;

        SetWindowTextW(media_meta_, meta.empty() ? L"Sessao GSMTC ativa" : meta.c_str());
        SetWindowTextW(media_toggle_button_, media.playing ? L"Pausar" : L"Reproduzir");
        EnableWindow(media_toggle_button_, media.can_toggle);
        EnableWindow(media_next_button_, media.can_next);
        EnableWindow(media_previous_button_, media.can_previous);
    }
    else
    {
        SetWindowTextW(media_label_, L"Midia  ·  nenhuma sessao ativa");
        SetWindowTextW(media_meta_, L"Nenhuma reproducao ativa");
        SetWindowTextW(media_toggle_button_, L"Reproduzir");
        EnableWindow(media_toggle_button_, FALSE);
        EnableWindow(media_next_button_, FALSE);
        EnableWindow(media_previous_button_, FALSE);
    }

    const NativeAudioState audio = model_v12_.Snapshot().audio;
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
        audio_sessions_ = cached.sessions;
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

    const NativeBrightnessState brightness = cached.brightness;
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
    else brightness_text += L"ajuste no monitor";
    SetWindowTextW(brightness_label_, brightness_text.c_str());

    const NativePowerState power = cached.power;
    std::wstring power_text = L"Energia  ·  " + (power.active_plan.empty() ? std::wstring(L"plano atual") : power.active_plan);
    if (power.battery_present)
        power_text += L"  ·  " + std::to_wstring(power.battery_percent) + L"%" + (power.on_ac ? L" AC" : L" bateria");
    SetWindowTextW(power_label_, power_text.c_str());

    ++wifi_refresh_tick_;
    if (force_network || wifi_networks_.empty() || (wifi_refresh_tick_ % 3u) == 0u)
    {
        const int previous = SelectedWifiIndex();
        wifi_networks_ = cached.wifi;
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

    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeQuickSettingsWindow::ApplyVolumeFromSlider()
{
    if(updating_slider_) return;
    const auto value=static_cast<unsigned>(SendMessageW(volume_slider_,TBM_GETPOS,0,0));
    model_v12_.Action(window_,L"Volume",[value](std::wstring& error){
        if(!NativeSystemControlBackend::SetMasterVolume(value,&error)) return false;
        return value==0 || NativeSystemControlBackend::SetMasterMute(false,&error);
    });
}

void CloudOSNativeQuickSettingsWindow::ApplyMixerFromSlider()
{
    if(updating_slider_) return;
    const int index=SelectedAudioSessionIndex();
    if(index<0 || index>=static_cast<int>(audio_sessions_.size())) return;
    const auto pid=audio_sessions_[static_cast<std::size_t>(index)].process_id;
    const auto value=static_cast<unsigned>(SendMessageW(mixer_slider_,TBM_GETPOS,0,0));
    model_v12_.Action(window_,L"Mixer",[pid,value](std::wstring&){
        return NativeAudioMixerV7::SetVolume(pid,value) && (value==0 || NativeAudioMixerV7::SetMute(pid,false));
    });
}

void CloudOSNativeQuickSettingsWindow::ApplyBrightnessFromSlider()
{
    if(updating_slider_) return;
    const auto value=static_cast<unsigned>(SendMessageW(brightness_slider_,TBM_GETPOS,0,0));
    model_v12_.Action(window_,L"Brilho",[value](std::wstring& error){ return NativeSystemControlBackend::SetBrightness(value,&error); },true);
}

void CloudOSNativeQuickSettingsWindow::ToggleMute()
{
    const auto audio=model_v12_.Snapshot().audio;
    if(!audio.available) return;
    model_v12_.Action(window_,L"Audio",[muted=!audio.muted](std::wstring& error){ return NativeSystemControlBackend::SetMasterMute(muted,&error); });
}

void CloudOSNativeQuickSettingsWindow::ToggleMixerMute()
{
    const int index=SelectedAudioSessionIndex();
    if(index<0 || index>=static_cast<int>(audio_sessions_.size())) return;
    const auto session=audio_sessions_[static_cast<std::size_t>(index)];
    model_v12_.Action(window_,L"Mixer",[session](std::wstring&){ return NativeAudioMixerV7::SetMute(session.process_id,!session.muted); });
}

void CloudOSNativeQuickSettingsWindow::HandleWifiAction()
{
    const int index=SelectedWifiIndex();
    if(index<0 || index>=static_cast<int>(wifi_networks_.size())) return;
    const auto network=wifi_networks_[static_cast<std::size_t>(index)];
    if(!network.connected && network.profile_name.empty())
    { (void)NativeSystemControlBackend::OpenWindowsTarget(window_,L"ms-settings:network-wifi"); return; }
    model_v12_.Action(window_,L"Wi-Fi",[network](std::wstring& error){ return network.connected
        ? NativeSystemControlBackend::DisconnectWifi(network.interface_guid,&error)
        : NativeSystemControlBackend::ConnectKnownWifi(network,&error); },true);
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
    model_v12_.Action(window_,L"Plano de energia",[plan](std::wstring& error){
        if(plan==0) return NativeSystemControlBackend::SetBalancedPowerPlan(&error);
        if(plan==1) return NativeSystemControlBackend::SetPowerSaverPlan(&error);
        return NativeSystemControlBackend::SetHighPerformancePlan(&error);
    });
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
    const auto open_begin = PerformanceV12::NowUs();
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    const UINT dpi = GetDpiForWindow(window_);
    const RECT fitted = FitFlyout(anchor, info.rcWork, Scale(420, dpi), Scale(620, dpi), Scale(12,dpi));
    SetWindowPos(window_, HWND_TOPMOST, fitted.left, fitted.top, fitted.right-fitted.left, fitted.bottom-fitted.top, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetTimer(window_, kRefreshTimer, 5000, nullptr);
    UpdateState(true);
    model_v12_.Request(window_);
    NativeMediaControlV7::RefreshAsync();
    NativeBluetoothV7::RefreshAsync();
    UpdateWindow(window_); // first paint completes before the open-latency sample
    PerformanceV12::Set(PerformanceV12::QuickOpenUs, PerformanceV12::NowUs()-open_begin);
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
    if (!window_ || !IsWindowVisible(window_)) return;
    model_v12_.Request(window_);
    UpdateState(false);
}

LRESULT CloudOSNativeQuickSettingsWindow::HandleMessage(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_CLOUDOS_QUICK_DATA_V12:
        for(const auto& result : model_v12_.TakeResults()) ShowOperationResult(result.title,result.success,result.error);
        if(IsWindowVisible(window_)) UpdateState(true);
        return 0;
    case WM_VSCROLL: scroll_v12_.Scroll(window_, w_param, Scale(28, GetDpiForWindow(window_))); Layout(); InvalidateRect(window_, nullptr, FALSE); return 0;
    case WM_MOUSEWHEEL: scroll_v12_.Wheel(GET_WHEEL_DELTA_WPARAM(w_param), Scale(28, GetDpiForWindow(window_))); Layout(); InvalidateRect(window_, nullptr, FALSE); return 0;
    case WM_SIZE: Layout(); return 0;
    case WM_DPICHANGED:
    { const auto rect=FitSuggestedFlyout(*reinterpret_cast<RECT*>(l_param)); SetWindowPos(window_,nullptr,rect.left,rect.top,rect.right-rect.left,rect.bottom-rect.top,SWP_NOZORDER|SWP_NOACTIVATE); Layout(); return 0; }
    case WM_HSCROLL:
        if (LOWORD(w_param) == TB_THUMBTRACK || LOWORD(w_param) == TB_ENDTRACK) return 0;
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
        case IDCANCEL: Hide(); return 0;
        case 8821: advanced_v12_ = !advanced_v12_; SetWindowTextW(advanced_button_, advanced_v12_ ? L"Menos controles" : L"Mais controles"); Layout(); InvalidateRect(window_, nullptr, FALSE); return 0;
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
            if (!IsWindowVisible(window_)) return 0;
            model_v12_.Request(window_);
            NativeMediaControlV7::RefreshAsync();
            if (++bluetooth_refresh_tick_ % 6 == 0) NativeBluetoothV7::RefreshAsync();
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
    case WM_CTLCOLORLISTBOX:
    case WM_CTLCOLORSTATIC:
        SetBkMode(reinterpret_cast<HDC>(w_param), TRANSPARENT);
        SetTextColor(reinterpret_cast<HDC>(w_param), WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(background_);
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
    {
        PerformanceV12::PaintScope telemetry(PerformanceV12::QuickPaint);
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