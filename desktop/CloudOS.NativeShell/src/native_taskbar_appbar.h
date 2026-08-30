#pragma once

#include <windows.h>

#include <algorithm>
#include <cstddef>
#include <functional>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "native_shell_pins.h"
#include "native_window_manager.h"

namespace CloudOS
{
constexpr UINT CLOUDOS_WM_TASKBAR_QUERY_HIT = WM_APP + 0x492;

// Floating Dock V7 keeps the full-width HWND as a real SHAppBarMessage AppBar,
// so maximized windows and multi-monitor rcWork remain correct. Only the visible
// and hit-testable region is clipped into a rounded, inset dock. This gives the
// shell the detached 10-DIP bottom gap without sacrificing Windows AppBar
// semantics or introducing a fake overlay taskbar.
namespace FloatingDockV7
{
constexpr int HorizontalInsetDip = 10;
constexpr int TopInsetDip = 4;
constexpr int BottomGapDip = 10;
constexpr int CornerRadiusDip = 20;

inline bool IsTaskbar(HWND window) noexcept
{
    if (window == nullptr || !IsWindow(window)) return false;
    wchar_t class_name[96]{};
    if (GetClassNameW(window, class_name, static_cast<int>(std::size(class_name))) <= 0)
        return false;
    return _wcsicmp(class_name, L"CloudOS.NativeShell.Taskbar.v4") == 0;
}

inline void Apply(HWND window) noexcept
{
    if (!IsTaskbar(window)) return;
    RECT client{};
    if (!GetClientRect(window, &client)) return;
    const int width = static_cast<int>(client.right - client.left);
    const int height = static_cast<int>(client.bottom - client.top);
    if (width <= 0 || height <= 0) return;

    const UINT dpi = GetDpiForWindow(window);
    const auto dip = [dpi](int value) noexcept
    {
        return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
    };
    const int inset = dip(HorizontalInsetDip);
    const int top = dip(TopInsetDip);
    const int bottom_gap = dip(BottomGapDip);
    const int radius = dip(CornerRadiusDip);
    const int right = std::max(inset + 1, width - inset);
    const int bottom = std::max(top + 1, height - bottom_gap);

    HRGN region = CreateRoundRectRgn(
        inset,
        top,
        right + 1,
        bottom + 1,
        radius * 2,
        radius * 2);
    if (region == nullptr) return;
    // SetWindowRgn emits a location-change WinEvent. Avoid feeding that event
    // back into the hook when the geometry is already applied.
    HRGN current = CreateRectRgn(0, 0, 0, 0);
    if (current != nullptr && GetWindowRgn(window, current) != ERROR && EqualRgn(current, region))
    {
        DeleteObject(current);
        DeleteObject(region);
        return;
    }
    if (current != nullptr) DeleteObject(current);
    if (SetWindowRgn(window, region, TRUE) == 0)
        DeleteObject(region); // ownership transfers to USER only on success.
}

inline void CALLBACK WinEventCallback(
    HWINEVENTHOOK,
    DWORD event,
    HWND window,
    LONG object_id,
    LONG child_id,
    DWORD,
    DWORD)
{
    if ((event == EVENT_OBJECT_CREATE || event == EVENT_OBJECT_LOCATIONCHANGE) &&
        object_id == OBJID_WINDOW && child_id == CHILDID_SELF)
    {
        Apply(window);
    }
}

class Bootstrap final
{
public:
    Bootstrap() noexcept
    {
        hook_ = SetWinEventHook(
            EVENT_OBJECT_CREATE,
            EVENT_OBJECT_LOCATIONCHANGE,
            nullptr,
            &WinEventCallback,
            GetCurrentProcessId(),
            0,
            WINEVENT_OUTOFCONTEXT);
    }
    ~Bootstrap()
    {
        if (hook_ != nullptr) UnhookWinEvent(hook_);
    }
    Bootstrap(const Bootstrap&) = delete;
    Bootstrap& operator=(const Bootstrap&) = delete;
private:
    HWINEVENTHOOK hook_{};
};

inline Bootstrap bootstrap;
} // namespace FloatingDockV7

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

    HWND Hwnd() const noexcept
    {
        FloatingDockV7::Apply(window_);
        return window_;
    }
    HMONITOR Monitor() const noexcept { return monitor_; }
    RECT Bounds() const noexcept;

    void SetStartCallback(AnchorCallback callback) { on_start_ = std::move(callback); }
    void SetQuickSettingsCallback(AnchorCallback callback) { on_quick_settings_ = std::move(callback); }
    void SetNotificationsCallback(AnchorCallback callback) { on_notifications_ = std::move(callback); }

private:
    struct TaskGroup final
    {
        DWORD process_id{};
        std::wstring class_name;
        std::vector<HWND> windows;
        std::wstring title;
    };

    void Paint();
    void RebuildHitTargets();
    void ReloadPins();
    void LaunchPinned(std::size_t index);
    void LaunchPin(const ShellPinItem& pin);
    void ShowPinnedContextMenu(std::size_t index, POINT screen_point);
    void ShowPinOverflowMenu(POINT screen_point);
    void ShowTaskContextMenu(std::size_t index, POINT screen_point);
    void ShowTaskGroupPicker(std::size_t index, POINT screen_point);
    void ShowTaskOverflowMenu(POINT screen_point);
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
    RECT pin_overflow_rect_{};
    RECT task_overflow_rect_{};
    std::vector<RECT> workspace_rects_;
    std::vector<RECT> pinned_rects_;
    std::vector<ShellPinItem> pinned_items_;
    std::vector<RECT> task_rects_;
    std::vector<TaskGroup> task_groups_;
    std::size_t visible_pin_count_{};
    std::size_t visible_task_group_count_{};

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
