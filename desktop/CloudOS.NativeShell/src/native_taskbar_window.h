#pragma once

#include <windows.h>
#include <functional>
#include <vector>
#include <array>
#include "native_theme.h"
#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSNativeTaskbarWindow final
{
public:
    using StartToggleCallback = std::function<void(POINT anchor)>;
    using AppCallback = std::function<void(const AppItem&)>;
    using WorkspaceCallback = std::function<void(int)>;

    CloudOSNativeTaskbarWindow() = default;
    ~CloudOSNativeTaskbarWindow();

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();

    void UpdateLayout(const RECT& work_area);
    void Redraw();

    void SetStartToggleCallback(StartToggleCallback callback) { on_start_toggle_ = std::move(callback); }
    void SetAppCallback(AppCallback callback) { on_app_ = std::move(callback); }
    void SetWorkspaceCallback(WorkspaceCallback callback) { on_workspace_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }
    int HeightPixels() const noexcept;

private:
    void Paint();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HWND hwnd_{};
    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{nullptr};

    RECT start_btn_rect_{};
    std::array<RECT, 6> pinned_app_rects_{};
    std::array<RECT, 4> workspace_rects_{};
    std::vector<TaskHit> task_hits_;

    StartToggleCallback on_start_toggle_;
    AppCallback on_app_;
    WorkspaceCallback on_workspace_;
};
} // namespace CloudOS
