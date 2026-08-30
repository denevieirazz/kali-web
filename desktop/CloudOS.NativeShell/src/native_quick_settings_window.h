#pragma once

#include <windows.h>

#include <string>
#include <vector>

#include "native_system_control_backend.h"

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
    void UpdateState(bool force_wifi = false);
    void ApplyVolumeFromSlider();
    void ApplyBrightnessFromSlider();
    void ToggleMute();
    void HandleWifiAction();
    void ApplyPowerPlan(int plan);
    void CycleAccent();
    void OpenSystemCenter();
    int SelectedWifiIndex() const noexcept;
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
    HWND volume_label_{};
    HWND volume_slider_{};
    HWND mute_button_{};
    HWND wifi_label_{};
    HWND wifi_combo_{};
    HWND wifi_action_button_{};
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
    std::vector<NativeWifiNetwork> wifi_networks_;
};
} // namespace CloudOS
