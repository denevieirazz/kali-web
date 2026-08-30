#pragma once

#include <functional>

namespace CloudOS
{
class NativeShellBridge final
{
public:
    using Callback = std::function<void()>;

    static void SetWorkspaceOverviewCallback(Callback callback);
    static void SetShowDesktopCallback(Callback callback);
    static bool OpenWorkspaceOverview();
    static bool ToggleShowDesktop();
    static void Clear() noexcept;
};
} // namespace CloudOS
