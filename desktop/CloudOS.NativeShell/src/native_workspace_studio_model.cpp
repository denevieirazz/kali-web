#include "native_workspace_studio_model.h"

#include <shlobj.h>

#include <algorithm>
#include <array>
#include <fstream>
#include <limits>

namespace CloudOS
{
namespace
{
constexpr std::array<char, 8> kMagic{{'C','L','D','W','S','T','2','\0'}};
constexpr std::uint32_t kVersion = 2;
constexpr std::uint32_t kMaximumCollection = 4096;
constexpr std::uint32_t kMaximumStringLength = 32768;

std::wstring ParentFolder(const std::wstring& path)
{
    const std::size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring{} : path.substr(0, slash);
}

bool EnsureDirectoryTree(const std::wstring& folder)
{
    if (folder.empty())
    {
        return false;
    }
    const int result = SHCreateDirectoryExW(nullptr, folder.c_str(), nullptr);
    return result == ERROR_SUCCESS || result == ERROR_ALREADY_EXISTS || result == ERROR_FILE_EXISTS;
}

void WriteU32(std::ofstream& out, std::uint32_t value)
{
    out.write(reinterpret_cast<const char*>(&value), sizeof(value));
}

void WriteU64(std::ofstream& out, std::uint64_t value)
{
    out.write(reinterpret_cast<const char*>(&value), sizeof(value));
}

void WriteBool(std::ofstream& out, bool value)
{
    const std::uint8_t raw = value ? 1u : 0u;
    out.write(reinterpret_cast<const char*>(&raw), sizeof(raw));
}

void WriteRect(std::ofstream& out, const RECT& rect)
{
    out.write(reinterpret_cast<const char*>(&rect), sizeof(rect));
}

void WriteString(std::ofstream& out, const std::wstring& value)
{
    const std::uint32_t length = static_cast<std::uint32_t>(
        std::min<std::size_t>(value.size(), kMaximumStringLength));
    WriteU32(out, length);
    if (length != 0)
    {
        out.write(
            reinterpret_cast<const char*>(value.data()),
            static_cast<std::streamsize>(length * sizeof(wchar_t)));
    }
}

bool ReadU32(std::ifstream& in, std::uint32_t* value)
{
    return value != nullptr &&
        static_cast<bool>(in.read(reinterpret_cast<char*>(value), sizeof(*value)));
}

bool ReadU64(std::ifstream& in, std::uint64_t* value)
{
    return value != nullptr &&
        static_cast<bool>(in.read(reinterpret_cast<char*>(value), sizeof(*value)));
}

bool ReadBool(std::ifstream& in, bool* value)
{
    if (value == nullptr)
    {
        return false;
    }
    std::uint8_t raw = 0;
    if (!in.read(reinterpret_cast<char*>(&raw), sizeof(raw)))
    {
        return false;
    }
    *value = raw != 0;
    return true;
}

bool ReadRect(std::ifstream& in, RECT* rect)
{
    return rect != nullptr &&
        static_cast<bool>(in.read(reinterpret_cast<char*>(rect), sizeof(*rect)));
}

bool ReadString(std::ifstream& in, std::wstring* value)
{
    if (value == nullptr)
    {
        return false;
    }
    std::uint32_t length = 0;
    if (!ReadU32(in, &length) || length > kMaximumStringLength)
    {
        return false;
    }
    value->assign(length, L'\0');
    if (length != 0 && !in.read(
            reinterpret_cast<char*>(value->data()),
            static_cast<std::streamsize>(length * sizeof(wchar_t))))
    {
        return false;
    }
    return true;
}

bool WriteProfile(std::ofstream& out, const WorkspaceProfile& profile)
{
    WriteString(out, profile.name);
    WriteString(out, profile.wallpaper_path);
    WriteU32(out, static_cast<std::uint32_t>(profile.layout));
    WriteBool(out, profile.auto_tile);
    WriteBool(out, profile.auto_launch);
    WriteBool(out, profile.apply_wallpaper);
    return static_cast<bool>(out);
}

bool ReadProfile(std::ifstream& in, WorkspaceProfile* profile)
{
    if (profile == nullptr)
    {
        return false;
    }
    std::uint32_t layout = 0;
    return ReadString(in, &profile->name) &&
        ReadString(in, &profile->wallpaper_path) &&
        ReadU32(in, &layout) &&
        ReadBool(in, &profile->auto_tile) &&
        ReadBool(in, &profile->auto_launch) &&
        ReadBool(in, &profile->apply_wallpaper) &&
        (profile->layout = static_cast<WorkspaceLayoutPreset>(layout), true);
}

bool WriteRule(std::ofstream& out, const WorkspaceRule& rule)
{
    WriteU32(out, rule.id);
    WriteBool(out, rule.enabled);
    WriteU32(out, static_cast<std::uint32_t>(rule.field));
    WriteU32(out, static_cast<std::uint32_t>(rule.mode));
    WriteString(out, rule.pattern);
    WriteU32(out, static_cast<std::uint32_t>(std::clamp(rule.workspace, 0, kWorkspaceStudioCount - 1)));
    WriteBool(out, rule.floating);
    WriteBool(out, rule.maximize);
    return static_cast<bool>(out);
}

bool ReadRule(std::ifstream& in, WorkspaceRule* rule)
{
    if (rule == nullptr)
    {
        return false;
    }
    std::uint32_t field = 0;
    std::uint32_t mode = 0;
    std::uint32_t workspace = 0;
    if (!ReadU32(in, &rule->id) ||
        !ReadBool(in, &rule->enabled) ||
        !ReadU32(in, &field) ||
        !ReadU32(in, &mode) ||
        !ReadString(in, &rule->pattern) ||
        !ReadU32(in, &workspace) ||
        !ReadBool(in, &rule->floating) ||
        !ReadBool(in, &rule->maximize))
    {
        return false;
    }
    rule->field = static_cast<WorkspaceMatchField>(field);
    rule->mode = static_cast<WorkspaceMatchMode>(mode);
    rule->workspace = static_cast<int>(std::min<std::uint32_t>(workspace, kWorkspaceStudioCount - 1));
    return true;
}

bool WriteLaunch(std::ofstream& out, const WorkspaceLaunchEntry& entry)
{
    WriteU32(out, entry.id);
    WriteBool(out, entry.enabled);
    WriteU32(out, static_cast<std::uint32_t>(std::clamp(entry.workspace, 0, kWorkspaceStudioCount - 1)));
    WriteBool(out, entry.cloudos_app);
    WriteString(out, entry.target);
    WriteString(out, entry.arguments);
    WriteU32(out, entry.delay_ms);
    return static_cast<bool>(out);
}

bool ReadLaunch(std::ifstream& in, WorkspaceLaunchEntry* entry)
{
    if (entry == nullptr)
    {
        return false;
    }
    std::uint32_t workspace = 0;
    if (!ReadU32(in, &entry->id) ||
        !ReadBool(in, &entry->enabled) ||
        !ReadU32(in, &workspace) ||
        !ReadBool(in, &entry->cloudos_app) ||
        !ReadString(in, &entry->target) ||
        !ReadString(in, &entry->arguments) ||
        !ReadU32(in, &entry->delay_ms))
    {
        return false;
    }
    entry->workspace = static_cast<int>(std::min<std::uint32_t>(workspace, kWorkspaceStudioCount - 1));
    return true;
}

bool WriteSnapshotWindow(std::ofstream& out, const WorkspaceLayoutWindow& window)
{
    WriteString(out, window.process_name);
    WriteString(out, window.window_class);
    WriteString(out, window.title_hint);
    WriteString(out, window.monitor_device);
    WriteRect(out, window.normalized_bounds);
    WriteBool(out, window.floating);
    WriteU32(out, window.show_command);
    return static_cast<bool>(out);
}

bool ReadSnapshotWindow(std::ifstream& in, WorkspaceLayoutWindow* window)
{
    if (window == nullptr)
    {
        return false;
    }
    std::uint32_t show = 0;
    if (!ReadString(in, &window->process_name) ||
        !ReadString(in, &window->window_class) ||
        !ReadString(in, &window->title_hint) ||
        !ReadString(in, &window->monitor_device) ||
        !ReadRect(in, &window->normalized_bounds) ||
        !ReadBool(in, &window->floating) ||
        !ReadU32(in, &show))
    {
        return false;
    }
    window->show_command = show;
    return true;
}

bool WriteSnapshot(std::ofstream& out, const WorkspaceSnapshot& snapshot)
{
    WriteU32(out, snapshot.id);
    WriteU32(out, static_cast<std::uint32_t>(std::clamp(snapshot.workspace, 0, kWorkspaceStudioCount - 1)));
    WriteString(out, snapshot.name);
    WriteU64(out, snapshot.created_filetime);
    WriteU32(out, static_cast<std::uint32_t>(std::min<std::size_t>(snapshot.windows.size(), kMaximumCollection)));
    for (std::size_t index = 0; index < snapshot.windows.size() && index < kMaximumCollection; ++index)
    {
        if (!WriteSnapshotWindow(out, snapshot.windows[index]))
        {
            return false;
        }
    }
    return static_cast<bool>(out);
}

bool ReadSnapshot(std::ifstream& in, WorkspaceSnapshot* snapshot)
{
    if (snapshot == nullptr)
    {
        return false;
    }
    std::uint32_t workspace = 0;
    std::uint32_t count = 0;
    if (!ReadU32(in, &snapshot->id) ||
        !ReadU32(in, &workspace) ||
        !ReadString(in, &snapshot->name) ||
        !ReadU64(in, &snapshot->created_filetime) ||
        !ReadU32(in, &count) || count > kMaximumCollection)
    {
        return false;
    }
    snapshot->workspace = static_cast<int>(std::min<std::uint32_t>(workspace, kWorkspaceStudioCount - 1));
    snapshot->windows.clear();
    snapshot->windows.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index)
    {
        WorkspaceLayoutWindow window{};
        if (!ReadSnapshotWindow(in, &window))
        {
            return false;
        }
        snapshot->windows.push_back(std::move(window));
    }
    return true;
}

bool ReadStore(const std::wstring& path, NativeWorkspaceStudioStore* store)
{
    if (store == nullptr)
    {
        return false;
    }
    std::ifstream in(path, std::ios::binary);
    if (!in)
    {
        return false;
    }

    std::array<char, 8> magic{};
    in.read(magic.data(), static_cast<std::streamsize>(magic.size()));
    std::uint32_t version = 0;
    if (!in || magic != kMagic || !ReadU32(in, &version) || version != kVersion)
    {
        return false;
    }

    auto& profiles = store->Profiles();
    for (auto& profile : profiles)
    {
        if (!ReadProfile(in, &profile))
        {
            return false;
        }
    }

    std::uint32_t count = 0;
    if (!ReadU32(in, &count) || count > kMaximumCollection)
    {
        return false;
    }
    auto& rules = store->Rules();
    rules.clear();
    rules.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index)
    {
        WorkspaceRule rule{};
        if (!ReadRule(in, &rule))
        {
            return false;
        }
        rules.push_back(std::move(rule));
    }

    if (!ReadU32(in, &count) || count > kMaximumCollection)
    {
        return false;
    }
    auto& launches = store->LaunchEntries();
    launches.clear();
    launches.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index)
    {
        WorkspaceLaunchEntry entry{};
        if (!ReadLaunch(in, &entry))
        {
            return false;
        }
        launches.push_back(std::move(entry));
    }

    if (!ReadU32(in, &count) || count > kMaximumCollection)
    {
        return false;
    }
    auto& snapshots = store->Snapshots();
    snapshots.clear();
    snapshots.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index)
    {
        WorkspaceSnapshot snapshot{};
        if (!ReadSnapshot(in, &snapshot))
        {
            return false;
        }
        snapshots.push_back(std::move(snapshot));
    }

    std::uint32_t next_rule = 1;
    std::uint32_t next_launch = 1;
    std::uint32_t next_snapshot = 1;
    (void)ReadU32(in, &next_rule);
    (void)ReadU32(in, &next_launch);
    (void)ReadU32(in, &next_snapshot);
    while (store->NextRuleId() < next_rule) {}
    while (store->NextLaunchId() < next_launch) {}
    while (store->NextSnapshotId() < next_snapshot) {}
    return true;
}
}

NativeWorkspaceStudioStore::NativeWorkspaceStudioStore()
{
    ResetDefaults();
}

bool NativeWorkspaceStudioStore::Load()
{
    ResetDefaults();
    const std::wstring path = StorePath();
    if (ReadStore(path, this))
    {
        return true;
    }
    const std::wstring backup = path + L".bak";
    if (ReadStore(backup, this))
    {
        (void)Save();
        return true;
    }
    ResetDefaults();
    return false;
}

bool NativeWorkspaceStudioStore::Save() const
{
    const std::wstring path = StorePath();
    const std::wstring folder = ParentFolder(path);
    if (!EnsureDirectoryTree(folder))
    {
        return false;
    }

    const std::wstring temporary = path + L".tmp";
    const std::wstring backup = path + L".bak";
    std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
    if (!out)
    {
        return false;
    }

    out.write(kMagic.data(), static_cast<std::streamsize>(kMagic.size()));
    WriteU32(out, kVersion);
    for (const auto& profile : profiles_)
    {
        if (!WriteProfile(out, profile))
        {
            return false;
        }
    }

    WriteU32(out, static_cast<std::uint32_t>(std::min<std::size_t>(rules_.size(), kMaximumCollection)));
    for (std::size_t index = 0; index < rules_.size() && index < kMaximumCollection; ++index)
    {
        if (!WriteRule(out, rules_[index]))
        {
            return false;
        }
    }

    WriteU32(out, static_cast<std::uint32_t>(std::min<std::size_t>(launch_entries_.size(), kMaximumCollection)));
    for (std::size_t index = 0; index < launch_entries_.size() && index < kMaximumCollection; ++index)
    {
        if (!WriteLaunch(out, launch_entries_[index]))
        {
            return false;
        }
    }

    WriteU32(out, static_cast<std::uint32_t>(std::min<std::size_t>(snapshots_.size(), kMaximumCollection)));
    for (std::size_t index = 0; index < snapshots_.size() && index < kMaximumCollection; ++index)
    {
        if (!WriteSnapshot(out, snapshots_[index]))
        {
            return false;
        }
    }

    WriteU32(out, next_rule_id_);
    WriteU32(out, next_launch_id_);
    WriteU32(out, next_snapshot_id_);
    out.flush();
    if (!out)
    {
        return false;
    }
    out.close();

    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        (void)CopyFileW(path.c_str(), backup.c_str(), FALSE);
    }
    return MoveFileExW(
        temporary.c_str(),
        path.c_str(),
        MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
}

void NativeWorkspaceStudioStore::ResetDefaults()
{
    for (int index = 0; index < kWorkspaceStudioCount; ++index)
    {
        WorkspaceProfile profile{};
        profile.name = L"Área ";
        profile.name += std::to_wstring(index + 1);
        profiles_[static_cast<std::size_t>(index)] = std::move(profile);
    }
    rules_.clear();
    launch_entries_.clear();
    snapshots_.clear();
    next_rule_id_ = 1;
    next_launch_id_ = 1;
    next_snapshot_id_ = 1;
}

const std::array<WorkspaceProfile, kWorkspaceStudioCount>& NativeWorkspaceStudioStore::Profiles() const noexcept { return profiles_; }
std::array<WorkspaceProfile, kWorkspaceStudioCount>& NativeWorkspaceStudioStore::Profiles() noexcept { return profiles_; }
const std::vector<WorkspaceRule>& NativeWorkspaceStudioStore::Rules() const noexcept { return rules_; }
std::vector<WorkspaceRule>& NativeWorkspaceStudioStore::Rules() noexcept { return rules_; }
const std::vector<WorkspaceLaunchEntry>& NativeWorkspaceStudioStore::LaunchEntries() const noexcept { return launch_entries_; }
std::vector<WorkspaceLaunchEntry>& NativeWorkspaceStudioStore::LaunchEntries() noexcept { return launch_entries_; }
const std::vector<WorkspaceSnapshot>& NativeWorkspaceStudioStore::Snapshots() const noexcept { return snapshots_; }
std::vector<WorkspaceSnapshot>& NativeWorkspaceStudioStore::Snapshots() noexcept { return snapshots_; }

std::uint32_t NativeWorkspaceStudioStore::NextRuleId() noexcept { return next_rule_id_++; }
std::uint32_t NativeWorkspaceStudioStore::NextLaunchId() noexcept { return next_launch_id_++; }
std::uint32_t NativeWorkspaceStudioStore::NextSnapshotId() noexcept { return next_snapshot_id_++; }

std::wstring NativeWorkspaceStudioStore::WorkspaceName(int workspace) const
{
    if (workspace < 0 || workspace >= kWorkspaceStudioCount)
    {
        return L"Área";
    }
    const auto& name = profiles_[static_cast<std::size_t>(workspace)].name;
    if (!name.empty())
    {
        return name;
    }
    return L"Área " + std::to_wstring(workspace + 1);
}

std::wstring NativeWorkspaceStudioStore::StorePath()
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &raw)) || raw == nullptr)
    {
        return L"workspace_studio_v2.dat";
    }
    std::wstring path(raw);
    CoTaskMemFree(raw);
    path += L"\\CloudOS\\workspace_studio_v2.dat";
    return path;
}

std::wstring WorkspaceLayoutPresetName(WorkspaceLayoutPreset preset)
{
    switch (preset)
    {
    case WorkspaceLayoutPreset::MasterStack: return L"Mestre + pilha";
    case WorkspaceLayoutPreset::Columns: return L"Colunas";
    case WorkspaceLayoutPreset::Grid: return L"Grade";
    case WorkspaceLayoutPreset::Focus: return L"Foco";
    case WorkspaceLayoutPreset::Free:
    default: return L"Livre";
    }
}

std::wstring WorkspaceMatchFieldName(WorkspaceMatchField field)
{
    switch (field)
    {
    case WorkspaceMatchField::WindowTitle: return L"Título";
    case WorkspaceMatchField::WindowClass: return L"Classe";
    case WorkspaceMatchField::ProcessName:
    default: return L"Processo";
    }
}

std::wstring WorkspaceMatchModeName(WorkspaceMatchMode mode)
{
    switch (mode)
    {
    case WorkspaceMatchMode::Exact: return L"Exato";
    case WorkspaceMatchMode::Prefix: return L"Prefixo";
    case WorkspaceMatchMode::Wildcard: return L"Wildcard";
    case WorkspaceMatchMode::Contains:
    default: return L"Contém";
    }
}
} // namespace CloudOS
