#pragma once

#include <windows.h>

#include <cstdint>

namespace CloudOS::SupervisorProtocolV11
{
constexpr wchar_t SupervisedArgument[] = L"--supervised";
constexpr wchar_t ProbeFailureArgument[] = L"--supervisor-probe-fail";
constexpr wchar_t SupervisorMutexName[] = L"Local\\CloudOS.NativeShell.Supervisor.v11";
constexpr wchar_t HealthMappingName[] = L"Local\\CloudOS.NativeShell.Health.v9";
constexpr wchar_t DesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
constexpr wchar_t ExplorerTrayClass[] = L"Shell_TrayWnd";
constexpr UINT RequestGracefulExitMessage = WM_APP + 0x5B1;
constexpr std::uint32_t HealthMagic = 0x39484F43u;
constexpr std::uint32_t HealthSchema = 9u;
constexpr std::uint32_t HealthStructureSize = 96u;
constexpr std::uint32_t HealthReadyState = 2u;

struct NativeHealthSnapshotV9 final
{
    std::uint32_t magic{};
    std::uint32_t schema{};
    std::uint32_t structure_size{};
    std::uint32_t state{};
    std::uint32_t process_id{};
    std::uint32_t session_id{};
    std::uint32_t ui_thread_id{};
    std::uint32_t reserved0{};
    std::uint64_t sequence{};
    std::uint64_t started_tick_ms{};
    std::uint64_t ready_tick_ms{};
    std::uint64_t heartbeat_tick_ms{};
    std::uint64_t heartbeat_count{};
    std::uint64_t main_window_value{};
    std::uint32_t gdi_objects{};
    std::uint32_t user_objects{};
    std::uint32_t handle_count{};
    std::uint32_t reserved1{};
};

static_assert(sizeof(NativeHealthSnapshotV9) == HealthStructureSize);
} // namespace CloudOS::SupervisorProtocolV11
