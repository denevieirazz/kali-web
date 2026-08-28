#pragma once

#include <Windows.h>
#include <cstdint>

#define CLOUDOS_NATIVE_RUNTIME_ABI 1u
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

}
