#pragma once

#include <windows.h>

#include <array>
#include <functional>
#include <string>
#include <vector>

#include "native_system_stats.h"
#include "native_theme.h"
#include "native_window_manager.h"

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
    void FocusSearch();

    void SetActionCallback(ActionCallback callback) { on_action_ = std::move(callback); }
    void SetHotKeyCallback(HotKeyCallback callback) { on_hotkey_ = std::move(callback); }
    void SetTimerCallback(TimerCallback callback) { on_timer_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }

private:
    void Paint();
    void OnSearchChanged();
    void SelectFocusedApp();
    void ActivateAppIndex(int app_index);
    void RefreshWorkArea();
    void SetStartMenuOpen(bool open, bool focus_search = true);
    void ToggleStartMenu();
    bool IsPointClickable(POINT point) const;

    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK SearchSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data);
    static LRESULT CALLBACK WindowProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param);

    HWND hwnd_{};
    HWND search_edit_{};
    HFONT search_font_{};
    HBRUSH edit_bg_brush_{};
    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{nullptr};

    std::wstring search_query_;
    std::vector<int> filtered_indices_;
    std::vector<RECT> app_grid_rects_;
    std::vector<RECT> quick_launch_rects_;
    std::vector<int> quick_launch_app_indices_;
    std::vector<RECT> dock_rects_;
    std::vector<int> dock_app_indices_;
    std::vector<TaskHit> task_hits_;
    std::array<RECT, 4> workspace_rects_{};

    int focused_app_index_{0};
    int hovered_app_index_{-1};
    int hovered_widget_id_{-1};
    int hovered_dock_id_{-1};
    bool tracking_mouse_{false};
    bool start_menu_open_{false};

    RECT start_button_rect_{};
    RECT start_menu_rect_{};
    RECT power_button_rect_{};
    RECT desktop_status_rect_{};
    RECT system_button_rect_{};
    RECT clock_rect_{};

    SystemStats current_stats_{};

    ActionCallback on_action_;
    HotKeyCallback on_hotkey_;
    TimerCallback on_timer_;
};
} // namespace CloudOS
