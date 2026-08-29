#pragma once

#include <windows.h>
#include <functional>
#include <vector>
#include <array>
#include "native_theme.h"
#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSNativeDashWindow final
{
public:
    using AppCallback = std::function<void(const AppItem&)>;
    using ActionCallback = std::function<void()>;

    CloudOSNativeDashWindow() = default;
    ~CloudOSNativeDashWindow();

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();

    void UpdateLayout(const RECT& work_area);
    void Redraw();

    void SetAppCallback(AppCallback callback) { on_app_ = std::move(callback); }
    void SetToggleGridCallback(ActionCallback callback) { on_toggle_grid_ = std::move(callback); }

    HWND Hwnd() const noexcept { return hwnd_; }

private:
    void Paint();
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HWND hwnd_{};
    HINSTANCE instance_{};
    CloudOSNativeWindowManager* window_manager_{nullptr};

    std::vector<RECT> dash_app_rects_;
    RECT nine_dots_rect_{};
    int hovered_index_{-1};
    bool tracking_mouse_{false};

    AppCallback on_app_;
    ActionCallback on_toggle_grid_;
};
} // namespace CloudOS
