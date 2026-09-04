#include "native_quick_settings_window.h"

#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_system_control_backend.h"
#include "native_theme.h"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kQuickSettingsClass[] = L"CloudOS.NativeShell.QuickSettings.v2";
constexpr int kVolumeSliderId = 8801;
constexpr int kMuteId = 8802;
constexpr int kWifiId = 8803;
constexpr int kBluetoothId = 8804;
constexpr int kNetworkId = 8805;
constexpr int kDisplayId = 8806;
constexpr int kSoundId = 8807;
constexpr int kPowerId = 8808;
constexpr UINT_PTR kRefreshTimer = 8809;

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

bool OpenSettings(HWND owner, const wchar_t* uri)
{
    const HINSTANCE result = ShellExecuteW(owner, L"open", uri, nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) > 32) return true;

    CloudOSNativeNotificationCenter::Post(
        L"Configuracao do Windows indisponivel",
        L"O Windows nao aceitou abrir esta pagina de configuracao.");
    return false;
}

std::wstring PowerStatusText()
{
    SYSTEM_POWER_STATUS power{};
    if (!GetSystemPowerStatus(&power)) return L"Energia  ·  indisponivel";

    std::wstring text = L"Energia  ·  ";
    const bool ac_known = power.ACLineStatus == 0 || power.ACLineStatus == 1;
    const bool battery_flag_known = power.BatteryFlag != 255;
    const bool battery_absent = power.BatteryFlag == 128;
    const bool percentage_known = power.BatteryLifePercent != 255;

    if (!ac_known && !battery_flag_known && !percentage_known)
    {
        text += L"estado desconhecido";
        return text;
    }
    if (battery_absent)
    {
        text += ac_known && power.ACLineStatus == 1
            ? L"desktop / alimentacao conectada"
            : L"desktop / sem bateria";
        return text;
    }

    if (percentage_known)
    {
        text += std::to_wstring(power.BatteryLifePercent);
        text += L"%";
        if (ac_known)
            text += power.ACLineStatus == 1 ? L" · conectado" : L" · bateria";
        else
            text += L" · fonte desconhecida";
        return text;
    }

    if (ac_known)
        text += power.ACLineStatus == 1 ? L"alimentacao conectada" : L"bateria (percentual indisponivel)";
    else
        text += L"bateria/energia sem telemetria";
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
        0, 0, 438, 382,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    background_ = WebSkin::CreateBackgroundBrush();
    const UINT dpi = GetDpiForWindow(window_);
    font_ = CreateFontW(
        -Scale(15, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    title_font_ = CreateFontW(
        -Scale(22, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    title_ = CreateWindowW(L"STATIC", L"Configuracoes rapidas", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_label_ = CreateWindowW(L"STATIC", L"Volume", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kVolumeSliderId)), instance_, nullptr);
    mute_button_ = CreateWindowW(L"BUTTON", L"Mudo", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteId)), instance_, nullptr);
    power_label_ = CreateWindowW(L"STATIC", L"Energia", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    monitor_label_ = CreateWindowW(L"STATIC", L"Monitores", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    wifi_button_ = CreateWindowW(L"BUTTON", L"Wi-Fi", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiId)), instance_, nullptr);
    bluetooth_button_ = CreateWindowW(L"BUTTON", L"Bluetooth", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothId)), instance_, nullptr);
    network_button_ = CreateWindowW(L"BUTTON", L"Rede", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNetworkId)), instance_, nullptr);
    display_button_ = CreateWindowW(L"BUTTON", L"Tela / brilho", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDisplayId)), instance_, nullptr);
    sound_button_ = CreateWindowW(L"BUTTON", L"Som", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSoundId)), instance_, nullptr);
    power_button_ = CreateWindowW(L"BUTTON", L"Energia", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kPowerId)), instance_, nullptr);

    if (title_ == nullptr || volume_label_ == nullptr || volume_slider_ == nullptr ||
        mute_button_ == nullptr || power_label_ == nullptr || monitor_label_ == nullptr ||
        wifi_button_ == nullptr || bluetooth_button_ == nullptr || network_button_ == nullptr ||
        display_button_ == nullptr || sound_button_ == nullptr || power_button_ == nullptr)
    {
        Destroy();
        return false;
    }

    SetControlFont(title_, title_font_);
    for (HWND child : {volume_label_, volume_slider_, mute_button_, power_label_, monitor_label_,
                       wifi_button_, bluetooth_button_, network_button_, display_button_, sound_button_, power_button_})
        SetControlFont(child, font_);

    SendMessageW(volume_slider_, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
    SendMessageW(volume_slider_, TBM_SETPAGESIZE, 0, 5);

    for (HWND button : {mute_button_, wifi_button_, bluetooth_button_, network_button_, display_button_, sound_button_, power_button_})
        WebSkin::PrepareButton(button);
    WebSkin::ApplyUxTheme(volume_slider_);
    ApplyWebFlyoutMaterial(window_);
    Layout();
    UpdateState();
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
    title_ = nullptr;
    volume_label_ = nullptr;
    volume_slider_ = nullptr;
    mute_button_ = nullptr;
    power_label_ = nullptr;
    monitor_label_ = nullptr;
    wifi_button_ = nullptr;
    bluetooth_button_ = nullptr;
    network_button_ = nullptr;
    display_button_ = nullptr;
    sound_button_ = nullptr;
    power_button_ = nullptr;

    if (font_ != nullptr) { DeleteObject(font_); font_ = nullptr; }
    if (title_font_ != nullptr) { DeleteObject(title_font_); title_font_ = nullptr; }
    if (background_ != nullptr) { DeleteObject(background_); background_ = nullptr; }
}

void CloudOSNativeQuickSettingsWindow::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(20, dpi);
    const int width = std::max(1L, client.right - client.left);
    const int button_gap = Scale(10, dpi);
    const int button_width = (width - margin * 2 - button_gap * 2) / 3;
    const int button_height = Scale(48, dpi);

    MoveWindow(title_, margin, Scale(18, dpi), width - margin * 2, Scale(34, dpi), TRUE);
    MoveWindow(volume_label_, margin, Scale(66, dpi), Scale(180, dpi), Scale(24, dpi), TRUE);
    MoveWindow(volume_slider_, margin, Scale(92, dpi), width - margin * 2 - Scale(94, dpi), Scale(32, dpi), TRUE);
    MoveWindow(mute_button_, width - margin - Scale(82, dpi), Scale(89, dpi), Scale(82, dpi), Scale(36, dpi), TRUE);
    MoveWindow(power_label_, margin, Scale(140, dpi), width - margin * 2, Scale(24, dpi), TRUE);
    MoveWindow(monitor_label_, margin, Scale(166, dpi), width - margin * 2, Scale(24, dpi), TRUE);

    const int row1 = Scale(210, dpi);
    const int row2 = row1 + button_height + button_gap;
    MoveWindow(wifi_button_, margin, row1, button_width, button_height, TRUE);
    MoveWindow(bluetooth_button_, margin + button_width + button_gap, row1, button_width, button_height, TRUE);
    MoveWindow(network_button_, margin + (button_width + button_gap) * 2, row1, button_width, button_height, TRUE);
    MoveWindow(display_button_, margin, row2, button_width, button_height, TRUE);
    MoveWindow(sound_button_, margin + button_width + button_gap, row2, button_width, button_height, TRUE);
    MoveWindow(power_button_, margin + (button_width + button_gap) * 2, row2, button_width, button_height, TRUE);
}

void CloudOSNativeQuickSettingsWindow::UpdateState()
{
    const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
    updating_slider_ = true;
    if (audio.available)
    {
        SendMessageW(volume_slider_, TBM_SETPOS, TRUE, static_cast<LPARAM>(audio.volume_percent));
    }
    updating_slider_ = false;
    EnableWindow(volume_slider_, audio.available ? TRUE : FALSE);
    EnableWindow(mute_button_, audio.available ? TRUE : FALSE);

    std::wstring volume_text = L"Volume  ·  ";
    if (audio.available)
    {
        volume_text += std::to_wstring(audio.volume_percent) + L"%";
        if (!audio.endpoint_name.empty()) volume_text += L" · " + audio.endpoint_name;
    }
    else
    {
        volume_text += L"indisponivel";
    }
    SetWindowTextW(volume_label_, volume_text.c_str());
    SetWindowTextW(mute_button_, audio.available && audio.muted ? L"Ativar som" : L"Mudo");

    const std::wstring power_text = PowerStatusText();
    SetWindowTextW(power_label_, power_text.c_str());

    const std::size_t monitor_count = NativeMonitorManager::Enumerate().size();
    std::wstring monitor_text = std::to_wstring(monitor_count);
    monitor_text += monitor_count == 1 ? L" monitor ativo" : L" monitores ativos";
    SetWindowTextW(monitor_label_, monitor_text.c_str());
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSNativeQuickSettingsWindow::ApplyVolumeFromSlider()
{
    if (updating_slider_ || volume_slider_ == nullptr) return;
    const int position = static_cast<int>(SendMessageW(volume_slider_, TBM_GETPOS, 0, 0));
    std::wstring error;
    if (!NativeSystemControlBackend::SetMasterVolume(
            static_cast<unsigned>(std::clamp(position, 0, 100)),
            &error))
    {
        CloudOSNativeNotificationCenter::Post(
            L"Volume indisponivel",
            error.empty() ? L"O Windows recusou a alteracao do volume." : error);
    }
    else if (position > 0)
    {
        const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
        if (audio.available && audio.muted)
            (void)NativeSystemControlBackend::SetMasterMute(false, nullptr);
    }
    UpdateState();
}

void CloudOSNativeQuickSettingsWindow::ToggleMute()
{
    const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
    if (!audio.available) return;

    std::wstring error;
    if (!NativeSystemControlBackend::SetMasterMute(!audio.muted, &error))
    {
        CloudOSNativeNotificationCenter::Post(
            L"Audio indisponivel",
            error.empty() ? L"O Windows recusou a alteracao de mute." : error);
    }
    UpdateState();
}

void CloudOSNativeQuickSettingsWindow::ShowNear(const RECT& anchor)
{
    if (window_ == nullptr) return;
    UpdateState();
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (monitor == nullptr || !GetMonitorInfoW(monitor, &info))
    {
        monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTOPRIMARY);
        info.cbSize = sizeof(info);
        if (!GetMonitorInfoW(monitor, &info)) return;
    }

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(438, dpi);
    const int height = Scale(356, dpi);
    int x = anchor.right - width;
    int y = anchor.top - height - Scale(10, dpi);
    x = std::clamp<int>(x, static_cast<int>(info.rcWork.left),
        std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(y, static_cast<int>(info.rcWork.top),
        std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));

    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetTimer(window_, kRefreshTimer, 1500, nullptr);
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
    UpdateState();
}

LRESULT CloudOSNativeQuickSettingsWindow::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_DPICHANGED:
    {
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        if (suggested != nullptr)
        {
            SetWindowPos(
                window_,
                HWND_TOPMOST,
                suggested->left,
                suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOACTIVATE);
        }

        if (font_ != nullptr) { DeleteObject(font_); font_ = nullptr; }
        if (title_font_ != nullptr) { DeleteObject(title_font_); title_font_ = nullptr; }
        const UINT dpi = GetDpiForWindow(window_);
        font_ = CreateFontW(
            -Scale(15, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
        title_font_ = CreateFontW(
            -Scale(22, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
        SetControlFont(title_, title_font_);
        for (HWND child : {volume_label_, volume_slider_, mute_button_, power_label_, monitor_label_,
                           wifi_button_, bluetooth_button_, network_button_, display_button_, sound_button_, power_button_})
            SetControlFont(child, font_);
        Layout();
        return 0;
    }
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE) Hide();
        return 0;
    case WM_HSCROLL:
        if (reinterpret_cast<HWND>(l_param) == volume_slider_)
        {
            ApplyVolumeFromSlider();
            return 0;
        }
        break;
    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kMuteId: ToggleMute(); return 0;
        case kWifiId: (void)OpenSettings(window_, L"ms-settings:network-wifi"); return 0;
        case kBluetoothId: (void)OpenSettings(window_, L"ms-settings:bluetooth"); return 0;
        case kNetworkId: (void)OpenSettings(window_, L"ms-settings:network-status"); return 0;
        case kDisplayId: (void)OpenSettings(window_, L"ms-settings:display"); return 0;
        case kSoundId: (void)OpenSettings(window_, L"ms-settings:sound"); return 0;
        case kPowerId: (void)OpenSettings(window_, L"ms-settings:powersleep"); return 0;
        default: break;
        }
        break;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr)
        {
            const ButtonTone tone = draw->CtlID == kMuteId ? ButtonTone::Accent : ButtonTone::Neutral;
            if (WebSkin::PaintOwnerDrawButton(draw, tone)) return TRUE;
        }
        break;
    }
    case WM_TIMER:
        if (w_param == kRefreshTimer) { UpdateState(); return 0; }
        break;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE) { Hide(); return 0; }
        break;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, reinterpret_cast<HWND>(l_param) == title_ ? WebSkin::TextPrimary : WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(window_, &client);
        WebSkin::PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_DESTROY:
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeQuickSettingsWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeQuickSettingsWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeQuickSettingsWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->window_ = window;
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
