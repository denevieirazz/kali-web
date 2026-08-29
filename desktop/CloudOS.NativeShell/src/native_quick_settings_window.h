#pragma once

#include <windows.h>

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
    void UpdateState();
    void ApplyVolumeFromSlider();
    void ToggleMute();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND title_{};
    HWND volume_label_{};
    HWND volume_slider_{};
    HWND mute_button_{};
    HWND power_label_{};
    HWND monitor_label_{};
    HWND wifi_button_{};
    HWND bluetooth_button_{};
    HWND network_button_{};
    HWND display_button_{};
    HWND sound_button_{};
    HWND power_button_{};
    HFONT font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    bool updating_slider_{};
};
} // namespace CloudOS
