#include "native_watchdog.h"

#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <string>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kWatchdogMutex[] = L"Local\\CloudOS.NativeShell.Watchdog.v1";
constexpr DWORD kRestartExitCode = 23;
constexpr int kMaximumRapidCrashes = 5;
constexpr ULONGLONG kCrashWindowMilliseconds = 30000ull;

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

void SurfaceExistingShell()
{
    for (const wchar_t* class_name : {
             L"CloudOS.NativeShell.Desktop.v2",
             L"CloudOS.NativeShell.CloudOSDesktop.v19"})
    {
        HWND window = FindWindowW(class_name, nullptr);
        if (window != nullptr)
        {
            SetForegroundWindow(window);
            return;
        }
    }
}
}

bool NativeWatchdog::HasSessionArgument()
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
        if (_wcsicmp(arguments[index], L"--session") == 0)
        {
            found = true;
            break;
        }
    }
    LocalFree(arguments);
    return found;
}

int NativeWatchdog::Run()
{
    HANDLE mutex = CreateMutexW(nullptr, TRUE, kWatchdogMutex);
    if (mutex == nullptr)
    {
        return 2;
    }
    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        SurfaceExistingShell();
        CloseHandle(mutex);
        return 0;
    }

    const std::wstring executable = ExecutablePath();
    if (executable.empty())
    {
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return 3;
    }

    int rapid_crashes = 0;
    ULONGLONG first_crash_tick = 0;
    int result = 0;

    for (;;)
    {
        std::wstring command_line = L"\"" + executable + L"\" --session";
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};

        const BOOL created = CreateProcessW(
            executable.c_str(),
            command_line.data(),
            nullptr,
            nullptr,
            FALSE,
            0,
            nullptr,
            nullptr,
            &startup,
            &process);
        if (!created)
        {
            result = 4;
            break;
        }

        CloseHandle(process.hThread);
        const DWORD wait = WaitForSingleObject(process.hProcess, INFINITE);
        DWORD exit_code = 1;
        if (wait == WAIT_OBJECT_0)
        {
            (void)GetExitCodeProcess(process.hProcess, &exit_code);
        }
        CloseHandle(process.hProcess);

        if (wait != WAIT_OBJECT_0)
        {
            result = 5;
            break;
        }
        if (exit_code == 0)
        {
            result = 0;
            break;
        }

        if (exit_code == kRestartExitCode)
        {
            rapid_crashes = 0;
            first_crash_tick = 0;
            Sleep(150);
            continue;
        }

        const ULONGLONG now = GetTickCount64();
        if (first_crash_tick == 0 || now - first_crash_tick > kCrashWindowMilliseconds)
        {
            first_crash_tick = now;
            rapid_crashes = 1;
        }
        else
        {
            ++rapid_crashes;
        }

        if (rapid_crashes > kMaximumRapidCrashes)
        {
            MessageBoxW(
                nullptr,
                L"O CloudOS falhou repetidamente em menos de 30 segundos.\n\n"
                L"O watchdog interrompeu o reinicio automatico para evitar um loop de crash. "
                L"Execute o CloudOS novamente depois de verificar os logs/build.",
                L"CloudOS Watchdog",
                MB_OK | MB_ICONERROR);
            result = static_cast<int>(exit_code);
            break;
        }

        const DWORD backoff = static_cast<DWORD>(
            std::min(3000, 250 * rapid_crashes));
        Sleep(backoff);
    }

    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return result;
}
} // namespace CloudOS
