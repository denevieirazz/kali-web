#pragma once

#include <Windows.h>

class CloudOSNativeWindowManager;

namespace CloudOS
{
class NativeSnapAssist final
{
public:
    NativeSnapAssist() = default;
    ~NativeSnapAssist();

    NativeSnapAssist(const NativeSnapAssist&) = delete;
    NativeSnapAssist& operator=(const NativeSnapAssist&) = delete;

    bool Start(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Stop() noexcept;

private:
    enum class Zone
    {
        None,
        Maximize,
        LeftHalf,
        RightHalf,
        TopLeftQuarter,
        TopRightQuarter,
        BottomLeftQuarter,
        BottomRightQuarter,
        LeftThird,
        CenterThird,
        RightThird,
        LeftTwoThirds,
        RightTwoThirds,
    };

    static void CALLBACK WinEventCallback(
        HWINEVENTHOOK hook,
        DWORD event,
        HWND window,
        LONG object_id,
        LONG child_id,
        DWORD event_thread,
        DWORD event_time);
    static LRESULT CALLBACK OverlayProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK LayoutProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    bool EnsureOverlay();
    bool EnsureLayoutFlyout();
    void BeginMove(HWND window);
    void UpdateMove(HWND window);
    void EndMove(HWND window);
    void HideOverlay() noexcept;
    void ShowOverlay(const RECT& target);
    void HideLayoutFlyout() noexcept;
    void ShowLayoutFlyout(const RECT& work, Zone selected);
    Zone ResolveZone(HWND window, POINT cursor, RECT* target, bool* show_layout) const;
    bool ApplyZone(HWND window, Zone zone, const RECT& target);
    static bool IsCandidate(HWND window);

    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{};
    HWINEVENTHOOK move_hook_{};
    HWINEVENTHOOK location_hook_{};
    HWND overlay_{};
    HWND layout_flyout_{};
    HWND moving_window_{};
    Zone active_zone_{Zone::None};
    Zone layout_zone_{Zone::None};
    RECT active_target_{};
    RECT layout_work_{};

    static NativeSnapAssist* active_instance_;
};
} // namespace CloudOS
