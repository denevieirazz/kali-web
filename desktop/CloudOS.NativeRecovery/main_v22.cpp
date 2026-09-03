#define wWinMain CloudOSLegacySupervisorMainV11
#include "main.cpp"
#undef wWinMain

#include <deque>
#include <sstream>

namespace
{
constexpr ULONGLONG kV22CrashWindowMs = 60000ull;
constexpr wchar_t kV22StateFileName[] = L"supervisor-state-v22.json";
const ULONGLONG g_supervisor_start_tick_v22 = GetTickCount64();
volatile LONG64 g_transition_sequence_v22 = 0;

enum class SupervisorStateV22
{
    Starting,
    Healthy,
    Degraded,
    Restarting,
    CrashLoop,
    SafeMode,
    Stopping
};

const wchar_t* SupervisorStateNameV22(SupervisorStateV22 state) noexcept
{
    switch (state)
    {
    case SupervisorStateV22::Starting: return L"STARTING";
    case SupervisorStateV22::Healthy: return L"HEALTHY";
    case SupervisorStateV22::Degraded: return L"DEGRADED";
    case SupervisorStateV22::Restarting: return L"RESTARTING";
    case SupervisorStateV22::CrashLoop: return L"CRASH_LOOP";
    case SupervisorStateV22::SafeMode: return L"SAFE_MODE";
    case SupervisorStateV22::Stopping: return L"STOPPING";
    default: return L"DEGRADED";
    }
}

struct V22Handle final
{
    HANDLE value{};
    explicit V22Handle(HANDLE handle = nullptr) noexcept : value(handle) {}
    ~V22Handle()
    {
        if (value != nullptr && value != INVALID_HANDLE_VALUE) CloseHandle(value);
    }
    V22Handle(const V22Handle&) = delete;
    V22Handle& operator=(const V22Handle&) = delete;
};

struct V22LaunchResult final
{
    PROCESS_INFORMATION process{};
    bool job_assigned{};
};

std::wstring JsonEscapeV22(std::wstring_view value)
{
    std::wstring output;
    output.reserve(value.size() + 16u);
    for (const wchar_t ch : value)
    {
        switch (ch)
        {
        case L'\\': output += L"\\\\"; break;
        case L'\"': output += L"\\\""; break;
        case L'\r': output += L"\\r"; break;
        case L'\n': output += L"\\n"; break;
        case L'\t': output += L"\\t"; break;
        default:
            if (ch >= 0x20) output.push_back(ch);
            break;
        }
    }
    return output;
}

std::wstring SupervisorStateDirectoryV22()
{
    std::array<wchar_t, 32768> buffer{};
    const DWORD required = GetEnvironmentVariableW(
        L"LOCALAPPDATA",
        buffer.data(),
        static_cast<DWORD>(buffer.size()));
    if (required == 0 || required >= buffer.size()) return {};

    std::wstring cloudos = std::wstring(buffer.data(), required) + L"\\CloudOS";
    if (!CreateDirectoryW(cloudos.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)
        return {};

    std::wstring recovery = cloudos + L"\\Recovery";
    if (!CreateDirectoryW(recovery.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)
        return {};

    return recovery;
}

bool WriteUtf8FileV22(const std::wstring& path, const std::wstring& text)
{
    if (path.empty()) return false;
    const int bytes = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        text.data(),
        static_cast<int>(text.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (bytes <= 0) return false;

    std::string utf8(static_cast<std::size_t>(bytes), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            text.data(),
            static_cast<int>(text.size()),
            utf8.data(),
            bytes,
            nullptr,
            nullptr) != bytes)
    {
        return false;
    }
    if (utf8.size() > static_cast<std::size_t>(MAXDWORD)) return false;

    V22Handle file(CreateFileW(
        path.c_str(),
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH,
        nullptr));
    if (file.value == INVALID_HANDLE_VALUE) return false;

    DWORD written = 0;
    const DWORD requested = static_cast<DWORD>(utf8.size());
    return WriteFile(file.value, utf8.data(), requested, &written, nullptr) != FALSE &&
        written == requested && FlushFileBuffers(file.value) != FALSE;
}

void PersistSupervisorStateV22(
    SupervisorStateV22 state,
    std::wstring_view reason,
    DWORD shell_pid,
    unsigned failures,
    DWORD exit_code,
    bool job_assigned)
{
    const std::wstring directory = SupervisorStateDirectoryV22();
    if (directory.empty()) return;

    SYSTEMTIME utc{};
    GetSystemTime(&utc);
    wchar_t timestamp[64]{};
    swprintf_s(
        timestamp,
        L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        utc.wYear,
        utc.wMonth,
        utc.wDay,
        utc.wHour,
        utc.wMinute,
        utc.wSecond,
        utc.wMilliseconds);

    const LONG64 sequence = InterlockedIncrement64(&g_transition_sequence_v22);
    const ULONGLONG now = GetTickCount64();
    const ULONGLONG uptime = now >= g_supervisor_start_tick_v22
        ? now - g_supervisor_start_tick_v22
        : 0ull;

    std::wostringstream json;
    json << L"{\n"
         << L"  \"schema\": 22,\n"
         << L"  \"component\": \"CloudOS.Supervisor\",\n"
         << L"  \"state\": \"" << SupervisorStateNameV22(state) << L"\",\n"
         << L"  \"reason\": \"" << JsonEscapeV22(reason) << L"\",\n"
         << L"  \"transition_sequence\": " << sequence << L",\n"
         << L"  \"supervisor_pid\": " << GetCurrentProcessId() << L",\n"
         << L"  \"supervisor_uptime_ms\": " << uptime << L",\n"
         << L"  \"shell_pid\": " << shell_pid << L",\n"
         << L"  \"failure_count\": " << failures << L",\n"
         << L"  \"last_exit_code\": " << exit_code << L",\n"
         << L"  \"job_kill_on_close_assigned\": " << (job_assigned ? L"true" : L"false") << L",\n"
         << L"  \"job_breakaway_enabled\": true,\n"
         << L"  \"updated_utc\": \"" << timestamp << L"\"\n"
         << L"}\n";

    const std::wstring target = directory + L"\\" + kV22StateFileName;
    const std::wstring temporary =
        target + L".tmp." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(sequence);
    if (!WriteUtf8FileV22(temporary, json.str())) return;

    if (!MoveFileExW(
            temporary.c_str(),
            target.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        (void)DeleteFileW(temporary.c_str());
    }
}

HANDLE CreateKillOnCloseJobV22() noexcept
{
    HANDLE job = CreateJobObjectW(nullptr, nullptr);
    if (job == nullptr) return nullptr;

    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
        JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (!SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &limits,
            static_cast<DWORD>(sizeof(limits))))
    {
        CloseHandle(job);
        return nullptr;
    }
    return job;
}

bool AssignShellToJobV22(HANDLE job, HANDLE process) noexcept
{
    return job != nullptr && process != nullptr && AssignProcessToJobObject(job, process) != FALSE;
}

bool LaunchCloudOSSuspendedV22(
    bool probe_failure,
    HANDLE job,
    V22LaunchResult* result)
{
    if (result == nullptr) return false;
    *result = V22LaunchResult{};

    const std::wstring executable = ShellPath();
    if (executable.empty())
    {
        SetLastError(ERROR_FILE_NOT_FOUND);
        return false;
    }

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
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            executable.c_str(),
            command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_SUSPENDED | CREATE_DEFAULT_ERROR_MODE,
            nullptr,
            working_directory.empty() ? nullptr : working_directory.c_str(),
            &startup,
            &process))
    {
        return false;
    }

    bool job_assigned = false;
    if (job != nullptr)
    {
        job_assigned = AssignShellToJobV22(job, process.hProcess);
    }

    if (ResumeThread(process.hThread) == static_cast<DWORD>(-1))
    {
        const DWORD resume_error = GetLastError();
        (void)TerminateProcess(process.hProcess, kSupervisorHangExit);
        (void)WaitForSingleObject(process.hProcess, 3000);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        SetLastError(resume_error);
        return false;
    }

    result->process = process;
    result->job_assigned = job_assigned;
    return true;
}

void PurgeOldFailuresV22(std::deque<ULONGLONG>& failures, ULONGLONG now)
{
    while (!failures.empty() && now - failures.front() > kV22CrashWindowMs)
        failures.pop_front();
}

bool RecordFailureV22(std::deque<ULONGLONG>& failures, unsigned maximum_failures)
{
    const ULONGLONG now = GetTickCount64();
    PurgeOldFailuresV22(failures, now);
    failures.push_back(now);
    return failures.size() >= static_cast<std::size_t>(maximum_failures);
}

int EnterSafeModeV22(
    const SupervisorOptions& options,
    unsigned failure_count,
    DWORD exit_code,
    std::wstring_view reason)
{
    PersistSupervisorStateV22(
        SupervisorStateV22::CrashLoop,
        reason,
        0,
        failure_count,
        exit_code,
        false);
    PersistSupervisorStateV22(
        SupervisorStateV22::SafeMode,
        L"restart budget exhausted; Windows Explorer fallback requested",
        0,
        failure_count,
        exit_code,
        false);
    return FallbackToExplorer(options.suppress_explorer);
}

int RunSupervisorV22(const SupervisorOptions& options)
{
    Handle supervisor_mutex(CreateMutexW(
        nullptr,
        TRUE,
        CloudOS::SupervisorProtocolV11::SupervisorMutexName));
    if (supervisor_mutex.value == nullptr) return 20;
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;

    unsigned failure_count = 0;
    std::deque<ULONGLONG> recent_failures;
    PersistSupervisorStateV22(
        SupervisorStateV22::Starting,
        L"supervisor authority started",
        0,
        failure_count,
        0,
        false);

    for (;;)
    {
        V22Handle job(CreateKillOnCloseJobV22());
        V22LaunchResult launch{};
        if (!LaunchCloudOSSuspendedV22(options.probe_failure_loop, job.value, &launch))
        {
            const DWORD launch_error = GetLastError();
            ++failure_count;
            const bool crash_loop = RecordFailureV22(recent_failures, options.maximum_failures);
            PersistSupervisorStateV22(
                SupervisorStateV22::Degraded,
                L"CloudOS.exe suspended launch/resume failed",
                0,
                failure_count,
                launch_error,
                false);
            if (crash_loop || failure_count >= options.maximum_failures)
            {
                return EnterSafeModeV22(
                    options,
                    failure_count,
                    launch_error,
                    L"repeated CloudOS.exe launch failures");
            }

            PersistSupervisorStateV22(
                SupervisorStateV22::Restarting,
                L"bounded restart after launch failure",
                0,
                failure_count,
                launch_error,
                false);
            Sleep(RestartBackoff(failure_count));
            continue;
        }

        CloseHandle(launch.process.hThread);
        Handle process(launch.process.hProcess);
        const DWORD process_id = launch.process.dwProcessId;
        const bool job_assigned = launch.job_assigned;
        const ULONGLONG launch_tick = GetTickCount64();
        DWORD exit_code = 1;

        PersistSupervisorStateV22(
            SupervisorStateV22::Starting,
            job_assigned
                ? L"CloudOS.exe created suspended, assigned to kill-on-close/breakaway Job Object, then resumed"
                : L"CloudOS.exe created suspended and resumed; Job Object ownership unavailable",
            process_id,
            failure_count,
            0,
            job_assigned);

        const WaitOutcome ready = WaitForReady(
            process.value,
            process_id,
            options.ready_timeout_ms,
            options.heartbeat_timeout_ms,
            &exit_code);

        if (ready == WaitOutcome::NormalExit)
        {
            PersistSupervisorStateV22(
                SupervisorStateV22::Stopping,
                L"CloudOS.exe exited normally before readiness",
                process_id,
                failure_count,
                exit_code,
                job_assigned);
            return 0;
        }

        if (ready == WaitOutcome::Ready)
        {
            PersistSupervisorStateV22(
                job_assigned ? SupervisorStateV22::Healthy : SupervisorStateV22::Degraded,
                job_assigned
                    ? L"readiness and heartbeat healthy; process tree supervised"
                    : L"readiness healthy but Job Object ownership unavailable",
                process_id,
                failure_count,
                0,
                job_assigned);

            if (options.probe_ready_once)
            {
                const bool heartbeat_ok = ProbeReadyHeartbeat(
                    process.value,
                    process_id,
                    options.heartbeat_timeout_ms);
                PersistSupervisorStateV22(
                    SupervisorStateV22::Stopping,
                    L"ready probe requested graceful shutdown",
                    process_id,
                    failure_count,
                    0,
                    job_assigned);
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
            if (monitored == MonitorOutcome::NormalExit)
            {
                PersistSupervisorStateV22(
                    SupervisorStateV22::Stopping,
                    L"CloudOS.exe exited normally",
                    process_id,
                    failure_count,
                    exit_code,
                    job_assigned);
                return 0;
            }
            if (monitored == MonitorOutcome::HeartbeatStale)
            {
                PersistSupervisorStateV22(
                    SupervisorStateV22::Degraded,
                    L"heartbeat became stale; graceful shutdown requested",
                    process_id,
                    failure_count,
                    kSupervisorHangExit,
                    job_assigned);
                StopHungProcess(process.value, process_id);
                exit_code = kSupervisorHangExit;
            }
        }
        else if (ready == WaitOutcome::Timeout)
        {
            PersistSupervisorStateV22(
                SupervisorStateV22::Degraded,
                L"readiness deadline exceeded; graceful shutdown requested",
                process_id,
                failure_count,
                kSupervisorHangExit,
                job_assigned);
            StopHungProcess(process.value, process_id);
            exit_code = kSupervisorHangExit;
        }
        else
        {
            PersistSupervisorStateV22(
                SupervisorStateV22::Degraded,
                L"CloudOS.exe failed before or after readiness",
                process_id,
                failure_count,
                exit_code,
                job_assigned);
        }

        if (GetTickCount64() - launch_tick >= kStableRunResetMs)
        {
            failure_count = 0;
            recent_failures.clear();
        }

        ++failure_count;
        const bool crash_loop = RecordFailureV22(recent_failures, options.maximum_failures);
        if (crash_loop || failure_count >= options.maximum_failures)
        {
            return EnterSafeModeV22(
                options,
                failure_count,
                exit_code,
                L"restart budget exhausted inside the rolling crash window");
        }

        PersistSupervisorStateV22(
            SupervisorStateV22::Restarting,
            L"bounded restart scheduled",
            0,
            failure_count,
            exit_code,
            false);
        Sleep(RestartBackoff(failure_count));
    }
}

int SelfTestV22()
{
    if (std::wstring(SupervisorStateNameV22(SupervisorStateV22::Starting)) != L"STARTING") return 61;
    if (std::wstring(SupervisorStateNameV22(SupervisorStateV22::Healthy)) != L"HEALTHY") return 62;
    if (std::wstring(SupervisorStateNameV22(SupervisorStateV22::CrashLoop)) != L"CRASH_LOOP") return 63;
    if (std::wstring(SupervisorStateNameV22(SupervisorStateV22::SafeMode)) != L"SAFE_MODE") return 64;

    std::deque<ULONGLONG> failures;
    if (RecordFailureV22(failures, 3)) return 65;
    if (RecordFailureV22(failures, 3)) return 66;
    if (!RecordFailureV22(failures, 3)) return 67;

    V22Handle job(CreateKillOnCloseJobV22());
    if (job.value == nullptr) return 68;

    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    if (!QueryInformationJobObject(
            job.value,
            JobObjectExtendedLimitInformation,
            &limits,
            static_cast<DWORD>(sizeof(limits)),
            nullptr))
    {
        return 69;
    }
    const DWORD required = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if ((limits.BasicLimitInformation.LimitFlags & required) != required) return 70;

    return 0;
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    const std::vector<std::wstring> arguments = Arguments();
    if (HasArgument(arguments, L"--self-test"))
    {
        const int legacy = SelfTest();
        return legacy == 0 ? SelfTestV22() : legacy;
    }
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

    return RunSupervisorV22(options);
}
