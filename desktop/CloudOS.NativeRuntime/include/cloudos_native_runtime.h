#pragma once

#include <Windows.h>
#include <cstdint>

#define CLOUDOS_NATIVE_RUNTIME_ABI 4u
#define CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES 256u

typedef enum cloudos_native_window_event_kind : std::uint32_t {
    CLOUDOS_NATIVE_WINDOW_UNKNOWN = 0u,
    CLOUDOS_NATIVE_WINDOW_CREATED = 1u,
    CLOUDOS_NATIVE_WINDOW_DESTROYED = 2u,
    CLOUDOS_NATIVE_WINDOW_SHOWN = 3u,
    CLOUDOS_NATIVE_WINDOW_HIDDEN = 4u,
    CLOUDOS_NATIVE_WINDOW_FOREGROUND = 5u,
    CLOUDOS_NATIVE_WINDOW_LOCATION_CHANGED = 6u,
} cloudos_native_window_event_kind;

typedef void (CALLBACK* cloudos_native_window_event_callback)(
    cloudos_native_window_event_kind kind,
    HWND window,
    DWORD process_id,
    void* context);

typedef BOOL (CALLBACK* cloudos_native_window_enumeration_callback)(
    HWND window,
    DWORD process_id,
    BOOL visible,
    void* context);

extern "C" {

__declspec(dllexport) std::uint32_t WINAPI cloudos_native_runtime_abi() noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_launch_suspended(
    const wchar_t* executable,
    const wchar_t* command_line,
    void* environment_block,
    const wchar_t* working_directory,
    void** lease_out,
    DWORD* process_id_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_resume(
    void* lease) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_query_members(
    void* lease,
    DWORD* process_ids,
    DWORD capacity,
    DWORD* process_count_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminate(
    void* lease,
    DWORD timeout_milliseconds) noexcept;

__declspec(dllexport) void WINAPI cloudos_native_release(
    void* lease) noexcept;

// Native ConPTY terminal runtime. The terminal process is created suspended,
// assigned to a kill-on-close Job Object, and only then resumed. No browser,
// WebView, Node process, socket bridge, or JavaScript terminal is involved.
__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_create(
    const wchar_t* command_line,
    const wchar_t* working_directory,
    SHORT columns,
    SHORT rows,
    void** terminal_out,
    DWORD* process_id_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_write(
    void* terminal,
    const void* data,
    DWORD size,
    DWORD* written_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_read(
    void* terminal,
    void* buffer,
    DWORD capacity,
    DWORD* read_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_resize(
    void* terminal,
    SHORT columns,
    SHORT rows) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_get_exit_code(
    void* terminal,
    DWORD* exit_code_out,
    BOOL* exited_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_terminal_terminate(
    void* terminal,
    DWORD exit_code) noexcept;

__declspec(dllexport) void WINAPI cloudos_native_terminal_release(
    void* terminal) noexcept;

// Event-driven window discovery. The shell consumes real top-level Windows HWNDs
// instead of requiring arbitrary third-party applications to be reparented into a
// browser/XAML surface.
__declspec(dllexport) BOOL WINAPI cloudos_native_window_events_start(
    cloudos_native_window_event_callback callback,
    void* context,
    void** watcher_out) noexcept;

__declspec(dllexport) void WINAPI cloudos_native_window_events_stop(
    void* watcher) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_window_enumerate(
    cloudos_native_window_enumeration_callback callback,
    void* context) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_window_extended_frame_bounds(
    HWND window,
    RECT* bounds_out) noexcept;

// Legacy/direct window-surface operations retained as an opt-in compatibility path.
// They are not the universal application model of the native shell.
__declspec(dllexport) BOOL WINAPI cloudos_native_window_attach(
    HWND window,
    HWND owner,
    int x,
    int y,
    int width,
    int height,
    BOOL visible,
    LONG_PTR* applied_style_out,
    LONG_PTR* applied_extended_style_out) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_window_layout(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    BOOL visible,
    BOOL preserve_minimized) noexcept;

__declspec(dllexport) BOOL WINAPI cloudos_native_window_focus(
    HWND window,
    HWND owner,
    LONG_PTR expected_style,
    LONG_PTR expected_extended_style,
    int x,
    int y,
    int width,
    int height,
    DWORD restore_timeout_milliseconds) noexcept;

}
