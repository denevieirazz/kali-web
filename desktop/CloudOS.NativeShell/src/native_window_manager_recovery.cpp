#include "native_window_manager.h"

#include <algorithm>
#include <utility>

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

    const int width = std::max<int>(64, static_cast<int>(bounds.right - bounds.left));
    const int height = std::max<int>(48, static_cast<int>(bounds.bottom - bounds.top));

    if (IsZoomed(window))
    {
        ShowWindow(window, SW_RESTORE);
    }
    (void)SetWindowPos(
        window,
        nullptr,
        bounds.left,
        bounds.top,
        width,
        height,
        SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE);

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
