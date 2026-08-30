#include "native_monitor_manager.h"

#include <algorithm>
#include <sstream>

namespace CloudOS
{
namespace
{
BOOL CALLBACK EnumerateMonitor(
    HMONITOR monitor,
    HDC,
    LPRECT,
    LPARAM parameter)
{
    auto* result = reinterpret_cast<std::vector<NativeMonitorInfo>*>(parameter);
    if (result == nullptr)
    {
        return FALSE;
    }

    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info))
    {
        return TRUE;
    }

    NativeMonitorInfo item{};
    item.handle = monitor;
    item.monitor = info.rcMonitor;
    item.work = info.rcWork;
    item.primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    item.device = info.szDevice;
    result->push_back(std::move(item));
    return TRUE;
}

int CenterX(const RECT& rectangle) noexcept
{
    return rectangle.left + (rectangle.right - rectangle.left) / 2;
}

int CenterY(const RECT& rectangle) noexcept
{
    return rectangle.top + (rectangle.bottom - rectangle.top) / 2;
}
}

std::vector<NativeMonitorInfo> NativeMonitorManager::Enumerate()
{
    std::vector<NativeMonitorInfo> result;
    (void)EnumDisplayMonitors(
        nullptr,
        nullptr,
        &EnumerateMonitor,
        reinterpret_cast<LPARAM>(&result));

    std::stable_sort(
        result.begin(),
        result.end(),
        [](const NativeMonitorInfo& left, const NativeMonitorInfo& right)
        {
            if (left.primary != right.primary)
            {
                return left.primary;
            }
            if (left.monitor.left != right.monitor.left)
            {
                return left.monitor.left < right.monitor.left;
            }
            return left.monitor.top < right.monitor.top;
        });
    return result;
}

RECT NativeMonitorManager::VirtualBounds()
{
    RECT result{
        GetSystemMetrics(SM_XVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN),
        GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
        GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN),
    };

    if (result.right <= result.left || result.bottom <= result.top)
    {
        result = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    }
    return result;
}

HMONITOR NativeMonitorManager::PrimaryMonitor()
{
    const auto monitors = Enumerate();
    for (const auto& monitor : monitors)
    {
        if (monitor.primary)
        {
            return monitor.handle;
        }
    }
    return MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
}

std::wstring NativeMonitorManager::Signature()
{
    std::wostringstream stream;
    for (const auto& item : Enumerate())
    {
        stream
            << item.device << L':'
            << item.monitor.left << L','
            << item.monitor.top << L','
            << item.monitor.right << L','
            << item.monitor.bottom << L';'
            << (item.primary ? L'P' : L'S') << L'|';
    }
    return stream.str();
}

bool NativeMonitorManager::MoveWindowToAdjacentMonitor(HWND window, int direction)
{
    if (window == nullptr || !IsWindow(window) || direction == 0)
    {
        return false;
    }

    const auto monitors = Enumerate();
    if (monitors.size() < 2)
    {
        return false;
    }

    const HMONITOR current_handle = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    const auto current_iterator = std::find_if(
        monitors.begin(),
        monitors.end(),
        [current_handle](const NativeMonitorInfo& item)
        {
            return item.handle == current_handle;
        });
    if (current_iterator == monitors.end())
    {
        return false;
    }

    const int current_x = CenterX(current_iterator->monitor);
    const int current_y = CenterY(current_iterator->monitor);

    const NativeMonitorInfo* best = nullptr;
    long long best_score = 0;
    for (const auto& candidate : monitors)
    {
        if (candidate.handle == current_handle)
        {
            continue;
        }

        const int dx = CenterX(candidate.monitor) - current_x;
        const int dy = CenterY(candidate.monitor) - current_y;
        if ((direction < 0 && dx >= 0) || (direction > 0 && dx <= 0))
        {
            continue;
        }

        const long long score =
            static_cast<long long>(std::abs(dx)) * 4LL +
            static_cast<long long>(std::abs(dy));
        if (best == nullptr || score < best_score)
        {
            best = &candidate;
            best_score = score;
        }
    }

    if (best == nullptr)
    {
        for (const auto& candidate : monitors)
        {
            if (candidate.handle == current_handle)
            {
                continue;
            }
            if (best == nullptr ||
                (direction < 0
                    ? candidate.monitor.left < best->monitor.left
                    : candidate.monitor.left > best->monitor.left))
            {
                best = &candidate;
            }
        }
    }

    if (best == nullptr)
    {
        return false;
    }

    WINDOWPLACEMENT placement{};
    placement.length = sizeof(placement);
    if (!GetWindowPlacement(window, &placement))
    {
        return false;
    }

    const bool maximized = placement.showCmd == SW_SHOWMAXIMIZED || IsZoomed(window);
    if (maximized)
    {
        ShowWindow(window, SW_RESTORE);
    }

    RECT bounds{};
    if (!GetWindowRect(window, &bounds))
    {
        return false;
    }

    const RECT source_work = current_iterator->work;
    const RECT target_work = best->work;
    const int source_width = std::max(1L, source_work.right - source_work.left);
    const int source_height = std::max(1L, source_work.bottom - source_work.top);
    const int target_width = std::max(1L, target_work.right - target_work.left);
    const int target_height = std::max(1L, target_work.bottom - target_work.top);
    const int width = std::min<int>(bounds.right - bounds.left, target_width);
    const int height = std::min<int>(bounds.bottom - bounds.top, target_height);

    const double relative_x = static_cast<double>(bounds.left - source_work.left) /
        static_cast<double>(source_width);
    const double relative_y = static_cast<double>(bounds.top - source_work.top) /
        static_cast<double>(source_height);

    int x = target_work.left + static_cast<int>(relative_x * target_width);
    int y = target_work.top + static_cast<int>(relative_y * target_height);
    x = std::clamp<int>(x, static_cast<int>(target_work.left), std::max<int>(static_cast<int>(target_work.left), static_cast<int>(target_work.right - width)));
    y = std::clamp<int>(y, static_cast<int>(target_work.top), std::max<int>(static_cast<int>(target_work.top), static_cast<int>(target_work.bottom - height)));

    (void)SetWindowPos(
        window,
        HWND_TOP,
        x,
        y,
        width,
        height,
        SWP_NOOWNERZORDER | SWP_SHOWWINDOW);

    if (maximized)
    {
        ShowWindow(window, SW_MAXIMIZE);
    }
    return true;
}
} // namespace CloudOS
