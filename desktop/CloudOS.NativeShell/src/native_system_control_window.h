#pragma once

#include <windows.h>

#include <array>
#include <string>
#include <vector>

#include "native_system_control_backend.h"

namespace CloudOS
{
class CloudOSNativeSystemControlWindow final
{
public:
    static HWND Open(HINSTANCE instance, HWND owner = nullptr);

private:
    enum class Page : int
    {
        Overview = 0,
        Wifi,
        Display,
        Audio,
        Power,
        Network,
        Storage,
        Processes,
    };

    explicit CloudOSNativeSystemControlWindow(HINSTANCE instance) noexcept;
    ~CloudOSNativeSystemControlWindow();

    bool Create(HWND owner);
    void Destroy() noexcept;
    void Layout();
    void Paint();
    void SetPage(Page page);
    void Refresh(bool force = false);
    void RefreshOverview();
    void RefreshWifi();
    void RefreshDisplay();
    void RefreshAudio();
    void RefreshPower();
    void RefreshNetwork();
    void RefreshStorage();
    void RefreshProcesses();
    void RefreshStatus();
    void ResetListColumns();
    void SetListColumns(const std::vector<std::pair<std::wstring, int>>& columns);
    void ClearDetails();
    void ConfigurePageControls();
    void HandleAction(int control_id);
    void HandleSlider(HWND slider);
    void ConnectSelectedWifi();
    void DisconnectSelectedWifi();
    void ShowError(const std::wstring& title, const std::wstring& error);
    void OpenTarget(const wchar_t* target, const wchar_t* parameters = nullptr);
    int SelectedListIndex() const noexcept;

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND title_{};
    HWND subtitle_{};
    HWND list_{};
    HWND slider_{};
    HWND slider_value_{};
    HWND status_{};
    std::array<HWND, 8> nav_buttons_{};
    std::array<HWND, 6> detail_labels_{};
    std::array<HWND, 4> action_buttons_{};
    HFONT font_{};
    HFONT small_font_{};
    HFONT title_font_{};
    HBRUSH background_{};
    HBRUSH panel_{};

    Page page_{Page::Overview};
    unsigned refresh_tick_{};
    bool slider_programmatic_{};
    std::vector<NativeWifiNetwork> wifi_;
    std::vector<NativeNetworkAdapter> adapters_;
    std::vector<NativeDriveInfo> drives_;
    std::vector<NativeProcessInfo> processes_;
    NativeAudioState audio_{};
    NativeBrightnessState brightness_{};
    NativePowerState power_{};
};
} // namespace CloudOS
