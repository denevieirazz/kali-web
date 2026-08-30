#pragma once

#include <windows.h>

#include <functional>
#include <vector>

#include "native_system_stats.h"
#include "native_theme.h"
#include "native_window_manager.h"

namespace CloudOS
{
// Shell V3 desktop is intentionally narrow: wallpaper, desktop namespace,
// first-party shortcuts and input forwarding. Start, AppBar/taskbar and flyouts
// are separate HWND components and must not creep back into this class.
class CloudOSNativeDesktopWindow final
{
public:
    using ActionCallback = std::function<void(int)>;
    using HotKeyCallback = std::function<void(int)>;
    using TimerCallback = std::function<void()>;

    CloudOSNativeDesktopWindow() = default;
    ~CloudOSNativeDesktopWindow();

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();

    void UpdateLayout(const RECT& work_area);
    void Redraw();
    void FocusSearch();

    void SetActionCallback(ActionCallback callback) { on_action_ = std::move(callback); }
    void SetHotKeyCallback(HotKeyCallback callback) { on_hotkey_ = std::move(callback); }
    void SetTimerCallback(TimerCallback callback) { on_timer_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }

private:
    void Paint();
    void ActivateAppIndex(int app_index);
    void RefreshWorkArea();

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

    HWND hwnd_{};
    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{nullptr};

    std::vector<RECT> quick_launch_rects_;
    std::vector<int> quick_launch_app_indices_;
    SystemStats current_stats_{};

    ActionCallback on_action_;
    HotKeyCallback on_hotkey_;
    TimerCallback on_timer_;
};
} // namespace CloudOS
