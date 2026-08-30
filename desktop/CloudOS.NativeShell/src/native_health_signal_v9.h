#pragma once

#include <windows.h>

#include <cstdint>

namespace CloudOS
{
enum class NativeHealthStateV9 : std::uint32_t
{
    Starting = 1,
    Ready = 2,
    ShuttingDown = 3,
};

// Fixed binary ABI consumed by scripts/native/native-health-v9.ps1.
// Keep this structure POD, pointer-free and exactly 96 bytes so external
// diagnostics can read it without loading CloudOS code into another process.
struct alignas(8) NativeHealthSnapshotV9 final
{
    std::uint32_t magic{};               // 0  = 'COH9' (0x39484F43)
    std::uint32_t schema{};              // 4  = 9
    std::uint32_t structure_size{};      // 8  = sizeof(NativeHealthSnapshotV9)
    std::uint32_t state{};               // 12 = NativeHealthStateV9
    std::uint32_t process_id{};          // 16
    std::uint32_t session_id{};          // 20
    std::uint32_t ui_thread_id{};        // 24
    std::uint32_t reserved0{};           // 28
    volatile LONG64 sequence{};          // 32 = seqlock; even means stable
    std::uint64_t started_tick_ms{};     // 40 = GetTickCount64 domain
    std::uint64_t ready_tick_ms{};       // 48
    std::uint64_t heartbeat_tick_ms{};   // 56
    std::uint64_t heartbeat_count{};     // 64
    std::uint64_t main_window_value{};   // 72 = HWND as integer, no title/content
    std::uint32_t gdi_objects{};         // 80
    std::uint32_t user_objects{};        // 84
    std::uint32_t handle_count{};        // 88
    std::uint32_t reserved1{};           // 92
};
static_assert(sizeof(NativeHealthSnapshotV9) == 96);

class NativeHealthSignalV9 final
{
public:
    static constexpr wchar_t MappingName[] = L"Local\\CloudOS.NativeShell.Health.v9";
    static constexpr wchar_t ReadyEventName[] = L"Local\\CloudOS.NativeShell.Ready.v9";
    static constexpr std::uint32_t Magic = 0x39484F43u;
    static constexpr std::uint32_t Schema = 9u;

    NativeHealthSignalV9() = default;
    ~NativeHealthSignalV9() { Shutdown(); }

    NativeHealthSignalV9(const NativeHealthSignalV9&) = delete;
    NativeHealthSignalV9& operator=(const NativeHealthSignalV9&) = delete;

    bool Initialize() noexcept
    {
        Shutdown();

        DWORD session_id = 0;
        if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id))
        {
            return false;
        }

        mapping_ = CreateFileMappingW(
            INVALID_HANDLE_VALUE,
            nullptr,
            PAGE_READWRITE,
            0,
            static_cast<DWORD>(sizeof(NativeHealthSnapshotV9)),
            MappingName);
        if (mapping_ == nullptr)
        {
            return false;
        }

        snapshot_ = static_cast<NativeHealthSnapshotV9*>(MapViewOfFile(
            mapping_,
            FILE_MAP_ALL_ACCESS,
            0,
            0,
            sizeof(NativeHealthSnapshotV9)));
        if (snapshot_ == nullptr)
        {
            CloseHandle(mapping_);
            mapping_ = nullptr;
            return false;
        }

        ready_event_ = CreateEventW(nullptr, TRUE, FALSE, ReadyEventName);
        if (ready_event_ == nullptr)
        {
            UnmapViewOfFile(snapshot_);
            snapshot_ = nullptr;
            CloseHandle(mapping_);
            mapping_ = nullptr;
            return false;
        }

        ResetEvent(ready_event_);
        ZeroMemory(snapshot_, sizeof(*snapshot_));
        snapshot_->magic = Magic;
        snapshot_->schema = Schema;
        snapshot_->structure_size = static_cast<std::uint32_t>(sizeof(*snapshot_));
        snapshot_->state = static_cast<std::uint32_t>(NativeHealthStateV9::Starting);
        snapshot_->process_id = GetCurrentProcessId();
        snapshot_->session_id = session_id;
        snapshot_->ui_thread_id = GetCurrentThreadId();
        snapshot_->started_tick_ms = GetTickCount64();
        snapshot_->heartbeat_tick_ms = snapshot_->started_tick_ms;
        RefreshResources();
        return true;
    }

    void MarkReady(HWND main_window) noexcept
    {
        if (snapshot_ == nullptr) return;
        const std::uint64_t now = GetTickCount64();
        BeginWrite();
        snapshot_->state = static_cast<std::uint32_t>(NativeHealthStateV9::Ready);
        if (snapshot_->ready_tick_ms == 0)
        {
            snapshot_->ready_tick_ms = now;
        }
        snapshot_->heartbeat_tick_ms = now;
        ++snapshot_->heartbeat_count;
        snapshot_->main_window_value = static_cast<std::uint64_t>(
            reinterpret_cast<std::uintptr_t>(main_window));
        RefreshResources();
        EndWrite();
        SetEvent(ready_event_);
    }

    void Pulse(HWND main_window) noexcept
    {
        if (snapshot_ == nullptr) return;
        BeginWrite();
        snapshot_->heartbeat_tick_ms = GetTickCount64();
        ++snapshot_->heartbeat_count;
        snapshot_->main_window_value = static_cast<std::uint64_t>(
            reinterpret_cast<std::uintptr_t>(main_window));
        RefreshResources();
        EndWrite();
    }

    void MarkShuttingDown(HWND main_window) noexcept
    {
        if (snapshot_ == nullptr) return;
        BeginWrite();
        snapshot_->state = static_cast<std::uint32_t>(NativeHealthStateV9::ShuttingDown);
        snapshot_->heartbeat_tick_ms = GetTickCount64();
        ++snapshot_->heartbeat_count;
        snapshot_->main_window_value = static_cast<std::uint64_t>(
            reinterpret_cast<std::uintptr_t>(main_window));
        RefreshResources();
        EndWrite();
    }

    void Shutdown() noexcept
    {
        if (ready_event_ != nullptr)
        {
            ResetEvent(ready_event_);
            CloseHandle(ready_event_);
            ready_event_ = nullptr;
        }
        if (snapshot_ != nullptr)
        {
            UnmapViewOfFile(snapshot_);
            snapshot_ = nullptr;
        }
        if (mapping_ != nullptr)
        {
            CloseHandle(mapping_);
            mapping_ = nullptr;
        }
    }

    [[nodiscard]] bool Active() const noexcept { return snapshot_ != nullptr; }

private:
    void BeginWrite() noexcept
    {
        (void)InterlockedIncrement64(&snapshot_->sequence);
        MemoryBarrier();
    }

    void EndWrite() noexcept
    {
        MemoryBarrier();
        (void)InterlockedIncrement64(&snapshot_->sequence);
    }

    void RefreshResources() noexcept
    {
        if (snapshot_ == nullptr) return;
        HANDLE process = GetCurrentProcess();
        snapshot_->gdi_objects = GetGuiResources(process, GR_GDIOBJECTS);
        snapshot_->user_objects = GetGuiResources(process, GR_USEROBJECTS);
        DWORD handles = 0;
        if (GetProcessHandleCount(process, &handles))
        {
            snapshot_->handle_count = handles;
        }
    }

    HANDLE mapping_{};
    HANDLE ready_event_{};
    NativeHealthSnapshotV9* snapshot_{};
};
} // namespace CloudOS
