#pragma once

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

#include "native_shell_pins.h"
#include "native_window_manager.h"

namespace CloudOS
{
constexpr UINT CLOUDOS_WM_TASKBAR_QUERY_HIT = WM_APP + 0x492;

struct CloudOSTaskbarHitQuery final
{
    POINT client_point{};
    RECT task_rect{};
    HWND window{};
};

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
    struct TaskGroup final
    {
        DWORD process_id{};
        std::vector<HWND> windows;
        std::wstring title;
    };

    void Paint();
    void RebuildHitTargets();
    void ReloadPins();
    void LaunchPinned(std::size_t index);
    void LaunchPin(const ShellPinItem& pin);
    void ShowPinnedContextMenu(std::size_t index, POINT screen_point);
    void ShowTaskContextMenu(std::size_t index, POINT screen_point);
    void ShowTaskGroupPicker(std::size_t index, POINT screen_point);
    void ActivateTaskGroup(std::size_t index);
    void MoveTaskToWorkspace(HWND window, int workspace);
    void CloseTaskGroup(const TaskGroup& group);
    [[nodiscard]] int FindCloudApp(std::wstring_view id) const;
    [[nodiscard]] std::wstring PinTitle(const ShellPinItem& pin) const;
    [[nodiscard]] HWND HitTaskWindow(POINT point, RECT* bounds) const;
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
    std::vector<ShellPinItem> pinned_items_;
    std::vector<RECT> task_rects_;
    std::vector<TaskGroup> task_groups_;

    int hovered_kind_{-1};
    int hovered_index_{-1};
    int drag_pin_index_{-1};
    bool drag_pin_moved_{};
    bool tracking_mouse_{};

    AnchorCallback on_start_;
    AnchorCallback on_quick_settings_;
    AnchorCallback on_notifications_;
};
} // namespace CloudOS
