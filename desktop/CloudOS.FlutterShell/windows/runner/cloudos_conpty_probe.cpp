#include "cloudos_conpty_manager.h"

#include <Windows.h>
#include <Psapi.h>
#include <TlHelp32.h>

#include <chrono>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace
{

struct ProcessSnapshot
{
    DWORD handles{0};
    DWORD threads{0};
    SIZE_T working_set{0};
    SIZE_T private_bytes{0};
};

ProcessSnapshot CaptureProcessSnapshot()
{
    ProcessSnapshot result;
    GetProcessHandleCount(GetCurrentProcess(), &result.handles);

    PROCESS_MEMORY_COUNTERS_EX memory{};
    memory.cb = sizeof(memory);
    if (GetProcessMemoryInfo(
            GetCurrentProcess(),
            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory),
            sizeof(memory)))
    {
        result.working_set = memory.WorkingSetSize;
        result.private_bytes = memory.PrivateUsage;
    }

    CloudOS::UniqueWinHandle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0));
    if (snapshot.valid())
    {
        THREADENTRY32 entry{};
        entry.dwSize = sizeof(entry);
        if (Thread32First(snapshot.get(), &entry))
        {
            do
            {
                if (entry.th32OwnerProcessID == GetCurrentProcessId())
                {
                    ++result.threads;
                }
            } while (Thread32Next(snapshot.get(), &entry));
        }
    }
    return result;
}

std::string WideToUtf8(const std::wstring& value)
{
    if (value.empty()) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string result(static_cast<size_t>(required), '\0');
    return WideCharToMultiByte(
               CP_UTF8,
               WC_ERR_INVALID_CHARS,
               value.data(),
               static_cast<int>(value.size()),
               result.data(),
               required,
               nullptr,
               nullptr) == required
        ? result
        : std::string{};
}

std::string EscapeJson(const std::string& value)
{
    std::string result;
    result.reserve(value.size());
    for (const unsigned char ch : value)
    {
        switch (ch)
        {
        case '\\': result += "\\\\"; break;
        case '"': result += "\\\""; break;
        case '\r': result += "\\r"; break;
        case '\n': result += "\\n"; break;
        case '\t': result += "\\t"; break;
        default:
            if (ch >= 0x20) result.push_back(static_cast<char>(ch));
            break;
        }
    }
    return result;
}

struct SessionEvents
{
    std::string output;
    bool exited{false};
    int exit_code{0};
};

class Probe final
{
public:
    Probe()
    {
        CloudOS::CloudOSConPTYManager::Instance().SetEventSinkForTesting(
            [this](const std::string& session_id,
                   const std::string& data,
                   int exit_code,
                   bool is_exit) {
                std::lock_guard<std::mutex> lock(mutex_);
                auto& event = events_[session_id];
                if (is_exit)
                {
                    event.exited = true;
                    event.exit_code = exit_code;
                }
                else if (event.output.size() < 1024 * 1024)
                {
                    event.output += data;
                }
                condition_.notify_all();

                // PSReadLine asks a real terminal for device attributes and
                // cursor position before accepting interactive input. xterm
                // answers these in the app; the native probe supplies only
                // the minimal equivalent handshake.
                if (!is_exit && data.find("\x1b[6n") != std::string::npos)
                {
                    CloudOS::CloudOSConPTYManager::Instance().WriteSession(
                        session_id, "\x1b[1;1R");
                }
                if (!is_exit && data.find("\x1b[c") != std::string::npos)
                {
                    CloudOS::CloudOSConPTYManager::Instance().WriteSession(
                        session_id, "\x1b[?1;2c");
                }
            });
    }

    ~Probe()
    {
        CloudOS::CloudOSConPTYManager::Instance().SetEventSinkForTesting({});
        CloudOS::CloudOSConPTYManager::Instance().ShutdownAll();
    }

    bool RunCommand(
        const std::string& shell,
        const std::string& distro,
        const std::string& command,
        const std::string& marker,
        std::string& output,
        std::string& error,
        const std::string& working_directory = {})
    {
        auto& manager = CloudOS::CloudOSConPTYManager::Instance();
        const std::string session_id =
            manager.CreateSession(shell, distro, 100, 30, error, working_directory);
        if (session_id.empty()) return false;

        // Match a real terminal: wait for the shell to initialize its line
        // editor before sending text and the Enter key as separate writes.
        {
            std::unique_lock<std::mutex> lock(mutex_);
            condition_.wait_for(lock, std::chrono::seconds(5), [&]() {
                const auto it = events_.find(session_id);
                if (it == events_.end()) return false;
                if (shell == "powershell")
                {
                    return it->second.output.find("PS ") != std::string::npos;
                }
                if (shell == "cmd")
                {
                    return it->second.output.find('>') != std::string::npos;
                }
                return !it->second.output.empty();
            });
        }

        std::string input = command;
        const bool has_enter = !input.empty() && input.back() == '\r';
        if (has_enter) input.pop_back();
        if (!manager.WriteSession(session_id, input))
        {
            error = "WriteSession failed";
            manager.CloseSession(session_id);
            return false;
        }
        if (has_enter)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
            if (!manager.WriteSession(session_id, "\r"))
            {
                error = "WriteSession(Enter) failed";
                manager.CloseSession(session_id);
                return false;
            }
        }

        bool marker_seen = false;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            marker_seen = condition_.wait_for(
                lock,
                std::chrono::seconds(20),
                [&]() {
                    const auto it = events_.find(session_id);
                    return it != events_.end() &&
                           (it->second.output.find(marker) != std::string::npos ||
                            it->second.exited);
                });
            output = events_[session_id].output;
        }
        manager.CloseSession(session_id);
        if (!marker_seen || output.find(marker) == std::string::npos)
        {
            error = "Timed out before marker was observed";
            return false;
        }
        return true;
    }

    bool RunLifecycleIterations(int count, std::string& error)
    {
        auto& manager = CloudOS::CloudOSConPTYManager::Instance();
        for (int index = 0; index < count; ++index)
        {
            std::string create_error;
            const std::string session_id = manager.CreateSession(
                "powershell", "", 80 + index % 20, 24 + index % 8, create_error);
            if (session_id.empty())
            {
                error = "Iteration " + std::to_string(index) + ": " + create_error;
                return false;
            }
            {
                std::unique_lock<std::mutex> lock(mutex_);
                condition_.wait_for(lock, std::chrono::seconds(3), [&]() {
                    const auto it = events_.find(session_id);
                    return it != events_.end() &&
                           it->second.output.find("PS ") != std::string::npos;
                });
            }
            manager.ResizeSession(session_id, 90 + index % 10, 28 + index % 5);
            manager.WriteSession(session_id, "exit");
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            manager.WriteSession(session_id, "\r");
            {
                std::unique_lock<std::mutex> lock(mutex_);
                condition_.wait_for(lock, std::chrono::seconds(2), [&]() {
                    const auto it = events_.find(session_id);
                    return it != events_.end() && it->second.exited;
                });
            }
            if (!manager.CloseSession(session_id))
            {
                error = "CloseSession failed at iteration " + std::to_string(index);
                return false;
            }
        }
        if (!manager.ListSessions().empty())
        {
            error = "Session map is not empty after lifecycle iterations";
            return false;
        }
        return true;
    }

private:
    std::mutex mutex_;
    std::condition_variable condition_;
    std::unordered_map<std::string, SessionEvents> events_;
};

void PrintSnapshot(const char* name, const ProcessSnapshot& value)
{
    std::cout << "\"" << name << "\":{";
    std::cout << "\"handles\":" << value.handles << ",";
    std::cout << "\"threads\":" << value.threads << ",";
    std::cout << "\"workingSetBytes\":" << value.working_set << ",";
    std::cout << "\"privateBytes\":" << value.private_bytes << "}";
}

} // namespace

int main()
{
    // The Codex host prepends its own PowerShell module path. The production
    // desktop process does not need that host-specific path, so the probe
    // removes it to test the stock shell startup deterministically.
    SetEnvironmentVariableW(L"PSModulePath", L"");

    Probe probe;
    const ProcessSnapshot before = CaptureProcessSnapshot();

    std::string powershell_output;
    std::string powershell_error;
    const bool powershell_ok = probe.RunCommand(
        "powershell",
        "",
        "$m='__CLOUDOS_'+'PS_DONE__'; Get-Location; Write-Output $m; exit\r",
        "__CLOUDOS_PS_DONE__",
        powershell_output,
        powershell_error);

    std::string cmd_output;
    std::string cmd_error;
    const bool cmd_ok = probe.RunCommand(
        "cmd",
        "",
        "ver & echo __CLOUDOS_^CMD_DONE__ & exit\r",
        "__CLOUDOS_CMD_DONE__",
        cmd_output,
        cmd_error);

    std::string cwd_output;
    std::string cwd_error;
    bool cwd_ok = false;
    WCHAR temp_path[MAX_PATH]{};
    const DWORD temp_length = GetTempPathW(MAX_PATH, temp_path);
    std::wstring cwd_test_directory;
    if (temp_length > 0 && temp_length < MAX_PATH)
    {
        cwd_test_directory = std::wstring(temp_path) +
            L"cloudos_conpty_cwd_" + std::to_wstring(GetCurrentProcessId());
        if (CreateDirectoryW(cwd_test_directory.c_str(), nullptr) != FALSE ||
            GetLastError() == ERROR_ALREADY_EXISTS)
        {
            const std::wstring cwd_marker_path =
                cwd_test_directory + L"\\__cloudos_cwd_probe.marker";
            DeleteFileW(cwd_marker_path.c_str());

            const std::string cwd_utf8 = WideToUtf8(cwd_test_directory);
            cwd_ok = !cwd_utf8.empty() && probe.RunCommand(
                "powershell",
                "",
                "$m='__CLOUDOS_'+'CWD_DONE__'; [IO.File]::WriteAllText('.\\__cloudos_cwd_probe.marker','ok'); Write-Output (Get-Location).Path; Write-Output $m; exit\r",
                "__CLOUDOS_CWD_DONE__",
                cwd_output,
                cwd_error,
                cwd_utf8);

            if (cwd_ok && GetFileAttributesW(cwd_marker_path.c_str()) == INVALID_FILE_ATTRIBUTES)
            {
                cwd_ok = false;
                cwd_error = "PowerShell did not create the marker in the requested working directory";
            }

            DeleteFileW(cwd_marker_path.c_str());
            RemoveDirectoryW(cwd_test_directory.c_str());
        }
        else
        {
            cwd_error = "Failed to create working-directory probe folder";
        }
    }
    else
    {
        cwd_error = "GetTempPathW failed for working-directory probe";
    }

    std::string wsl_output;
    std::string wsl_error;
    const bool wsl_ok = probe.RunCommand(
        "wsl",
        "",
        "uname -a; printf '__CLOUDOS_%s_DONE__\\n' WSL; exit\r",
        "__CLOUDOS_WSL_DONE__",
        wsl_output,
        wsl_error);

    std::string lifecycle_error;
    const bool lifecycle_ok = probe.RunLifecycleIterations(20, lifecycle_error);
    const ProcessSnapshot after = CaptureProcessSnapshot();

    std::cout << "{";
    std::cout << "\"powershell\":{";
    std::cout << "\"ok\":" << (powershell_ok ? "true" : "false") << ",";
    std::cout << "\"error\":\"" << EscapeJson(powershell_error) << "\",";
    std::cout << "\"output\":\"" << EscapeJson(powershell_output) << "\"},";
    std::cout << "\"cmd\":{";
    std::cout << "\"ok\":" << (cmd_ok ? "true" : "false") << ",";
    std::cout << "\"error\":\"" << EscapeJson(cmd_error) << "\",";
    std::cout << "\"output\":\"" << EscapeJson(cmd_output) << "\"},";
    std::cout << "\"workingDirectory\":{";
    std::cout << "\"ok\":" << (cwd_ok ? "true" : "false") << ",";
    std::cout << "\"error\":\"" << EscapeJson(cwd_error) << "\",";
    std::cout << "\"output\":\"" << EscapeJson(cwd_output) << "\"},";
    std::cout << "\"wsl\":{";
    std::cout << "\"ok\":" << (wsl_ok ? "true" : "false") << ",";
    std::cout << "\"error\":\"" << EscapeJson(wsl_error) << "\",";
    std::cout << "\"output\":\"" << EscapeJson(wsl_output) << "\"},";
    std::cout << "\"lifecycle20\":{";
    std::cout << "\"ok\":" << (lifecycle_ok ? "true" : "false") << ",";
    std::cout << "\"error\":\"" << EscapeJson(lifecycle_error) << "\"},";
    PrintSnapshot("before", before);
    std::cout << ",";
    PrintSnapshot("after", after);
    std::cout << "}" << std::endl;

    return powershell_ok && cmd_ok && cwd_ok && lifecycle_ok ? 0 : 1;
}
