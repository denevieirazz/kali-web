#include "native_quick_settings_window.h"

#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_theme.h"

#include <commctrl.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <shellapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <string>

namespace CloudOS
{
namespace
{
using Microsoft::WRL::ComPtr;

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

ComPtr<IAudioEndpointVolume> DefaultEndpointVolume()
{
    ComPtr<IMMDeviceEnumerator> enumerator;
    if (FAILED(CoCreateInstance(
            __uuidof(MMDeviceEnumerator),
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&enumerator))))
    {
        return {};
    }

    ComPtr<IMMDevice> device;
    if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device)))
    {
        return {};
    }

    ComPtr<IAudioEndpointVolume> volume;
    if (FAILED(device->Activate(
            __uuidof(IAudioEndpointVolume),
            CLSCTX_INPROC_SERVER,
            nullptr,
            reinterpret_cast<void**>(volume.GetAddressOf()))))
    {
        return {};
    }
    return volume;
}

void SetControlFont(HWND control, HFONT font)
{
    if (control != nullptr && font != nullptr)
    {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

void OpenSettings(HWND owner, const wchar_t* uri)
{
    (void)ShellExecuteW(owner, L"open", uri, nullptr, nullptr, SW_SHOWNORMAL);
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
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kQuickSettingsClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kQuickSettingsClass,
        L"Configuracoes Rapidas - CloudOS",
        WS_POPUP | WS_BORDER | WS_CLIPCHILDREN,
        0, 0, 420, 430,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    background_ = CreateSolidBrush(RGB(24, 26, 31));
    font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    title_font_ = CreateFontW(
        -20, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");

    title_ = CreateWindowW(L"STATIC", L"Configuracoes rapidas", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_label_ = CreateWindowW(L"STATIC", L"Volume", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    volume_slider_ = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
        WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kVolumeSliderId)), instance_, nullptr);
    mute_button_ = CreateWindowW(L"BUTTON", L"Mudo", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteId)), instance_, nullptr);
    power_label_ = CreateWindowW(L"STATIC", L"Energia", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);
    monitor_label_ = CreateWindowW(L"STATIC", L"Monitores", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    wifi_button_ = CreateWindowW(L"BUTTON", L"Wi-Fi", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kWifiId)), instance_, nullptr);
    bluetooth_button_ = CreateWindowW(L"BUTTON", L"Bluetooth", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kBluetoothId)), instance_, nullptr);
    network_button_ = CreateWindowW(L"BUTTON", L"Rede", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNetworkId)), instance_, nullptr);
    display_button_ = CreateWindowW(L"BUTTON", L"Tela / brilho", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDisplayId)), instance_, nullptr);
    sound_button_ = CreateWindowW(L"BUTTON", L"Som", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSoundId)), instance_, nullptr);
    power_button_ = CreateWindowW(L"BUTTON", L"Energia", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
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
    {
        SetControlFont(child, font_);
    }

    SendMessageW(volume_slider_, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
    SendMessageW(volume_slider_, TBM_SETPAGESIZE, 0, 5);

    DarkWindow(window_);
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
    if (background_ != nullptr)
    {
        DeleteObject(background_);
        background_ = nullptr;
    }
}

void CloudOSNativeQuickSettingsWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(18, dpi);
    const int width = std::max(1L, client.right - client.left);
    const int button_gap = Scale(10, dpi);
    const int button_width = (width - margin * 2 - button_gap * 2) / 3;
    const int button_height = Scale(44, dpi);

    MoveWindow(title_, margin, Scale(14, dpi), width - margin * 2, Scale(32, dpi), TRUE);
    MoveWindow(volume_label_, margin, Scale(58, dpi), Scale(100, dpi), Scale(24, dpi), TRUE);
    MoveWindow(volume_slider_, margin, Scale(84, dpi), width - margin * 2 - Scale(82, dpi), Scale(32, dpi), TRUE);
    MoveWindow(mute_button_, width - margin - Scale(72, dpi), Scale(82, dpi), Scale(72, dpi), Scale(32, dpi), TRUE);
    MoveWindow(power_label_, margin, Scale(126, dpi), width - margin * 2, Scale(24, dpi), TRUE);
    MoveWindow(monitor_label_, margin, Scale(152, dpi), width - margin * 2, Scale(24, dpi), TRUE);

    const int row1 = Scale(198, dpi);
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
    const auto volume = DefaultEndpointVolume();
    float level = 0.0f;
    BOOL muted = FALSE;
    if (volume != nullptr)
    {
        (void)volume->GetMasterVolumeLevelScalar(&level);
        (void)volume->GetMute(&muted);
        updating_slider_ = true;
        SendMessageW(volume_slider_, TBM_SETPOS, TRUE, static_cast<LPARAM>(std::clamp(static_cast<int>(level * 100.0f + 0.5f), 0, 100)));
        updating_slider_ = false;
    }
    EnableWindow(volume_slider_, volume != nullptr);
    EnableWindow(mute_button_, volume != nullptr);

    std::wstring volume_text = L"Volume ";
    volume_text += volume != nullptr ? std::to_wstring(std::clamp(static_cast<int>(level * 100.0f + 0.5f), 0, 100)) + L"%" : L"indisponivel";
    SetWindowTextW(volume_label_, volume_text.c_str());
    SetWindowTextW(mute_button_, muted ? L"Ativar som" : L"Mudo");

    SYSTEM_POWER_STATUS power{};
    std::wstring power_text = L"Energia: ";
    if (GetSystemPowerStatus(&power))
    {
        if (power.BatteryFlag == 128)
        {
            power_text += L"desktop / sem bateria";
        }
        else if (power.BatteryLifePercent == 255)
        {
            power_text += power.ACLineStatus == 1 ? L"conectado a energia" : L"bateria";
        }
        else
        {
            power_text += std::to_wstring(power.BatteryLifePercent);
            power_text += L"%";
            power_text += power.ACLineStatus == 1 ? L" · carregando/AC" : L" · bateria";
        }
    }
    else
    {
        power_text += L"indisponivel";
    }
    SetWindowTextW(power_label_, power_text.c_str());

    const std::size_t monitor_count = NativeMonitorManager::Enumerate().size();
    std::wstring monitor_text = std::to_wstring(monitor_count);
    monitor_text += monitor_count == 1 ? L" monitor ativo" : L" monitores ativos";
    SetWindowTextW(monitor_label_, monitor_text.c_str());
}

void CloudOSNativeQuickSettingsWindow::ApplyVolumeFromSlider()
{
    if (updating_slider_ || volume_slider_ == nullptr)
    {
        return;
    }

    const int position = static_cast<int>(SendMessageW(volume_slider_, TBM_GETPOS, 0, 0));
    const auto volume = DefaultEndpointVolume();
    if (volume != nullptr)
    {
        (void)volume->SetMasterVolumeLevelScalar(
            static_cast<float>(std::clamp(position, 0, 100)) / 100.0f,
            nullptr);
        BOOL muted = FALSE;
        (void)volume->GetMute(&muted);
        if (muted && position > 0)
        {
            (void)volume->SetMute(FALSE, nullptr);
        }
    }
    UpdateState();
}

void CloudOSNativeQuickSettingsWindow::ToggleMute()
{
    const auto volume = DefaultEndpointVolume();
    if (volume == nullptr)
    {
        return;
    }
    BOOL muted = FALSE;
    if (SUCCEEDED(volume->GetMute(&muted)))
    {
        (void)volume->SetMute(!muted, nullptr);
    }
    UpdateState();
}

void CloudOSNativeQuickSettingsWindow::ShowNear(const RECT& anchor)
{
    if (window_ == nullptr)
    {
        return;
    }

    UpdateState();
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(420, dpi);
    const int height = Scale(350, dpi);
    int x = anchor.right - width;
    int y = anchor.top - height - Scale(8, dpi);
    x = std::clamp(x, info.rcWork.left, std::max(info.rcWork.left, info.rcWork.right - width));
    y = std::clamp(y, info.rcWork.top, std::max(info.rcWork.top, info.rcWork.bottom - height));

    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetTimer(window_, kRefreshTimer, 1500, nullptr);
}

void CloudOSNativeQuickSettingsWindow::ToggleNear(const RECT& anchor)
{
    if (window_ == nullptr)
    {
        return;
    }
    IsWindowVisible(window_) ? Hide() : ShowNear(anchor);
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

LRESULT CloudOSNativeQuickSettingsWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE)
        {
            Hide();
        }
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
        case kMuteId:
            ToggleMute();
            return 0;
        case kWifiId:
            OpenSettings(window_, L"ms-settings:network-wifi");
            return 0;
        case kBluetoothId:
            OpenSettings(window_, L"ms-settings:bluetooth");
            return 0;
        case kNetworkId:
            OpenSettings(window_, L"ms-settings:network-status");
            return 0;
        case kDisplayId:
            OpenSettings(window_, L"ms-settings:display");
            return 0;
        case kSoundId:
            OpenSettings(window_, L"ms-settings:sound");
            return 0;
        case kPowerId:
            OpenSettings(window_, L"ms-settings:powersleep");
            return 0;
        default:
            break;
        }
        break;
    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            UpdateState();
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE)
        {
            Hide();
            return 0;
        }
        break;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, RGB(238, 241, 247));
        SetBkColor(dc, RGB(24, 26, 31));
        return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(window_, &client);
        FillRect(reinterpret_cast<HDC>(w_param), &client, background_);
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

LRESULT CALLBACK CloudOSNativeQuickSettingsWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeQuickSettingsWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeQuickSettingsWindow*>(create->lpCreateParams);
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
