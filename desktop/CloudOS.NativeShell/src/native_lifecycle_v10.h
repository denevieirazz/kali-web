#pragma once

#include <windows.h>
#include <shellapi.h>

#include <string_view>

#include "native_session_events_v7.h"

#pragma comment(lib, "shell32.lib")

namespace CloudOS::NativeLifecycleV10
{
constexpr UINT RevalidateMessage = WM_APP + 0x5A0;
constexpr UINT ProbeSuspendMessage = WM_APP + 0x5A1;
constexpr UINT ProbeResumeMessage = WM_APP + 0x5A2;
constexpr UINT ProbeDisplayMessage = WM_APP + 0x5A3;
constexpr UINT ProbeSessionDisconnectMessage = WM_APP + 0x5A4;
constexpr UINT ProbeSessionReconnectMessage = WM_APP + 0x5A5;
constexpr UINT_PTR SubclassId = 0xC10D5A10u;
constexpr UINT_PTR RetryTimerId = 0xC10D5A11u;
constexpr UINT RetryTimerMilliseconds = 1000u;
constexpr unsigned WtsRetryEveryTicks = 30u;
constexpr wchar_t DesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
constexpr wchar_t TaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v4";
constexpr wchar_t ProbeArgument[] = L"--lifecycle-probe";

enum class RevalidateReason : WPARAM
{
    Resume = 1,
    Display = 2,
    Session = 3,
    Probe = 4,
};

inline bool HasArgument(std::wstring_view expected) noexcept
{
    int count = 0;
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (arguments == nullptr)
    {
        return false;
    }

    bool found = false;
    for (int index = 1; index < count; ++index)
    {
        if (_wcsicmp(arguments[index], expected.data()) == 0)
        {
            found = true;
            break;
        }
    }
    LocalFree(arguments);
    return found;
}

inline bool ProbeEnabled() noexcept
{
    return HasArgument(ProbeArgument);
}

inline bool IsPowerSuspend(WPARAM event) noexcept
{
    return event == PBT_APMSUSPEND;
}

inline bool IsPowerResume(WPARAM event) noexcept
{
    return event == PBT_APMRESUMEAUTOMATIC ||
        event == PBT_APMRESUMECRITICAL ||
        event == PBT_APMRESUMESUSPEND;
}

inline bool IsProbeMessage(UINT message) noexcept
{
    return message >= ProbeSuspendMessage &&
        message <= ProbeSessionReconnectMessage;
}

inline void PostToCurrentProcessClass(
    const wchar_t* class_name,
    UINT message,
    WPARAM w_param = 0,
    LPARAM l_param = 0) noexcept
{
    if (class_name == nullptr || *class_name == L'\0')
    {
        return;
    }

    HWND after = nullptr;
    while ((after = FindWindowExW(nullptr, after, class_name, nullptr)) != nullptr)
    {
        DWORD process_id = 0;
        GetWindowThreadProcessId(after, &process_id);
        if (process_id == GetCurrentProcessId())
        {
            (void)PostMessageW(after, message, w_param, l_param);
        }
    }
}

inline void RevalidateShellSurfaces(HWND owner) noexcept
{
    // Resume and session reconnect can leave AppBar/work-area state stale even
    // when monitor topology did not change. Re-run the native handlers instead
    // of inventing a synthetic monitor configuration.
    PostToCurrentProcessClass(TaskbarClass, WM_DISPLAYCHANGE, 0, 0);

    if (owner != nullptr && IsWindow(owner))
    {
        (void)PostMessageW(owner, WM_SETTINGCHANGE, SPI_SETWORKAREA, 0);
        (void)InvalidateRect(owner, nullptr, FALSE);
    }
}
} // namespace CloudOS::NativeLifecycleV10
