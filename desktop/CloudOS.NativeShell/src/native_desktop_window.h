#pragma once

#include <windows.h>
#include <functional>
#include <vector>
#include "native_theme.h"
#include "native_window_manager.h"
#include "native_system_stats.h"

namespace CloudOS
{
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

    void SetActionCallback(ActionCallback callback) { on_action_ = std::move(callback); }
    void SetHotKeyCallback(HotKeyCallback callback) { on_hotkey_ = std::move(callback); }
    void SetTimerCallback(TimerCallback callback) { on_timer_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }

private:
    void Paint();
    void OnSearchChanged();
    void SelectFocusedApp();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK SearchSubclass(HWND window, UINT message, WPARAM w_param, LPARAM l_param, UINT_PTR uIdSubclass, DWORD_PTR dwRefData);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HWND hwnd_{};
    HWND search_edit_{};
    HFONT search_font_{};
    HBRUSH edit_bg_brush_{};
    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{nullptr};

    std::wstring search_query_;
    std::vector<int> filtered_indices_;
    std::vector<RECT> app_grid_rects_;
    int focused_app_index_{0};
    int hovered_app_index_{-1};
    int hovered_widget_id_{-1};
    int hovered_dock_id_{-1};
    bool tracking_mouse_{false};

    // Widget Clickable Rectangles
    RECT profile_rect_{};
    RECT weather_rect_{};
    RECT calendar_rect_{};
    RECT perf_rect_{};
    RECT news_rect_{};
    std::vector<RECT> dock_rects_;

    SystemStats current_stats_{};

    ActionCallback on_action_;
    HotKeyCallback on_hotkey_;
    TimerCallback on_timer_;
};
} // namespace CloudOS
