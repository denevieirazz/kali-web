#pragma once

#include <windows.h>

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace CloudOS
{
constexpr int kWorkspaceStudioCount = 4;

enum class WorkspaceLayoutPreset : std::uint32_t
{
    Free = 0,
    MasterStack = 1,
    Columns = 2,
    Grid = 3,
    Focus = 4,
};

enum class WorkspaceMatchField : std::uint32_t
{
    ProcessName = 0,
    WindowTitle = 1,
    WindowClass = 2,
};

enum class WorkspaceMatchMode : std::uint32_t
{
    Contains = 0,
    Exact = 1,
    Prefix = 2,
    Wildcard = 3,
};

struct WorkspaceProfile final
{
    std::wstring name;
    std::wstring wallpaper_path;
    WorkspaceLayoutPreset layout{WorkspaceLayoutPreset::Free};
    bool auto_tile{};
    bool auto_launch{};
    bool apply_wallpaper{};
};

struct WorkspaceRule final
{
    std::uint32_t id{};
    bool enabled{true};
    WorkspaceMatchField field{WorkspaceMatchField::ProcessName};
    WorkspaceMatchMode mode{WorkspaceMatchMode::Contains};
    std::wstring pattern;
    int workspace{};
    bool floating{};
    bool maximize{};
};

struct WorkspaceLaunchEntry final
{
    std::uint32_t id{};
    bool enabled{true};
    int workspace{};
    bool cloudos_app{true};
    std::wstring target;
    std::wstring arguments;
    std::uint32_t delay_ms{};
};

struct WorkspaceLayoutWindow final
{
    std::wstring process_name;
    std::wstring window_class;
    std::wstring title_hint;
    std::wstring monitor_device;
    RECT normalized_bounds{};
    bool floating{};
    UINT show_command{SW_SHOWNORMAL};
};

struct WorkspaceSnapshot final
{
    std::uint32_t id{};
    int workspace{};
    std::wstring name;
    std::uint64_t created_filetime{};
    std::vector<WorkspaceLayoutWindow> windows;
};

class NativeWorkspaceStudioStore final
{
public:
    NativeWorkspaceStudioStore();

    bool Load();
    bool Save() const;
    void ResetDefaults();

    [[nodiscard]] const std::array<WorkspaceProfile, kWorkspaceStudioCount>& Profiles() const noexcept;
    [[nodiscard]] std::array<WorkspaceProfile, kWorkspaceStudioCount>& Profiles() noexcept;
    [[nodiscard]] const std::vector<WorkspaceRule>& Rules() const noexcept;
    [[nodiscard]] std::vector<WorkspaceRule>& Rules() noexcept;
    [[nodiscard]] const std::vector<WorkspaceLaunchEntry>& LaunchEntries() const noexcept;
    [[nodiscard]] std::vector<WorkspaceLaunchEntry>& LaunchEntries() noexcept;
    [[nodiscard]] const std::vector<WorkspaceSnapshot>& Snapshots() const noexcept;
    [[nodiscard]] std::vector<WorkspaceSnapshot>& Snapshots() noexcept;

    [[nodiscard]] std::uint32_t NextRuleId() noexcept;
    [[nodiscard]] std::uint32_t NextLaunchId() noexcept;
    [[nodiscard]] std::uint32_t NextSnapshotId() noexcept;
    [[nodiscard]] std::wstring WorkspaceName(int workspace) const;

    static std::wstring StorePath();

private:
    std::array<WorkspaceProfile, kWorkspaceStudioCount> profiles_{};
    std::vector<WorkspaceRule> rules_;
    std::vector<WorkspaceLaunchEntry> launch_entries_;
    std::vector<WorkspaceSnapshot> snapshots_;
    std::uint32_t next_rule_id_{1};
    std::uint32_t next_launch_id_{1};
    std::uint32_t next_snapshot_id_{1};
};

std::wstring WorkspaceLayoutPresetName(WorkspaceLayoutPreset preset);
std::wstring WorkspaceMatchFieldName(WorkspaceMatchField field);
std::wstring WorkspaceMatchModeName(WorkspaceMatchMode mode);
} // namespace CloudOS
