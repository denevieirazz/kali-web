#include "../include/cloudos_native_runtime.h"

#include <algorithm>
#include <memory>
#include <new>
#include <vector>

namespace {

constexpr DWORD kTerminalCreationFlags =
    EXTENDED_STARTUPINFO_PRESENT |
    CREATE_UNICODE_ENVIRONMENT |
    CREATE_NEW_PROCESS_GROUP |
    CREATE_SUSPENDED;
constexpr DWORD kTerminalJobFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
constexpr DWORD kMaxTerminalIoBytes = 1024u * 1024u;

struct TerminalLease final {
    HPCON pseudo_console = nullptr;
    HANDLE input_write = nullptr;
    HANDLE output_read = nullptr;
    HANDLE job = nullptr;
    HANDLE process = nullptr;
    HANDLE primary_thread = nullptr;
    DWORD process_id = 0;

    ~TerminalLease() noexcept {
        if (output_read != nullptr) {
            CloseHandle(output_read);
            output_read = nullptr;
        }
        if (input_write != nullptr) {
            CloseHandle(input_write);
            input_write = nullptr;
        }
        if (pseudo_console != nullptr) {
            ClosePseudoConsole(pseudo_console);
            pseudo_console = nullptr;
        }
        if (primary_thread != nullptr) {
            CloseHandle(primary_thread);
            primary_thread = nullptr;
        }
        if (process != nullptr) {
            CloseHandle(process);
            process = nullptr;
        }
        if (job != nullptr) {
            CloseHandle(job);
            job = nullptr;
        }
    }
};

BOOL terminal_fail(DWORD error) noexcept {
    SetLastError(error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : error);
    return FALSE;
}

TerminalLease* checked_terminal(void* opaque) noexcept {
    return static_cast<TerminalLease*>(opaque);
}

BOOL configure_terminal_job(HANDLE job) noexcept {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION information{};
    information.BasicLimitInformation.LimitFlags = kTerminalJobFlags;
    return SetInformationJobObject(
        job,
        JobObjectExtendedLimitInformation,
        &information,
        static_cast<DWORD>(sizeof(information)));
}

void close_if_valid(HANDLE& handle) noexcept {
    if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
        CloseHandle(handle);
    }
    handle = nullptr;
}

BOOL create_pipe_pair(HANDLE& read_side, HANDLE& write_side) noexcept {
    read_side = nullptr;
    write_side = nullptr;
    SECURITY_ATTRIBUTES security{
        sizeof(SECURITY_ATTRIBUTES),
        nullptr,
        TRUE,
    };
    return CreatePipe(&read_side, &write_side, &security, 0);
}

BOOL build_attribute_list(
    HPCON pseudo_console,
    std::vector<std::byte>& storage,
    STARTUPINFOEXW& startup) noexcept {
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
    const DWORD sizing_error = GetLastError();
    if (bytes == 0 || (sizing_error != ERROR_INSUFFICIENT_BUFFER && sizing_error != ERROR_SUCCESS)) {
        return FALSE;
    }

    try {
        storage.resize(bytes);
    } catch (...) {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    startup.lpAttributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &bytes)) {
        return FALSE;
    }

    if (!UpdateProcThreadAttribute(
            startup.lpAttributeList,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            pseudo_console,
            sizeof(HPCON),
            nullptr,
            nullptr)) {
        DeleteProcThreadAttributeList(startup.lpAttributeList);
        startup.lpAttributeList = nullptr;
        return FALSE;
    }

    return TRUE;
}

} // namespace

extern "C" {

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_create(
    const wchar_t* command_line,
    const wchar_t* working_directory,
    SHORT columns,
    SHORT rows,
    void** terminal_out,
    DWORD* process_id_out) noexcept {
    if (command_line == nullptr || *command_line == L'\0' ||
        terminal_out == nullptr || process_id_out == nullptr ||
        columns <= 0 || rows <= 0) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }

    *terminal_out = nullptr;
    *process_id_out = 0;

    HANDLE input_read = nullptr;
    HANDLE input_write = nullptr;
    HANDLE output_read = nullptr;
    HANDLE output_write = nullptr;
    HPCON pseudo_console = nullptr;
    LPPROC_THREAD_ATTRIBUTE_LIST attribute_list = nullptr;

    auto lease = std::unique_ptr<TerminalLease>(new (std::nothrow) TerminalLease{});
    if (!lease) return terminal_fail(ERROR_NOT_ENOUGH_MEMORY);

    if (!create_pipe_pair(input_read, input_write)) return FALSE;
    if (!create_pipe_pair(output_read, output_write)) {
        close_if_valid(input_read);
        close_if_valid(input_write);
        return FALSE;
    }

    const COORD size{columns, rows};
    const HRESULT pseudo_result = CreatePseudoConsole(size, input_read, output_write, 0, &pseudo_console);
    if (FAILED(pseudo_result)) {
        close_if_valid(input_read);
        close_if_valid(input_write);
        close_if_valid(output_read);
        close_if_valid(output_write);
        return terminal_fail(HRESULT_CODE(pseudo_result));
    }

    // ConPTY owns its duplicates after successful creation. The host side keeps only
    // input_write/output_read, so the source process cannot inherit an accidental
    // extra copy that would prevent EOF propagation.
    close_if_valid(input_read);
    close_if_valid(output_write);

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    std::vector<std::byte> attribute_storage;
    if (!build_attribute_list(pseudo_console, attribute_storage, startup)) {
        const DWORD error = GetLastError();
        ClosePseudoConsole(pseudo_console);
        close_if_valid(input_write);
        close_if_valid(output_read);
        return terminal_fail(error);
    }
    attribute_list = startup.lpAttributeList;

    std::vector<wchar_t> mutable_command;
    try {
        const std::size_t length = wcslen(command_line);
        mutable_command.assign(command_line, command_line + length + 1);
    } catch (...) {
        DeleteProcThreadAttributeList(attribute_list);
        ClosePseudoConsole(pseudo_console);
        close_if_valid(input_write);
        close_if_valid(output_read);
        return terminal_fail(ERROR_NOT_ENOUGH_MEMORY);
    }

    lease->job = CreateJobObjectW(nullptr, nullptr);
    if (lease->job == nullptr || !configure_terminal_job(lease->job)) {
        const DWORD error = GetLastError();
        DeleteProcThreadAttributeList(attribute_list);
        ClosePseudoConsole(pseudo_console);
        close_if_valid(input_write);
        close_if_valid(output_read);
        return terminal_fail(error);
    }

    PROCESS_INFORMATION process{};
    const BOOL created = CreateProcessW(
        nullptr,
        mutable_command.data(),
        nullptr,
        nullptr,
        FALSE,
        kTerminalCreationFlags,
        nullptr,
        working_directory,
        &startup.StartupInfo,
        &process);
    const DWORD create_error = created ? ERROR_SUCCESS : GetLastError();
    DeleteProcThreadAttributeList(attribute_list);

    if (!created) {
        ClosePseudoConsole(pseudo_console);
        close_if_valid(input_write);
        close_if_valid(output_read);
        return terminal_fail(create_error);
    }

    lease->process = process.hProcess;
    lease->primary_thread = process.hThread;
    lease->process_id = process.dwProcessId;
    lease->pseudo_console = pseudo_console;
    lease->input_write = input_write;
    lease->output_read = output_read;

    if (!AssignProcessToJobObject(lease->job, lease->process)) {
        const DWORD error = GetLastError();
        TerminateProcess(lease->process, 1);
        return terminal_fail(error);
    }

    if (ResumeThread(lease->primary_thread) == static_cast<DWORD>(-1)) {
        const DWORD error = GetLastError();
        TerminateJobObject(lease->job, 1);
        return terminal_fail(error);
    }

    *process_id_out = lease->process_id;
    *terminal_out = lease.release();
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_write(
    void* terminal,
    const void* data,
    DWORD size,
    DWORD* written_out) noexcept {
    auto* lease = checked_terminal(terminal);
    if (lease == nullptr || data == nullptr || written_out == nullptr ||
        size == 0 || size > kMaxTerminalIoBytes || lease->input_write == nullptr) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }

    *written_out = 0;
    return WriteFile(lease->input_write, data, size, written_out, nullptr);
}

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_read(
    void* terminal,
    void* buffer,
    DWORD capacity,
    DWORD* read_out) noexcept {
    auto* lease = checked_terminal(terminal);
    if (lease == nullptr || buffer == nullptr || read_out == nullptr ||
        capacity == 0 || capacity > kMaxTerminalIoBytes || lease->output_read == nullptr) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }

    *read_out = 0;
    return ReadFile(lease->output_read, buffer, capacity, read_out, nullptr);
}

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_resize(
    void* terminal,
    SHORT columns,
    SHORT rows) noexcept {
    auto* lease = checked_terminal(terminal);
    if (lease == nullptr || lease->pseudo_console == nullptr || columns <= 0 || rows <= 0) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }

    const HRESULT result = ResizePseudoConsole(lease->pseudo_console, COORD{columns, rows});
    if (FAILED(result)) return terminal_fail(HRESULT_CODE(result));
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_get_exit_code(
    void* terminal,
    DWORD* exit_code_out,
    BOOL* exited_out) noexcept {
    auto* lease = checked_terminal(terminal);
    if (lease == nullptr || exit_code_out == nullptr || exited_out == nullptr || lease->process == nullptr) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }

    DWORD exit_code = STILL_ACTIVE;
    if (!GetExitCodeProcess(lease->process, &exit_code)) return FALSE;
    *exit_code_out = exit_code;
    *exited_out = exit_code == STILL_ACTIVE ? FALSE : TRUE;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_terminate(
    void* terminal,
    DWORD exit_code) noexcept {
    auto* lease = checked_terminal(terminal);
    if (lease == nullptr || lease->job == nullptr) {
        return terminal_fail(ERROR_INVALID_PARAMETER);
    }
    return TerminateJobObject(lease->job, exit_code);
}

__declspec(dllexport) void WINAPI cloudos_native_terminal_release(void* terminal) noexcept {
    delete checked_terminal(terminal);
}

} // extern "C"
