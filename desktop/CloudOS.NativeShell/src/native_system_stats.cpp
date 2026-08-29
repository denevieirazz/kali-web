#include "native_system_stats.h"
#include <algorithm>

namespace CloudOS
{
static ULONGLONG s_prev_idle = 0;
static ULONGLONG s_prev_kernel = 0;
static ULONGLONG s_prev_user = 0;

static ULONGLONG ToUll(const FILETIME& ft)
{
    ULARGE_INTEGER li;
    li.LowPart = ft.dwLowDateTime;
    li.HighPart = ft.dwHighDateTime;
    return li.QuadPart;
}

SystemStats NativeSystemStats::Query()
{
    SystemStats stats{};

    // CPU
    FILETIME idle_ft{}, kernel_ft{}, user_ft{};
    if (GetSystemTimes(&idle_ft, &kernel_ft, &user_ft))
    {
        ULONGLONG idle = ToUll(idle_ft);
        ULONGLONG kernel = ToUll(kernel_ft);
        ULONGLONG user = ToUll(user_ft);

        ULONGLONG usr_diff = user - s_prev_user;
        ULONGLONG ker_diff = kernel - s_prev_kernel;
        ULONGLONG idl_diff = idle - s_prev_idle;
        ULONGLONG total = usr_diff + ker_diff;

        s_prev_idle = idle;
        s_prev_kernel = kernel;
        s_prev_user = user;

        if (total > 0)
        {
            stats.cpu_percent = static_cast<int>(std::clamp<ULONGLONG>((total - idl_diff) * 100 / total, 0, 100));
        }
        else
        {
            stats.cpu_percent = 24;
        }
    }

    // RAM
    MEMORYSTATUSEX mem{};
    mem.dwLength = sizeof(mem);
    if (GlobalMemoryStatusEx(&mem))
    {
        stats.ram_percent = static_cast<int>(mem.dwMemoryLoad);
        stats.ram_total_mb = mem.ullTotalPhys / (1024 * 1024);
        stats.ram_used_mb = (mem.ullTotalPhys - mem.ullAvailPhys) / (1024 * 1024);
    }

    // Disk C:
    ULARGE_INTEGER free_bytes{}, total_bytes{}, total_free{};
    if (GetDiskFreeSpaceExW(L"C:\\", &free_bytes, &total_bytes, &total_free))
    {
        stats.disk_free_gb = free_bytes.QuadPart / (1024 * 1024 * 1024);
        stats.disk_total_gb = total_bytes.QuadPart / (1024 * 1024 * 1024);
    }

    // Uptime
    ULONGLONG uptime_ms = GetTickCount64();
    unsigned long hours = static_cast<unsigned long>(uptime_ms / (1000 * 60 * 60));
    unsigned long minutes = static_cast<unsigned long>((uptime_ms / (1000 * 60)) % 60);
    wchar_t buf[64]{};
    swprintf_s(buf, L"%luh %lum", hours, minutes);
    stats.uptime_str = buf;

    return stats;
}

} // namespace CloudOS
