#pragma once

#include <cstddef>
#include <cstdint>

namespace CloudOS::ShellNotificationV21
{
inline constexpr std::uint32_t kSchema = 21;
inline constexpr std::uintptr_t kCopyDataTag = static_cast<std::uintptr_t>(0x434F534E56323100ull);
inline constexpr std::size_t kMaxItems = 100;
inline constexpr std::size_t kMappingNameChars = 96;
inline constexpr std::size_t kTitleChars = 160;
inline constexpr std::size_t kMessageChars = 640;
inline constexpr wchar_t kMappingPrefix[] = L"Local\\CloudOS.NotificationSnapshot.v21.";

enum class Action : std::uint32_t
{
    Query = 1,
    MarkAllRead = 2,
    Dismiss = 3,
    Clear = 4,
};

struct Request final
{
    std::uint32_t schema{kSchema};
    Action action{Action::Query};
    std::uint64_t notification_id{};
    wchar_t mapping_name[kMappingNameChars]{};
};

struct Item final
{
    std::uint64_t id{};
    std::uint16_t year{};
    std::uint16_t month{};
    std::uint16_t day{};
    std::uint16_t hour{};
    std::uint16_t minute{};
    std::uint16_t second{};
    std::int32_t severity{};
    std::uint32_t read{};
    wchar_t title[kTitleChars]{};
    wchar_t message[kMessageChars]{};
};

struct Snapshot final
{
    std::uint32_t schema{kSchema};
    std::uint32_t count{};
    std::uint32_t unread_count{};
    std::uint32_t reserved{};
    std::uint64_t revision{};
    Item items[kMaxItems]{};
};

[[nodiscard]] constexpr bool IsSupported(Action action) noexcept
{
    return action == Action::Query ||
        action == Action::MarkAllRead ||
        action == Action::Dismiss ||
        action == Action::Clear;
}
} // namespace CloudOS::ShellNotificationV21
