#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace CloudOS
{
struct NativeFilesPersistedState final
{
    std::vector<std::wstring> favorites;
    std::vector<std::wstring> tabs;
    std::size_t active_tab{};
    bool preview_visible{true};
};

class NativeFilesStateStore final
{
public:
    static NativeFilesPersistedState Load();
    static bool Save(const NativeFilesPersistedState& state) noexcept;

    static bool ContainsFavorite(
        const NativeFilesPersistedState& state,
        const std::wstring& path) noexcept;
    static bool AddFavorite(
        NativeFilesPersistedState* state,
        const std::wstring& path) noexcept;
    static bool RemoveFavorite(
        NativeFilesPersistedState* state,
        const std::wstring& path) noexcept;

    static constexpr std::size_t MaximumTabs = 24;
    static constexpr std::size_t MaximumFavorites = 64;
    static constexpr std::size_t MaximumPathCharacters = 8192;
};
} // namespace CloudOS
