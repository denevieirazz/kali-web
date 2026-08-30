#include "native_shell_bridge.h"

#include <mutex>
#include <utility>

namespace CloudOS
{
namespace
{
std::mutex g_bridge_mutex;
NativeShellBridge::Callback g_workspace_overview_callback;
NativeShellBridge::Callback g_show_desktop_callback;

bool Invoke(const NativeShellBridge::Callback& callback)
{
    if (!callback)
    {
        return false;
    }
    callback();
    return true;
}
}

void NativeShellBridge::SetWorkspaceOverviewCallback(Callback callback)
{
    std::scoped_lock lock(g_bridge_mutex);
    g_workspace_overview_callback = std::move(callback);
}

void NativeShellBridge::SetShowDesktopCallback(Callback callback)
{
    std::scoped_lock lock(g_bridge_mutex);
    g_show_desktop_callback = std::move(callback);
}

bool NativeShellBridge::OpenWorkspaceOverview()
{
    Callback callback;
    {
        std::scoped_lock lock(g_bridge_mutex);
        callback = g_workspace_overview_callback;
    }
    return Invoke(callback);
}

bool NativeShellBridge::ToggleShowDesktop()
{
    Callback callback;
    {
        std::scoped_lock lock(g_bridge_mutex);
        callback = g_show_desktop_callback;
    }
    return Invoke(callback);
}

void NativeShellBridge::Clear() noexcept
{
    std::scoped_lock lock(g_bridge_mutex);
    g_workspace_overview_callback = {};
    g_show_desktop_callback = {};
}
} // namespace CloudOS
