#pragma once

#include <cmath>
#include <utility>

#include "native_workspace_automation.h"

namespace CloudOS
{
inline WorkspaceWindowIdentity IdentifyWindow(HWND window, DWORD process_id = 0)
{
    return NativeWorkspaceAutomationEngine::IdentifyWindow(window, process_id);
}
} // namespace CloudOS
