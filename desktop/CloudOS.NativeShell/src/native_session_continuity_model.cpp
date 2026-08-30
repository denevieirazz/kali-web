#include "native_session_continuity_model.h"

#include <KnownFolders.h>
#include <ShlObj.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cwchar>
#include <limits>
#include <unordered_map>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr std::uint32_t kMagic = 0x33434F43u; // COC3
constexpr std::uint32_t kVersion = 3u;
constexpr std::uint32_t kMaximumCheckpoints = 128u;
constexpr std::uint32_t kMaximumEvents = 512u;
constexpr std::uint32_t kMaximumWindows = 128u;
constexpr std::uint32_t kMaximumString = 2048u;
constexpr std::uint32_t kMaximumRetention = 32u;

struct FileHeader final
{
    std::uint32_t magic{};
    std::uint32_t version{};
    std::uint32_t flags{};
    std::uint32_t interval_seconds{};
    std::uint32_t retention_per_workspace{};
    std::int32_t last_workspace{};
    std::uint32_t next_checkpoint_id{};
    std::uint64_t next_event_sequence{};
    std::uint32_t checkpoint_count{};
    std::uint32_t event_count{};
};

struct CheckpointDisk final
{
    std::uint32_t id{};
    std::int32_t workspace{};
    std::uint64_t created_filetime{};
    std::uint32_t reason_length{};
    std::uint32_t window_count{};
};

struct WindowDisk final
{
    std::uint32_t process_length{};
    std::uint32_t class_length{};
    std::uint32_t title_length{};
    std::uint32_t monitor_length{};
    std::int32_t left{};
    std::int32_t top{};
    std::int32_t right{};
    std::int32_t bottom{};
    std::uint32_t floating{};
    std::uint32_t show_command{};
};

struct EventDisk final
{
    std::uint64_t sequence{};
    std::uint64_t created_filetime{};
    std::uint32_t kind{};
    std::int32_t workspace{};
    std::uint32_t title_length{};
    std::uint32_t detail_length{};
};

bool ReadExact(HANDLE file, void* data, DWORD bytes)
{
    DWORD read = 0;
    return ReadFile(file, data, bytes, &read, nullptr) != FALSE && read == bytes;
}

bool WriteExact(HANDLE file, const void* data, DWORD bytes)
{
    DWORD written = 0;
    return WriteFile(file, data, bytes, &written, nullptr) != FALSE && written == bytes;
}

std::uint32_t StringLength(const std::wstring& value)
{
    return static_cast<std::uint32_t>(
        std::min<std::size_t>(value.size(), kMaximumString));
}

bool ReadString(HANDLE file, std::uint32_t length, std::wstring* value)
{
    if (value == nullptr || length > kMaximumString)
    {
        return false;
    }
    value->assign(length, L'\0');
    if (length == 0u)
    {
        return true;
    }
    const std::size_t bytes = static_cast<std::size_t>(length) * sizeof(wchar_t);
    if (bytes > std::numeric_limits<DWORD>::max())
    {
        return false;
    }
    return ReadExact(file, value->data(), static_cast<DWORD>(bytes));
}

bool WriteString(HANDLE file, const std::wstring& value)
{
    const std::uint32_t length = StringLength(value);
    if (length == 0u)
    {
        return true;
    }
    return WriteExact(
        file,
        value.data(),
        static_cast<DWORD>(static_cast<std::size_t>(length) * sizeof(wchar_t)));
}

std::uint32_t EncodeFlags(const ContinuityPreferences& preferences)
{
    std::uint32_t flags = 0u;
    if (preferences.enabled) flags |= 1u << 0u;
    if (preferences.auto_checkpoint) flags |= 1u << 1u;
    if (preferences.restore_after_unclean) flags |= 1u << 2u;
    if (preferences.restore_last_workspace) flags |= 1u << 3u;
    if (preferences.record_focus_history) flags |= 1u << 4u;
    return flags;
}

ContinuityPreferences DecodePreferences(
    std::uint32_t flags,
    std::uint32_t interval,
    std::uint32_t retention)
{
    ContinuityPreferences preferences{};
    preferences.enabled = (flags & (1u << 0u)) != 0u;
    preferences.auto_checkpoint = (flags & (1u << 1u)) != 0u;
    preferences.restore_after_unclean = (flags & (1u << 2u)) != 0u;
    preferences.restore_last_workspace = (flags & (1u << 3u)) != 0u;
    preferences.record_focus_history = (flags & (1u << 4u)) != 0u;
    preferences.checkpoint_interval_seconds = std::clamp<std::uint32_t>(interval, 5u, 3600u);
    preferences.retention_per_workspace = std::clamp<std::uint32_t>(retention, 1u, kMaximumRetention);
    return preferences;
}
}

NativeSessionContinuityStore::NativeSessionContinuityStore()
{
    ResetDefaults();
}

std::wstring NativeSessionContinuityStore::StoreDirectory()
{
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &value)) ||
        value == nullptr)
    {
        if (value != nullptr)
        {
            CoTaskMemFree(value);
        }
        return {};
    }
    std::wstring path(value);
    CoTaskMemFree(value);
    path += L"\\CloudOS";
    return path;
}

std::wstring NativeSessionContinuityStore::StorePath()
{
    std::wstring directory = StoreDirectory();
    if (directory.empty())
    {
        return {};
    }
    return directory + L"\\continuity_v3.dat";
}

std::uint64_t NativeSessionContinuityStore::FileTimeNow() noexcept
{
    FILETIME value{};
    GetSystemTimeAsFileTime(&value);
    ULARGE_INTEGER raw{};
    raw.LowPart = value.dwLowDateTime;
    raw.HighPart = value.dwHighDateTime;
    return raw.QuadPart;
}

void NativeSessionContinuityStore::ResetDefaults()
{
    preferences_ = ContinuityPreferences{};
    checkpoints_.clear();
    journal_.clear();
    last_workspace_ = 0;
    next_checkpoint_id_ = 1;
    next_event_sequence_ = 1;
    loaded_from_backup_ = false;
}

bool NativeSessionContinuityStore::Load()
{
    ResetDefaults();
    const std::wstring path = StorePath();
    if (path.empty())
    {
        return false;
    }

    if (LoadFromPath(path))
    {
        RepairCounters();
        Trim();
        return true;
    }

    const std::wstring backup = path + L".bak";
    ResetDefaults();
    if (LoadFromPath(backup))
    {
        loaded_from_backup_ = true;
        RepairCounters();
        Trim();
        return true;
    }

    ResetDefaults();
    return false;
}

bool NativeSessionContinuityStore::LoadFromPath(const std::wstring& path)
{
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return false;
    }

    FileHeader header{};
    bool success = ReadExact(file, &header, static_cast<DWORD>(sizeof(header))) &&
        header.magic == kMagic &&
        header.version == kVersion &&
        header.checkpoint_count <= kMaximumCheckpoints &&
        header.event_count <= kMaximumEvents;

    if (success)
    {
        preferences_ = DecodePreferences(
            header.flags,
            header.interval_seconds,
            header.retention_per_workspace);
        last_workspace_ = std::clamp<int>(header.last_workspace, 0, 3);
        next_checkpoint_id_ = std::max<std::uint32_t>(1u, header.next_checkpoint_id);
        next_event_sequence_ = std::max<std::uint64_t>(1u, header.next_event_sequence);
    }

    for (std::uint32_t index = 0; success && index < header.checkpoint_count; ++index)
    {
        CheckpointDisk disk{};
        success = ReadExact(file, &disk, static_cast<DWORD>(sizeof(disk))) &&
            disk.reason_length <= kMaximumString &&
            disk.window_count <= kMaximumWindows;
        if (!success)
        {
            break;
        }

        ContinuityCheckpoint checkpoint{};
        checkpoint.id = disk.id;
        checkpoint.workspace = std::clamp<int>(disk.workspace, 0, 3);
        checkpoint.created_filetime = disk.created_filetime;
        success = ReadString(file, disk.reason_length, &checkpoint.reason);
        checkpoint.windows.reserve(disk.window_count);

        for (std::uint32_t window_index = 0; success && window_index < disk.window_count; ++window_index)
        {
            WindowDisk window_disk{};
            success = ReadExact(file, &window_disk, static_cast<DWORD>(sizeof(window_disk))) &&
                window_disk.process_length <= kMaximumString &&
                window_disk.class_length <= kMaximumString &&
                window_disk.title_length <= kMaximumString &&
                window_disk.monitor_length <= kMaximumString;
            if (!success)
            {
                break;
            }

            ContinuityWindowState state{};
            success = ReadString(file, window_disk.process_length, &state.process_name) &&
                ReadString(file, window_disk.class_length, &state.window_class) &&
                ReadString(file, window_disk.title_length, &state.title_hint) &&
                ReadString(file, window_disk.monitor_length, &state.monitor_device);
            state.normalized_bounds = RECT{
                window_disk.left,
                window_disk.top,
                window_disk.right,
                window_disk.bottom};
            state.floating = window_disk.floating != 0u;
            state.show_command = window_disk.show_command;
            checkpoint.windows.push_back(std::move(state));
        }
        if (success)
        {
            checkpoints_.push_back(std::move(checkpoint));
        }
    }

    for (std::uint32_t index = 0; success && index < header.event_count; ++index)
    {
        EventDisk disk{};
        success = ReadExact(file, &disk, static_cast<DWORD>(sizeof(disk))) &&
            disk.title_length <= kMaximumString &&
            disk.detail_length <= kMaximumString &&
            disk.kind <= static_cast<std::uint32_t>(ContinuityEventKind::StoreRecoveredFromBackup);
        if (!success)
        {
            break;
        }

        ContinuityJournalEvent event{};
        event.sequence = disk.sequence;
        event.created_filetime = disk.created_filetime;
        event.kind = static_cast<ContinuityEventKind>(disk.kind);
        event.workspace = std::clamp<int>(disk.workspace, 0, 3);
        success = ReadString(file, disk.title_length, &event.title) &&
            ReadString(file, disk.detail_length, &event.detail);
        if (success)
        {
            journal_.push_back(std::move(event));
        }
    }

    CloseHandle(file);
    if (!success)
    {
        checkpoints_.clear();
        journal_.clear();
    }
    return success;
}

bool NativeSessionContinuityStore::Save() const
{
    const std::wstring directory = StoreDirectory();
    const std::wstring path = StorePath();
    if (directory.empty() || path.empty())
    {
        return false;
    }

    (void)CreateDirectoryW(directory.c_str(), nullptr);
    const std::wstring temporary = path + L".tmp";
    const std::wstring backup = path + L".bak";
    if (!WriteToPath(temporary))
    {
        (void)DeleteFileW(temporary.c_str());
        return false;
    }

    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        (void)CopyFileW(path.c_str(), backup.c_str(), FALSE);
    }
    if (!MoveFileExW(
            temporary.c_str(),
            path.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        (void)DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

bool NativeSessionContinuityStore::WriteToPath(const std::wstring& path) const
{
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return false;
    }

    const FileHeader header{
        kMagic,
        kVersion,
        EncodeFlags(preferences_),
        std::clamp<std::uint32_t>(preferences_.checkpoint_interval_seconds, 5u, 3600u),
        std::clamp<std::uint32_t>(preferences_.retention_per_workspace, 1u, kMaximumRetention),
        std::clamp(last_workspace_, 0, 3),
        next_checkpoint_id_,
        next_event_sequence_,
        static_cast<std::uint32_t>(std::min<std::size_t>(checkpoints_.size(), kMaximumCheckpoints)),
        static_cast<std::uint32_t>(std::min<std::size_t>(journal_.size(), kMaximumEvents))};

    bool success = WriteExact(file, &header, static_cast<DWORD>(sizeof(header)));
    for (std::uint32_t index = 0; success && index < header.checkpoint_count; ++index)
    {
        const ContinuityCheckpoint& checkpoint = checkpoints_[index];
        const CheckpointDisk disk{
            checkpoint.id,
            std::clamp(checkpoint.workspace, 0, 3),
            checkpoint.created_filetime,
            StringLength(checkpoint.reason),
            static_cast<std::uint32_t>(std::min<std::size_t>(checkpoint.windows.size(), kMaximumWindows))};
        success = WriteExact(file, &disk, static_cast<DWORD>(sizeof(disk))) &&
            WriteString(file, checkpoint.reason);

        for (std::uint32_t window_index = 0; success && window_index < disk.window_count; ++window_index)
        {
            const ContinuityWindowState& state = checkpoint.windows[window_index];
            const WindowDisk window_disk{
                StringLength(state.process_name),
                StringLength(state.window_class),
                StringLength(state.title_hint),
                StringLength(state.monitor_device),
                state.normalized_bounds.left,
                state.normalized_bounds.top,
                state.normalized_bounds.right,
                state.normalized_bounds.bottom,
                state.floating ? 1u : 0u,
                state.show_command};
            success = WriteExact(file, &window_disk, static_cast<DWORD>(sizeof(window_disk))) &&
                WriteString(file, state.process_name) &&
                WriteString(file, state.window_class) &&
                WriteString(file, state.title_hint) &&
                WriteString(file, state.monitor_device);
        }
    }

    for (std::uint32_t index = 0; success && index < header.event_count; ++index)
    {
        const ContinuityJournalEvent& event = journal_[index];
        const EventDisk disk{
            event.sequence,
            event.created_filetime,
            static_cast<std::uint32_t>(event.kind),
            std::clamp(event.workspace, 0, 3),
            StringLength(event.title),
            StringLength(event.detail)};
        success = WriteExact(file, &disk, static_cast<DWORD>(sizeof(disk))) &&
            WriteString(file, event.title) &&
            WriteString(file, event.detail);
    }

    if (success)
    {
        success = FlushFileBuffers(file) != FALSE;
    }
    CloseHandle(file);
    return success;
}

void NativeSessionContinuityStore::SetLastWorkspace(int workspace) noexcept
{
    last_workspace_ = std::clamp(workspace, 0, 3);
}

std::uint32_t NativeSessionContinuityStore::NextCheckpointId() noexcept
{
    const std::uint32_t value = next_checkpoint_id_++;
    if (next_checkpoint_id_ == 0u)
    {
        next_checkpoint_id_ = 1u;
    }
    return value == 0u ? next_checkpoint_id_++ : value;
}

std::uint64_t NativeSessionContinuityStore::NextEventSequence() noexcept
{
    const std::uint64_t value = next_event_sequence_++;
    if (next_event_sequence_ == 0u)
    {
        next_event_sequence_ = 1u;
    }
    return value == 0u ? next_event_sequence_++ : value;
}

void NativeSessionContinuityStore::AddCheckpoint(ContinuityCheckpoint checkpoint)
{
    if (checkpoint.id == 0u)
    {
        checkpoint.id = NextCheckpointId();
    }
    if (checkpoint.created_filetime == 0u)
    {
        checkpoint.created_filetime = FileTimeNow();
    }
    checkpoint.workspace = std::clamp(checkpoint.workspace, 0, 3);
    if (checkpoint.windows.size() > kMaximumWindows)
    {
        checkpoint.windows.resize(kMaximumWindows);
    }
    checkpoints_.push_back(std::move(checkpoint));
    Trim();
}

void NativeSessionContinuityStore::AddEvent(
    ContinuityEventKind kind,
    int workspace,
    const std::wstring& title,
    const std::wstring& detail)
{
    ContinuityJournalEvent event{};
    event.sequence = NextEventSequence();
    event.created_filetime = FileTimeNow();
    event.kind = kind;
    event.workspace = std::clamp(workspace, 0, 3);
    event.title = title;
    event.detail = detail;
    journal_.push_back(std::move(event));
    if (journal_.size() > kMaximumEvents)
    {
        journal_.erase(
            journal_.begin(),
            journal_.begin() + static_cast<std::ptrdiff_t>(journal_.size() - kMaximumEvents));
    }
}

void NativeSessionContinuityStore::Trim()
{
    preferences_.checkpoint_interval_seconds = std::clamp<std::uint32_t>(
        preferences_.checkpoint_interval_seconds,
        5u,
        3600u);
    preferences_.retention_per_workspace = std::clamp<std::uint32_t>(
        preferences_.retention_per_workspace,
        1u,
        kMaximumRetention);

    std::array<std::uint32_t, 4> kept{};
    std::vector<ContinuityCheckpoint> reversed;
    reversed.reserve(checkpoints_.size());
    for (auto iterator = checkpoints_.rbegin(); iterator != checkpoints_.rend(); ++iterator)
    {
        const int workspace = std::clamp(iterator->workspace, 0, 3);
        if (kept[static_cast<std::size_t>(workspace)] >= preferences_.retention_per_workspace)
        {
            continue;
        }
        ++kept[static_cast<std::size_t>(workspace)];
        reversed.push_back(*iterator);
    }
    std::reverse(reversed.begin(), reversed.end());
    if (reversed.size() > kMaximumCheckpoints)
    {
        reversed.erase(
            reversed.begin(),
            reversed.begin() + static_cast<std::ptrdiff_t>(reversed.size() - kMaximumCheckpoints));
    }
    checkpoints_ = std::move(reversed);

    if (journal_.size() > kMaximumEvents)
    {
        journal_.erase(
            journal_.begin(),
            journal_.begin() + static_cast<std::ptrdiff_t>(journal_.size() - kMaximumEvents));
    }
}

void NativeSessionContinuityStore::ClearCheckpoints()
{
    checkpoints_.clear();
}

void NativeSessionContinuityStore::ClearJournal()
{
    journal_.clear();
}

const ContinuityCheckpoint* NativeSessionContinuityStore::LatestCheckpoint(int workspace) const noexcept
{
    workspace = std::clamp(workspace, 0, 3);
    for (auto iterator = checkpoints_.rbegin(); iterator != checkpoints_.rend(); ++iterator)
    {
        if (iterator->workspace == workspace)
        {
            return &(*iterator);
        }
    }
    return nullptr;
}

const ContinuityCheckpoint* NativeSessionContinuityStore::FindCheckpoint(std::uint32_t id) const noexcept
{
    const auto iterator = std::find_if(
        checkpoints_.cbegin(),
        checkpoints_.cend(),
        [id](const ContinuityCheckpoint& item)
        {
            return item.id == id;
        });
    return iterator == checkpoints_.cend() ? nullptr : &(*iterator);
}

void NativeSessionContinuityStore::RepairCounters() noexcept
{
    std::uint32_t maximum_checkpoint = 0u;
    for (const auto& checkpoint : checkpoints_)
    {
        maximum_checkpoint = std::max(maximum_checkpoint, checkpoint.id);
    }
    if (next_checkpoint_id_ <= maximum_checkpoint)
    {
        next_checkpoint_id_ = maximum_checkpoint + 1u;
        if (next_checkpoint_id_ == 0u)
        {
            next_checkpoint_id_ = 1u;
        }
    }

    std::uint64_t maximum_event = 0u;
    for (const auto& event : journal_)
    {
        maximum_event = std::max(maximum_event, event.sequence);
    }
    if (next_event_sequence_ <= maximum_event)
    {
        next_event_sequence_ = maximum_event + 1u;
        if (next_event_sequence_ == 0u)
        {
            next_event_sequence_ = 1u;
        }
    }
}

std::wstring ContinuityEventKindName(ContinuityEventKind kind)
{
    switch (kind)
    {
    case ContinuityEventKind::SessionStarted: return L"Sessão iniciada";
    case ContinuityEventKind::SessionRecovered: return L"Sessão recuperada";
    case ContinuityEventKind::SessionClosedCleanly: return L"Sessão encerrada";
    case ContinuityEventKind::WorkspaceChanged: return L"Área alterada";
    case ContinuityEventKind::CheckpointCreated: return L"Checkpoint criado";
    case ContinuityEventKind::CheckpointRestored: return L"Checkpoint restaurado";
    case ContinuityEventKind::CheckpointFailed: return L"Falha ao restaurar";
    case ContinuityEventKind::TopologyChanged: return L"Monitores alterados";
    case ContinuityEventKind::WindowFocusChanged: return L"Foco alterado";
    case ContinuityEventKind::ManualSave: return L"Salvamento manual";
    case ContinuityEventKind::SettingsChanged: return L"Preferências alteradas";
    case ContinuityEventKind::StoreRecoveredFromBackup: return L"Backup recuperado";
    default: return L"Evento";
    }
}

std::wstring ContinuityFileTimeText(std::uint64_t value)
{
    if (value == 0u)
    {
        return L"—";
    }
    ULARGE_INTEGER raw{};
    raw.QuadPart = value;
    FILETIME utc{};
    utc.dwLowDateTime = raw.LowPart;
    utc.dwHighDateTime = raw.HighPart;
    FILETIME local{};
    if (!FileTimeToLocalFileTime(&utc, &local))
    {
        return L"—";
    }
    SYSTEMTIME time{};
    if (!FileTimeToSystemTime(&local, &time))
    {
        return L"—";
    }
    wchar_t buffer[64]{};
    _snwprintf_s(
        buffer,
        _countof(buffer),
        _TRUNCATE,
        L"%02u/%02u/%04u %02u:%02u:%02u",
        time.wDay,
        time.wMonth,
        time.wYear,
        time.wHour,
        time.wMinute,
        time.wSecond);
    return buffer;
}
} // namespace CloudOS
