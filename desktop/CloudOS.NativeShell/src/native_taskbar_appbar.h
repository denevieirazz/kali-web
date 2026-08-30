#pragma once

#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstddef>
#include <functional>
#include <iterator>
#include <new>
#include <string>
#include <string_view>
#include <vector>

#include "native_shell_pins.h"
#include "native_theme.h"
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

    // Read-only visual telemetry consumed by the V8 post-paint compositor.
    // Keeping these accessors inside the Taskbar class means the overlay uses
    // the authoritative hit geometry instead of duplicating layout formulas.
    [[nodiscard]] int V8CurrentWorkspace() const noexcept
    {
        return window_manager_ != nullptr ? window_manager_->CurrentWorkspace() : 0;
    }
    [[nodiscard]] const std::vector<RECT>& V8WorkspaceRects() const noexcept
    {
        return workspace_rects_;
    }
    [[nodiscard]] const std::vector<RECT>& V8TaskRects() const noexcept
    {
        return task_rects_;
    }
    [[nodiscard]] const std::vector<RECT>& V8PinnedRects() const noexcept
    {
        return pinned_rects_;
    }
    [[nodiscard]] bool V8TaskActive(std::size_t index) const noexcept
    {
        if (window_manager_ == nullptr || index >= task_groups_.size()) return false;
        const HWND active = window_manager_->ActiveManagedWindow();
        if (active == nullptr) return false;
        const auto& windows = task_groups_[index].windows;
        return std::find(windows.begin(), windows.end(), active) != windows.end();
    }
    [[nodiscard]] int V8HoveredKind() const noexcept { return hovered_kind_; }
    [[nodiscard]] int V8HoveredIndex() const noexcept { return hovered_index_; }

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

// Shell Experience V8 is deliberately a post-paint layer. Taskbar V4 remains
// authoritative for AppBar registration, hit testing, grouping and input; V8
// only adds motion/light after the proven renderer finishes.
namespace DockExperienceV8
{
constexpr UINT_PTR kSubclassId = 0xC10D8008u;
constexpr UINT_PTR kMotionTimer = 0xC808u;
constexpr ULONGLONG kWorkspaceMotionMs = 220u;

struct State final
{
    bool initialized{};
    bool animating{};
    int settled_workspace{};
    int from_workspace{};
    int to_workspace{};
    ULONGLONG started{};
};

inline LONG LerpLong(LONG from, LONG to, float progress) noexcept
{
    const float value = static_cast<float>(from) +
        (static_cast<float>(to - from) * WebSkin::ClampUnit(progress));
    return static_cast<LONG>(value >= 0.0f ? value + 0.5f : value - 0.5f);
}

inline RECT InterpolateRect(const RECT& from, const RECT& to, float progress) noexcept
{
    return RECT{
        LerpLong(from.left, to.left, progress),
        LerpLong(from.top, to.top, progress),
        LerpLong(from.right, to.right, progress),
        LerpLong(from.bottom, to.bottom, progress)};
}

inline void DrawWorkspaceNumber(
    Gdiplus::Graphics& graphics,
    const RECT& rect,
    UINT dpi,
    int number,
    bool active)
{
    Gdiplus::Font font(
        L"Segoe UI Variable Text",
        static_cast<Gdiplus::REAL>(Scale(10, dpi)),
        Gdiplus::FontStyleBold,
        Gdiplus::UnitPixel);
    Gdiplus::SolidBrush brush(WebSkin::GdiColor(
        active ? WebSkin::TextPrimary : WebSkin::TextSecondary));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    const std::wstring value = std::to_wstring(number);
    graphics.DrawString(
        value.c_str(),
        -1,
        &font,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(rect.left),
            static_cast<Gdiplus::REAL>(rect.top),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.right - rect.left)),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.bottom - rect.top))),
        &format,
        &brush);
}

inline void DrawTaskIndicator(
    Gdiplus::Graphics& graphics,
    const RECT& rect,
    UINT dpi,
    bool active)
{
    if (rect.right <= rect.left || rect.bottom <= rect.top) return;
    const int indicator_width = Scale(active ? 46 : 20, dpi);
    const int indicator_height = std::max(2, Scale(active ? 3 : 2, dpi));
    const int center = (rect.left + rect.right) / 2;
    const int top = rect.bottom - Scale(5, dpi);
    Gdiplus::RectF line(
        static_cast<Gdiplus::REAL>(center - indicator_width / 2),
        static_cast<Gdiplus::REAL>(top),
        static_cast<Gdiplus::REAL>(indicator_width),
        static_cast<Gdiplus::REAL>(indicator_height));

    if (active)
    {
        Gdiplus::RectF glow = line;
        glow.X -= static_cast<Gdiplus::REAL>(Scale(10, dpi));
        glow.Y -= static_cast<Gdiplus::REAL>(Scale(5, dpi));
        glow.Width += static_cast<Gdiplus::REAL>(Scale(20, dpi));
        glow.Height += static_cast<Gdiplus::REAL>(Scale(10, dpi));
        WebSkin::DrawRoundedPanel(
            graphics,
            glow,
            static_cast<Gdiplus::REAL>(Scale(8, dpi)),
            WebSkin::GdiColor(WebSkin::Accent, 28),
            Gdiplus::Color(0, 0, 0, 0),
            0.0f);
        Gdiplus::LinearGradientBrush gradient(
            Gdiplus::PointF(line.X, line.Y),
            Gdiplus::PointF(line.GetRight(), line.Y),
            WebSkin::GdiColor(WebSkin::Accent),
            WebSkin::GdiColor(WebSkin::AccentCyan));
        Gdiplus::GraphicsPath path;
        path.AddRectangle(line);
        graphics.FillPath(&gradient, &path);
    }
    else
    {
        WebSkin::DrawRoundedPanel(
            graphics,
            line,
            static_cast<Gdiplus::REAL>(Scale(3, dpi)),
            WebSkin::GdiColor(WebSkin::AccentHover, 185),
            Gdiplus::Color(0, 0, 0, 0),
            0.0f);
    }
}

inline void Draw(HWND window, State* state)
{
    if (window == nullptr || state == nullptr || !IsWindow(window)) return;
    auto* taskbar = reinterpret_cast<CloudOSTaskbarAppBar*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (taskbar == nullptr) return;

    const auto& workspace_rects = taskbar->V8WorkspaceRects();
    const auto& task_rects = taskbar->V8TaskRects();
    if (workspace_rects.empty() && task_rects.empty()) return;

    const int current_workspace = std::clamp(taskbar->V8CurrentWorkspace(), 0, 3);
    if (!state->initialized)
    {
        state->initialized = true;
        state->settled_workspace = current_workspace;
        state->from_workspace = current_workspace;
        state->to_workspace = current_workspace;
    }
    else if (current_workspace != state->to_workspace)
    {
        state->from_workspace = state->animating
            ? state->to_workspace
            : state->settled_workspace;
        state->to_workspace = current_workspace;
        state->started = GetTickCount64();
        state->animating = true;
        (void)SetTimer(window, kMotionTimer, 16, nullptr);
    }

    float progress = 1.0f;
    if (state->animating)
    {
        const ULONGLONG elapsed = GetTickCount64() - state->started;
        progress = WebSkin::EaseOutCubic(
            static_cast<float>(std::min<ULONGLONG>(elapsed, kWorkspaceMotionMs)) /
            static_cast<float>(kWorkspaceMotionMs));
        if (elapsed >= kWorkspaceMotionMs)
        {
            state->animating = false;
            state->settled_workspace = state->to_workspace;
            (void)KillTimer(window, kMotionTimer);
            progress = 1.0f;
        }
    }

    HDC dc = GetDC(window);
    if (dc == nullptr) return;
    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(window);

    // Repaint the workspace cluster as a neutral translucent rail, then draw a
    // single animated indicator. This hides the old instant-switch accent pill
    // without replacing Taskbar V4's hit targets or click handling.
    for (std::size_t index = 0; index < workspace_rects.size(); ++index)
    {
        const RECT& rect = workspace_rects[index];
        const bool hot = taskbar->V8HoveredKind() == 8 &&
            taskbar->V8HoveredIndex() == static_cast<int>(index);
        WebSkin::DrawRoundedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(rect.left),
                static_cast<Gdiplus::REAL>(rect.top),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.right - rect.left)),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.bottom - rect.top))),
            static_cast<Gdiplus::REAL>(Scale(12, dpi)),
            WebSkin::GdiColor(hot ? WebSkin::BgHover : WebSkin::BgTertiary, 248),
            WebSkin::GdiColor(hot ? WebSkin::BorderStrong : WebSkin::BorderDefault, 235),
            1.0f);
    }

    if (state->from_workspace >= 0 && state->to_workspace >= 0 &&
        static_cast<std::size_t>(state->from_workspace) < workspace_rects.size() &&
        static_cast<std::size_t>(state->to_workspace) < workspace_rects.size())
    {
        const RECT indicator = InterpolateRect(
            workspace_rects[static_cast<std::size_t>(state->from_workspace)],
            workspace_rects[static_cast<std::size_t>(state->to_workspace)],
            progress);
        RECT glow = indicator;
        InflateRect(&glow, Scale(3, dpi), Scale(3, dpi));
        WebSkin::DrawRoundedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(glow.left),
                static_cast<Gdiplus::REAL>(glow.top),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, glow.right - glow.left)),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, glow.bottom - glow.top))),
            static_cast<Gdiplus::REAL>(Scale(14, dpi)),
            WebSkin::GdiColor(WebSkin::Accent, 34),
            WebSkin::GdiColor(WebSkin::AccentCyan, 70),
            1.0f);
        WebSkin::DrawRoundedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(indicator.left),
                static_cast<Gdiplus::REAL>(indicator.top),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, indicator.right - indicator.left)),
                static_cast<Gdiplus::REAL>(std::max<LONG>(1, indicator.bottom - indicator.top))),
            static_cast<Gdiplus::REAL>(Scale(12, dpi)),
            WebSkin::GdiColor(WebSkin::Accent, 238),
            WebSkin::GdiColor(WebSkin::AccentHover),
            1.0f);
    }

    for (std::size_t index = 0; index < workspace_rects.size(); ++index)
    {
        DrawWorkspaceNumber(
            graphics,
            workspace_rects[index],
            dpi,
            static_cast<int>(index) + 1,
            static_cast<int>(index) == current_workspace);
    }

    for (std::size_t index = 0; index < task_rects.size(); ++index)
    {
        DrawTaskIndicator(graphics, task_rects[index], dpi, taskbar->V8TaskActive(index));
    }

    // Pinned icons keep their original raster position, but the hovered icon
    // receives a cyan halo/specular edge so it reads as lifted from the dock.
    if (taskbar->V8HoveredKind() == 2)
    {
        const int hovered = taskbar->V8HoveredIndex();
        const auto& pinned = taskbar->V8PinnedRects();
        if (hovered >= 0 && static_cast<std::size_t>(hovered) < pinned.size())
        {
            RECT halo = pinned[static_cast<std::size_t>(hovered)];
            InflateRect(&halo, Scale(2, dpi), Scale(2, dpi));
            WebSkin::DrawRoundedPanel(
                graphics,
                Gdiplus::RectF(
                    static_cast<Gdiplus::REAL>(halo.left),
                    static_cast<Gdiplus::REAL>(halo.top - Scale(2, dpi)),
                    static_cast<Gdiplus::REAL>(std::max<LONG>(1, halo.right - halo.left)),
                    static_cast<Gdiplus::REAL>(std::max<LONG>(1, halo.bottom - halo.top))),
                static_cast<Gdiplus::REAL>(Scale(13, dpi)),
                WebSkin::GdiColor(WebSkin::AccentCyan, 18),
                WebSkin::GdiColor(WebSkin::AccentCyan, 105),
                1.0f);
        }
    }

    ReleaseDC(window, dc);
}

inline LRESULT CALLBACK SubclassProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference)
{
    auto* state = reinterpret_cast<State*>(reference);
    if (message == WM_TIMER && w_param == kMotionTimer)
    {
        InvalidateRect(window, nullptr, FALSE);
        return 0;
    }

    const LRESULT result = DefSubclassProc(window, message, w_param, l_param);
    if (message == WM_PAINT)
    {
        Draw(window, state);
    }
    else if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, SubclassProcedure, subclass_id);
        delete state;
    }
    return result;
}

inline void Attach(HWND window) noexcept
{
    if (!FloatingDockV7::IsTaskbar(window)) return;
    DWORD_PTR existing = 0;
    if (GetWindowSubclass(window, SubclassProcedure, kSubclassId, &existing) != FALSE)
        return;

    State* state = new (std::nothrow) State{};
    if (state == nullptr) return;
    if (SetWindowSubclass(
            window,
            SubclassProcedure,
            kSubclassId,
            reinterpret_cast<DWORD_PTR>(state)) == FALSE)
    {
        delete state;
    }
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
        Attach(window);
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
} // namespace DockExperienceV8
} // namespace CloudOS
