#include "native_system_stats.h"

#include <algorithm>
#include <array>

namespace CloudOS
{
namespace
{
ULONGLONG s_previous_idle{};
ULONGLONG s_previous_kernel{};
ULONGLONG s_previous_user{};
bool s_have_cpu_sample{};

ULONGLONG ToUnsignedLongLong(const FILETIME& file_time) noexcept
{
    ULARGE_INTEGER value{};
    value.LowPart = file_time.dwLowDateTime;
    value.HighPart = file_time.dwHighDateTime;
    return value.QuadPart;
}

std::wstring WindowsVolumeRoot()
{
    std::array<wchar_t, MAX_PATH> windows_directory{};
    const UINT length = GetWindowsDirectoryW(
        windows_directory.data(),
        static_cast<UINT>(windows_directory.size()));
    if (length == 0 || length >= windows_directory.size())
    {
        return L"C:\\";
    }

    std::array<wchar_t, MAX_PATH> volume_path{};
    if (GetVolumePathNameW(
            windows_directory.data(),
            volume_path.data(),
            static_cast<DWORD>(volume_path.size())))
    {
        return volume_path.data();
    }
    return L"C:\\";
}
}

SystemStats NativeSystemStats::Query()
{
    SystemStats stats{};

    FILETIME idle_file_time{};
    FILETIME kernel_file_time{};
    FILETIME user_file_time{};
    if (GetSystemTimes(&idle_file_time, &kernel_file_time, &user_file_time))
    {
        const ULONGLONG idle = ToUnsignedLongLong(idle_file_time);
        const ULONGLONG kernel = ToUnsignedLongLong(kernel_file_time);
        const ULONGLONG user = ToUnsignedLongLong(user_file_time);

        if (s_have_cpu_sample &&
            idle >= s_previous_idle &&
            kernel >= s_previous_kernel &&
            user >= s_previous_user)
        {
            const ULONGLONG idle_delta = idle - s_previous_idle;
            const ULONGLONG kernel_delta = kernel - s_previous_kernel;
            const ULONGLONG user_delta = user - s_previous_user;
            const ULONGLONG total_delta = kernel_delta + user_delta;

            if (total_delta > 0)
            {
                const ULONGLONG busy_delta =
                    total_delta > idle_delta ? total_delta - idle_delta : 0;
                stats.cpu_percent = static_cast<int>(
                    std::clamp<ULONGLONG>(
                        busy_delta * 100u / total_delta,
                        0u,
                        100u));
            }
        }

        s_previous_idle = idle;
        s_previous_kernel = kernel;
        s_previous_user = user;
        s_have_cpu_sample = true;
    }

    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory))
    {
        stats.ram_percent = static_cast<int>(memory.dwMemoryLoad);
        stats.ram_total_mb = memory.ullTotalPhys / (1024ull * 1024ull);
        stats.ram_used_mb =
            (memory.ullTotalPhys - memory.ullAvailPhys) / (1024ull * 1024ull);
    }

    ULARGE_INTEGER free_bytes{};
    ULARGE_INTEGER total_bytes{};
    ULARGE_INTEGER total_free_bytes{};
    const std::wstring system_volume = WindowsVolumeRoot();
    if (GetDiskFreeSpaceExW(
            system_volume.c_str(),
            &free_bytes,
            &total_bytes,
            &total_free_bytes))
    {
        stats.disk_free_gb = free_bytes.QuadPart / (1024ull * 1024ull * 1024ull);
        stats.disk_total_gb = total_bytes.QuadPart / (1024ull * 1024ull * 1024ull);
    }

    const ULONGLONG uptime_ms = GetTickCount64();
    const unsigned long long total_minutes = uptime_ms / (1000ull * 60ull);
    const unsigned long long hours = total_minutes / 60ull;
    const unsigned long long minutes = total_minutes % 60ull;
    wchar_t buffer[64]{};
    swprintf_s(buffer, L"%lluh %llum", hours, minutes);
    stats.uptime_str = buffer;

    return stats;
}

} // namespace CloudOS
