#include "../include/cloudos_native_runtime.h"

#include <algorithm>
#include <cwchar>
#include <limits>
#include <memory>
#include <new>
#include <vector>

namespace {

constexpr DWORD kCreateSuspended = CREATE_SUSPENDED;
constexpr DWORD kCreateUnicodeEnvironment = CREATE_UNICODE_ENVIRONMENT;
constexpr DWORD kKillOnJobClose = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
constexpr DWORD kPollMilliseconds = 20;

struct NativeLease final {
    HANDLE job = nullptr;
    HANDLE process = nullptr;
    HANDLE primary_thread = nullptr;
    DWORD process_id = 0;
    bool resumed = false;

    ~NativeLease() noexcept {
        if (primary_thread != nullptr) {
            CloseHandle(primary_thread);
            primary_thread = nullptr;
        }
        if (process != nullptr) {
            CloseHandle(process);
            process = nullptr;
        }
        if (job != nullptr) {
            // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is the final containment fail-safe.
            CloseHandle(job);
            job = nullptr;
        }
    }
};

struct JobProcessListBuffer final {
    DWORD assigned = 0;
    DWORD listed = 0;
    ULONG_PTR process_ids[CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES]{};
};

static_assert(offsetof(JobProcessListBuffer, process_ids) == 8u);

BOOL fail(DWORD error) noexcept {
    SetLastError(error == ERROR_SUCCESS ? ERROR_GEN_FAILURE : error);
    return FALSE;
}

NativeLease* checked_lease(void* opaque) noexcept {
    return static_cast<NativeLease*>(opaque);
}

BOOL configure_job(HANDLE job) noexcept {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION information{};
    information.BasicLimitInformation.LimitFlags = kKillOnJobClose;
    if (!SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &information,
            static_cast<DWORD>(sizeof(information)))) {
        return FALSE;
    }
    return TRUE;
}

BOOL query_job_members(
    NativeLease* lease,
    DWORD* output,
    DWORD capacity,
    DWORD* count_out) noexcept {
    if (lease == nullptr || count_out == nullptr) {
        return fail(ERROR_INVALID_PARAMETER);
    }

    JobProcessListBuffer storage{};
    auto* information = reinterpret_cast<JOBOBJECT_BASIC_PROCESS_ID_LIST*>(&storage);
    if (!QueryInformationJobObject(
            lease->job,
            JobObjectBasicProcessIdList,
            information,
            static_cast<DWORD>(sizeof(storage)),
            nullptr)) {
        return FALSE;
    }

    if (information->NumberOfAssignedProcesses > CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES ||
        information->NumberOfProcessIdsInList > CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES ||
        information->NumberOfProcessIdsInList > information->NumberOfAssignedProcesses) {
        return fail(ERROR_BUFFER_OVERFLOW);
    }

    if (information->NumberOfProcessIdsInList != information->NumberOfAssignedProcesses) {
        return fail(ERROR_MORE_DATA);
    }

    *count_out = information->NumberOfProcessIdsInList;
    if (output == nullptr) {
        return capacity == 0 ? TRUE : fail(ERROR_INVALID_PARAMETER);
    }
    if (capacity < information->NumberOfProcessIdsInList) {
        return fail(ERROR_MORE_DATA);
    }

    for (DWORD index = 0; index < information->NumberOfProcessIdsInList; ++index) {
        const ULONG_PTR raw = information->ProcessIdList[index];
        if (raw == 0 || raw > std::numeric_limits<DWORD>::max()) {
            return fail(ERROR_INVALID_DATA);
        }
        output[index] = static_cast<DWORD>(raw);
    }
    return TRUE;
}

void terminate_process_if_needed(HANDLE process) noexcept {
    if (process == nullptr) {
        return;
    }
    DWORD exit_code = STILL_ACTIVE;
    if (GetExitCodeProcess(process, &exit_code) && exit_code == STILL_ACTIVE) {
        TerminateProcess(process, 1);
    }
}

} // namespace

extern "C" {

std::uint32_t WINAPI cloudos_native_runtime_abi() noexcept {
    return CLOUDOS_NATIVE_RUNTIME_ABI;
}

BOOL WINAPI cloudos_native_launch_suspended(
    const wchar_t* executable,
    const wchar_t* command_line,
    void* environment_block,
    const wchar_t* working_directory,
    void** lease_out,
    DWORD* process_id_out) noexcept {
    if (executable == nullptr || *executable == L'\0' ||
        command_line == nullptr || *command_line == L'\0' ||
        working_directory == nullptr || *working_directory == L'\0' ||
        lease_out == nullptr || process_id_out == nullptr) {
        return fail(ERROR_INVALID_PARAMETER);
    }

    *lease_out = nullptr;
    *process_id_out = 0;

    try {
        std::unique_ptr<NativeLease> lease(new (std::nothrow) NativeLease());
        if (!lease) {
            return fail(ERROR_NOT_ENOUGH_MEMORY);
        }

        lease->job = CreateJobObjectW(nullptr, nullptr);
        if (lease->job == nullptr) {
            return FALSE;
        }
        if (!configure_job(lease->job)) {
            return FALSE;
        }

        const std::size_t length = std::wcslen(command_line);
        std::vector<wchar_t> mutable_command(length + 1u, L'\0');
        std::copy_n(command_line, length, mutable_command.data());

        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_HIDE;

        PROCESS_INFORMATION process_information{};
        if (!CreateProcessW(
                executable,
                mutable_command.data(),
                nullptr,
                nullptr,
                FALSE,
                kCreateSuspended | kCreateUnicodeEnvironment,
                environment_block,
                working_directory,
                &startup,
                &process_information)) {
            return FALSE;
        }

        lease->process = process_information.hProcess;
        lease->primary_thread = process_information.hThread;
        lease->process_id = process_information.dwProcessId;

        if (!AssignProcessToJobObject(lease->job, lease->process)) {
            const DWORD error = GetLastError();
            terminate_process_if_needed(lease->process);
            return fail(error);
        }

        *process_id_out = lease->process_id;
        *lease_out = lease.release();
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    } catch (...) {
        return fail(ERROR_GEN_FAILURE);
    }
}

BOOL WINAPI cloudos_native_resume(void* opaque) noexcept {
    NativeLease* lease = checked_lease(opaque);
    if (lease == nullptr) {
        return fail(ERROR_INVALID_HANDLE);
    }
    if (lease->resumed) {
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    }
    if (lease->primary_thread == nullptr) {
        return fail(ERROR_INVALID_HANDLE);
    }

    if (ResumeThread(lease->primary_thread) == static_cast<DWORD>(-1)) {
        return FALSE;
    }

    CloseHandle(lease->primary_thread);
    lease->primary_thread = nullptr;
    lease->resumed = true;
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

BOOL WINAPI cloudos_native_query_members(
    void* opaque,
    DWORD* process_ids,
    DWORD capacity,
    DWORD* process_count_out) noexcept {
    NativeLease* lease = checked_lease(opaque);
    return query_job_members(lease, process_ids, capacity, process_count_out);
}

BOOL WINAPI cloudos_native_terminate(
    void* opaque,
    DWORD timeout_milliseconds) noexcept {
    NativeLease* lease = checked_lease(opaque);
    if (lease == nullptr) {
        return fail(ERROR_INVALID_HANDLE);
    }

    if (!TerminateJobObject(lease->job, 1)) {
        const DWORD error = GetLastError();
        if (error != ERROR_ACCESS_DENIED) {
            return fail(error);
        }
    }

    const ULONGLONG deadline = GetTickCount64() + timeout_milliseconds;
    for (;;) {
        DWORD members[CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES]{};
        DWORD count = 0;
        if (!query_job_members(
                lease,
                members,
                CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES,
                &count)) {
            const DWORD error = GetLastError();
            // An already-torn-down Job is equivalent to successful termination.
            if (error == ERROR_INVALID_HANDLE) {
                SetLastError(ERROR_SUCCESS);
                return TRUE;
            }
            return fail(error);
        }
        if (count == 0) {
            SetLastError(ERROR_SUCCESS);
            return TRUE;
        }
        if (GetTickCount64() >= deadline) {
            return fail(ERROR_TIMEOUT);
        }
        Sleep(kPollMilliseconds);
    }
}

void WINAPI cloudos_native_release(void* opaque) noexcept {
    delete checked_lease(opaque);
}

} // extern "C"
