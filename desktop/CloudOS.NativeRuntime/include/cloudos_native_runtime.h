#pragma once

#include <Windows.h>
#include <cstdint>

#define CLOUDOS_NATIVE_RUNTIME_ABI 2u
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

// Real Windows surface operations. The Host validates the launch/session capability first;
// the C++ runtime then performs the Win32 mutation directly so Web/React never renders or
// forwards pixels for a native application.
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
