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

struct DriveItemV21 final
{
    std::string mount_path;
    std::string label;
    std::string drive_type; // "fixed", "removable", "wsl", "network", "cdrom"
    std::uint64_t total_bytes{};
    std::uint64_t free_bytes{};
    std::string total_formatted;
    std::string free_formatted;
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

    bool CreateFolder(
        const std::string& parent_entry_id,
        const std::string& name,
        FileItemV21& out_created_item,
        std::string& error);

    bool RenameItem(
        const std::string& entry_id,
        const std::string& new_name,
        FileItemV21& out_renamed_item,
        std::string& error);

    bool DeleteItems(
        const std::vector<std::string>& entry_ids,
        bool permanent,
        std::vector<std::string>& deleted_entry_ids,
        std::string& error);

    bool CopyOrMoveItemsAsync(
        const std::string& type, // "copy" or "move"
        const std::vector<std::string>& source_entry_ids,
        const std::string& destination_entry_id,
        const std::string& conflict_strategy,
        std::string& out_job_id,
        std::string& error);
    bool CopyOrMoveItemsAsync(
        const std::string& type,
        const std::vector<std::string>& source_entry_ids,
        const std::string& destination_entry_id,
        std::string& out_job_id,
        std::string& error)
    {
        return CopyOrMoveItemsAsync(type, source_entry_ids, destination_entry_id, "replace", out_job_id, error);
    }

    bool ListDrives(
        std::vector<DriveItemV21>& out_drives,
        std::string& error);

    [[nodiscard]] static bool IsAllowedLocation(const std::string& location) noexcept;
    [[nodiscard]] static bool IsProtectedSystemPath(const std::wstring& path);

    std::string IssueCapability(const std::wstring& path, bool is_folder);

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
    bool ResolveCapability(
        const std::string& entry_id,
        EntryCapability& capability,
        std::string& error);
    void CleanupExpiredLocked(Clock::time_point now);

    static constexpr std::size_t kMaxCapabilities = 131072;
    static constexpr auto kCapabilityLifetime = std::chrono::minutes(60);

    std::mutex capabilities_mutex_;
    std::unordered_map<std::string, EntryCapability> capabilities_;
};

} // namespace CloudOS
