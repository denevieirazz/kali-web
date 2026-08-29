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
constexpr LONG_PTR kForbiddenFrameStyles = WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
constexpr int kBoundsTolerance = 4;

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

BOOL valid_bounds(int x, int y, int width, int height) noexcept {
    return width >= 32 && height >= 32 && width <= 32768 && height <= 32768
        && x >= -131072 && x <= 131072 && y >= -131072 && y <= 131072;
}

BOOL validate_owner(HWND owner) noexcept {
    if (owner == nullptr || !IsWindow(owner)) {
        return fail(ERROR_INVALID_WINDOW_HANDLE);
    }
    DWORD owner_process_id = 0;
    GetWindowThreadProcessId(owner, &owner_process_id);
    if (owner_process_id == 0 || owner_process_id != GetCurrentProcessId()) {
        return fail(ERROR_ACCESS_DENIED);
    }
    return TRUE;
}

BOOL set_window_long_checked(HWND window, int index, LONG_PTR value) noexcept {
    SetLastError(ERROR_SUCCESS);
    const LONG_PTR previous = SetWindowLongPtrW(window, index, value);
    const DWORD error = GetLastError();
    if (previous == 0 && error != ERROR_SUCCESS) {
        return fail(error);
    }
    return TRUE;
}

BOOL restore_window(HWND window, DWORD timeout_milliseconds) noexcept {
    if (!IsWindow(window)) return fail(ERROR_INVALID_WINDOW_HANDLE);
    if (!IsIconic(window) && !IsZoomed(window)) return TRUE;

    DWORD_PTR result = 0;
    if (SendMessageTimeoutW(
            window,
            WM_SYSCOMMAND,
            static_cast<WPARAM>(SC_RESTORE),
            0,
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            timeout_milliseconds,
            &result) == 0) {
        const DWORD error = GetLastError();
        return fail(error == ERROR_SUCCESS ? ERROR_TIMEOUT : error);
    }
    if (!IsWindow(window) || IsIconic(window) || IsZoomed(window)) {
        return fail(ERROR_TIMEOUT);
    }
    return TRUE;
}

BOOL validate_window_surface(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    BOOL visible) noexcept {
    if (!IsWindow(window)) return fail(ERROR_INVALID_WINDOW_HANDLE);
    if (!validate_owner(owner)) return FALSE;
    if (GetWindow(window, GW_OWNER) != owner) return fail(ERROR_INVALID_STATE);
    if (GetWindowLongPtrW(window, GWL_STYLE) != expected_style) return fail(ERROR_INVALID_STATE);
    if (GetWindowLongPtrW(window, GWL_EXSTYLE) != expected_extended_style) return fail(ERROR_INVALID_STATE);

    if (!IsIconic(window)) {
        RECT actual{};
        if (!GetWindowRect(window, &actual)) return FALSE;
        if (actual.left < x - kBoundsTolerance || actual.top < y - kBoundsTolerance
            || actual.right > x + width + kBoundsTolerance
            || actual.bottom > y + height + kBoundsTolerance) {
            return fail(ERROR_INVALID_STATE);
        }
        if ((IsWindowVisible(window) ? TRUE : FALSE) != visible) {
            return fail(ERROR_INVALID_STATE);
        }
    }
    return TRUE;
}

BOOL apply_window_layout(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    BOOL visible,
    BOOL frame_changed,
    BOOL preserve_minimized) noexcept {
    if (!IsWindow(window)) return fail(ERROR_INVALID_WINDOW_HANDLE);
    if (!validate_owner(owner)) return FALSE;
    if (!valid_bounds(x, y, width, height)) return fail(ERROR_INVALID_PARAMETER);
    if (GetWindow(window, GW_OWNER) != owner) return fail(ERROR_INVALID_STATE);

    if (preserve_minimized && IsIconic(window)) {
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    }

    const LONG_PTR current_style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR current_extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if (frame_changed) {
        if ((current_style & kForbiddenFrameStyles) != 0) return fail(ERROR_INVALID_STATE);
        if ((current_extended_style & WS_EX_APPWINDOW) != 0
            || (current_extended_style & WS_EX_TOOLWINDOW) == 0) {
            return fail(ERROR_INVALID_STATE);
        }
    } else if (current_style != expected_style || current_extended_style != expected_extended_style) {
        return fail(ERROR_INVALID_STATE);
    }

    UINT flags = SWP_NOACTIVATE | SWP_NOOWNERZORDER | (visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW);
    if (frame_changed) flags |= SWP_FRAMECHANGED;
    if (!visible) flags |= SWP_NOZORDER;
    if (!SetWindowPos(
            window,
            visible ? HWND_TOP : nullptr,
            x,
            y,
            width,
            height,
            flags)) {
        return FALSE;
    }

    const LONG_PTR current_style_after_frame = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR current_extended_style_after_frame = GetWindowLongPtrW(window, GWL_EXSTYLE);

    // SWP_FRAMECHANGED is allowed to normalize otherwise harmless style bits. On the
    // initial attach validate containment invariants and let the caller persist the
    // actual post-frame styles. Subsequent layout/focus calls require exact equality.
    if (frame_changed) {
        if (GetWindow(window, GW_OWNER) != owner) return fail(ERROR_INVALID_STATE);
        if ((current_style_after_frame & kForbiddenFrameStyles) != 0) return fail(ERROR_INVALID_STATE);
        if ((current_extended_style_after_frame & WS_EX_APPWINDOW) != 0
            || (current_extended_style_after_frame & WS_EX_TOOLWINDOW) == 0) {
            return fail(ERROR_INVALID_STATE);
        }
        if (!IsIconic(window)) {
            RECT actual{};
            if (!GetWindowRect(window, &actual)) return FALSE;
            if (actual.left < x - kBoundsTolerance || actual.top < y - kBoundsTolerance
                || actual.right > x + width + kBoundsTolerance
                || actual.bottom > y + height + kBoundsTolerance) {
                return fail(ERROR_INVALID_STATE);
            }
            if ((IsWindowVisible(window) ? TRUE : FALSE) != visible) {
                return fail(ERROR_INVALID_STATE);
            }
        }
        SetLastError(ERROR_SUCCESS);
        return TRUE;
    }

    // marker: frame_changed ? current_style_after_frame
    return validate_window_surface(
        window,
        owner,
        expected_style,
        expected_extended_style,
        x,
        y,
        width,
        height,
        visible);
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

BOOL WINAPI cloudos_native_window_attach(
    HWND window,
    HWND owner,
    int x,
    int y,
    int width,
    int height,
    BOOL visible,
    LONG_PTR* applied_style_out,
    LONG_PTR* applied_extended_style_out) noexcept {
    if (window == nullptr || applied_style_out == nullptr || applied_extended_style_out == nullptr) {
        return fail(ERROR_INVALID_PARAMETER);
    }
    if (!IsWindow(window)) return fail(ERROR_INVALID_WINDOW_HANDLE);
    if (!validate_owner(owner)) return FALSE;
    if (!valid_bounds(x, y, width, height)) return fail(ERROR_INVALID_PARAMETER);
    if (GetAncestor(window, GA_ROOT) != window) return fail(ERROR_INVALID_STATE);

    const LONG_PTR original_style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR original_extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    const LONG_PTR attached_style = original_style & ~kForbiddenFrameStyles;
    const LONG_PTR attached_extended_style = (original_extended_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;

    ShowWindowAsync(window, SW_HIDE);
    if (!set_window_long_checked(window, GWL_STYLE, attached_style)) return FALSE;
    if (!set_window_long_checked(window, GWL_EXSTYLE, attached_extended_style)) return FALSE;
    if (!set_window_long_checked(window, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner))) return FALSE;

    if (GetWindow(window, GW_OWNER) != owner
        || (GetWindowLongPtrW(window, GWL_STYLE) & kForbiddenFrameStyles) != 0
        || (GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_APPWINDOW) != 0
        || (GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) == 0) {
        return fail(ERROR_INVALID_STATE);
    }

    if (!restore_window(window, 1500)) return FALSE;
    if (!apply_window_layout(
            window,
            owner,
            attached_style,
            attached_extended_style,
            x,
            y,
            width,
            height,
            visible,
            TRUE,
            FALSE)) {
        return FALSE;
    }

    *applied_style_out = GetWindowLongPtrW(window, GWL_STYLE);
    *applied_extended_style_out = GetWindowLongPtrW(window, GWL_EXSTYLE);
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

BOOL WINAPI cloudos_native_window_layout(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    BOOL visible,
    BOOL preserve_minimized) noexcept {
    return apply_window_layout(
        window,
        owner,
        expected_style,
        expected_extended_style,
        x,
        y,
        width,
        height,
        visible,
        FALSE,
        preserve_minimized);
}

BOOL WINAPI cloudos_native_window_focus(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    DWORD restore_timeout_milliseconds) noexcept {
    if (!restore_window(window, restore_timeout_milliseconds)) return FALSE;
    if (!apply_window_layout(
            window,
            owner,
            expected_style,
            expected_extended_style,
            x,
            y,
            width,
            height,
            TRUE,
            FALSE,
            FALSE)) {
        return FALSE;
    }
    if (!SetForegroundWindow(window)) return fail(ERROR_ACCESS_DENIED);
    SetLastError(ERROR_SUCCESS);
    return TRUE;
}

} // extern "C"
