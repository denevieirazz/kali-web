#pragma once

#include <windows.h>

namespace CloudOS::SupervisorBootstrapV22
{
constexpr DWORD kSupervisorShutdownLevel = 0x180u;

// The Supervisor owns CloudOS crash-loop recovery. Windows Application Restart is
// therefore registered only for OS servicing/reboot scenarios, never as a second
// crash/hang watchdog. RESTART_NO_CRASH | RESTART_NO_HANG keeps those authorities
// separated while still allowing Restart Manager / reboot flows to restore the
// supervisor instance after Windows maintenance.
//
// Windows closes higher shutdown levels first. Keeping Supervisor in the
// application-reserved "late" band lets CloudOS.exe persist/close before the
// recovery authority disappears, without using any system-reserved shutdown level.
class ProcessBootstrap final
{
public:
    ProcessBootstrap() noexcept
    {
        previous_error_mode_ = SetErrorMode(
            SEM_FAILCRITICALERRORS |
            SEM_NOGPFAULTERRORBOX |
            SEM_NOOPENFILEERRORBOX);

        shutdown_order_succeeded_ = SetProcessShutdownParameters(
            kSupervisorShutdownLevel,
            SHUTDOWN_NORETRY) != FALSE;

        const HRESULT result = RegisterApplicationRestart(
            L"--windows-restart",
            RESTART_NO_CRASH | RESTART_NO_HANG);
        restart_registration_succeeded_ = SUCCEEDED(result);

        if (!shutdown_order_succeeded_)
        {
            OutputDebugStringW(
                L"[CloudOS Supervisor V22] Late application shutdown ordering unavailable; default Windows ordering remains active.\n");
        }
        OutputDebugStringW(
            restart_registration_succeeded_
                ? L"[CloudOS Supervisor V22] Windows restart registration active.\n"
                : L"[CloudOS Supervisor V22] Windows restart registration unavailable; supervisor remains functional.\n");
    }

    ~ProcessBootstrap() noexcept
    {
        // Best-effort cleanup for intentional exits. During Windows servicing the
        // process can be terminated without ordinary C++ teardown, which is exactly
        // when the active registration is useful.
        if (restart_registration_succeeded_)
        {
            (void)UnregisterApplicationRestart();
        }
        (void)SetErrorMode(previous_error_mode_);
    }

    ProcessBootstrap(const ProcessBootstrap&) = delete;
    ProcessBootstrap& operator=(const ProcessBootstrap&) = delete;

    bool restart_registration_succeeded() const noexcept
    {
        return restart_registration_succeeded_;
    }

    bool shutdown_order_succeeded() const noexcept
    {
        return shutdown_order_succeeded_;
    }

private:
    UINT previous_error_mode_{};
    bool restart_registration_succeeded_{};
    bool shutdown_order_succeeded_{};
};

// main_v22.cpp is the single Supervisor translation unit. Forced-including this
// header gives the process an early bootstrap before wWinMain without adding a
// second executable entrypoint or changing the V11/V22 recovery ABI.
inline ProcessBootstrap g_process_bootstrap;
} // namespace CloudOS::SupervisorBootstrapV22
