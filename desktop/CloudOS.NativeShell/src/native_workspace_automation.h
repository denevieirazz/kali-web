#pragma once

#include <windows.h>

#include <array>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include "native_workspace_studio_model.h"

class CloudOSNativeWindowManager;

namespace CloudOS
{
struct WorkspaceWindowIdentity final
{
    HWND hwnd{};
    DWORD process_id{};
    std::wstring process_name;
    std::wstring window_title;
    std::wstring window_class;
};

struct WorkspaceFocusRecord final
{
    HWND hwnd{};
    DWORD process_id{};
    int workspace{};
    std::wstring process_name;
    std::wstring title;
    std::uint64_t touched_filetime{};
};

class NativeWorkspaceLayoutEngine final
{
public:
    static WorkspaceSnapshot Capture(
        CloudOSNativeWindowManager& manager,
        NativeWorkspaceStudioStore& store,
        int workspace,
        const std::wstring& name);

    static bool Restore(
        CloudOSNativeWindowManager& manager,
        const WorkspaceSnapshot& snapshot);

    static void ApplyPreset(
        CloudOSNativeWindowManager& manager,
        int workspace,
        WorkspaceLayoutPreset preset);
};

class NativeWorkspaceAutomationEngine final
{
public:
    void ResetRuntimeState();
    void Tick(
        HINSTANCE instance,
        HWND owner,
        CloudOSNativeWindowManager& manager,
        NativeWorkspaceStudioStore& store);

    void ReapplyAllRules(CloudOSNativeWindowManager& manager, NativeWorkspaceStudioStore& store);
    void LaunchWorkspaceEntries(HINSTANCE instance, HWND owner, int workspace, NativeWorkspaceStudioStore& store);

    [[nodiscard]] const std::vector<WorkspaceFocusRecord>& FocusHistory() const noexcept;
    void ClearFocusHistory() noexcept;
    bool FocusHistoryItem(CloudOSNativeWindowManager& manager, std::size_t index);

    static WorkspaceWindowIdentity IdentifyWindow(HWND window, DWORD process_id = 0);
    static bool RuleMatches(const WorkspaceRule& rule, const WorkspaceWindowIdentity& identity);

private:
    void ApplyRulesToNewWindows(CloudOSNativeWindowManager& manager, NativeWorkspaceStudioStore& store);
    void HandleWorkspaceTransition(
        HINSTANCE instance,
        HWND owner,
        CloudOSNativeWindowManager& manager,
        NativeWorkspaceStudioStore& store,
        int workspace);
    void TrackFocus(CloudOSNativeWindowManager& manager);
    static void ApplyRule(
        CloudOSNativeWindowManager& manager,
        const WorkspaceRule& rule,
        const WorkspaceWindowIdentity& identity);

    std::unordered_map<HWND, std::uint64_t> processed_windows_;
    std::vector<WorkspaceFocusRecord> focus_history_;
    int last_workspace_{-1};
    HWND last_foreground_{};
};
} // namespace CloudOS
