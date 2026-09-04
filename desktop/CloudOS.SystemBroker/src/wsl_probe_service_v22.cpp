#include "wsl_probe_service_v22.h"
#include "wsl_service_v21.h"

#include <Windows.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr const char* kHealthMarker = "CLOUDOS_WSL_HEALTH_V22";
constexpr uint32_t kMinTimeoutMs = 1000;
constexpr uint32_t kDefaultTimeoutMs = 8000;
constexpr uint32_t kMaxTimeoutMs = 15000;
constexpr size_t kMaxCapturedBytes = 64 * 1024;
constexpr size_t kMaxReturnedBytes = 8 * 1024;

std::string LowerAscii(std::string value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
}

std::wstring Utf8ToWide(const std::string& value)
{
    if (value.empty()) return {};
    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (required <= 0) return {};

    std::wstring result(static_cast<size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            required) != required)
    {
        return {};
    }
    return result;
}

std::wstring QuoteWindowsArgument(const std::wstring& argument)
{
    if (argument.empty()) return L"\"\"";
    if (argument.find_first_of(L" \t\n\v\"") == std::wstring::npos)
    {
        return argument;
    }

    std::wstring quoted = L"\"";
    size_t backslashes = 0;
    for (const wchar_t ch : argument)
    {
        if (ch == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (ch == L'\"')
        {
            quoted.append(backslashes * 2 + 1, L'\\');
            quoted.push_back(L'\"');
            backslashes = 0;
            continue;
        }
        quoted.append(backslashes, L'\\');
        backslashes = 0;
        quoted.push_back(ch);
    }
    quoted.append(backslashes * 2, L'\\');
    quoted.push_back(L'\"');
    return quoted;
}

std::wstring ResolveWslExe()
{
    wchar_t system_directory[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(system_directory, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return {};
    return std::wstring(system_directory) + L"\\wsl.exe";
}

const WslDistributionInfoV21* FindDistribution(
    const WslRuntimeSnapshotV21& snapshot,
    const std::string& requested)
{
    const std::string wanted = LowerAscii(requested);
    if (wanted.empty()) return nullptr;
    for (const auto& distro : snapshot.distributions)
    {
        if (LowerAscii(distro.name) == wanted) return &distro;
    }
    return nullptr;
}

std::string ResolveRequestedDistro(
    const WslRuntimeSnapshotV21& snapshot,
    const std::string& requested)
{
    if (!requested.empty()) return requested;
    if (!snapshot.default_distribution.empty()) return snapshot.default_distribution;
    return snapshot.distributions.empty()
        ? std::string{}
        : snapshot.distributions.front().name;
}

std::string SanitizeOutput(std::string output)
{
    if (output.size() > kMaxReturnedBytes)
    {
        output.resize(kMaxReturnedBytes);
        output += "\n[CloudOS: output truncated]";
    }
    for (char& ch : output)
    {
        const unsigned char value = static_cast<unsigned char>(ch);
        if (value == 0 || (value < 0x20U && ch != '\r' && ch != '\n' && ch != '\t'))
        {
            ch = ' ';
        }
    }
    return output;
}

void DrainAvailablePipe(HANDLE pipe, std::string& output)
{
    if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE) return;
    char buffer[4096];
    while (output.size() < kMaxCapturedBytes)
    {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr)) break;
        if (available == 0) break;

        const DWORD capacity = static_cast<DWORD>(
            std::min<size_t>(sizeof(buffer), kMaxCapturedBytes - output.size()));
        const DWORD wanted = std::min<DWORD>(available, capacity);
        if (wanted == 0) break;

        DWORD bytes_read = 0;
        if (!ReadFile(pipe, buffer, wanted, &bytes_read, nullptr) || bytes_read == 0)
        {
            break;
        }
        output.append(buffer, bytes_read);
    }
}

uint64_t ElapsedMs(std::chrono::steady_clock::time_point started)
{
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started)
            .count());
}

void CloseIfValid(HANDLE handle)
{
    if (handle != nullptr && handle != INVALID_HANDLE_VALUE)
    {
        CloseHandle(handle);
    }
}
} // namespace

WslProbeServiceV22& WslProbeServiceV22::Instance()
{
    static WslProbeServiceV22 instance;
    return instance;
}

WslProbeResultV22 WslProbeServiceV22::Probe(
    const std::string& requested_distro,
    uint32_t timeout_ms)
{
    WslProbeResultV22 result;
    const auto started = std::chrono::steady_clock::now();

    const WslRuntimeSnapshotV21 snapshot =
        WslServiceV21::Instance().GetRuntimeSnapshot();
    if (!snapshot.engine_available)
    {
        result.error_code = "wsl_engine_unavailable";
        result.error_message = "The Windows WSL engine was not detected";
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    result.distro = ResolveRequestedDistro(snapshot, requested_distro);
    if (result.distro.empty())
    {
        result.error_code = "wsl_no_registered_distro";
        result.error_message = "No registered WSL distribution is available";
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    const WslDistributionInfoV21* distro = FindDistribution(snapshot, result.distro);
    if (distro == nullptr)
    {
        result.error_code = "wsl_distro_not_registered";
        result.error_message = "The requested WSL distribution is not registered";
        result.duration_ms = ElapsedMs(started);
        return result;
    }
    result.distro = distro->name;

    if (!distro->base_path_present)
    {
        result.error_code = "wsl_distro_storage_missing";
        result.error_message = "The registered WSL distribution storage path is missing";
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    const std::wstring wsl_exe = ResolveWslExe();
    if (wsl_exe.empty())
    {
        result.error_code = "wsl_executable_unavailable";
        result.error_message = "Unable to resolve wsl.exe from the Windows system directory";
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    const std::wstring wide_distro = Utf8ToWide(result.distro);
    if (wide_distro.empty())
    {
        result.error_code = "invalid_distro_name";
        result.error_message = "The registered distro name is not valid UTF-8";
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    timeout_ms = timeout_ms == 0 ? kDefaultTimeoutMs : timeout_ms;
    timeout_ms = std::clamp(timeout_ms, kMinTimeoutMs, kMaxTimeoutMs);

    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;

    HANDLE read_pipe = nullptr;
    HANDLE write_pipe = nullptr;
    if (!CreatePipe(&read_pipe, &write_pipe, &security, 0))
    {
        result.error_code = "probe_pipe_failed";
        result.error_message = "CreatePipe failed with error " + std::to_string(GetLastError());
        result.duration_ms = ElapsedMs(started);
        return result;
    }
    if (!SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0))
    {
        const DWORD error = GetLastError();
        CloseIfValid(write_pipe);
        CloseIfValid(read_pipe);
        result.error_code = "probe_pipe_security_failed";
        result.error_message = "SetHandleInformation failed with error " + std::to_string(error);
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    HANDLE nul_input = CreateFileW(
        L"NUL",
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        &security,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (nul_input == INVALID_HANDLE_VALUE)
    {
        const DWORD error = GetLastError();
        CloseIfValid(write_pipe);
        CloseIfValid(read_pipe);
        result.error_code = "probe_stdin_failed";
        result.error_message = "Unable to open NUL for probe stdin: " + std::to_string(error);
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    // The command body is fixed by CloudOS. RPC callers can only choose a
    // distro already present in WslServiceV21's registration inventory.
    const std::wstring probe_script =
        L"printf 'CLOUDOS_WSL_HEALTH_V22\\n'; "
        L"printf 'uid='; id -u; "
        L"printf 'kernel='; uname -s; "
        L"printf 'cwd='; pwd";

    std::wstring command_line =
        QuoteWindowsArgument(wsl_exe) +
        L" -d " + QuoteWindowsArgument(wide_distro) +
        L" --exec /bin/sh -lc " + QuoteWindowsArgument(probe_script);
    std::vector<wchar_t> command_buffer(command_line.begin(), command_line.end());
    command_buffer.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdInput = nul_input;
    startup.hStdOutput = write_pipe;
    startup.hStdError = write_pipe;

    PROCESS_INFORMATION process{};
    result.attempted = true;
    const BOOL created = CreateProcessW(
        wsl_exe.c_str(),
        command_buffer.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
        nullptr,
        nullptr,
        &startup,
        &process);
    const DWORD create_error = created ? ERROR_SUCCESS : GetLastError();

    CloseIfValid(write_pipe);
    CloseIfValid(nul_input);

    if (!created)
    {
        result.error_code = "wsl_probe_start_failed";
        result.error_message = "CreateProcessW failed with error " + std::to_string(create_error);
        DrainAvailablePipe(read_pipe, result.output);
        CloseIfValid(read_pipe);
        result.output = SanitizeOutput(std::move(result.output));
        result.duration_ms = ElapsedMs(started);
        return result;
    }

    CloseIfValid(process.hThread);

    const DWORD wait_result = WaitForSingleObject(process.hProcess, timeout_ms);
    if (wait_result == WAIT_TIMEOUT)
    {
        result.timed_out = true;
        if (!TerminateProcess(process.hProcess, ERROR_TIMEOUT))
        {
            result.error_code = "wsl_probe_timeout_termination_failed";
            result.error_message = "The probe timed out and its Windows launcher could not be terminated";
        }
        else
        {
            WaitForSingleObject(process.hProcess, 2000);
            result.error_code = "wsl_probe_timeout";
            result.error_message = "The fixed WSL health probe exceeded its deadline";
        }
    }
    else if (wait_result != WAIT_OBJECT_0)
    {
        const DWORD wait_error = GetLastError();
        TerminateProcess(process.hProcess, wait_error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : wait_error);
        WaitForSingleObject(process.hProcess, 2000);
        result.error_code = "wsl_probe_wait_failed";
        result.error_message = "WaitForSingleObject failed with error " + std::to_string(wait_error);
    }

    DWORD exit_code = static_cast<DWORD>(-1);
    if (GetExitCodeProcess(process.hProcess, &exit_code))
    {
        result.exit_code = static_cast<int>(exit_code);
    }

    // Process has exited (or was terminated), so collect the bounded output
    // already waiting in the pipe without risking a blocking read.
    DrainAvailablePipe(read_pipe, result.output);
    CloseIfValid(read_pipe);
    CloseIfValid(process.hProcess);

    result.output = SanitizeOutput(std::move(result.output));
    result.marker_seen = result.output.find(kHealthMarker) != std::string::npos;
    result.success =
        !result.timed_out &&
        result.error_code.empty() &&
        result.exit_code == 0 &&
        result.marker_seen;

    if (!result.success && result.error_code.empty())
    {
        result.error_code = result.marker_seen
            ? "wsl_probe_nonzero_exit"
            : "wsl_probe_marker_missing";
        result.error_message = result.marker_seen
            ? "The fixed WSL health probe returned a non-zero exit code"
            : "The WSL process exited without the CloudOS health marker";
    }

    result.duration_ms = ElapsedMs(started);
    return result;
}

} // namespace CloudOS
