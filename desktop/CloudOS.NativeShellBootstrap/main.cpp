#include <windows.h>
#include <tlhelp32.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <chrono>
#include <thread>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

namespace
{
constexpr DWORD kDefaultReadyTimeoutMs = 15000;
constexpr DWORD kBrokerPollIntervalMs = 250;
constexpr int kMaxCrashBudget = 3;
constexpr ULONGLONG kRollingCrashWindowMs = 60000;

DWORD GetCurrentSessionId()
{
    DWORD sessionId = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &sessionId);
    return sessionId;
}

std::wstring GetExecutableDir()
{
    wchar_t path[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    return std::filesystem::path(path).parent_path().wstring();
}

std::wstring GetRecoveryDir()
{
    wchar_t localAppData[MAX_PATH] = {0};
    if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData) == S_OK)
    {
        std::filesystem::path p(localAppData);
        p /= L"CloudOS";
        p /= L"Recovery";
        std::error_code ec;
        std::filesystem::create_directories(p, ec);
        return p.wstring();
    }
    return L"";
}

void LogEvent(const std::wstring& msg)
{
    std::wstring recDir = GetRecoveryDir();
    if (recDir.empty()) return;
    std::filesystem::path logFile = std::filesystem::path(recDir) / L"shell-bootstrap.log";
    std::wofstream out(logFile, std::ios::app);
    if (out.is_open())
    {
        const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        out << L"[" << now << L"] " << msg << std::endl;
    }
}

bool IsProcessRunning(const wchar_t* exeName)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool found = false;
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            if (_wcsicmp(entry.szExeFile, exeName) == 0)
            {
                found = true;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

std::string WideToUtf8(std::wstring_view wide)
{
    if (wide.empty()) return {};
    const int req = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    if (req <= 0) return {};
    std::string out(static_cast<size_t>(req), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), req, nullptr, nullptr);
    return out;
}

bool LaunchExplorerFallback(const std::wstring& reason)
{
    LogEvent(L"FALLBACK: Triggering Explorer fallback. Reason: " + reason);

    std::wstring recDir = GetRecoveryDir();
    if (!recDir.empty())
    {
        std::filesystem::path fallbackLog = std::filesystem::path(recDir) / L"shell-fallback.log";
        std::wofstream out(fallbackLog, std::ios::app);
        if (out.is_open())
        {
            const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
            out << L"[" << now << L"] Explorer fallback activated: " << reason << std::endl;
        }

        std::filesystem::path stateFile = std::filesystem::path(recDir) / L"shell-bootstrap-state.json";
        std::ofstream stateOut(stateFile, std::ios::trunc);
        if (stateOut.is_open())
        {
            stateOut << "{\n"
                     << "  \"state\": \"FALLBACK\",\n"
                     << "  \"last_fallback_tick_ms\": " << GetTickCount64() << ",\n"
                     << "  \"reason\": \"" << WideToUtf8(reason) << "\",\n"
                     << "  \"explorer_running\": true\n"
                     << "}\n";
        }
    }

    if (!IsProcessRunning(L"explorer.exe"))
    {
        wchar_t winDir[MAX_PATH] = {0};
        GetWindowsDirectoryW(winDir, MAX_PATH);
        std::wstring explorerPath = std::wstring(winDir) + L"\\explorer.exe";

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi{};
        if (CreateProcessW(explorerPath.c_str(), nullptr, nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
        {
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
            LogEvent(L"FALLBACK: explorer.exe spawned successfully.");
            return true;
        }
        else
        {
            LogEvent(L"FALLBACK_ERROR: Failed to spawn explorer.exe. Error: " + std::to_wstring(GetLastError()));
            return false;
        }
    }
    else
    {
        LogEvent(L"FALLBACK: explorer.exe is already active.");
        return true;
    }
}

bool CheckCrashBudgetExceeded(int maxBudget = kMaxCrashBudget, ULONGLONG rollingWindowMs = kRollingCrashWindowMs)
{
    std::wstring recDir = GetRecoveryDir();
    if (recDir.empty()) return false;

    std::filesystem::path crashFile = std::filesystem::path(recDir) / L"shell-crash-history.txt";
    std::vector<ULONGLONG> timestamps;
    const ULONGLONG now = GetTickCount64();

    if (std::filesystem::exists(crashFile))
    {
        std::ifstream in(crashFile);
        ULONGLONG ts = 0;
        while (in >> ts)
        {
            if (now >= ts && (now - ts) <= rollingWindowMs)
            {
                timestamps.push_back(ts);
            }
        }
    }

    timestamps.push_back(now);

    std::ofstream out(crashFile, std::ios::trunc);
    for (ULONGLONG t : timestamps)
    {
        out << t << "\n";
    }

    return (static_cast<int>(timestamps.size()) > maxBudget);
}

void ClearCrashHistory()
{
    std::wstring recDir = GetRecoveryDir();
    if (recDir.empty()) return;
    std::filesystem::path crashFile = std::filesystem::path(recDir) / L"shell-crash-history.txt";
    std::error_code ec;
    std::filesystem::remove(crashFile, ec);
}

bool ProbeBrokerReady(DWORD sessionId, DWORD timeoutMs)
{
    const std::wstring pipeName = L"\\\\.\\pipe\\cloudos-system-broker-v21-" + std::to_wstring(sessionId);
    const ULONGLONG deadline = GetTickCount64() + timeoutMs;

    while (GetTickCount64() < deadline)
    {
        HANDLE hPipe = CreateFileW(
            pipeName.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr);

        if (hPipe != INVALID_HANDLE_VALUE)
        {
            const std::string probeReq = "{\"protocol_version\":21,\"type\":\"request\",\"message_id\":\"bootstrap-probe\",\"method\":\"broker.ping\",\"payload\":{}}\n";
            DWORD written = 0;
            if (WriteFile(hPipe, probeReq.data(), static_cast<DWORD>(probeReq.size()), &written, nullptr) && written > 0)
            {
                char buf[512] = {0};
                DWORD readBytes = 0;
                if (ReadFile(hPipe, buf, sizeof(buf) - 1, &readBytes, nullptr) && readBytes > 0)
                {
                    std::string res(buf, readBytes);
                    if (res.find("\"ok\":true") != std::string::npos || res.find("pong") != std::string::npos)
                    {
                        CloseHandle(hPipe);
                        return true;
                    }
                }
            }
            CloseHandle(hPipe);
        }

        Sleep(kBrokerPollIntervalMs);
    }
    return false;
}

bool ProbeFlutterWindowVisible(DWORD timeoutMs)
{
    const ULONGLONG deadline = GetTickCount64() + timeoutMs;
    while (GetTickCount64() < deadline)
    {
        HWND hwnd = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
        if (hwnd && IsWindowVisible(hwnd))
        {
            return true;
        }
        Sleep(100);
    }
    return false;
}

bool LaunchChildProcess(const std::wstring& cmd, PROCESS_INFORMATION& pi, bool hidden = false)
{
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    if (hidden)
    {
        si.dwFlags |= STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
    }

    std::vector<wchar_t> cmdBuffer(cmd.begin(), cmd.end());
    cmdBuffer.push_back(L'\0');

    DWORD flags = hidden ? CREATE_NO_WINDOW : 0;
    return CreateProcessW(
        nullptr,
        cmdBuffer.data(),
        nullptr,
        nullptr,
        FALSE,
        flags,
        nullptr,
        nullptr,
        &si,
        &pi) != FALSE;
}

void PersistBootstrapState(const std::string& state, DWORD bootstrapPid, DWORD supervisorPid, DWORD brokerPid, DWORD flutterPid)
{
    std::wstring recDir = GetRecoveryDir();
    if (recDir.empty()) return;

    std::filesystem::path stateFile = std::filesystem::path(recDir) / L"shell-bootstrap-state.json";
    std::ofstream out(stateFile, std::ios::trunc);
    if (out.is_open())
    {
        out << "{\n"
            << "  \"state\": \"" << state << "\",\n"
            << "  \"timestamp_tick_ms\": " << GetTickCount64() << ",\n"
            << "  \"bootstrap_pid\": " << bootstrapPid << ",\n"
            << "  \"supervisor_pid\": " << supervisorPid << ",\n"
            << "  \"broker_pid\": " << brokerPid << ",\n"
            << "  \"flutter_pid\": " << flutterPid << ",\n"
            << "  \"session_id\": " << GetCurrentSessionId() << ",\n"
            << "  \"health\": \"HEALTHY\"\n"
            << "}\n";
    }
}
} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR lpCmdLine, int)
{
    const std::wstring cmdLine(lpCmdLine ? lpCmdLine : L"");
    const bool isCanary = (cmdLine.find(L"--canary") != std::wstring::npos);
    const bool isFallbackReq = (cmdLine.find(L"--fallback-explorer") != std::wstring::npos);

    if (isFallbackReq)
    {
        LaunchExplorerFallback(L"Direct CLI request --fallback-explorer");
        return 0;
    }

    const DWORD sessionId = GetCurrentSessionId();
    const std::wstring mutexName = L"Local\\CloudOS_ShellBootstrap_Session_" + std::to_wstring(sessionId);
    HANDLE hMutex = CreateMutexW(nullptr, TRUE, mutexName.c_str());
    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        if (hMutex) CloseHandle(hMutex);
        LogEvent(L"Another instance of CloudOS.ShellBootstrap is already running in this session. Exiting.");
        return 0;
    }

    LogEvent(L"CloudOS.ShellBootstrap started. Session: " + std::to_wstring(sessionId) +
             (isCanary ? L" (CANARY MODE)" : L" (PRODUCTION SHELL MODE)"));

    // 1. Crash Budget Check
    if (!isCanary && CheckCrashBudgetExceeded())
    {
        LogEvent(L"Crash loop threshold exceeded within rolling window. Triggering automatic Explorer fallback.");
        LaunchExplorerFallback(L"Crash budget exceeded (3 crashes within 60 seconds)");
        if (hMutex) CloseHandle(hMutex);
        return 1;
    }

    const std::wstring installDir = GetExecutableDir();
    const std::wstring supervisorExe = installDir + L"\\CloudOS.Supervisor.exe";
    const std::wstring brokerExe = installDir + L"\\CloudOS.SystemBroker.exe";
    const std::wstring flutterExe = installDir + L"\\cloudos_flutter_shell.exe";

    if (!std::filesystem::exists(supervisorExe) ||
        !std::filesystem::exists(brokerExe) ||
        !std::filesystem::exists(flutterExe))
    {
        LogEvent(L"FATAL: Required CloudOS binaries missing from installation directory: " + installDir);
        LaunchExplorerFallback(L"Missing installation binaries");
        if (hMutex) CloseHandle(hMutex);
        return 2;
    }

    PROCESS_INFORMATION piSupervisor{};
    PROCESS_INFORMATION piBroker{};
    PROCESS_INFORMATION piFlutter{};

    // 2. Launch Supervisor
    LogEvent(L"Launching CloudOS.Supervisor.exe...");
    if (!LaunchChildProcess(L"\"" + supervisorExe + L"\" --supervised", piSupervisor, false))
    {
        LogEvent(L"Failed to launch CloudOS.Supervisor.exe. Error: " + std::to_wstring(GetLastError()));
        LaunchExplorerFallback(L"Failed to start Supervisor");
        if (hMutex) CloseHandle(hMutex);
        return 3;
    }

    // 3. Launch SystemBroker
    LogEvent(L"Launching CloudOS.SystemBroker.exe...");
    if (!LaunchChildProcess(L"\"" + brokerExe + L"\"", piBroker, true))
    {
        LogEvent(L"Failed to launch CloudOS.SystemBroker.exe. Error: " + std::to_wstring(GetLastError()));
        TerminateProcess(piSupervisor.hProcess, 0);
        CloseHandle(piSupervisor.hThread);
        CloseHandle(piSupervisor.hProcess);
        LaunchExplorerFallback(L"Failed to start SystemBroker");
        if (hMutex) CloseHandle(hMutex);
        return 4;
    }

    // 4. Bounded Health Gate: Broker Readiness
    LogEvent(L"Waiting for SystemBroker readiness (deadline: 10s)...");
    if (!ProbeBrokerReady(sessionId, 10000))
    {
        LogEvent(L"SystemBroker health probe timed out after 10 seconds.");
        TerminateProcess(piBroker.hProcess, 0);
        TerminateProcess(piSupervisor.hProcess, 0);
        CloseHandle(piBroker.hThread);
        CloseHandle(piBroker.hProcess);
        CloseHandle(piSupervisor.hThread);
        CloseHandle(piSupervisor.hProcess);
        LaunchExplorerFallback(L"SystemBroker readiness deadline exceeded");
        if (hMutex) CloseHandle(hMutex);
        return 5;
    }
    LogEvent(L"SystemBroker is HEALTHY.");

    // 5. Launch Flutter Shell
    LogEvent(L"Launching cloudos_flutter_shell.exe...");
    if (!LaunchChildProcess(L"\"" + flutterExe + L"\"", piFlutter, false))
    {
        LogEvent(L"Failed to launch cloudos_flutter_shell.exe. Error: " + std::to_wstring(GetLastError()));
        TerminateProcess(piBroker.hProcess, 0);
        TerminateProcess(piSupervisor.hProcess, 0);
        CloseHandle(piFlutter.hThread);
        CloseHandle(piFlutter.hProcess);
        CloseHandle(piBroker.hThread);
        CloseHandle(piBroker.hProcess);
        CloseHandle(piSupervisor.hThread);
        CloseHandle(piSupervisor.hProcess);
        LaunchExplorerFallback(L"Failed to start FlutterShell");
        if (hMutex) CloseHandle(hMutex);
        return 6;
    }

    // 6. Bounded Health Gate: Flutter Window Visibility
    LogEvent(L"Waiting for Flutter window visibility (deadline: 5s)...");
    if (!ProbeFlutterWindowVisible(5000))
    {
        LogEvent(L"Flutter window visibility deadline exceeded.");
        TerminateProcess(piFlutter.hProcess, 0);
        TerminateProcess(piBroker.hProcess, 0);
        TerminateProcess(piSupervisor.hProcess, 0);
        CloseHandle(piFlutter.hThread);
        CloseHandle(piFlutter.hProcess);
        CloseHandle(piBroker.hThread);
        CloseHandle(piBroker.hProcess);
        CloseHandle(piSupervisor.hThread);
        CloseHandle(piSupervisor.hProcess);
        LaunchExplorerFallback(L"Flutter window visibility deadline exceeded");
        if (hMutex) CloseHandle(hMutex);
        return 7;
    }

    LogEvent(L"All CloudOS Shell components are HEALTHY and ACTIVE!");
    ClearCrashHistory();

    PersistBootstrapState(
        isCanary ? "CLOUDOS_CANARY" : "CLOUDOS_ACTIVE",
        GetCurrentProcessId(),
        piSupervisor.dwProcessId,
        piBroker.dwProcessId,
        piFlutter.dwProcessId);

    // 7. Watchdog Loop: Observe Flutter Shell and Supervisor
    HANDLE waitHandles[2] = {piFlutter.hProcess, piSupervisor.hProcess};
    const DWORD waitRes = WaitForMultipleObjects(2, waitHandles, FALSE, INFINITE);

    LogEvent(L"A primary CloudOS shell process exited. Wait result: " + std::to_wstring(waitRes));

    // Cleanup handles
    CloseHandle(piFlutter.hThread);
    CloseHandle(piFlutter.hProcess);
    CloseHandle(piBroker.hThread);
    CloseHandle(piBroker.hProcess);
    CloseHandle(piSupervisor.hThread);
    CloseHandle(piSupervisor.hProcess);

    // If Explorer is not running, restore Explorer to prevent black screen
    if (!IsProcessRunning(L"explorer.exe"))
    {
        LogEvent(L"CloudOS stack ended and Explorer is not running. Spawning explorer.exe...");
        LaunchExplorerFallback(L"CloudOS shell session closed");
    }

    if (hMutex) CloseHandle(hMutex);
    return 0;
}
