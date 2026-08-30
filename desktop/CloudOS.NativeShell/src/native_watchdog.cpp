#include "native_watchdog.h"

#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <string>
#include <string_view>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kSessionMutex[] = L"Local\\CloudOS.NativeShell.Session.v1";
constexpr wchar_t kWatchdogArgument[] = L"--watchdog";
constexpr wchar_t kStabilityProbeArgument[] = L"--stability-probe";
constexpr int kMaximumRapidCrashes = 5;
constexpr ULONGLONG kCrashWindowMilliseconds = 30000ull;
constexpr DWORD kNtStatusFailureMask = 0x80000000u;
constexpr DWORD kStatusControlCExit = 0xC000013Au;

std::wstring ExecutablePath()
{
    std::array<wchar_t, 32768> buffer{};
    const DWORD length = GetModuleFileNameW(
        nullptr,
        buffer.data(),
        static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size())
    {
        return {};
    }
    return std::wstring(buffer.data(), static_cast<std::size_t>(length));
}

std::vector<std::wstring> Arguments()
{
    int count = 0;
    LPWSTR* raw = CommandLineToArgvW(GetCommandLineW(), &count);
    if (raw == nullptr)
    {
        return {};
    }

    std::vector<std::wstring> result;
    result.reserve(static_cast<std::size_t>(std::max(0, count)));
    for (int index = 0; index < count; ++index)
    {
        result.emplace_back(raw[index]);
    }
    LocalFree(raw);
    return result;
}

bool HasArgument(std::wstring_view expected)
{
    const auto arguments = Arguments();
    for (std::size_t index = 1; index < arguments.size(); ++index)
    {
        if (_wcsicmp(arguments[index].c_str(), expected.data()) == 0)
        {
            return true;
        }
    }
    return false;
}

DWORD WatchedProcessId()
{
    const auto arguments = Arguments();
    for (std::size_t index = 1; index + 1u < arguments.size(); ++index)
    {
        if (_wcsicmp(arguments[index].c_str(), kWatchdogArgument) != 0)
        {
            continue;
        }

        wchar_t* end = nullptr;
        errno = 0;
        const unsigned long value = std::wcstoul(arguments[index + 1u].c_str(), &end, 10);
        if (errno == 0 && end != arguments[index + 1u].c_str() && *end == L'\0' && value != 0)
        {
            return static_cast<DWORD>(value);
        }
    }
    return 0;
}

void SurfaceExistingShell()
{
    for (const wchar_t* class_name : {
             L"CloudOS.NativeShell.Desktop.v2",
             L"CloudOS.NativeShell.CloudOSDesktop.v19"})
    {
        HWND window = FindWindowW(class_name, nullptr);
        if (window != nullptr)
        {
            ShowWindow(window, SW_SHOWNA);
            SetForegroundWindow(window);
            return;
        }
    }
}

bool LaunchNormalShell()
{
    const std::wstring executable = ExecutablePath();
    if (executable.empty())
    {
        return false;
    }

    std::wstring command_line = L"\"" + executable + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            executable.c_str(),
            command_line.data(),
            nullptr,
            nullptr,
            FALSE,
            0,
            nullptr,
            nullptr,
            &startup,
            &process))
    {
        return false;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

bool ShouldRestartAfterExit(DWORD exit_code) noexcept
{
    // The watchdog exists to recover a crashed shell, not to fight the user.
    // Task Manager/taskkill commonly terminate a process with a small ordinary
    // exit code (for example 1). Treat those exits as intentional and stay
    // closed. Only NT failure/status exits with the high bit set are eligible
    // for automatic recovery. Ctrl+C/console close is also intentional.
    if (exit_code == 0 || exit_code == kStatusControlCExit)
    {
        return false;
    }
    return (exit_code & kNtStatusFailureMask) != 0;
}
}

bool NativeWatchdog::IsWatchdogInvocation()
{
    return WatchedProcessId() != 0;
}

int NativeWatchdog::RunWatchdogInvocation()
{
    const DWORD process_id = WatchedProcessId();
    if (process_id == 0)
    {
        return 2;
    }

    HANDLE process = OpenProcess(
        SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        process_id);
    if (process == nullptr)
    {
        // The parent may already have completed while the helper was starting.
        return 0;
    }

    const DWORD wait = WaitForSingleObject(process, INFINITE);
    DWORD exit_code = 0;
    if (wait == WAIT_OBJECT_0)
    {
        (void)GetExitCodeProcess(process, &exit_code);
    }
    CloseHandle(process);

    if (wait != WAIT_OBJECT_0)
    {
        return 3;
    }
    if (!ShouldRestartAfterExit(exit_code))
    {
        return 0;
    }

    // Give Windows time to release HWNDs, AppBars and the session mutex before
    // the replacement shell attempts to acquire them.
    Sleep(450);

    const ULONGLONG now = GetTickCount64();
    wchar_t environment_name[] = L"CLOUDOS_WATCHDOG_CRASH_TICK";
    std::array<wchar_t, 64> previous{};
    const DWORD previous_length = GetEnvironmentVariableW(
        environment_name,
        previous.data(),
        static_cast<DWORD>(previous.size()));
    ULONGLONG first_tick = now;
    int crash_count = 1;
    if (previous_length > 0 && previous_length < previous.size())
    {
        unsigned long long parsed_tick = 0;
        int parsed_count = 0;
        if (swscanf_s(previous.data(), L"%llu:%d", &parsed_tick, &parsed_count) == 2 &&
            parsed_tick != 0 && now - parsed_tick <= kCrashWindowMilliseconds)
        {
            first_tick = parsed_tick;
            crash_count = parsed_count + 1;
        }
    }

    if (crash_count > kMaximumRapidCrashes)
    {
        MessageBoxW(
            nullptr,
            L"O CloudOS falhou repetidamente. O watchdog interrompeu o reinicio automatico "
            L"para impedir um loop de crash.",
            L"CloudOS Watchdog",
            MB_OK | MB_ICONERROR);
        return static_cast<int>(exit_code);
    }

    wchar_t state[64]{};
    swprintf_s(state, L"%llu:%d", first_tick, crash_count);
    SetEnvironmentVariableW(environment_name, state);

    const DWORD backoff = static_cast<DWORD>(std::min(3000, 250 * crash_count));
    Sleep(backoff);
    return LaunchNormalShell() ? 0 : 4;
}

HANDLE NativeWatchdog::AcquireSessionMutex(DWORD wait_milliseconds)
{
    HANDLE mutex = CreateMutexW(nullptr, FALSE, kSessionMutex);
    if (mutex == nullptr)
    {
        return nullptr;
    }

    const DWORD wait = WaitForSingleObject(mutex, wait_milliseconds);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED)
    {
        return mutex;
    }

    SurfaceExistingShell();
    CloseHandle(mutex);
    return nullptr;
}

void NativeWatchdog::ReleaseSessionMutex(HANDLE mutex) noexcept
{
    if (mutex != nullptr)
    {
        (void)ReleaseMutex(mutex);
        CloseHandle(mutex);
    }
}

bool NativeWatchdog::StartForCurrentProcess()
{
    // wWinMain reaches this method only after CloudOSApplication::Initialize()
    // succeeds. Use that deterministic lifecycle point to arm the UI heartbeat.
    HealthBootstrapV9::bootstrap.AttachAfterInitialization();

    // Stability/soak runs must observe the original process directly. A crash
    // must fail the probe instead of being hidden by the normal recovery helper.
    if (HasArgument(kStabilityProbeArgument))
    {
        return true;
    }

    const std::wstring executable = ExecutablePath();
    if (executable.empty())
    {
        return false;
    }

    std::wstring command_line = L"\"" + executable + L"\" ";
    command_line += kWatchdogArgument;
    command_line += L" ";
    command_line += std::to_wstring(GetCurrentProcessId());

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            executable.c_str(),
            command_line.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            &startup,
            &process))
    {
        return false;
    }

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}
} // namespace CloudOS
