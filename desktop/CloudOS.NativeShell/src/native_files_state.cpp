#include "native_files_state.h"

#include <Windows.h>
#include <ShlObj.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwchar>
#include <limits>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr std::array<char, 8> kMagic{{'C', 'L', 'D', 'F', 'I', 'L', 'E', '5'}};
constexpr std::uint32_t kVersion = 1;
constexpr std::uint32_t kFlagPreviewVisible = 1u << 0;
constexpr std::uint64_t kMaximumStateBytes = 4ull * 1024ull * 1024ull;

struct DiskHeader final
{
    char magic[8]{};
    std::uint32_t version{};
    std::uint32_t flags{};
    std::uint32_t favorite_count{};
    std::uint32_t tab_count{};
    std::uint32_t active_tab{};
    std::uint32_t reserved{};
};

std::wstring JoinPath(const std::wstring& left, const wchar_t* right)
{
    if (left.empty()) return right == nullptr ? std::wstring{} : std::wstring(right);
    std::wstring result = left;
    if (result.back() != L'\\') result.push_back(L'\\');
    if (right != nullptr) result += right;
    return result;
}

std::wstring StateDirectory()
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &raw)) || raw == nullptr)
        return {};
    std::wstring root(raw);
    CoTaskMemFree(raw);
    root = JoinPath(root, L"CloudOS");
    (void)CreateDirectoryW(root.c_str(), nullptr);
    root = JoinPath(root, L"FilesV5");
    (void)CreateDirectoryW(root.c_str(), nullptr);
    return root;
}

std::wstring StatePath()
{
    const std::wstring directory = StateDirectory();
    return directory.empty() ? std::wstring{} : JoinPath(directory, L"state.dat");
}

bool ReadExact(HANDLE file, void* destination, DWORD bytes) noexcept
{
    auto* cursor = static_cast<std::byte*>(destination);
    DWORD remaining = bytes;
    while (remaining > 0)
    {
        DWORD read = 0;
        if (!ReadFile(file, cursor, remaining, &read, nullptr) || read == 0) return false;
        cursor += read;
        remaining -= read;
    }
    return true;
}

bool WriteExact(HANDLE file, const void* source, DWORD bytes) noexcept
{
    const auto* cursor = static_cast<const std::byte*>(source);
    DWORD remaining = bytes;
    while (remaining > 0)
    {
        DWORD written = 0;
        if (!WriteFile(file, cursor, remaining, &written, nullptr) || written == 0) return false;
        cursor += written;
        remaining -= written;
    }
    return true;
}

bool ReadString(HANDLE file, std::wstring* value)
{
    if (value == nullptr) return false;
    std::uint32_t length = 0;
    if (!ReadExact(file, &length, sizeof(length))) return false;
    if (length == 0 || length > NativeFilesStateStore::MaximumPathCharacters) return false;
    if (length > std::numeric_limits<DWORD>::max() / sizeof(wchar_t)) return false;
    value->assign(length, L'\0');
    return ReadExact(
        file,
        value->data(),
        static_cast<DWORD>(length * sizeof(wchar_t)));
}

bool WriteString(HANDLE file, const std::wstring& value) noexcept
{
    if (value.empty() || value.size() > NativeFilesStateStore::MaximumPathCharacters ||
        value.size() > std::numeric_limits<std::uint32_t>::max())
        return false;
    const auto length = static_cast<std::uint32_t>(value.size());
    if (!WriteExact(file, &length, sizeof(length))) return false;
    return WriteExact(
        file,
        value.data(),
        static_cast<DWORD>(value.size() * sizeof(wchar_t)));
}

bool IsUsablePath(const std::wstring& path) noexcept
{
    return !path.empty() && path.size() <= NativeFilesStateStore::MaximumPathCharacters &&
        path.find(L'\0') == std::wstring::npos;
}

void Normalize(NativeFilesPersistedState* state)
{
    if (state == nullptr) return;
    auto sanitize = [](std::vector<std::wstring>* values, std::size_t maximum)
    {
        if (values == nullptr) return;
        values->erase(
            std::remove_if(values->begin(), values->end(), [](const std::wstring& path)
            {
                return !IsUsablePath(path);
            }),
            values->end());
        std::vector<std::wstring> unique;
        unique.reserve(std::min(values->size(), maximum));
        for (const auto& path : *values)
        {
            const bool duplicate = std::any_of(unique.cbegin(), unique.cend(), [&path](const std::wstring& existing)
            {
                return _wcsicmp(existing.c_str(), path.c_str()) == 0;
            });
            if (!duplicate) unique.push_back(path);
            if (unique.size() >= maximum) break;
        }
        *values = std::move(unique);
    };
    sanitize(&state->favorites, NativeFilesStateStore::MaximumFavorites);
    sanitize(&state->tabs, NativeFilesStateStore::MaximumTabs);
    if (state->tabs.empty()) state->active_tab = 0;
    else state->active_tab = std::min(state->active_tab, state->tabs.size() - 1);
}
} // namespace

NativeFilesPersistedState NativeFilesStateStore::Load()
{
    NativeFilesPersistedState state{};
    const std::wstring path = StatePath();
    if (path.empty()) return state;

    HANDLE file = CreateFileW(
        path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) return state;

    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < static_cast<LONGLONG>(sizeof(DiskHeader)) ||
        static_cast<std::uint64_t>(size.QuadPart) > kMaximumStateBytes)
    {
        CloseHandle(file);
        return state;
    }

    DiskHeader header{};
    const bool header_ok = ReadExact(file, &header, sizeof(header)) &&
        std::equal(kMagic.cbegin(), kMagic.cend(), header.magic) &&
        header.version == kVersion &&
        header.favorite_count <= MaximumFavorites &&
        header.tab_count <= MaximumTabs;
    if (!header_ok)
    {
        CloseHandle(file);
        return {};
    }

    state.preview_visible = (header.flags & kFlagPreviewVisible) != 0;
    state.active_tab = header.active_tab;
    state.favorites.reserve(header.favorite_count);
    state.tabs.reserve(header.tab_count);

    bool valid = true;
    for (std::uint32_t index = 0; index < header.favorite_count && valid; ++index)
    {
        std::wstring value;
        valid = ReadString(file, &value);
        if (valid) state.favorites.push_back(std::move(value));
    }
    for (std::uint32_t index = 0; index < header.tab_count && valid; ++index)
    {
        std::wstring value;
        valid = ReadString(file, &value);
        if (valid) state.tabs.push_back(std::move(value));
    }
    CloseHandle(file);
    if (!valid) return {};
    Normalize(&state);
    return state;
}

bool NativeFilesStateStore::Save(const NativeFilesPersistedState& source) noexcept
{
    NativeFilesPersistedState state = source;
    Normalize(&state);
    const std::wstring path = StatePath();
    if (path.empty()) return false;
    const std::wstring temporary = path + L".tmp";

    HANDLE file = CreateFileW(
        temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    DiskHeader header{};
    std::copy(kMagic.cbegin(), kMagic.cend(), header.magic);
    header.version = kVersion;
    header.flags = state.preview_visible ? kFlagPreviewVisible : 0;
    header.favorite_count = static_cast<std::uint32_t>(state.favorites.size());
    header.tab_count = static_cast<std::uint32_t>(state.tabs.size());
    header.active_tab = static_cast<std::uint32_t>(state.active_tab);

    bool success = WriteExact(file, &header, sizeof(header));
    for (const auto& value : state.favorites)
        success = success && WriteString(file, value);
    for (const auto& value : state.tabs)
        success = success && WriteString(file, value);
    if (success) success = FlushFileBuffers(file) != FALSE;
    CloseHandle(file);

    if (!success)
    {
        (void)DeleteFileW(temporary.c_str());
        return false;
    }
    if (!MoveFileExW(
            temporary.c_str(), path.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    {
        (void)DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

bool NativeFilesStateStore::ContainsFavorite(
    const NativeFilesPersistedState& state,
    const std::wstring& path) noexcept
{
    if (!IsUsablePath(path)) return false;
    return std::any_of(state.favorites.cbegin(), state.favorites.cend(), [&path](const std::wstring& existing)
    {
        return _wcsicmp(existing.c_str(), path.c_str()) == 0;
    });
}

bool NativeFilesStateStore::AddFavorite(
    NativeFilesPersistedState* state,
    const std::wstring& path) noexcept
{
    if (state == nullptr || !IsUsablePath(path) || ContainsFavorite(*state, path) ||
        state->favorites.size() >= MaximumFavorites)
        return false;
    state->favorites.push_back(path);
    return true;
}

bool NativeFilesStateStore::RemoveFavorite(
    NativeFilesPersistedState* state,
    const std::wstring& path) noexcept
{
    if (state == nullptr || !IsUsablePath(path)) return false;
    const auto before = state->favorites.size();
    state->favorites.erase(
        std::remove_if(state->favorites.begin(), state->favorites.end(), [&path](const std::wstring& existing)
        {
            return _wcsicmp(existing.c_str(), path.c_str()) == 0;
        }),
        state->favorites.end());
    return state->favorites.size() != before;
}
} // namespace CloudOS
