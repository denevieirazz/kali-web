#pragma once

#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

#include <array>
#include <string>
#include <string_view>

#include "../../CloudOS.NativeCommon/native_supervisor_protocol_v11.h"
#include "native_health_signal_v9.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS::HealthBootstrapV9
{
constexpr UINT_PTR HealthTimerId = 0xC509;
constexpr UINT_PTR HealthSubclassId = 0xC509A11;
constexpr UINT HealthIntervalMilliseconds = 1000;
constexpr wchar_t WatchdogArgument[] = L"--watchdog";
constexpr wchar_t DesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
constexpr wchar_t TaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v4";
constexpr wchar_t StartClass[] = L"CloudOS.NativeShell.Start.v4";
constexpr wchar_t QuickSettingsClass[] = L"CloudOS.NativeShell.QuickSettings.v4";
constexpr wchar_t NotificationClass[] = L"CloudOS.NativeShell.NotificationCenter.v2";

inline bool HasCommandLineArgument(std::wstring_view expected) noexcept
{
    int count = 0;
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (arguments == nullptr) return false;

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

inline bool RequiredShellSurfacesExist() noexcept
{
    const DWORD current_pid = GetCurrentProcessId();
    const auto owns = [current_pid](const wchar_t* class_name) noexcept
    {
        HWND window = nullptr;
        while ((window = FindWindowExW(nullptr, window, class_name, nullptr)) != nullptr)
        {
            DWORD window_pid = 0;
            GetWindowThreadProcessId(window, &window_pid);
            if (window_pid == current_pid) return true;
        }
        return false;
    };

    return owns(DesktopClass) &&
        owns(TaskbarClass) &&
        owns(StartClass) &&
        owns(QuickSettingsClass) &&
        owns(NotificationClass);
}

class Bootstrap final
{
public:
    Bootstrap() noexcept
    {
        if (HasCommandLineArgument(WatchdogArgument)) return;
        active_ = this;
        hook_ = SetWinEventHook(
            EVENT_OBJECT_SHOW,
            EVENT_OBJECT_SHOW,
            nullptr,
            &Bootstrap::WinEventCallback,
            GetCurrentProcessId(),
            0,
            WINEVENT_OUTOFCONTEXT);
    }

    ~Bootstrap()
    {
        if (hook_ != nullptr)
        {
            UnhookWinEvent(hook_);
            hook_ = nullptr;
        }
        if (desktop_ != nullptr && IsWindow(desktop_))
        {
            signal_.MarkShuttingDown(desktop_);
            KillTimer(desktop_, HealthTimerId);
            RemoveWindowSubclass(desktop_, &Bootstrap::DesktopSubclass, HealthSubclassId);
        }
        desktop_ = nullptr;
        signal_.Shutdown();
        if (active_ == this) active_ = nullptr;
    }

    Bootstrap(const Bootstrap&) = delete;
    Bootstrap& operator=(const Bootstrap&) = delete;

    void AttachAfterInitialization() noexcept
    {
        if (HasCommandLineArgument(WatchdogArgument)) return;
        TryAttach(FindWindowW(DesktopClass, nullptr));
    }

    void Pulse() noexcept
    {
        if (desktop_ != nullptr && IsWindow(desktop_))
        {
            signal_.Pulse(desktop_);
        }
    }

private:
    static void CALLBACK WinEventCallback(
        HWINEVENTHOOK,
        DWORD event,
        HWND window,
        LONG object_id,
        LONG child_id,
        DWORD,
        DWORD)
    {
        if (event != EVENT_OBJECT_SHOW || object_id != OBJID_WINDOW || child_id != CHILDID_SELF)
            return;
        if (active_ != nullptr)
            active_->TryAttach(window);
    }

    void TryAttach(HWND candidate) noexcept
    {
        if (desktop_ != nullptr && IsWindow(desktop_)) return;

        HWND desktop = candidate;
        wchar_t class_name[128]{};
        if (desktop == nullptr ||
            GetClassNameW(desktop, class_name, static_cast<int>(std::size(class_name))) <= 0 ||
            std::wstring_view(class_name) != DesktopClass)
        {
            desktop = nullptr;
            while ((desktop = FindWindowExW(nullptr, desktop, DesktopClass, nullptr)) != nullptr)
            {
                DWORD window_pid = 0;
                GetWindowThreadProcessId(desktop, &window_pid);
                if (window_pid == GetCurrentProcessId()) break;
            }
        }
        if (desktop == nullptr || !IsWindow(desktop)) return;

        DWORD window_pid = 0;
        GetWindowThreadProcessId(desktop, &window_pid);
        if (window_pid != GetCurrentProcessId())
        {
            desktop = nullptr;
            while ((desktop = FindWindowExW(nullptr, desktop, DesktopClass, nullptr)) != nullptr)
            {
                DWORD pid = 0;
                GetWindowThreadProcessId(desktop, &pid);
                if (pid == GetCurrentProcessId())
                {
                    desktop = desktop;
                    break;
                }
            }
            if (desktop == nullptr || !IsWindow(desktop)) return;
        }

        if (!signal_.Initialize()) return;
        if (SetWindowSubclass(
                desktop,
                &Bootstrap::DesktopSubclass,
                HealthSubclassId,
                reinterpret_cast<DWORD_PTR>(this)) == FALSE)
        {
            signal_.Shutdown();
            return;
        }

        desktop_ = desktop;
        ready_ = false;
        consecutive_ready_checks_ = 0;
        ChangeWindowMessageFilterEx(desktop_, SupervisorProtocolV11::RequestGracefulExitMessage, MSGFLT_ALLOW, nullptr);
        signal_.Pulse(desktop_);
        if (SetTimer(desktop_, HealthTimerId, HealthIntervalMilliseconds, nullptr) == 0)
        {
            RemoveWindowSubclass(desktop_, &Bootstrap::DesktopSubclass, HealthSubclassId);
            desktop_ = nullptr;
            signal_.Shutdown();
        }
    }

    void Tick() noexcept
    {
        if (desktop_ == nullptr || !IsWindow(desktop_)) return;
        signal_.Pulse(desktop_);

        if (ready_) return;
        if (RequiredShellSurfacesExist())
        {
            ++consecutive_ready_checks_;
            if (consecutive_ready_checks_ >= 2)
            {
                ready_ = true;
                signal_.MarkReady(desktop_);
            }
        }
        else
        {
            consecutive_ready_checks_ = 0;
        }
    }

    static LRESULT CALLBACK DesktopSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data)
    {
        auto* self = reinterpret_cast<Bootstrap*>(reference_data);
        if (self != nullptr)
        {
            if (message == SupervisorProtocolV11::RequestGracefulExitMessage)
            {
                self->signal_.MarkShuttingDown(window);
                PostQuitMessage(0);
                return 0;
            }
            if (message == WM_TIMER && w_param == HealthTimerId)
            {
                self->Tick();
                return 0;
            }
            if ((message == WM_ENDSESSION && w_param != FALSE) || message == WM_NCDESTROY)
            {
                self->signal_.MarkShuttingDown(window);
            }
            if (message == WM_NCDESTROY)
            {
                KillTimer(window, HealthTimerId);
                RemoveWindowSubclass(window, &Bootstrap::DesktopSubclass, subclass_id);
                self->desktop_ = nullptr;
                self->ready_ = false;
                self->consecutive_ready_checks_ = 0;
                self->signal_.Shutdown();
            }
        }
        return DefSubclassProc(window, message, w_param, l_param);
    }

    inline static Bootstrap* active_{};
    NativeHealthSignalV9 signal_;
    HWINEVENTHOOK hook_{};
    HWND desktop_{};
    int consecutive_ready_checks_{};
    bool ready_{};
};

inline Bootstrap bootstrap;
} // namespace CloudOS::HealthBootstrapV9
