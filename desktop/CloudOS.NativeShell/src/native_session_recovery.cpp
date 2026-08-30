#include "native_session_recovery.h"

#include "native_app_launcher.h"

#include <KnownFolders.h>
#include <ShlObj.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <unordered_set>
#include <utility>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr std::uint32_t kMagic = 0x33534F43u; // COS3
constexpr std::uint32_t kVersion = 3u;
constexpr std::uint32_t kMaximumRecords = 256u;
constexpr std::uint32_t kMaximumString = 2048u;

struct FileHeader final
{
    std::uint32_t magic{};
    std::uint32_t version{};
    std::uint32_t count{};
};

struct FileRecord final
{
    std::uint32_t class_length{};
    std::uint32_t title_length{};
    std::uint32_t app_id_length{};
    std::uint32_t process_id{};
    std::int32_t workspace{};
    std::uint32_t floating{};
    std::int32_t left{};
    std::int32_t top{};
    std::int32_t right{};
    std::int32_t bottom{};
    std::uint32_t show_command{};
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

bool ReadString(HANDLE file, std::uint32_t length, std::wstring* value)
{
    if (value == nullptr || length > kMaximumString)
    {
        return false;
    }
    value->assign(length, L'\0');
    if (length == 0)
    {
        return true;
    }
    return ReadExact(
        file,
        value->data(),
        static_cast<DWORD>(length * sizeof(wchar_t)));
}

bool WriteString(HANDLE file, const std::wstring& value)
{
    if (value.empty())
    {
        return true;
    }
    return WriteExact(
        file,
        value.data(),
        static_cast<DWORD>(value.size() * sizeof(wchar_t)));
}

bool EqualInsensitive(const std::wstring& left, const wchar_t* right)
{
    return right != nullptr && _wcsicmp(left.c_str(), right) == 0;
}

bool ContainsInsensitive(std::wstring value, const wchar_t* needle)
{
    if (needle == nullptr || *needle == L'\0')
    {
        return false;
    }
    std::wstring target(needle);
    std::transform(value.begin(), value.end(), value.begin(), towlower);
    std::transform(target.begin(), target.end(), target.begin(), towlower);
    return value.find(target) != std::wstring::npos;
}
}

bool NativeSessionRecovery::BeginSession()
{
    if (begun_)
    {
        return true;
    }

    PWSTR local = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_DEFAULT,
            nullptr,
            &local)) ||
        local == nullptr)
    {
        if (local != nullptr)
        {
            CoTaskMemFree(local);
        }
        return false;
    }

    storage_directory_ = local;
    CoTaskMemFree(local);
    storage_directory_ += L"\\CloudOS";
    (void)CreateDirectoryW(storage_directory_.c_str(), nullptr);
    state_path_ = storage_directory_ + L"\\session_v3.dat";
    unclean_marker_path_ = storage_directory_ + L"\\session_v3.unclean";

    previous_unclean_ = GetFileAttributesW(unclean_marker_path_.c_str()) != INVALID_FILE_ATTRIBUTES;
    (void)Load();

    HANDLE marker = CreateFileW(
        unclean_marker_path_.c_str(),
        GENERIC_WRITE,
        FILE_SHARE_READ,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH,
        nullptr);
    if (marker != INVALID_HANDLE_VALUE)
    {
        const DWORD process_id = GetCurrentProcessId();
        FILETIME now{};
        GetSystemTimeAsFileTime(&now);
        (void)WriteExact(marker, &process_id, sizeof(process_id));
        (void)WriteExact(marker, &now, sizeof(now));
        FlushFileBuffers(marker);
        CloseHandle(marker);
    }

    begun_ = true;
    return true;
}

std::wstring NativeSessionRecovery::ClassName(HWND window)
{
    std::array<wchar_t, 256> buffer{};
    const int length = GetClassNameW(
        window,
        buffer.data(),
        static_cast<int>(buffer.size()));
    return length > 0
        ? std::wstring(buffer.data(), static_cast<std::size_t>(length))
        : std::wstring{};
}

std::wstring NativeSessionRecovery::AppIdFor(
    HWND,
    const std::wstring& class_name,
    const std::wstring& title)
{
    if (EqualInsensitive(class_name, L"CloudOS.NativeShell.Browser.v1")) return L"browser";
    if (EqualInsensitive(class_name, L"CloudOS.Native.Files.v5")) return L"files";
    if (EqualInsensitive(class_name, L"CloudOS.NativeNotepad.v1")) return L"notepad";
    if (EqualInsensitive(class_name, L"CloudOS.NativeCalculator.v1")) return L"calc";
    if (EqualInsensitive(class_name, L"CloudOS.Native.SystemMonitor.v1")) return L"sysmon";
    if (EqualInsensitive(class_name, L"CloudOS.NativeShell.Settings.v2")) return L"settings";
    if (EqualInsensitive(class_name, L"CloudOS.Native.Projects.v1")) return L"projects";
    if (EqualInsensitive(class_name, L"CloudOS.Native.Apps.v3")) return L"apps";
    if (EqualInsensitive(class_name, L"CloudOS.Native.Run.v2")) return L"run";
    if (EqualInsensitive(class_name, L"CloudOS.Native.EnvDoctor.v1")) return L"health";
    if (EqualInsensitive(class_name, L"CloudOS.NativeShell.CommandCenter.v1")) return L"control";
    if (EqualInsensitive(class_name, L"CloudOS.Native.FileOperations.v1")) return L"fileops";
    if (EqualInsensitive(class_name, L"CloudOS.Native.Terminal.v2"))
    {
        if (ContainsInsensitive(title, L"powershell")) return L"powershell";
        if (ContainsInsensitive(title, L"wsl") || ContainsInsensitive(title, L"kali")) return L"wsl";
        return L"terminal";
    }
    return {};
}

bool NativeSessionRecovery::MatchesExternal(
    const Record& record,
    const CloudOSManagedWindow& item)
{
    if (record.process_id == 0 || item.process_id != record.process_id ||
        item.hwnd == nullptr || !IsWindow(item.hwnd))
    {
        return false;
    }
    const std::wstring current_class = ClassName(item.hwnd);
    if (!record.class_name.empty() && _wcsicmp(record.class_name.c_str(), current_class.c_str()) != 0)
    {
        return false;
    }
    if (!record.title.empty() && !item.title.empty() &&
        _wcsicmp(record.title.c_str(), item.title.c_str()) != 0)
    {
        return false;
    }
    return true;
}

void NativeSessionRecovery::Restore(
    HINSTANCE instance,
    HWND owner,
    CloudOSNativeWindowManager& window_manager)
{
    if (!begun_ || loaded_records_.empty())
    {
        return;
    }

    window_manager.Reconcile();
    const auto current = window_manager.AllManagedWindows();
    std::unordered_set<HWND> restored_external;

    pending_internal_.clear();
    for (const Record& record : loaded_records_)
    {
        if (record.app_id.empty())
        {
            for (const auto& item : current)
            {
                if (restored_external.contains(item.hwnd) || !MatchesExternal(record, item))
                {
                    continue;
                }
                if (window_manager.RestoreWindowState(
                        item.hwnd,
                        record.workspace,
                        record.floating,
                        record.bounds,
                        record.show_command))
                {
                    restored_external.insert(item.hwnd);
                }
                break;
            }
            continue;
        }

        NativeAppLauncher::LaunchById(instance, owner, record.app_id);
        Record pending = record;
        pending.attempts = 0;
        pending_internal_.push_back(std::move(pending));
    }

    window_manager.Reconcile();
    ApplyPending(window_manager);
    loaded_records_.clear();
}

void NativeSessionRecovery::ApplyPending(CloudOSNativeWindowManager& window_manager)
{
    if (pending_internal_.empty())
    {
        return;
    }

    window_manager.Reconcile();
    const auto windows = window_manager.AllManagedWindows();
    std::unordered_set<HWND> used;

    for (Record& pending : pending_internal_)
    {
        if (pending.attempts < 0)
        {
            continue;
        }
        ++pending.attempts;

        for (const auto& item : windows)
        {
            if (item.hwnd == nullptr || !IsWindow(item.hwnd) || used.contains(item.hwnd))
            {
                continue;
            }
            DWORD process_id = 0;
            GetWindowThreadProcessId(item.hwnd, &process_id);
            if (process_id != GetCurrentProcessId())
            {
                continue;
            }

            const std::wstring class_name = ClassName(item.hwnd);
            const std::wstring app_id = AppIdFor(item.hwnd, class_name, item.title);
            if (_wcsicmp(app_id.c_str(), pending.app_id.c_str()) != 0)
            {
                continue;
            }

            if (window_manager.RestoreWindowState(
                    item.hwnd,
                    pending.workspace,
                    pending.floating,
                    pending.bounds,
                    pending.show_command))
            {
                used.insert(item.hwnd);
                pending.attempts = -1;
            }
            break;
        }
    }

    pending_internal_.erase(
        std::remove_if(
            pending_internal_.begin(),
            pending_internal_.end(),
            [](const Record& record)
            {
                return record.attempts < 0 || record.attempts > 12;
            }),
        pending_internal_.end());
}

void NativeSessionRecovery::Tick(CloudOSNativeWindowManager& window_manager)
{
    if (!begun_)
    {
        return;
    }

    ApplyPending(window_manager);
    ++tick_counter_;
    if ((tick_counter_ % 5u) == 0u)
    {
        Save(window_manager);
    }
}

void NativeSessionRecovery::Save(const CloudOSNativeWindowManager& window_manager)
{
    if (!begun_ || state_path_.empty())
    {
        return;
    }

    std::vector<Record> records;
    const auto windows = window_manager.AllManagedWindows();
    records.reserve(windows.size());

    for (const auto& item : windows)
    {
        if (item.hwnd == nullptr || !IsWindow(item.hwnd) || records.size() >= kMaximumRecords)
        {
            continue;
        }

        Record record{};
        record.class_name = ClassName(item.hwnd);
        record.title = item.title;
        record.process_id = item.process_id;
        record.workspace = item.workspace;
        record.floating = item.floating;
        record.app_id = AppIdFor(item.hwnd, record.class_name, record.title);
        if (record.process_id == GetCurrentProcessId() && record.app_id.empty())
        {
            continue;
        }
        if (!GetWindowRect(item.hwnd, &record.bounds))
        {
            continue;
        }

        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        if (GetWindowPlacement(item.hwnd, &placement))
        {
            record.show_command = placement.showCmd;
        }
        records.push_back(std::move(record));
    }

    (void)Write(records);
}

void NativeSessionRecovery::MarkCleanExit(
    const CloudOSNativeWindowManager& window_manager)
{
    if (!begun_)
    {
        return;
    }
    Save(window_manager);
    if (!unclean_marker_path_.empty())
    {
        (void)DeleteFileW(unclean_marker_path_.c_str());
    }
    begun_ = false;
}

bool NativeSessionRecovery::Load()
{
    loaded_records_.clear();
    HANDLE file = CreateFileW(
        state_path_.c_str(),
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
    if (!ReadExact(file, &header, sizeof(header)) ||
        header.magic != kMagic || header.version != kVersion || header.count > kMaximumRecords)
    {
        CloseHandle(file);
        return false;
    }

    bool success = true;
    for (std::uint32_t index = 0; index < header.count; ++index)
    {
        FileRecord disk{};
        if (!ReadExact(file, &disk, sizeof(disk)) ||
            disk.class_length > kMaximumString ||
            disk.title_length > kMaximumString ||
            disk.app_id_length > 128u)
        {
            success = false;
            break;
        }

        Record record{};
        if (!ReadString(file, disk.class_length, &record.class_name) ||
            !ReadString(file, disk.title_length, &record.title) ||
            !ReadString(file, disk.app_id_length, &record.app_id))
        {
            success = false;
            break;
        }
        record.process_id = disk.process_id;
        record.workspace = std::clamp<int>(disk.workspace, 0, 3);
        record.floating = disk.floating != 0;
        record.bounds = RECT{disk.left, disk.top, disk.right, disk.bottom};
        record.show_command = disk.show_command;
        loaded_records_.push_back(std::move(record));
    }

    CloseHandle(file);
    if (!success)
    {
        loaded_records_.clear();
    }
    return success;
}

bool NativeSessionRecovery::Write(const std::vector<Record>& records) const
{
    if (state_path_.empty())
    {
        return false;
    }

    const std::wstring temporary = state_path_ + L".tmp";
    HANDLE file = CreateFileW(
        temporary.c_str(),
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

    FileHeader header{kMagic, kVersion, static_cast<std::uint32_t>(std::min<std::size_t>(records.size(), kMaximumRecords))};
    bool success = WriteExact(file, &header, sizeof(header));
    for (std::uint32_t index = 0; success && index < header.count; ++index)
    {
        const Record& record = records[index];
        const std::uint32_t class_length = static_cast<std::uint32_t>(std::min<std::size_t>(record.class_name.size(), kMaximumString));
        const std::uint32_t title_length = static_cast<std::uint32_t>(std::min<std::size_t>(record.title.size(), kMaximumString));
        const std::uint32_t app_length = static_cast<std::uint32_t>(std::min<std::size_t>(record.app_id.size(), 128u));
        FileRecord disk{
            class_length,
            title_length,
            app_length,
            record.process_id,
            record.workspace,
            record.floating ? 1u : 0u,
            record.bounds.left,
            record.bounds.top,
            record.bounds.right,
            record.bounds.bottom,
            record.show_command};

        success = WriteExact(file, &disk, sizeof(disk));
        if (success && class_length > 0)
        {
            success = WriteExact(file, record.class_name.data(), class_length * sizeof(wchar_t));
        }
        if (success && title_length > 0)
        {
            success = WriteExact(file, record.title.data(), title_length * sizeof(wchar_t));
        }
        if (success && app_length > 0)
        {
            success = WriteExact(file, record.app_id.data(), app_length * sizeof(wchar_t));
        }
    }

    if (success)
    {
        FlushFileBuffers(file);
    }
    CloseHandle(file);

    if (!success || !MoveFileExW(
            temporary.c_str(),
            state_path_.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}
} // namespace CloudOS
