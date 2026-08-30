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

    // Snap Layouts V8 is a shell-owned popup and never enters another process.
    // This read-only bridge lets its final placement mark the managed HWND as
    // floating and reconcile the existing CloudOS window model immediately.
    static CloudOSNativeWindowManager* ActiveWindowManager() noexcept
    {
        return active_instance_ != nullptr ? active_instance_->window_manager_ : nullptr;
    }

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

    bool EnsureOverlay();
    void BeginMove(HWND window);
    void UpdateMove(HWND window);
    void EndMove(HWND window);
    void HideOverlay() noexcept;
    void ShowOverlay(const RECT& target);
    Zone ResolveZone(HWND window, POINT cursor, RECT* target) const;
    bool ApplyZone(HWND window, Zone zone, const RECT& target);
    static bool IsCandidate(HWND window);

    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{};
    HWINEVENTHOOK move_hook_{};
    HWINEVENTHOOK location_hook_{};
    HWND overlay_{};
    HWND moving_window_{};
    Zone active_zone_{Zone::None};
    RECT active_target_{};

    static NativeSnapAssist* active_instance_;
};
} // namespace CloudOS
