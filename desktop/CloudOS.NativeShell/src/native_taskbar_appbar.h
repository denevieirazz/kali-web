#pragma once

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSTaskbarAppBar final
{
public:
    using AnchorCallback = std::function<void(const RECT&)>;

    CloudOSTaskbarAppBar() = default;
    ~CloudOSTaskbarAppBar();

    bool Create(
        HINSTANCE instance,
        CloudOSNativeWindowManager* window_manager,
        HMONITOR monitor,
        bool primary);
    void Destroy();
    void Refresh();
    void PositionAppBar();

    HWND Hwnd() const noexcept { return window_; }
    HMONITOR Monitor() const noexcept { return monitor_; }
    RECT Bounds() const noexcept;

    void SetStartCallback(AnchorCallback callback) { on_start_ = std::move(callback); }
    void SetQuickSettingsCallback(AnchorCallback callback) { on_quick_settings_ = std::move(callback); }
    void SetNotificationsCallback(AnchorCallback callback) { on_notifications_ = std::move(callback); }

private:
    void Paint();
    void RebuildHitTargets();
    void LaunchPinned(std::size_t index);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{};
    HMONITOR monitor_{};
    bool primary_{};
    bool registered_{};
    HWND window_{};

    RECT start_rect_{};
    RECT quick_rect_{};
    RECT notification_rect_{};
    RECT clock_rect_{};
    std::vector<RECT> workspace_rects_;
    std::vector<RECT> pinned_rects_;
    std::vector<int> pinned_app_indices_;
    std::vector<RECT> task_rects_;
    std::vector<HWND> task_windows_;

    int hovered_kind_{-1};
    int hovered_index_{-1};
    bool tracking_mouse_{};

    AnchorCallback on_start_;
    AnchorCallback on_quick_settings_;
    AnchorCallback on_notifications_;
};
} // namespace CloudOS
