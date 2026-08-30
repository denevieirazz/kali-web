#pragma once

#include <windows.h>
#include <wtsapi32.h>

#include <string_view>

#pragma comment(lib, "Wtsapi32.lib")

namespace CloudOS
{
class NativeSessionEventsV7 final
{
public:
    static bool Register(HWND window) noexcept
    {
        return window != nullptr &&
            WTSRegisterSessionNotification(window, NOTIFY_FOR_THIS_SESSION) != FALSE;
    }

    static void Unregister(HWND window) noexcept
    {
        if (window != nullptr)
            (void)WTSUnRegisterSessionNotification(window);
    }

    static bool IsSessionMessage(UINT message) noexcept
    {
        return message == WM_WTSSESSION_CHANGE;
    }

    static bool ShouldCheckpoint(WPARAM event) noexcept
    {
        switch (event)
        {
        case WTS_SESSION_LOCK:
        case WTS_REMOTE_DISCONNECT:
        case WTS_CONSOLE_DISCONNECT:
        case WTS_SESSION_LOGOFF:
            return true;
        default:
            return false;
        }
    }

    static bool ShouldRefresh(WPARAM event) noexcept
    {
        switch (event)
        {
        case WTS_SESSION_UNLOCK:
        case WTS_REMOTE_CONNECT:
        case WTS_CONSOLE_CONNECT:
        case WTS_SESSION_LOGON:
            return true;
        default:
            return false;
        }
    }

    static std::wstring_view Label(WPARAM event) noexcept
    {
        switch (event)
        {
        case WTS_CONSOLE_CONNECT: return L"console-connect";
        case WTS_CONSOLE_DISCONNECT: return L"console-disconnect";
        case WTS_REMOTE_CONNECT: return L"remote-connect";
        case WTS_REMOTE_DISCONNECT: return L"remote-disconnect";
        case WTS_SESSION_LOGON: return L"logon";
        case WTS_SESSION_LOGOFF: return L"logoff";
        case WTS_SESSION_LOCK: return L"lock";
        case WTS_SESSION_UNLOCK: return L"unlock";
        default: return L"session-change";
        }
    }
};
} // namespace CloudOS
