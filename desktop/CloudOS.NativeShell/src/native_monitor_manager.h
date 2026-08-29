#pragma once

#include <windows.h>

#include <string>
#include <vector>

namespace CloudOS
{
struct NativeMonitorInfo final
{
    HMONITOR handle{};
    RECT monitor{};
    RECT work{};
    bool primary{};
    std::wstring device;
};

class NativeMonitorManager final
{
public:
    static std::vector<NativeMonitorInfo> Enumerate();
    static RECT VirtualBounds();
    static HMONITOR PrimaryMonitor();
    static std::wstring Signature();
    static bool MoveWindowToAdjacentMonitor(HWND window, int direction);
};
} // namespace CloudOS
