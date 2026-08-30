#pragma once

#include <windows.h>

#include <algorithm>

namespace CloudOS::FlyoutMotionV8
{
constexpr DWORD ShowMilliseconds = 115;
constexpr DWORD HideMilliseconds = 85;

inline bool AnimationsEnabled() noexcept
{
    BOOL enabled = TRUE;
    if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) == FALSE)
    {
        return true;
    }
    return enabled != FALSE;
}

inline void Show(
    HWND window,
    int x,
    int y,
    int width,
    int height,
    bool activate = true) noexcept
{
    if (window == nullptr || !IsWindow(window)) return;

    SetWindowPos(
        window,
        HWND_TOPMOST,
        x,
        y,
        std::max(1, width),
        std::max(1, height),
        SWP_NOACTIVATE);

    if (!IsWindowVisible(window))
    {
        const bool animated = AnimationsEnabled() &&
            AnimateWindow(
                window,
                ShowMilliseconds,
                AW_BLEND | (activate ? AW_ACTIVATE : 0)) != FALSE;
        if (!animated)
            ShowWindow(window, activate ? SW_SHOWNORMAL : SW_SHOWNOACTIVATE);
    }
    else
    {
        ShowWindow(window, activate ? SW_SHOWNORMAL : SW_SHOWNOACTIVATE);
    }

    if (activate)
        SetForegroundWindow(window);
}

inline void Hide(HWND window) noexcept
{
    if (window == nullptr || !IsWindow(window) || !IsWindowVisible(window)) return;
    if (!AnimationsEnabled() ||
        AnimateWindow(window, HideMilliseconds, AW_BLEND | AW_HIDE) == FALSE)
    {
        ShowWindow(window, SW_HIDE);
    }
}
} // namespace CloudOS::FlyoutMotionV8
