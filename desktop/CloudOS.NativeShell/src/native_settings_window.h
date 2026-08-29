#pragma once

#include <Windows.h>

#include <string>

constexpr UINT CLOUDOS_WM_NATIVE_SETTINGS_CHANGED = WM_APP + 0x471;

struct CloudOSNativeSettings final
{
    bool tiling_on_start{};
    std::wstring default_wsl_distribution{L"kali-linux"};
};

class CloudOSNativeSettingsWindow final
{
public:
    static void Open(HINSTANCE instance);
    static CloudOSNativeSettings Load();
    static bool Save(const CloudOSNativeSettings& settings);

    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

private:
    explicit CloudOSNativeSettingsWindow(HINSTANCE instance);
    ~CloudOSNativeSettingsWindow() = default;

    CloudOSNativeSettingsWindow(const CloudOSNativeSettingsWindow&) = delete;
    CloudOSNativeSettingsWindow& operator=(const CloudOSNativeSettingsWindow&) = delete;

    bool Create();
    void Layout();
    void LoadIntoControls();
    void SaveFromControls();
    void OpenWindowsSettings();
    void InstallWsl();
    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND title_{};
    HWND tiling_checkbox_{};
    HWND distro_label_{};
    HWND distro_edit_{};
    HWND save_button_{};
    HWND windows_settings_button_{};
    HWND install_wsl_button_{};
};
