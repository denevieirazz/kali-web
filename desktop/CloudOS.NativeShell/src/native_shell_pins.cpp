#include "native_shell_pins.h"

#include <Windows.h>
#include <KnownFolders.h>
#include <ShlObj.h>

#include <algorithm>
#include <array>
#include <utility>

namespace CloudOS
{
namespace
{
constexpr std::uint32_t kMagic = 0x504E5343u; // CSNP
constexpr std::uint32_t kVersion = 1u;
constexpr std::uint32_t kMaxPins = 128u;
constexpr std::uint32_t kMaxString = 4096u;

bool WriteExact(HANDLE file, const void* data, DWORD bytes)
{
    DWORD written = 0;
    return WriteFile(file, data, bytes, &written, nullptr) != FALSE && written == bytes;
}

bool ReadExact(HANDLE file, void* data, DWORD bytes)
{
    DWORD read = 0;
    return ReadFile(file, data, bytes, &read, nullptr) != FALSE && read == bytes;
}

bool WriteString(HANDLE file, const std::wstring& value)
{
    if (value.size() > kMaxString)
    {
        return false;
    }
    const std::uint32_t length = static_cast<std::uint32_t>(value.size());
    if (!WriteExact(file, &length, sizeof(length)))
    {
        return false;
    }
    if (length == 0)
    {
        return true;
    }
    return WriteExact(
        file,
        value.data(),
        static_cast<DWORD>(length * sizeof(wchar_t)));
}

bool ReadString(HANDLE file, std::wstring& value)
{
    std::uint32_t length = 0;
    if (!ReadExact(file, &length, sizeof(length)) || length > kMaxString)
    {
        return false;
    }
    value.assign(length, L'\0');
    if (length == 0)
    {
        return true;
    }
    return ReadExact(
        file,
        value.data(),
        static_cast<DWORD>(length * sizeof(wchar_t)));
}

bool WritePin(HANDLE file, const ShellPinItem& item)
{
    const auto kind = static_cast<std::uint32_t>(item.kind);
    return WriteExact(file, &kind, sizeof(kind)) &&
        WriteString(file, item.id) &&
        WriteString(file, item.title) &&
        WriteString(file, item.subtitle) &&
        WriteString(file, item.target);
}

bool ReadPin(HANDLE file, ShellPinItem& item)
{
    std::uint32_t kind = 0;
    if (!ReadExact(file, &kind, sizeof(kind)) ||
        (kind != static_cast<std::uint32_t>(ShellPinKind::CloudOSApp) &&
         kind != static_cast<std::uint32_t>(ShellPinKind::WindowsTarget)))
    {
        return false;
    }
    item.kind = static_cast<ShellPinKind>(kind);
    return ReadString(file, item.id) &&
        ReadString(file, item.title) &&
        ReadString(file, item.subtitle) &&
        ReadString(file, item.target);
}

ShellPinItem CloudPin(const wchar_t* id)
{
    ShellPinItem item{};
    item.kind = ShellPinKind::CloudOSApp;
    item.id = id != nullptr ? id : L"";
    return item;
}

template <typename Collection>
void Deduplicate(Collection& items)
{
    Collection unique;
    unique.reserve(items.size());
    for (const auto& item : items)
    {
        if (std::none_of(
                unique.begin(),
                unique.end(),
                [&item](const ShellPinItem& existing)
                {
                    return ShellPinStore::SameIdentity(existing, item);
                }))
        {
            unique.push_back(item);
        }
    }
    items = std::move(unique);
}
}

ShellPinStore& ShellPinStore::Instance()
{
    static ShellPinStore store;
    return store;
}

ShellPinStore::ShellPinStore()
    : storage_path_(StoragePath())
{
    Load();
    std::scoped_lock lock(mutex_);
    EnsureDefaultsLocked();
}

std::wstring ShellPinStore::StoragePath()
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_DEFAULT,
            nullptr,
            &raw)) || raw == nullptr)
    {
        if (raw != nullptr)
        {
            CoTaskMemFree(raw);
        }
        return {};
    }

    std::wstring directory(raw);
    CoTaskMemFree(raw);
    directory += L"\\CloudOS";
    (void)CreateDirectoryW(directory.c_str(), nullptr);
    return directory + L"\\shell_pins_v1.dat";
}

bool ShellPinStore::IsUsable(const ShellPinItem& item) noexcept
{
    if (item.kind == ShellPinKind::CloudOSApp)
    {
        return !item.id.empty();
    }
    return !item.target.empty();
}

bool ShellPinStore::SameIdentity(
    const ShellPinItem& left,
    const ShellPinItem& right) noexcept
{
    if (left.kind != right.kind)
    {
        return false;
    }
    if (left.kind == ShellPinKind::CloudOSApp)
    {
        return _wcsicmp(left.id.c_str(), right.id.c_str()) == 0;
    }
    return _wcsicmp(left.target.c_str(), right.target.c_str()) == 0;
}

void ShellPinStore::Load()
{
    if (storage_path_.empty())
    {
        return;
    }

    HANDLE file = CreateFileW(
        storage_path_.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return;
    }

    std::uint32_t magic = 0;
    std::uint32_t version = 0;
    std::uint32_t start_count = 0;
    std::uint32_t taskbar_count = 0;
    bool valid = ReadExact(file, &magic, sizeof(magic)) &&
        ReadExact(file, &version, sizeof(version)) &&
        ReadExact(file, &start_count, sizeof(start_count)) &&
        ReadExact(file, &taskbar_count, sizeof(taskbar_count)) &&
        magic == kMagic && version == kVersion &&
        start_count <= kMaxPins && taskbar_count <= kMaxPins;

    std::vector<ShellPinItem> start;
    std::vector<ShellPinItem> taskbar;
    if (valid)
    {
        start.reserve(start_count);
        for (std::uint32_t index = 0; index < start_count; ++index)
        {
            ShellPinItem item{};
            if (!ReadPin(file, item) || !IsUsable(item))
            {
                valid = false;
                break;
            }
            start.push_back(std::move(item));
        }
    }
    if (valid)
    {
        taskbar.reserve(taskbar_count);
        for (std::uint32_t index = 0; index < taskbar_count; ++index)
        {
            ShellPinItem item{};
            if (!ReadPin(file, item) || !IsUsable(item))
            {
                valid = false;
                break;
            }
            taskbar.push_back(std::move(item));
        }
    }
    CloseHandle(file);

    if (!valid)
    {
        return;
    }

    Deduplicate(start);
    Deduplicate(taskbar);
    std::scoped_lock lock(mutex_);
    start_pins_ = std::move(start);
    taskbar_pins_ = std::move(taskbar);
}

void ShellPinStore::EnsureDefaultsLocked()
{
    bool changed = false;
    if (start_pins_.empty())
    {
        for (const wchar_t* id : {
                 L"files", L"browser", L"terminal", L"powershell",
                 L"projects", L"drive", L"control", L"settings",
                 L"notepad", L"calc", L"sysmon", L"run"})
        {
            start_pins_.push_back(CloudPin(id));
        }
        changed = true;
    }
    if (taskbar_pins_.empty())
    {
        for (const wchar_t* id : {
                 L"files", L"terminal", L"browser", L"projects", L"control"})
        {
            taskbar_pins_.push_back(CloudPin(id));
        }
        changed = true;
    }
    if (changed)
    {
        SaveLocked();
    }
}

void ShellPinStore::SaveLocked() const
{
    if (storage_path_.empty())
    {
        return;
    }

    const std::wstring temporary = storage_path_ + L".tmp";
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
        return;
    }

    const std::uint32_t start_count = static_cast<std::uint32_t>(
        std::min<std::size_t>(start_pins_.size(), kMaxPins));
    const std::uint32_t taskbar_count = static_cast<std::uint32_t>(
        std::min<std::size_t>(taskbar_pins_.size(), kMaxPins));

    bool success = WriteExact(file, &kMagic, sizeof(kMagic)) &&
        WriteExact(file, &kVersion, sizeof(kVersion)) &&
        WriteExact(file, &start_count, sizeof(start_count)) &&
        WriteExact(file, &taskbar_count, sizeof(taskbar_count));

    for (std::uint32_t index = 0; success && index < start_count; ++index)
    {
        success = WritePin(file, start_pins_[index]);
    }
    for (std::uint32_t index = 0; success && index < taskbar_count; ++index)
    {
        success = WritePin(file, taskbar_pins_[index]);
    }

    if (success)
    {
        (void)FlushFileBuffers(file);
    }
    CloseHandle(file);

    if (!success || !MoveFileExW(
            temporary.c_str(),
            storage_path_.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        (void)DeleteFileW(temporary.c_str());
    }
}

std::vector<ShellPinItem> ShellPinStore::StartPins() const
{
    std::scoped_lock lock(mutex_);
    return start_pins_;
}

std::vector<ShellPinItem> ShellPinStore::TaskbarPins() const
{
    std::scoped_lock lock(mutex_);
    return taskbar_pins_;
}

bool ShellPinStore::IsStartPinned(const ShellPinItem& item) const
{
    std::scoped_lock lock(mutex_);
    return std::any_of(
        start_pins_.begin(),
        start_pins_.end(),
        [&item](const ShellPinItem& existing)
        {
            return SameIdentity(existing, item);
        });
}

bool ShellPinStore::IsTaskbarPinned(const ShellPinItem& item) const
{
    std::scoped_lock lock(mutex_);
    return std::any_of(
        taskbar_pins_.begin(),
        taskbar_pins_.end(),
        [&item](const ShellPinItem& existing)
        {
            return SameIdentity(existing, item);
        });
}

void ShellPinStore::PinStart(const ShellPinItem& item)
{
    if (!IsUsable(item))
    {
        return;
    }
    std::scoped_lock lock(mutex_);
    if (start_pins_.size() >= kMaxPins || std::any_of(
            start_pins_.begin(), start_pins_.end(),
            [&item](const ShellPinItem& existing) { return SameIdentity(existing, item); }))
    {
        return;
    }
    start_pins_.push_back(item);
    SaveLocked();
}

void ShellPinStore::UnpinStart(const ShellPinItem& item)
{
    std::scoped_lock lock(mutex_);
    const auto previous = start_pins_.size();
    std::erase_if(
        start_pins_,
        [&item](const ShellPinItem& existing) { return SameIdentity(existing, item); });
    if (start_pins_.size() != previous)
    {
        SaveLocked();
    }
}

void ShellPinStore::ToggleStart(const ShellPinItem& item)
{
    if (IsStartPinned(item))
    {
        UnpinStart(item);
    }
    else
    {
        PinStart(item);
    }
}

void ShellPinStore::PinTaskbar(const ShellPinItem& item)
{
    if (!IsUsable(item))
    {
        return;
    }
    std::scoped_lock lock(mutex_);
    if (taskbar_pins_.size() >= kMaxPins || std::any_of(
            taskbar_pins_.begin(), taskbar_pins_.end(),
            [&item](const ShellPinItem& existing) { return SameIdentity(existing, item); }))
    {
        return;
    }
    taskbar_pins_.push_back(item);
    SaveLocked();
}

void ShellPinStore::UnpinTaskbar(const ShellPinItem& item)
{
    std::scoped_lock lock(mutex_);
    const auto previous = taskbar_pins_.size();
    std::erase_if(
        taskbar_pins_,
        [&item](const ShellPinItem& existing) { return SameIdentity(existing, item); });
    if (taskbar_pins_.size() != previous)
    {
        SaveLocked();
    }
}

void ShellPinStore::ToggleTaskbar(const ShellPinItem& item)
{
    if (IsTaskbarPinned(item))
    {
        UnpinTaskbar(item);
    }
    else
    {
        PinTaskbar(item);
    }
}

void ShellPinStore::MoveStart(std::size_t from, std::size_t to)
{
    std::scoped_lock lock(mutex_);
    if (from >= start_pins_.size() || to >= start_pins_.size() || from == to)
    {
        return;
    }
    ShellPinItem item = std::move(start_pins_[from]);
    start_pins_.erase(start_pins_.begin() + static_cast<std::ptrdiff_t>(from));
    start_pins_.insert(start_pins_.begin() + static_cast<std::ptrdiff_t>(to), std::move(item));
    SaveLocked();
}

void ShellPinStore::MoveTaskbar(std::size_t from, std::size_t to)
{
    std::scoped_lock lock(mutex_);
    if (from >= taskbar_pins_.size() || to >= taskbar_pins_.size() || from == to)
    {
        return;
    }
    ShellPinItem item = std::move(taskbar_pins_[from]);
    taskbar_pins_.erase(taskbar_pins_.begin() + static_cast<std::ptrdiff_t>(from));
    taskbar_pins_.insert(taskbar_pins_.begin() + static_cast<std::ptrdiff_t>(to), std::move(item));
    SaveLocked();
}

} // namespace CloudOS
