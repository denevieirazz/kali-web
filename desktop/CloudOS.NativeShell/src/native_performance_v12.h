#pragma once
#include <windows.h>
#include <cstdint>
#include <cwchar>

namespace CloudOS::PerformanceV12
{
enum Counter : unsigned { DesktopPaint, TaskbarPaint, StartPaint, QuickPaint, NotificationPaint,
    DesktopFullPaint, TaskbarFullPaint, RefreshShell, Reconcile, FilesystemScan, IconLoad,
    IconLoadInPaint, BackbufferAllocation, StartOpenUs, QuickOpenUs, Count };
struct alignas(8) Snapshot
{
    std::uint64_t version{12}, pid{}, heartbeat_tick{};
    volatile LONG64 counters[Count]{};
    volatile LONG64 paint_total_us[5]{};
    volatile LONG64 paint_max_us[5]{};
};
static_assert(sizeof(Snapshot)==224,"Update the V12 numeric reader when changing the layout");
inline Snapshot fallback;
inline Snapshot* state = &fallback;
inline HANDLE mapping{};
inline thread_local unsigned paint_depth{};
inline void Initialize()
{
    wchar_t name[96]{};
    swprintf_s(name, L"Local\\CloudOS.Performance.V12.%lu", GetCurrentProcessId());
    mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(Snapshot), name);
    if (mapping)
    {
        auto* view = static_cast<Snapshot*>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Snapshot)));
        if (view) { state = view; ZeroMemory(state, sizeof(Snapshot)); }
    }
    state->version = 12; state->pid = GetCurrentProcessId();
}
inline void Heartbeat() { InterlockedExchange64(reinterpret_cast<volatile LONG64*>(&state->heartbeat_tick), static_cast<LONG64>(GetTickCount64())); }
inline void Add(Counter counter, LONG64 amount = 1) { InterlockedExchangeAdd64(&state->counters[counter], amount); }
inline void Set(Counter counter, LONG64 value) { InterlockedExchange64(&state->counters[counter], value); }
inline void IconRead() { Add(IconLoad); if (paint_depth) Add(IconLoadInPaint); }
inline LONG64 NowUs()
{
    LARGE_INTEGER now{}, frequency{}; QueryPerformanceCounter(&now); QueryPerformanceFrequency(&frequency);
    return (now.QuadPart / frequency.QuadPart) * 1000000 + (now.QuadPart % frequency.QuadPart) * 1000000 / frequency.QuadPart;
}
class PaintScope final
{
    unsigned surface_; LONG64 begin_;
public:
    explicit PaintScope(Counter surface) : surface_(surface), begin_(NowUs()) { ++paint_depth; Add(surface); }
    ~PaintScope()
    {
        --paint_depth; const LONG64 elapsed = NowUs() - begin_;
        InterlockedExchangeAdd64(&state->paint_total_us[surface_], elapsed);
        auto* target = &state->paint_max_us[surface_]; LONG64 old = *target;
        while (elapsed > old) { const LONG64 actual = InterlockedCompareExchange64(target, elapsed, old); if (actual == old) break; old = actual; }
    }
};
}
