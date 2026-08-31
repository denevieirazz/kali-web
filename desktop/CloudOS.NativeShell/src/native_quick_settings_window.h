#pragma once

#include <windows.h>

#include <string>
#include "native_quick_model_v12.h"
#include "native_flyout_layout.h"
#include <vector>

#include "native_audio_mixer_v7.h"
#include "native_bluetooth_v7.h"
#include "native_media_control_v7.h"
#include "native_quick_settings_media_v8.h"
#include "native_system_control_backend.h"
#include "native_windows_search_v7.h"

namespace CloudOS
{
class NativeSurfacePreview;
class CloudOSNativeQuickSettingsWindow final
{
public:
    CloudOSNativeQuickSettingsWindow() = default;
    ~CloudOSNativeQuickSettingsWindow();

    bool Create(HINSTANCE instance);
    bool Translate(MSG* message)
    {
        if(!window_ || !IsWindowVisible(window_) || (message->hwnd!=window_ && !IsChild(window_,message->hwnd))) return false;
        const bool handled=IsDialogMessageW(window_,message)!=FALSE;
        if(handled && message->message==WM_KEYDOWN && message->wParam==VK_TAB)
        {
            const HWND focus=GetFocus();
            if(focus && IsChild(window_,focus))
            {
                RECT rect{},client{};GetWindowRect(focus,&rect);MapWindowPoints(nullptr,window_,reinterpret_cast<POINT*>(&rect),2);GetClientRect(window_,&client);
                if(rect.top<0) scroll_v12_.position+=rect.top-8;
                else if(rect.bottom>client.bottom) scroll_v12_.position+=rect.bottom-client.bottom+8;
                scroll_v12_.Clamp();Layout();
            }
        }
        return handled;
    }

    void Destroy();
    void ToggleNear(const RECT& anchor);
    void ShowNear(const RECT& anchor);
    void Hide();
    void Refresh();

private:
    friend class NativeSurfacePreview;
    NativeQuickModelV12 model_v12_;
    NativeScrollState scroll_v12_;
    bool advanced_v12_{};
    HWND advanced_button_{};
    void Layout();
    void UpdateState(bool force_network = false);
    void ApplyVolumeFromSlider();
    void ApplyBrightnessFromSlider();
    void ApplyMixerFromSlider();
    void ToggleMute();
    void ToggleMixerMute();
    void HandleWifiAction();
    void HandleBluetoothAction();
    void ApplyPowerPlan(int plan);
    void CycleAccent();
    void OpenSystemCenter();
    void RefreshMixerSelection();
    void RefreshBluetoothSelection();
    int SelectedWifiIndex() const noexcept;
    int SelectedAudioSessionIndex() const noexcept;
    int SelectedBluetoothIndex() const noexcept;
    void ShowOperationResult(
        const std::wstring& title,
        bool success,
        const std::wstring& error = {});
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND title_{};
    HWND subtitle_{};

    HWND media_label_{};
    HWND media_meta_{};
    HWND media_previous_button_{};
    HWND media_toggle_button_{};
    HWND media_next_button_{};

    HWND volume_label_{};
    HWND volume_slider_{};
    HWND mute_button_{};

    HWND mixer_label_{};
    HWND mixer_combo_{};
    HWND mixer_slider_{};
    HWND mixer_mute_button_{};

    HWND wifi_label_{};
    HWND wifi_combo_{};
    HWND wifi_action_button_{};

    HWND bluetooth_label_{};
    HWND bluetooth_combo_{};
    HWND bluetooth_action_button_{};
    HWND bluetooth_button_{};

    HWND brightness_label_{};
    HWND brightness_slider_{};
    HWND power_label_{};
    HWND balanced_button_{};
    HWND saver_button_{};
    HWND performance_button_{};
    HWND system_center_button_{};
    HWND appearance_button_{};

    UINT font_dpi_v12_{};
    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    bool updating_slider_{};
    unsigned wifi_refresh_tick_{};
    unsigned mixer_refresh_tick_{};
    unsigned bluetooth_refresh_tick_{};
    std::vector<NativeWifiNetwork> wifi_networks_;
    std::vector<NativeAudioSessionV7> audio_sessions_;
    std::vector<NativeBluetoothDeviceV7> bluetooth_devices_;
};
} // namespace CloudOS
