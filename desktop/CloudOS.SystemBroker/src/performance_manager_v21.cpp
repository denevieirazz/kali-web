#include "performance_manager_v21.h"
#include "event_bus_v21.h"

#include <algorithm>

namespace CloudOS
{

std::string PerformanceProfileToString(PerformanceProfile profile)
{
    switch (profile)
    {
        case PerformanceProfile::Economy:
            return "economy";
        case PerformanceProfile::Performance:
            return "performance";
        case PerformanceProfile::Balanced:
        default:
            return "balanced";
    }
}

bool StringToPerformanceProfile(const std::string& str, PerformanceProfile& out)
{
    if (str == "economy")
    {
        out = PerformanceProfile::Economy;
        return true;
    }
    if (str == "balanced")
    {
        out = PerformanceProfile::Balanced;
        return true;
    }
    if (str == "performance")
    {
        out = PerformanceProfile::Performance;
        return true;
    }
    return false;
}

JsonObject HardwareMetrics::ToJsonObject() const
{
    JsonObject obj;
    obj["profile"] = JsonValue(PerformanceProfileToString(current_profile));
    obj["totalRamMb"] = JsonValue(static_cast<int64_t>(total_ram_mb));
    obj["freeRamMb"] = JsonValue(static_cast<int64_t>(free_ram_mb));
    obj["memoryLoadPercent"] = JsonValue(static_cast<int64_t>(memory_load_percent));
    obj["cpuCores"] = JsonValue(static_cast<int64_t>(cpu_cores));
    obj["onBattery"] = JsonValue(on_battery);
    obj["batteryPercent"] = JsonValue(static_cast<int64_t>(battery_percent));
    obj["isLowEndHardware"] = JsonValue(is_low_end_hardware);
    return obj;
}

PerformanceManagerV21& PerformanceManagerV21::Instance()
{
    static PerformanceManagerV21 instance;
    return instance;
}

PerformanceManagerV21::PerformanceManagerV21()
{
    RefreshHardwareDetection();
}

void PerformanceManagerV21::RefreshHardwareDetection()
{
    MEMORYSTATUSEX mem_status{};
    mem_status.dwLength = sizeof(mem_status);
    if (GlobalMemoryStatusEx(&mem_status))
    {
        total_ram_mb_ = mem_status.ullTotalPhys / (1024ULL * 1024ULL);
    }
    else
    {
        total_ram_mb_ = 8192;
    }

    SYSTEM_INFO sys_info{};
    GetSystemInfo(&sys_info);
    cpu_cores_ = sys_info.dwNumberOfProcessors > 0 ? sys_info.dwNumberOfProcessors : 4;

    // A machine with <= 8 GB RAM or <= 4 CPU threads is classified as low-end
    is_low_end_hardware_ = (total_ram_mb_ <= 8192 || cpu_cores_ <= 4);

    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power) && power.ACLineStatus == 0)
    {
        // On battery power
        profile_.store(PerformanceProfile::Economy);
    }
    else if (is_low_end_hardware_)
    {
        // On low-end desktop/laptop, default to economy to preserve CPU and GPU
        profile_.store(PerformanceProfile::Economy);
    }
    else
    {
        profile_.store(PerformanceProfile::Balanced);
    }

    initialized_.store(true);
}

HardwareMetrics PerformanceManagerV21::GetMetrics()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load())
    {
        RefreshHardwareDetection();
    }

    HardwareMetrics metrics;
    metrics.total_ram_mb = total_ram_mb_;
    metrics.cpu_cores = cpu_cores_;
    metrics.is_low_end_hardware = is_low_end_hardware_;
    metrics.current_profile = profile_.load();

    MEMORYSTATUSEX mem_status{};
    mem_status.dwLength = sizeof(mem_status);
    if (GlobalMemoryStatusEx(&mem_status))
    {
        metrics.free_ram_mb = mem_status.ullAvailPhys / (1024ULL * 1024ULL);
        metrics.memory_load_percent = mem_status.dwMemoryLoad;
    }

    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power))
    {
        metrics.on_battery = (power.ACLineStatus == 0);
        metrics.battery_percent = (power.BatteryLifePercent != 255)
            ? static_cast<int>(power.BatteryLifePercent)
            : -1;
    }

    return metrics;
}

bool PerformanceManagerV21::SetProfile(PerformanceProfile profile)
{
    profile_.store(profile);

    JsonObject payload;
    payload["profile"] = JsonValue(PerformanceProfileToString(profile));
    payload["isLowEndHardware"] = JsonValue(is_low_end_hardware_);
    EventBusV21::Instance().Publish("system.performanceProfileChanged", payload);
    return true;
}

bool PerformanceManagerV21::SetProfileByName(const std::string& name)
{
    PerformanceProfile profile = PerformanceProfile::Balanced;
    if (!StringToPerformanceProfile(name, profile))
    {
        return false;
    }
    return SetProfile(profile);
}

} // namespace CloudOS
