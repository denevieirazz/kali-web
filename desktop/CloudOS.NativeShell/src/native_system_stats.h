#pragma once

#include <windows.h>
#include <string>

namespace CloudOS
{
struct SystemStats final
{
    int cpu_percent{0};
    int ram_percent{0};
    unsigned long long ram_used_mb{0};
    unsigned long long ram_total_mb{0};
    unsigned long long disk_free_gb{0};
    unsigned long long disk_total_gb{0};
    std::wstring uptime_str;
};

class NativeSystemStats final
{
public:
    static SystemStats Query();
};
} // namespace CloudOS
