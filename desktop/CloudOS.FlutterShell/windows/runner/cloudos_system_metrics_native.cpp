#include "cloudos_system_metrics_native.h"

#include <psapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cmath>

namespace CloudOS
{

namespace
{

uint64_t FileTimeToUInt64(const FILETIME& ft)
{
    ULARGE_INTEGER uli;
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    return uli.QuadPart;
}

std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size, nullptr, nullptr);
    return result;
}

} // namespace

CloudOSSystemMetricsNative& CloudOSSystemMetricsNative::Instance()
{
    static CloudOSSystemMetricsNative instance;
    return instance;
}

CloudOSSystemMetricsNative::CloudOSSystemMetricsNative()
{
    GetSystemTimes(&prev_idle_time_, &prev_kernel_time_, &prev_user_time_);
    has_prev_times_ = true;
}

double CloudOSSystemMetricsNative::CalculateCpuLoad()
{
    FILETIME idle_time, kernel_time, user_time;
    if (!GetSystemTimes(&idle_time, &kernel_time, &user_time))
    {
        return 0.0;
    }

    if (!has_prev_times_)
    {
        prev_idle_time_ = idle_time;
        prev_kernel_time_ = kernel_time;
        prev_user_time_ = user_time;
        has_prev_times_ = true;
        return 0.0;
    }

    const uint64_t idle_diff = FileTimeToUInt64(idle_time) - FileTimeToUInt64(prev_idle_time_);
    const uint64_t kernel_diff = FileTimeToUInt64(kernel_time) - FileTimeToUInt64(prev_kernel_time_);
    const uint64_t user_diff = FileTimeToUInt64(user_time) - FileTimeToUInt64(prev_user_time_);

    prev_idle_time_ = idle_time;
    prev_kernel_time_ = kernel_time;
    prev_user_time_ = user_time;

    const uint64_t total_sys = kernel_diff + user_diff;
    if (total_sys == 0) return 0.0;

    const double cpu_busy = static_cast<double>(total_sys > idle_diff ? total_sys - idle_diff : 0);
    const double percent = (cpu_busy * 100.0) / static_cast<double>(total_sys);
    return std::clamp(std::round(percent * 10.0) / 10.0, 0.0, 100.0);
}

void CloudOSSystemMetricsNative::CollectMemory(NativeCompleteSystemMetrics& out_metrics)
{
    MEMORYSTATUSEX mem_info;
    mem_info.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&mem_info))
    {
        out_metrics.ram_total_mb = std::round((static_cast<double>(mem_info.ullTotalPhys) / (1024.0 * 1024.0)));
        out_metrics.ram_free_mb = std::round((static_cast<double>(mem_info.ullAvailPhys) / (1024.0 * 1024.0)));
        out_metrics.ram_used_mb = out_metrics.ram_total_mb - out_metrics.ram_free_mb;
        out_metrics.ram_percent = static_cast<double>(mem_info.dwMemoryLoad);
    }
}

void CloudOSSystemMetricsNative::CollectDisks(NativeCompleteSystemMetrics& out_metrics)
{
    // Detect Windows System Drive (e.g. C:)
    WCHAR sys_dir[MAX_PATH] = {0};
    if (GetSystemDirectoryW(sys_dir, MAX_PATH) > 0 && sys_dir[1] == L':')
    {
        out_metrics.system_drive = WideToUtf8(std::wstring(sys_dir, 2));
    }

    WCHAR drive_buffer[512] = {0};
    DWORD len = GetLogicalDriveStringsW(ARRAYSIZE(drive_buffer), drive_buffer);
    if (len == 0 || len > ARRAYSIZE(drive_buffer)) return;

    const WCHAR* p = drive_buffer;
    while (*p)
    {
        const UINT drive_type = GetDriveTypeW(p);
        if (drive_type == DRIVE_FIXED || drive_type == DRIVE_REMOVABLE)
        {
            ULARGE_INTEGER free_bytes_available, total_bytes, total_free_bytes;
            if (GetDiskFreeSpaceExW(p, &free_bytes_available, &total_bytes, &total_free_bytes))
            {
                NativeDiskInfo disk;
                std::wstring drive_str(p);
                // Trim trailing backslash for display e.g. "C:"
                if (drive_str.size() >= 2 && drive_str.back() == L'\\')
                {
                    drive_str.pop_back();
                }
                disk.name = WideToUtf8(drive_str);
                disk.total_gb = std::round((static_cast<double>(total_bytes.QuadPart) / (1024.0 * 1024.0 * 1024.0)) * 10.0) / 10.0;
                disk.free_gb = std::round((static_cast<double>(total_free_bytes.QuadPart) / (1024.0 * 1024.0 * 1024.0)) * 10.0) / 10.0;
                disk.used_gb = std::round((disk.total_gb - disk.free_gb) * 10.0) / 10.0;
                disk.percent_used = disk.total_gb > 0 ? std::round((disk.used_gb / disk.total_gb) * 100.0) : 0.0;

                out_metrics.disks.push_back(disk);
            }
        }
        p += wcslen(p) + 1;
    }
}

void CloudOSSystemMetricsNative::CollectTopProcesses(NativeCompleteSystemMetrics& out_metrics)
{
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return;

    PROCESSENTRY32W pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32W);

    std::vector<NativeProcessItem> proc_list;

    if (Process32FirstW(hSnap, &pe32))
    {
        do
        {
            if (pe32.th32ProcessID == 0) continue; // Skip System Idle

            HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe32.th32ProcessID);
            double mem_mb = 0.0;
            double cpu_seconds = 0.0;

            if (hProc != nullptr)
            {
                PROCESS_MEMORY_COUNTERS_EX pmc = {};
                if (GetProcessMemoryInfo(hProc, reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pmc), sizeof(pmc)))
                {
                    mem_mb = std::round((static_cast<double>(pmc.WorkingSetSize) / (1024.0 * 1024.0)) * 10.0) / 10.0;
                }

                FILETIME ftCreate, ftExit, ftKernel, ftUser;
                if (GetProcessTimes(hProc, &ftCreate, &ftExit, &ftKernel, &ftUser))
                {
                    const uint64_t total_time = FileTimeToUInt64(ftKernel) + FileTimeToUInt64(ftUser);
                    cpu_seconds = std::round((static_cast<double>(total_time) / 10000000.0) * 10.0) / 10.0;
                }

                CloseHandle(hProc);
            }

            NativeProcessItem item;
            item.pid = pe32.th32ProcessID;
            item.name = WideToUtf8(pe32.szExeFile);
            item.memory_mb = mem_mb;
            item.cpu_time_seconds = cpu_seconds;

            proc_list.push_back(item);

        } while (Process32NextW(hSnap, &pe32));
    }

    CloseHandle(hSnap);

    // Sort by memory descending
    std::sort(proc_list.begin(), proc_list.end(), [](const NativeProcessItem& a, const NativeProcessItem& b) {
        return a.memory_mb > b.memory_mb;
    });

    // Take top 15
    if (proc_list.size() > 15)
    {
        proc_list.resize(15);
    }

    out_metrics.top_processes = std::move(proc_list);
}

NativeCompleteSystemMetrics CloudOSSystemMetricsNative::CollectMetrics()
{
    NativeCompleteSystemMetrics metrics;
    metrics.cpu_load_percent = CalculateCpuLoad();
    CollectMemory(metrics);
    CollectDisks(metrics);
    metrics.uptime_seconds = GetTickCount64() / 1000;
    CollectTopProcesses(metrics);
    return metrics;
}

flutter::EncodableMap CloudOSSystemMetricsNative::ToEncodableMap(const NativeCompleteSystemMetrics& metrics)
{
    flutter::EncodableMap map;
    map[flutter::EncodableValue("cpuLoadPercent")] = flutter::EncodableValue(metrics.cpu_load_percent);
    map[flutter::EncodableValue("ramTotalMb")] = flutter::EncodableValue(metrics.ram_total_mb);
    map[flutter::EncodableValue("ramUsedMb")] = flutter::EncodableValue(metrics.ram_used_mb);
    map[flutter::EncodableValue("ramFreeMb")] = flutter::EncodableValue(metrics.ram_free_mb);
    map[flutter::EncodableValue("ramPercent")] = flutter::EncodableValue(metrics.ram_percent);
    map[flutter::EncodableValue("uptimeSeconds")] = flutter::EncodableValue(static_cast<int64_t>(metrics.uptime_seconds));
    map[flutter::EncodableValue("systemDrive")] = flutter::EncodableValue(metrics.system_drive);

    flutter::EncodableList disk_list;
    for (const auto& d : metrics.disks)
    {
        flutter::EncodableMap d_map;
        d_map[flutter::EncodableValue("name")] = flutter::EncodableValue(d.name);
        d_map[flutter::EncodableValue("totalGb")] = flutter::EncodableValue(d.total_gb);
        d_map[flutter::EncodableValue("usedGb")] = flutter::EncodableValue(d.used_gb);
        d_map[flutter::EncodableValue("freeGb")] = flutter::EncodableValue(d.free_gb);
        d_map[flutter::EncodableValue("percentUsed")] = flutter::EncodableValue(d.percent_used);
        disk_list.push_back(flutter::EncodableValue(std::move(d_map)));
    }
    map[flutter::EncodableValue("disks")] = flutter::EncodableValue(std::move(disk_list));

    flutter::EncodableList proc_list;
    for (const auto& p : metrics.top_processes)
    {
        flutter::EncodableMap p_map;
        p_map[flutter::EncodableValue("pid")] = flutter::EncodableValue(static_cast<int64_t>(p.pid));
        p_map[flutter::EncodableValue("name")] = flutter::EncodableValue(p.name);
        p_map[flutter::EncodableValue("memoryMb")] = flutter::EncodableValue(p.memory_mb);
        p_map[flutter::EncodableValue("cpuTimeSeconds")] = flutter::EncodableValue(p.cpu_time_seconds);
        proc_list.push_back(flutter::EncodableValue(std::move(p_map)));
    }
    map[flutter::EncodableValue("processes")] = flutter::EncodableValue(std::move(proc_list));

    return map;
}

} // namespace CloudOS
