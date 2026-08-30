#include "native_window_manager.h"

#include "native_workspace_studio_service.h"

#include <algorithm>

CloudOSNativeWindowManager::CloudOSNativeWindowManager()
{
    CloudOS::NativeWorkspaceStudioService::RegisterManager(this);
}

void CloudOSNativeWindowManager::SetTilingEnabled(bool enabled)
{
    if (tiling_enabled_ == enabled)
    {
        if (enabled)
        {
            TileCurrentWorkspace();
        }
        return;
    }
    tiling_enabled_ = enabled;
    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
    UpdateBorders();
}

void CloudOSNativeWindowManager::MoveWindowToWorkspace(HWND window, int workspace)
{
    workspace = std::clamp(workspace, 0, 3);
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }

    CloudOSManagedWindow* item = Find(window);
    if (item == nullptr)
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

    if (item->workspace == workspace)
    {
        if (workspace == current_workspace_ && item->hidden_by_workspace)
        {
            MarkWorkspaceHidden(window, false);
            item->hidden_by_workspace = false;
            if (!IsIconic(window))
            {
                ShowWindow(window, SW_SHOWNOACTIVATE);
            }
        }
        return;
    }

    item->workspace = workspace;
    if (workspace != current_workspace_)
    {
        MarkWorkspaceHidden(window, true);
        item->hidden_by_workspace = true;
        ShowWindow(window, SW_HIDE);
        if (active_window_ == window)
        {
            active_window_ = nullptr;
        }
    }
    else
    {
        MarkWorkspaceHidden(window, false);
        item->hidden_by_workspace = false;
        if (!IsWindowVisible(window) && !IsIconic(window))
        {
            ShowWindow(window, SW_SHOWNOACTIVATE);
        }
    }

    if (tiling_enabled_)
    {
        TileCurrentWorkspace();
    }
    UpdateBorders();
}
