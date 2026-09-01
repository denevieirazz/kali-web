#pragma once

#include "protocol_v21.h"

#include <chrono>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace CloudOS
{

struct FileItemV21 final
{
    std::string name;
    std::string path;
    bool is_folder{};
    std::string size_formatted;
    std::string modified_formatted;
    std::string source;
    std::string extension;
    std::string entry_id;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class FileServiceV21 final
{
public:
    static FileServiceV21& Instance();

    FileServiceV21(const FileServiceV21&) = delete;
    FileServiceV21& operator=(const FileServiceV21&) = delete;

    bool ListLocation(
        const std::string& location,
        std::vector<FileItemV21>& items,
        std::string& error);

    bool ListEntry(
        const std::string& entry_id,
        std::vector<FileItemV21>& items,
        std::string& error);

    bool OpenEntry(
        const std::string& entry_id,
        std::string& error);

    [[nodiscard]] static bool IsAllowedLocation(const std::string& location) noexcept;

private:
    using Clock = std::chrono::steady_clock;

    struct EntryCapability final
    {
        std::wstring path;
        bool is_folder{};
        Clock::time_point expires_at{};
    };

    FileServiceV21() = default;

    void AttachCapabilities(std::vector<FileItemV21>& items);
    std::string IssueCapability(const std::wstring& path, bool is_folder);
    bool ResolveCapability(
        const std::string& entry_id,
        EntryCapability& capability,
        std::string& error);
    void CleanupExpiredLocked(Clock::time_point now);

    static constexpr std::size_t kMaxCapabilities = 4096;
    static constexpr auto kCapabilityLifetime = std::chrono::minutes(30);

    std::mutex capabilities_mutex_;
    std::unordered_map<std::string, EntryCapability> capabilities_;
};

} // namespace CloudOS
