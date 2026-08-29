#pragma once

#include <Windows.h>
#include <cstdint>

#define CLOUDOS_NATIVE_RUNTIME_ABI 3u
#define CLOUDOS_NATIVE_RUNTIME_MAX_PROCESSES 256u

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

// Real Windows surface operations. The native shell validates the session
// capability first; the C++ runtime then performs the Win32 mutation directly.
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
