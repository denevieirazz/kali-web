#pragma once

#include <windows.h>

#include <string>
#include <vector>

#include "native_audio_mixer_v7.h"
#include "native_bluetooth_v7.h"
#include "native_media_control_v7.h"
#include "native_system_control_backend.h"
#include "native_windows_search_v7.h"

namespace CloudOS
{
class CloudOSNativeQuickSettingsWindow final
{
public:
    CloudOSNativeQuickSettingsWindow() = default;
    ~CloudOSNativeQuickSettingsWindow();

    bool Create(HINSTANCE instance);
    void Destroy();
    void ToggleNear(const RECT& anchor);
    void ShowNear(const RECT& anchor);
    void Hide();
    void Refresh();

private:
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