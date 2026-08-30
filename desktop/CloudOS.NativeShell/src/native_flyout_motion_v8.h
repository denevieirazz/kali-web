#pragma once

#include <windows.h>
#include <commctrl.h>

#include <algorithm>
#include <array>
#include <string_view>

namespace CloudOS::FlyoutMotionV8
{
constexpr UINT_PTR MotionTimerId = 0xC108;
constexpr UINT_PTR MotionSubclassId = 0xC108A11;
constexpr wchar_t AlphaProperty[] = L"CloudOS.FlyoutMotionV8.Alpha";
constexpr wchar_t LayeredProperty[] = L"CloudOS.FlyoutMotionV8.Layered";

inline bool AnimationsEnabled() noexcept
{
    BOOL enabled = TRUE;
    if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0) == FALSE)
        return true;
    return enabled != FALSE;
}

inline bool IsSupportedFlyout(HWND window) noexcept
{
    if (window == nullptr || !IsWindow(window)) return false;
    wchar_t class_name[128]{};
    const int length = GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
    if (length <= 0) return false;
    const std::wstring_view name(class_name, static_cast<std::size_t>(length));
    return name == L"CloudOS.NativeShell.Start.v4" ||
        name == L"CloudOS.NativeShell.QuickSettings.v4" ||
        name == L"CloudOS.NativeShell.NotificationCenter.v2";
}

inline void Finish(HWND window) noexcept
{
    KillTimer(window, MotionTimerId);
    SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA);
    RemovePropW(window, AlphaProperty);

    const bool originally_layered = GetPropW(window, LayeredProperty) != nullptr;
    RemovePropW(window, LayeredProperty);
    if (!originally_layered)
    {
        const LONG_PTR ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
        if ((ex_style & WS_EX_LAYERED) != 0)
        {
            SetWindowLongPtrW(window, GWL_EXSTYLE, ex_style & ~static_cast<LONG_PTR>(WS_EX_LAYERED));
            SetWindowPos(window, nullptr, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        }
    }
}

inline LRESULT CALLBACK MotionSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR)
{
    if (message == WM_TIMER && w_param == MotionTimerId)
    {
        const INT_PTR stored = reinterpret_cast<INT_PTR>(GetPropW(window, AlphaProperty));
        int alpha = stored > 0 ? static_cast<int>(stored - 1) : 0;
        alpha = std::min(255, alpha + 46);
        SetLayeredWindowAttributes(window, 0, static_cast<BYTE>(alpha), LWA_ALPHA);
        if (alpha >= 255)
            Finish(window);
        else
            SetPropW(window, AlphaProperty, reinterpret_cast<HANDLE>(static_cast<INT_PTR>(alpha + 1)));
        return 0;
    }
    if (message == WM_NCDESTROY)
    {
        KillTimer(window, MotionTimerId);
        RemovePropW(window, AlphaProperty);
        RemovePropW(window, LayeredProperty);
        RemoveWindowSubclass(window, MotionSubclass, subclass_id);
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

inline void AnimateShown(HWND window) noexcept
{
    if (!IsSupportedFlyout(window) || !AnimationsEnabled()) return;

    const LONG_PTR original_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    const bool already_layered = (original_style & WS_EX_LAYERED) != 0;
    SetPropW(window, LayeredProperty,
        already_layered ? reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)) : nullptr);
    if (!already_layered)
        SetWindowLongPtrW(window, GWL_EXSTYLE, original_style | WS_EX_LAYERED);

    (void)SetWindowSubclass(window, MotionSubclass, MotionSubclassId, 0);
    SetPropW(window, AlphaProperty, reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
    SetLayeredWindowAttributes(window, 0, 0, LWA_ALPHA);
    SetTimer(window, MotionTimerId, 16, nullptr);
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
    if (event == EVENT_OBJECT_SHOW &&
        object_id == OBJID_WINDOW &&
        child_id == CHILDID_SELF)
    {
        AnimateShown(window);
    }
}

class Bootstrap final
{
public:
    Bootstrap() noexcept
    {
        hook_ = SetWinEventHook(
            EVENT_OBJECT_SHOW,
            EVENT_OBJECT_SHOW,
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
} // namespace CloudOS::FlyoutMotionV8
