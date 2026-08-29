#pragma once

#include <Windows.h>

#include <functional>

#include "native_desktop_window.h"
#include "native_web_desktop_window.h"
#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSDesktopSurface final
{
public:
    using ActionCallback = std::function<void(int)>;
    using HotKeyCallback = std::function<void(int)>;
    using TimerCallback = std::function<void()>;

    CloudOSDesktopSurface() = default;
    ~CloudOSDesktopSurface();

    CloudOSDesktopSurface(const CloudOSDesktopSurface&) = delete;
    CloudOSDesktopSurface& operator=(const CloudOSDesktopSurface&) = delete;

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();
    void UpdateLayout(const RECT& work_area);
    void Redraw();
    void FocusSearch();

    void SetActionCallback(ActionCallback callback);
    void SetHotKeyCallback(HotKeyCallback callback);
    void SetTimerCallback(TimerCallback callback);

    [[nodiscard]] HWND Hwnd() const noexcept;
    [[nodiscard]] bool UsingWebUi() const noexcept { return web_active_; }

private:
    bool web_active_{};
    CloudOSNativeWebDesktopWindow web_;
    CloudOSNativeDesktopWindow fallback_;
};
} // namespace CloudOS
