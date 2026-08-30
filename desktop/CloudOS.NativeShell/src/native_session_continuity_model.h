#pragma once

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

namespace CloudOS
{
enum class ContinuityEventKind : std::uint32_t
{
    SessionStarted = 0,
    SessionRecovered = 1,
    SessionClosedCleanly = 2,
    WorkspaceChanged = 3,
    CheckpointCreated = 4,
    CheckpointRestored = 5,
    CheckpointFailed = 6,
    TopologyChanged = 7,
    WindowFocusChanged = 8,
    ManualSave = 9,
    SettingsChanged = 10,
    StoreRecoveredFromBackup = 11,
};

struct ContinuityPreferences final
{
    bool enabled{true};
    bool auto_checkpoint{true};
    bool restore_after_unclean{true};
    bool restore_last_workspace{true};
    bool record_focus_history{true};
    std::uint32_t checkpoint_interval_seconds{20};
    std::uint32_t retention_per_workspace{8};
};

struct ContinuityWindowState final
{
    std::wstring process_name;
    std::wstring window_class;
    std::wstring title_hint;
    std::wstring monitor_device;
    RECT normalized_bounds{};
    bool floating{};
    UINT show_command{SW_SHOWNORMAL};
};

struct ContinuityCheckpoint final
{
    std::uint32_t id{};
    int workspace{};
    std::uint64_t created_filetime{};
    std::wstring reason;
    std::vector<ContinuityWindowState> windows;
};

struct ContinuityJournalEvent final
{
    std::uint64_t sequence{};
    std::uint64_t created_filetime{};
    ContinuityEventKind kind{ContinuityEventKind::SessionStarted};
    int workspace{};
    std::wstring title;
    std::wstring detail;
};

class NativeSessionContinuityStore final
{
public:
    NativeSessionContinuityStore();

    bool Load();
    bool Save() const;
    void ResetDefaults();

    [[nodiscard]] const ContinuityPreferences& Preferences() const noexcept { return preferences_; }
    [[nodiscard]] ContinuityPreferences& Preferences() noexcept { return preferences_; }
    [[nodiscard]] const std::vector<ContinuityCheckpoint>& Checkpoints() const noexcept { return checkpoints_; }
    [[nodiscard]] std::vector<ContinuityCheckpoint>& Checkpoints() noexcept { return checkpoints_; }
    [[nodiscard]] const std::vector<ContinuityJournalEvent>& Journal() const noexcept { return journal_; }
    [[nodiscard]] std::vector<ContinuityJournalEvent>& Journal() noexcept { return journal_; }

    [[nodiscard]] int LastWorkspace() const noexcept { return last_workspace_; }
    void SetLastWorkspace(int workspace) noexcept;

    [[nodiscard]] std::uint32_t NextCheckpointId() noexcept;
    [[nodiscard]] std::uint64_t NextEventSequence() noexcept;

    void AddCheckpoint(ContinuityCheckpoint checkpoint);
    void AddEvent(
        ContinuityEventKind kind,
        int workspace,
        const std::wstring& title,
        const std::wstring& detail = {});
    void Trim();
    void ClearCheckpoints();
    void ClearJournal();

    [[nodiscard]] const ContinuityCheckpoint* LatestCheckpoint(int workspace) const noexcept;
    [[nodiscard]] const ContinuityCheckpoint* FindCheckpoint(std::uint32_t id) const noexcept;

    [[nodiscard]] bool LoadedFromBackup() const noexcept { return loaded_from_backup_; }

    static std::wstring StoreDirectory();
    static std::wstring StorePath();
    static std::uint64_t FileTimeNow() noexcept;

private:
    bool LoadFromPath(const std::wstring& path);
    bool WriteToPath(const std::wstring& path) const;
    void RepairCounters() noexcept;

    ContinuityPreferences preferences_{};
    std::vector<ContinuityCheckpoint> checkpoints_;
    std::vector<ContinuityJournalEvent> journal_;
    int last_workspace_{};
    std::uint32_t next_checkpoint_id_{1};
    std::uint64_t next_event_sequence_{1};
    bool loaded_from_backup_{};
};

std::wstring ContinuityEventKindName(ContinuityEventKind kind);
std::wstring ContinuityFileTimeText(std::uint64_t value);
} // namespace CloudOS
