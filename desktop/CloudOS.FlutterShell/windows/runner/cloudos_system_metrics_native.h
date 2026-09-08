#pragma once

#include <Windows.h>
#include <flutter/encodable_value.h>

#include <cstdint>
#include <string>
#include <vector>

namespace CloudOS
{

struct NativeDiskInfo
{
    std::string name;
    double total_gb{0.0};
    double used_gb{0.0};
    double free_gb{0.0};
    double percent_used{0.0};
};

struct NativeProcessItem
{
    DWORD pid{0};
    std::string name;
    double memory_mb{0.0};
    double cpu_time_seconds{0.0};
};

struct NativeCompleteSystemMetrics
{
    double cpu_load_percent{0.0};
    double ram_total_mb{0.0};
    double ram_used_mb{0.0};
    double ram_free_mb{0.0};
    double ram_percent{0.0};
    uint64_t uptime_seconds{0};
    std::string system_drive;
    std::vector<NativeDiskInfo> disks;
    std::vector<NativeProcessItem> top_processes;
};

class CloudOSSystemMetricsNative final
{
public:
    static CloudOSSystemMetricsNative& Instance();

    CloudOSSystemMetricsNative(const CloudOSSystemMetricsNative&) = delete;
    CloudOSSystemMetricsNative& operator=(const CloudOSSystemMetricsNative&) = delete;

    NativeCompleteSystemMetrics CollectMetrics();
    flutter::EncodableMap ToEncodableMap(const NativeCompleteSystemMetrics& metrics);

private:
    CloudOSSystemMetricsNative();
    ~CloudOSSystemMetricsNative() = default;

    double CalculateCpuLoad();
    void CollectMemory(NativeCompleteSystemMetrics& out_metrics);
    void CollectDisks(NativeCompleteSystemMetrics& out_metrics);
    void CollectTopProcesses(NativeCompleteSystemMetrics& out_metrics);

    FILETIME prev_idle_time_{};
    FILETIME prev_kernel_time_{};
    FILETIME prev_user_time_{};
    bool has_prev_times_{false};
};

} // namespace CloudOS
