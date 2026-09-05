#pragma once

#include "protocol_v21.h"

#include <Windows.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

namespace CloudOS
{

enum class PerformanceProfile
{
    Economy,
    Balanced,
    Performance
};

std::string PerformanceProfileToString(PerformanceProfile profile);
bool StringToPerformanceProfile(const std::string& str, PerformanceProfile& out);

struct HardwareMetrics final
{
    uint64_t total_ram_mb{0};
    uint64_t free_ram_mb{0};
    uint32_t memory_load_percent{0};
    uint32_t cpu_cores{0};
    bool on_battery{false};
    int battery_percent{-1};
    bool is_low_end_hardware{false};
    PerformanceProfile current_profile{PerformanceProfile::Balanced};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class PerformanceManagerV21 final
{
public:
    static PerformanceManagerV21& Instance();

    PerformanceManagerV21(const PerformanceManagerV21&) = delete;
    PerformanceManagerV21& operator=(const PerformanceManagerV21&) = delete;

    HardwareMetrics GetMetrics();
    [[nodiscard]] PerformanceProfile GetProfile() const noexcept { return profile_.load(); }
    bool SetProfile(PerformanceProfile profile);
    bool SetProfileByName(const std::string& name);

private:
    PerformanceManagerV21();
    ~PerformanceManagerV21() = default;

    void RefreshHardwareDetection();

    mutable std::mutex mutex_;
    std::atomic<PerformanceProfile> profile_{PerformanceProfile::Balanced};
    uint64_t total_ram_mb_{0};
    uint32_t cpu_cores_{0};
    bool is_low_end_hardware_{false};
    std::atomic_bool initialized_{false};
};

} // namespace CloudOS
