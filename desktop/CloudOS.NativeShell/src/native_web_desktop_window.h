#pragma once

#include <Windows.h>

#include <functional>
#include <string>

#include "native_webview_host.h"
#include "native_window_manager.h"

namespace CloudOS
{
class CloudOSNativeWebDesktopWindow final
{
public:
    using ActionCallback = std::function<void(int)>;
    using HotKeyCallback = std::function<void(int)>;
    using TimerCallback = std::function<void()>;

    CloudOSNativeWebDesktopWindow() = default;
    ~CloudOSNativeWebDesktopWindow();

    CloudOSNativeWebDesktopWindow(const CloudOSNativeWebDesktopWindow&) = delete;
    CloudOSNativeWebDesktopWindow& operator=(const CloudOSNativeWebDesktopWindow&) = delete;

    bool Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager);
    void Destroy();
    void UpdateLayout(const RECT& work_area);
    void Redraw();
    void FocusSearch();

    void SetActionCallback(ActionCallback callback) { on_action_ = std::move(callback); }
    void SetHotKeyCallback(HotKeyCallback callback) { on_hotkey_ = std::move(callback); }
    void SetTimerCallback(TimerCallback callback) { on_timer_ = std::move(callback); }

    [[nodiscard]] HWND Hwnd() const noexcept { return hwnd_; }
    [[nodiscard]] bool WebReady() const noexcept { return web_host_.Ready(); }

private:
    void HandleWebMessage(const std::wstring& message);
    [[nodiscard]] std::wstring BuildStateJson() const;
    static std::wstring JsonEscape(const std::wstring& value);
    static bool StartsWith(const std::wstring& value, const wchar_t* prefix) noexcept;
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND hwnd_{};
    CloudOSNativeWindowManager* window_manager_{};
    NativeWebViewHost web_host_;
    std::wstring web_failure_detail_;

    ActionCallback on_action_;
    HotKeyCallback on_hotkey_;
    TimerCallback on_timer_;
};
} // namespace CloudOS
