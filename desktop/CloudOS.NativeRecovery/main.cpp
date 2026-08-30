#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "../CloudOS.NativeCommon/native_supervisor_protocol_v11.h"

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

namespace
{
using CloudOS::SupervisorProtocolV11::NativeHealthSnapshotV9;

constexpr DWORD kStatusControlCExit = 0xC000013Au;
constexpr DWORD kSupervisorHangExit = 0xC0000409u;
constexpr DWORD kDefaultReadyTimeoutMs = 30000u;
constexpr DWORD kDefaultHeartbeatTimeoutMs = 5000u;
constexpr DWORD kGracefulExitTimeoutMs = 5000u;
constexpr DWORD kStableRunResetMs = 120000u;
constexpr unsigned kDefaultMaximumFailures = 3u;
constexpr int kProbeFallbackSuppressedExitCode = 42;

struct Handle final
{
    HANDLE value{};
    explicit Handle(HANDLE handle = nullptr) noexcept : value(handle) {}
    ~Handle()
    {
        if (value != nullptr && value != INVALID_HANDLE_VALUE) CloseHandle(value);
    }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
};

struct SupervisorOptions final
{
    DWORD ready_timeout_ms{kDefaultReadyTimeoutMs};
    DWORD heartbeat_timeout_ms{kDefaultHeartbeatTimeoutMs};
    unsigned maximum_failures{kDefaultMaximumFailures};
    bool probe_ready_once{};
    bool probe_failure_loop{};
    bool suppress_explorer{};
};

enum class WaitOutcome
{
    Ready,
    NormalExit,
    Failure,
    Timeout
};

enum class MonitorOutcome
{
    NormalExit,
    Failure,
    HeartbeatStale
};

std::vector<std::wstring> Arguments()
{
    int count = 0;
    LPWSTR* raw = CommandLineToArgvW(GetCommandLineW(), &count);
    if (raw == nullptr) return {};

    std::vector<std::wstring> result;
    result.reserve(static_cast<std::size_t>(std::max(0, count)));
    for (int index = 0; index < count; ++index) result.emplace_back(raw[index]);
    LocalFree(raw);
    return result;
}

bool HasArgument(const std::vector<std::wstring>& arguments, std::wstring_view expected)
{
    return std::any_of(
        arguments.begin() + static_cast<std::ptrdiff_t>(std::min<std::size_t>(1u, arguments.size())),
        arguments.end(),
        [expected](const std::wstring& value)
        {
            return _wcsicmp(value.c_str(), expected.data()) == 0;
        });
}

bool TryReadUnsigned(
    const std::vector<std::wstring>& arguments,
    std::wstring_view name,
    unsigned long minimum,
    unsigned long maximum,
    unsigned long* value)
{
    if (value == nullptr) return false;
    for (std::size_t index = 1; index + 1u < arguments.size(); ++index)
    {
        if (_wcsicmp(arguments[index].c_str(), name.data()) != 0) continue;
        wchar_t* end = nullptr;
        errno = 0;
        const unsigned long parsed = std::wcstoul(arguments[index + 1u].c_str(), &end, 10);
        if (errno != 0 || end == arguments[index + 1u].c_str() || *end != L'\0' ||
            parsed < minimum || parsed > maximum)
        {
            return false;
        }
        *value = parsed;
        return true;
    }
    return false;
}

std::wstring ImagePath(HANDLE process)
{
    std::array<wchar_t, 32768> buffer{};
    DWORD size = static_cast<DWORD>(buffer.size());
    return QueryFullProcessImageNameW(process, 0, buffer.data(), &size)
        ? std::wstring(buffer.data(), static_cast<std::size_t>(size))
        : std::wstring{};
}

std::wstring ShellPath()
{
    const std::wstring own = ImagePath(GetCurrentProcess());
    const std::size_t slash = own.find_last_of(L"\\/");
    return slash == std::wstring::npos
        ? std::wstring{}
        : own.substr(0, slash + 1u) + L"CloudOS.exe";
}

std::vector<BYTE> TokenUserData(HANDLE token)
{
    DWORD bytes = 0;
    (void)GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
    if (bytes == 0) return {};
    std::vector<BYTE> data(bytes);
    if (!GetTokenInformation(token, TokenUser, data.data(), bytes, &bytes)) return {};
    return data;
}

bool IsAllowedTarget(HANDLE process, const std::wstring& expected)
{
    if (process == nullptr || expected.empty()) return false;
    const std::wstring path = ImagePath(process);
    if (path.empty() || _wcsicmp(path.c_str(), expected.c_str()) != 0) return false;

    Handle target_token;
    Handle own_token;
    if (!OpenProcessToken(process, TOKEN_QUERY, &target_token.value) ||
        !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &own_token.value))
    {
        return false;
    }

    DWORD target_session = 0;
    DWORD own_session = 0;
    DWORD bytes = 0;
    if (!GetTokenInformation(
            target_token.value,
            TokenSessionId,
            &target_session,
            static_cast<DWORD>(sizeof(target_session)),
            &bytes) ||
        !GetTokenInformation(
            own_token.value,
            TokenSessionId,
            &own_session,
            static_cast<DWORD>(sizeof(own_session)),
            &bytes) ||
        target_session != own_session)
    {
        return false;
    }

    const auto target_user = TokenUserData(target_token.value);
    const auto own_user = TokenUserData(own_token.value);
    return !target_user.empty() && !own_user.empty() &&
        EqualSid(
            reinterpret_cast<const TOKEN_USER*>(target_user.data())->User.Sid,
            reinterpret_cast<const TOKEN_USER*>(own_user.data())->User.Sid) != FALSE;
}

bool StopInstallationShell(unsigned& stopped)
{
    const std::wstring expected = ShellPath();
    if (expected.empty()) return false;

    Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    if (snapshot.value == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool success = true;
    if (!Process32FirstW(snapshot.value, &entry)) return false;
    do
    {
        if (_wcsicmp(entry.szExeFile, L"CloudOS.exe") != 0) continue;
        Handle process(OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE,
            FALSE,
            entry.th32ProcessID));
        if (process.value == nullptr)
        {
            success = false;
            continue;
        }
        if (!IsAllowedTarget(process.value, expected)) continue;
        if (TerminateProcess(process.value, 1))
        {
            ++stopped;
            if (WaitForSingleObject(process.value, 2000) != WAIT_OBJECT_0) success = false;
        }
        else if (WaitForSingleObject(process.value, 0) != WAIT_OBJECT_0)
        {
            success = false;
        }
    } while (Process32NextW(snapshot.value, &entry));
    return success;
}

bool ExplorerShellPresent() noexcept
{
    return FindWindowW(CloudOS::SupervisorProtocolV11::ExplorerTrayClass, nullptr) != nullptr;
}

bool OpenWindowsExplorer()
{
    if (ExplorerShellPresent()) return true;

    std::array<wchar_t, MAX_PATH> directory{};
    const UINT size = GetWindowsDirectoryW(directory.data(), static_cast<UINT>(directory.size()));
    if (size == 0 || size >= static_cast<UINT>(directory.size())) return false;

    const std::wstring executable =
        std::wstring(directory.data(), static_cast<std::size_t>(size)) + L"\\explorer.exe";

    DWORD shell_pid = 0;
    const HWND shell_window = GetShellWindow();
    if (shell_window != nullptr) GetWindowThreadProcessId(shell_window, &shell_pid);
    Handle shell(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, shell_pid));
    if (shell.value != nullptr && IsAllowedTarget(shell.value, executable)) return true;

    std::wstring command = L"\"" + executable + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            executable.c_str(),
            command.data(),
            nullptr,
            nullptr,
            FALSE,
            0,
            nullptr,
            directory.data(),
            &startup,
            &process))
    {
        return false;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

bool ReadHealthSnapshot(NativeHealthSnapshotV9* snapshot)
{
    if (snapshot == nullptr) return false;
    Handle mapping(OpenFileMappingW(
        FILE_MAP_READ,
        FALSE,
        CloudOS::SupervisorProtocolV11::HealthMappingName));
    if (mapping.value == nullptr) return false;

    const void* view = MapViewOfFile(
        mapping.value,
        FILE_MAP_READ,
        0,
        0,
        CloudOS::SupervisorProtocolV11::HealthStructureSize);
    if (view == nullptr) return false;

    bool valid = false;
    for (int attempt = 0; attempt < 8; ++attempt)
    {
        NativeHealthSnapshotV9 first{};
        NativeHealthSnapshotV9 second{};
        std::memcpy(&first, view, sizeof(first));
        if ((first.sequence & 1ull) != 0ull)
        {
            Sleep(1);
            continue;
        }
        MemoryBarrier();
        std::memcpy(&second, view, sizeof(second));
        if (first.sequence != second.sequence || (second.sequence & 1ull) != 0ull)
        {
            Sleep(1);
            continue;
        }
        if (second.magic != CloudOS::SupervisorProtocolV11::HealthMagic ||
            second.schema != CloudOS::SupervisorProtocolV11::HealthSchema ||
            second.structure_size != CloudOS::SupervisorProtocolV11::HealthStructureSize)
        {
            break;
        }
        *snapshot = second;
        valid = true;
        break;
    }
    UnmapViewOfFile(view);
    return valid;
}

bool HeartbeatFresh(const NativeHealthSnapshotV9& snapshot, DWORD maximum_age_ms) noexcept
{
    const ULONGLONG now = GetTickCount64();
    if (snapshot.heartbeat_tick_ms > now + 2000u) return false;
    if (snapshot.heartbeat_tick_ms > now) return true;
    return now - snapshot.heartbeat_tick_ms <= static_cast<ULONGLONG>(maximum_age_ms);
}

bool IsFailureExitCode(DWORD exit_code) noexcept
{
    if (exit_code == 0 || exit_code == kStatusControlCExit) return false;
    return (exit_code & 0x80000000u) != 0u;
}

bool LaunchCloudOS(bool probe_failure, PROCESS_INFORMATION* process)
{
    if (process == nullptr) return false;
    *process = PROCESS_INFORMATION{};

    const std::wstring executable = ShellPath();
    if (executable.empty()) return false;

    std::wstring command = L"\"" + executable + L"\" ";
    command += CloudOS::SupervisorProtocolV11::SupervisedArgument;
    if (probe_failure)
    {
        command += L" ";
        command += CloudOS::SupervisorProtocolV11::ProbeFailureArgument;
    }

    const std::size_t slash = executable.find_last_of(L"\\/");
    const std::wstring working_directory = slash == std::wstring::npos
        ? std::wstring{}
        : executable.substr(0, slash);

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    return CreateProcessW(
        executable.c_str(),
        command.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        working_directory.empty() ? nullptr : working_directory.c_str(),
        &startup,
        process) != FALSE;
}

WaitOutcome WaitForReady(
    HANDLE process,
    DWORD process_id,
    DWORD timeout_ms,
    DWORD heartbeat_timeout_ms,
    DWORD* exit_code)
{
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    while (GetTickCount64() < deadline)
    {
        if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
        {
            DWORD code = 1;
            (void)GetExitCodeProcess(process, &code);
            if (exit_code != nullptr) *exit_code = code;
            return code == 0 ? WaitOutcome::NormalExit : WaitOutcome::Failure;
        }

        NativeHealthSnapshotV9 snapshot{};
        if (ReadHealthSnapshot(&snapshot) &&
            snapshot.process_id == process_id &&
            snapshot.state == CloudOS::SupervisorProtocolV11::HealthReadyState &&
            snapshot.ready_tick_ms != 0 &&
            HeartbeatFresh(snapshot, heartbeat_timeout_ms))
        {
            return WaitOutcome::Ready;
        }
        Sleep(100);
    }
    return WaitOutcome::Timeout;
}

MonitorOutcome MonitorShell(
    HANDLE process,
    DWORD process_id,
    DWORD heartbeat_timeout_ms,
    DWORD* exit_code)
{
    ULONGLONG last_fresh_tick = GetTickCount64();
    for (;;)
    {
        const DWORD wait = WaitForSingleObject(process, 1000);
        if (wait == WAIT_OBJECT_0)
        {
            DWORD code = 1;
            (void)GetExitCodeProcess(process, &code);
            if (exit_code != nullptr) *exit_code = code;
            return IsFailureExitCode(code) ? MonitorOutcome::Failure : MonitorOutcome::NormalExit;
        }
        if (wait != WAIT_TIMEOUT) return MonitorOutcome::Failure;

        NativeHealthSnapshotV9 snapshot{};
        if (ReadHealthSnapshot(&snapshot) &&
            snapshot.process_id == process_id &&
            snapshot.state == CloudOS::SupervisorProtocolV11::HealthReadyState &&
            HeartbeatFresh(snapshot, heartbeat_timeout_ms))
        {
            last_fresh_tick = GetTickCount64();
        }
        else if (GetTickCount64() - last_fresh_tick > heartbeat_timeout_ms)
        {
            return MonitorOutcome::HeartbeatStale;
        }
    }
}

bool RequestGracefulExit(HANDLE process, DWORD process_id)
{
    const HWND desktop = FindWindowW(CloudOS::SupervisorProtocolV11::DesktopClass, nullptr);
    if (desktop != nullptr)
    {
        DWORD window_process_id = 0;
        GetWindowThreadProcessId(desktop, &window_process_id);
        if (window_process_id == process_id)
        {
            (void)PostMessageW(
                desktop,
                CloudOS::SupervisorProtocolV11::RequestGracefulExitMessage,
                0,
                0);
        }
    }
    return WaitForSingleObject(process, kGracefulExitTimeoutMs) == WAIT_OBJECT_0;
}

void StopHungProcess(HANDLE process, DWORD process_id)
{
    if (process == nullptr) return;
    if (RequestGracefulExit(process, process_id)) return;
    (void)TerminateProcess(process, kSupervisorHangExit);
    (void)WaitForSingleObject(process, 3000);
}

DWORD RestartBackoff(unsigned failure_count) noexcept
{
    const unsigned shift = std::min<unsigned>(failure_count > 0 ? failure_count - 1u : 0u, 3u);
    return std::min<DWORD>(4000u, 500u * (1u << shift));
}

int FallbackToExplorer(bool suppress_explorer)
{
    if (ExplorerShellPresent()) return 0;
    if (suppress_explorer) return kProbeFallbackSuppressedExitCode;
    return OpenWindowsExplorer() ? 0 : 43;
}

bool ProbeReadyHeartbeat(HANDLE process, DWORD process_id, DWORD heartbeat_timeout_ms)
{
    NativeHealthSnapshotV9 initial{};
    if (!ReadHealthSnapshot(&initial) || initial.process_id != process_id) return false;
    const std::uint64_t target = initial.heartbeat_count + 3ull;
    const ULONGLONG deadline = GetTickCount64() + 6000u;
    while (GetTickCount64() < deadline)
    {
        if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0) return false;
        NativeHealthSnapshotV9 snapshot{};
        if (ReadHealthSnapshot(&snapshot) &&
            snapshot.process_id == process_id &&
            snapshot.heartbeat_count >= target &&
            HeartbeatFresh(snapshot, heartbeat_timeout_ms))
        {
            return true;
        }
        Sleep(250);
    }
    return false;
}

int RunSupervisor(const SupervisorOptions& options)
{
    Handle supervisor_mutex(CreateMutexW(
        nullptr,
        TRUE,
        CloudOS::SupervisorProtocolV11::SupervisorMutexName));
    if (supervisor_mutex.value == nullptr) return 20;
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;

    unsigned failure_count = 0;
    for (;;)
    {
        PROCESS_INFORMATION raw_process{};
        if (!LaunchCloudOS(options.probe_failure_loop, &raw_process))
        {
            ++failure_count;
            if (failure_count >= options.maximum_failures)
                return FallbackToExplorer(options.suppress_explorer);
            Sleep(RestartBackoff(failure_count));
            continue;
        }

        CloseHandle(raw_process.hThread);
        Handle process(raw_process.hProcess);
        const DWORD process_id = raw_process.dwProcessId;
        const ULONGLONG launch_tick = GetTickCount64();
        DWORD exit_code = 1;
        const WaitOutcome ready = WaitForReady(
            process.value,
            process_id,
            options.ready_timeout_ms,
            options.heartbeat_timeout_ms,
            &exit_code);

        if (ready == WaitOutcome::NormalExit) return 0;
        if (ready == WaitOutcome::Ready)
        {
            if (options.probe_ready_once)
            {
                const bool heartbeat_ok = ProbeReadyHeartbeat(
                    process.value,
                    process_id,
                    options.heartbeat_timeout_ms);
                const bool graceful = RequestGracefulExit(process.value, process_id);
                if (!graceful)
                {
                    (void)TerminateProcess(process.value, kSupervisorHangExit);
                    (void)WaitForSingleObject(process.value, 3000);
                }
                return heartbeat_ok && graceful ? 0 : 44;
            }

            const MonitorOutcome monitored = MonitorShell(
                process.value,
                process_id,
                options.heartbeat_timeout_ms,
                &exit_code);
            if (monitored == MonitorOutcome::NormalExit) return 0;
            if (monitored == MonitorOutcome::HeartbeatStale)
                StopHungProcess(process.value, process_id);
        }
        else if (ready == WaitOutcome::Timeout)
        {
            StopHungProcess(process.value, process_id);
        }

        if (GetTickCount64() - launch_tick >= kStableRunResetMs) failure_count = 0;
        ++failure_count;
        if (failure_count >= options.maximum_failures)
            return FallbackToExplorer(options.suppress_explorer);
        Sleep(RestartBackoff(failure_count));
    }
}

int SelfTest()
{
    const std::wstring own = ImagePath(GetCurrentProcess());
    if (own.empty() || !IsAllowedTarget(GetCurrentProcess(), own)) return 1;
    if (IsAllowedTarget(GetCurrentProcess(), L"")) return 2;
    if (IsAllowedTarget(GetCurrentProcess(), ShellPath())) return 3;
    if (IsAllowedTarget(GetCurrentProcess(), own + L".other")) return 4;
    if (IsFailureExitCode(0) || IsFailureExitCode(1) || IsFailureExitCode(kStatusControlCExit)) return 5;
    if (!IsFailureExitCode(0xC0000001u)) return 6;
    if (RestartBackoff(1) != 500u || RestartBackoff(2) != 1000u || RestartBackoff(4) != 4000u) return 7;
    return 0;
}

int RunRecoveryUi(HINSTANCE instance)
{
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&controls);
    const TASKDIALOG_BUTTON buttons[] = {
        {101, L"Abrir Explorer do Windows\nNao altera o shell padrao nem encerra aplicativos."},
        {102, L"Encerrar CloudOS desta instalacao\nApenas processos do mesmo usuario e sessao. Requer confirmacao."}
    };

    for (;;)
    {
        TASKDIALOGCONFIG config{};
        config.cbSize = sizeof(config);
        config.hInstance = instance;
        config.dwFlags = TDF_USE_COMMAND_LINKS | TDF_ALLOW_DIALOG_CANCELLATION | TDF_SIZE_TO_CONTENT;
        config.dwCommonButtons = TDCBF_CLOSE_BUTTON;
        config.pszWindowTitle = L"CloudOS Recovery";
        config.pszMainInstruction = L"Recuperacao independente do CloudOS";
        config.pszContent = L"Este utilitario funciona sem carregar CloudOS.exe, seu runtime ou WebView2.\n"
            L"Nenhuma acao destrutiva e automatica. Seus arquivos, pins e configuracoes nao serao apagados.\n"
            L"O modo Supervisor V11 usa este mesmo executavel para readiness, heartbeat e fallback seguro.";
        config.pszMainIcon = TD_INFORMATION_ICON;
        config.cButtons = static_cast<UINT>(std::size(buttons));
        config.pButtons = buttons;
        config.nDefaultButton = IDCLOSE;
        int choice = IDCLOSE;
        if (FAILED(TaskDialogIndirect(&config, &choice, nullptr, nullptr)))
        {
            MessageBoxW(
                nullptr,
                L"Nao foi possivel abrir a interface de recuperacao.",
                L"CloudOS Recovery",
                MB_OK | MB_ICONERROR);
            return 1;
        }
        if (choice == 101)
        {
            const bool opened = OpenWindowsExplorer();
            MessageBoxW(
                nullptr,
                opened
                    ? L"Explorer ja estava ativo ou sua inicializacao foi solicitada."
                    : L"Nao foi possivel iniciar Explorer. Nenhum processo foi encerrado.",
                L"CloudOS Recovery",
                MB_OK | (opened ? MB_ICONINFORMATION : MB_ICONERROR));
        }
        else if (choice == 102)
        {
            if (MessageBoxW(
                    nullptr,
                    L"Forcar o encerramento pode perder edicoes nao salvas nos apps internos do CloudOS.\n"
                    L"Outros aplicativos e instalacoes nao serao encerrados. Continuar?",
                    L"Confirmar recuperacao",
                    MB_YESNO | MB_DEFBUTTON2 | MB_ICONWARNING) != IDYES)
            {
                continue;
            }
            unsigned stopped = 0;
            const bool ok = StopInstallationShell(stopped);
            const std::wstring result =
                L"Processos CloudOS encerrados: " + std::to_wstring(stopped) +
                (ok
                    ? L". Nenhum arquivo de estado foi apagado."
                    : L". Alguns processos nao puderam ser consultados/encerrados.");
            MessageBoxW(
                nullptr,
                result.c_str(),
                L"CloudOS Recovery",
                MB_OK | (ok ? MB_ICONINFORMATION : MB_ICONWARNING));
        }
        else
        {
            return 0;
        }
    }
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    const std::vector<std::wstring> arguments = Arguments();
    if (HasArgument(arguments, L"--self-test")) return SelfTest();
    if (HasArgument(arguments, L"--recovery-ui")) return RunRecoveryUi(instance);

    SupervisorOptions options{};
    options.probe_ready_once = HasArgument(arguments, L"--probe-ready-once");
    options.probe_failure_loop = HasArgument(arguments, L"--probe-failure-loop");
    options.suppress_explorer = HasArgument(arguments, L"--probe-no-explorer");

    unsigned long parsed = 0;
    if (TryReadUnsigned(arguments, L"--ready-timeout-ms", 1000, 300000, &parsed))
        options.ready_timeout_ms = static_cast<DWORD>(parsed);
    if (TryReadUnsigned(arguments, L"--heartbeat-timeout-ms", 1000, 120000, &parsed))
        options.heartbeat_timeout_ms = static_cast<DWORD>(parsed);
    if (TryReadUnsigned(arguments, L"--max-failures", 1, 10, &parsed))
        options.maximum_failures = static_cast<unsigned>(parsed);

    return RunSupervisor(options);
}
