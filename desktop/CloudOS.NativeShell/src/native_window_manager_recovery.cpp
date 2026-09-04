#include "native_window_manager.h"

#include <algorithm>
#include <utility>

namespace
{
RECT ValidRestoreBounds(HWND window, const RECT& requested)
{
    RECT target = requested;
    UINT dpi = window != nullptr && IsWindow(window) ? GetDpiForWindow(window) : 96u;
    if (dpi == 0) dpi = 96u;

    const int minimum_width = std::max(64, MulDiv(160, static_cast<int>(dpi), 96));
    const int minimum_height = std::max(48, MulDiv(120, static_cast<int>(dpi), 96));
    int width = std::max(minimum_width, static_cast<int>(requested.right - requested.left));
    int height = std::max(minimum_height, static_cast<int>(requested.bottom - requested.top));

    HMONITOR monitor = MonitorFromRect(&target, MONITOR_DEFAULTTONEAREST);
    if (monitor == nullptr)
        monitor = MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    RECT work{};
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
        work = info.rcWork;
    else if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0))
        work = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};

    const int work_width = std::max(1L, work.right - work.left);
    const int work_height = std::max(1L, work.bottom - work.top);
    width = std::min(width, work_width);
    height = std::min(height, work_height);

    // Keep at least a title-bar-sized strip reachable even when old coordinates
    // came from a disconnected monitor or a different RDP/DPI topology.
    const int reachable_x = std::max(32, MulDiv(96, static_cast<int>(dpi), 96));
    const int reachable_y = std::max(24, MulDiv(40, static_cast<int>(dpi), 96));
    int left = requested.left;
    int top = requested.top;
    if (left + reachable_x > work.right) left = work.right - reachable_x;
    if (left + width - reachable_x < work.left) left = work.left - width + reachable_x;
    if (top + reachable_y > work.bottom) top = work.bottom - reachable_y;
    if (top < work.top) top = work.top;

    // If the whole window fits, prefer keeping it completely inside the work area.
    if (width <= work_width)
        left = std::clamp(left, static_cast<int>(work.left), static_cast<int>(work.right - width));
    if (height <= work_height)
        top = std::clamp(top, static_cast<int>(work.top), static_cast<int>(work.bottom - height));

    return RECT{left, top, left + width, top + height};
}
}

std::vector<CloudOSManagedWindow> CloudOSNativeWindowManager::AllManagedWindows() const
{
    std::vector<CloudOSManagedWindow> result;
    result.reserve(windows_.size());
    for (const auto& item : windows_)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd))
        {
            continue;
        }
        CloudOSManagedWindow copy = item;
        const std::wstring title = ReadWindowTitle(item.hwnd);
        if (!title.empty())
        {
            copy.title = title;
        }
        result.push_back(std::move(copy));
    }
    return result;
}

int CloudOSNativeWindowManager::WorkspaceFor(HWND window) const noexcept
{
    const CloudOSManagedWindow* item = Find(window);
    return item != nullptr ? item->workspace : -1;
}

void CloudOSNativeWindowManager::SetWindowFloating(HWND window, bool floating)
{
    CloudOSManagedWindow* item = Find(window);
    if (item == nullptr && window != nullptr && IsWindow(window))
    {
        DWORD process_id = 0;
        GetWindowThreadProcessId(window, &process_id);
        AddOrRefresh(window, process_id);
        item = Find(window);
    }
    if (item == nullptr)
    {
        return;
    }

    item->floating = floating;
    if (tiling_enabled_ && !floating)
    {
        TileCurrentWorkspace();
    }
}

bool CloudOSNativeWindowManager::RestoreWindowState(
    HWND window,
    int workspace,
    bool floating,
    const RECT& bounds,
    UINT show_command)
{
    if (window == nullptr || !IsWindow(window))
    {
        return false;
    }

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    CloudOSManagedWindow* item = Find(window);
    if (item == nullptr)
    {
        AddOrRefresh(window, process_id);
        item = Find(window);
    }
    if (item == nullptr)
    {
        return false;
    }

    workspace = std::clamp(workspace, 0, 3);
    item->workspace = workspace;
    item->floating = floating;

    const RECT safe = ValidRestoreBounds(window, bounds);
    const int width = std::max<int>(1, static_cast<int>(safe.right - safe.left));
    const int height = std::max<int>(1, static_cast<int>(safe.bottom - safe.top));

    if (IsZoomed(window))
    {
        ShowWindow(window, SW_RESTORE);
    }
    (void)SetWindowPos(
        window,
        nullptr,
        safe.left,
        safe.top,
        width,
        height,
        SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE);

    item->bounds = safe;
    item->monitor = MonitorFromRect(&safe, MONITOR_DEFAULTTONEAREST);

    if (workspace != current_workspace_)
    {
        MarkWorkspaceHidden(window, true);
        item->hidden_by_workspace = true;
        ShowWindow(window, SW_HIDE);
    }
    else
    {
        MarkWorkspaceHidden(window, false);
        item->hidden_by_workspace = false;
        if (show_command == SW_SHOWMAXIMIZED)
        {
            ShowWindow(window, SW_MAXIMIZE);
        }
        else if (show_command == SW_SHOWMINIMIZED || show_command == SW_MINIMIZE)
        {
            ShowWindow(window, SW_MINIMIZE);
        }
        else
        {
            ShowWindow(window, SW_SHOWNOACTIVATE);
        }
    }

    UpdateBorders();
    NotifyChanged();
    return true;
}
