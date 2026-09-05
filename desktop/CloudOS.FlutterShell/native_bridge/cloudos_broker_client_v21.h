#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#if __has_include("../../CloudOS.SystemBroker/src/protocol_v21.h")
#include "../../CloudOS.SystemBroker/src/protocol_v21.h"
#else
#include "protocol_v21.h"
#endif

#include <Windows.h>

#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

#include <atomic>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

enum class BrokerConnectionState
{
    Disconnected,
    Connecting,
    Connected,
    Degraded
};

std::string ConnectionStateToString(BrokerConnectionState s);

struct BrokerClientAppItem final
{
    std::string id;
    std::string name;
    std::string display_name;
    std::string platform;
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    std::string launch_target;
    std::string availability{"ready"};
    std::vector<std::string> capabilities;
    bool can_launch{true};
    bool can_uninstall{false};
    bool can_update{false};
    std::string icon_key;
    bool pinned{false};
    bool recent{false};
};

struct BrokerClientDistroInfo final
{
    std::string id;
    std::string name;
    std::string guid;
    uint32_t version{2};
    std::string state{"Stopped"};
    std::string base_path;
    uint32_t default_uid{0};
    uint32_t flags{15};
    bool is_default{false};
};

struct BrokerClientMountPoint final
{
    std::string id;
    std::string label;
    std::string path;
    std::string platform;
    bool is_online{true};
};

struct BrokerClientPathTranslation final
{
    std::string original_path;
    std::string translated_path;
    std::string target;
    std::string distro;
    bool exists{false};
};

struct BrokerClientLaunchResult final
{
    std::string id;
    std::string status{"failed"};
    bool launched{false};
    std::string platform{"windows"};
    std::string target;
    std::string message;
};

struct BrokerClientFileItem final
{
    std::string name;
    std::string path;
    bool is_folder{};
    std::string size_formatted;
    std::string modified_formatted;
    std::string source;
    std::string extension;
    std::string entry_id;
};

struct BrokerClientDriveItem final
{
    std::string mount_path;
    std::string label;
    std::string drive_type;
    uint64_t total_bytes{0};
    uint64_t free_bytes{0};
    std::string total_formatted;
    std::string free_formatted;
    std::string entry_id;
};

struct BrokerClientSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{0};
    bool battery_available{false};
    int battery_percent{};
    bool network_available{false};
    std::string network_name;
    bool volume_available{false};
    double volume{};
    bool brightness_available{false};
    double brightness{};
    bool wsl_available{false};
    std::vector<std::string> distros;
    std::string default_distro;
    int current_workspace{1};
    uint64_t timestamp_ms{0};
};

struct BrokerClientPerformanceProfile final
{
    std::string profile{"balanced"};
    int64_t total_ram_mb{0};
    int64_t free_ram_mb{0};
    int64_t memory_load_percent{0};
    int64_t cpu_cores{0};
    bool on_battery{false};
    int64_t battery_percent{-1};
    bool is_low_end_hardware{false};
};

class CloudOSBrokerClientV21 final
{
public:
    static CloudOSBrokerClientV21& Instance();

    CloudOSBrokerClientV21(const CloudOSBrokerClientV21&) = delete;
    CloudOSBrokerClientV21& operator=(const CloudOSBrokerClientV21&) = delete;

    bool EnsureConnected();
    void Disconnect();

    [[nodiscard]] bool IsConnected() const noexcept { return state_.load() == BrokerConnectionState::Connected; }
    [[nodiscard]] BrokerConnectionState GetConnectionState() const noexcept { return state_.load(); }

    bool GetApps(std::vector<BrokerClientAppItem>& out_apps);

    bool GetFiles(const std::string& location, std::vector<BrokerClientFileItem>& out_files)
    {
        return GetFilesByCapability("files.list", "location", location, out_files);
    }

    bool GetFilesEntry(
        const std::string& entry_id,
        std::vector<BrokerClientFileItem>& out_files)
    {
        return GetFilesByCapability("files.listEntry", "entryId", entry_id, out_files);
    }

    bool OpenFileEntry(const std::string& entry_id)
    {
        if (!EnsureConnected() || entry_id.empty()) return false;

        JsonObject payload;
        payload["entryId"] = JsonValue(entry_id);

        BrokerRequest request;
        request.protocol = kProtocolVersion;
        request.id = "open-file-entry-" + std::to_string(next_req_id_.fetch_add(1));
        request.method = "files.openEntry";
        request.payload = std::move(payload);

        std::string raw_response;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
            {
                state_.store(BrokerConnectionState::Degraded);
                return false;
            }
        }

        BrokerResponse response;
        std::string parse_error;
        if (!ParseResponse(raw_response, response, parse_error) || !response.ok) return false;
        const auto opened_it = response.payload.find("opened");
        return opened_it != response.payload.end() &&
            opened_it->second.IsBool() &&
            opened_it->second.AsBool();
    }

    bool CreateFolder(
        const std::string& parent_entry_id,
        const std::string& name,
        BrokerClientFileItem& out_item,
        std::string& err);

    bool RenameFile(
        const std::string& entry_id,
        const std::string& new_name,
        BrokerClientFileItem& out_item,
        std::string& err);

    bool DeleteFiles(
        const std::vector<std::string>& entry_ids,
        bool permanent,
        std::vector<std::string>& out_deleted_ids,
        std::string& err);

    bool CopyOrMoveFiles(
        const std::string& type,
        const std::vector<std::string>& source_ids,
        const std::string& destination_id,
        std::string& out_job_id,
        std::string& err);

    bool CancelFileOperation(const std::string& job_id);

    bool ListDrives(
        std::vector<BrokerClientDriveItem>& out_drives,
        std::string& err);

    bool LaunchApp(const std::string& app_id, std::string& err);
    bool LaunchAppStructured(const std::string& app_id, BrokerClientLaunchResult& out_result, std::string& err);
    bool ListWslDistros(std::vector<BrokerClientDistroInfo>& out_distros, std::string& out_default_distro, bool& out_available);
    bool TranslatePath(const std::string& path, const std::string& target, const std::string& distro, BrokerClientPathTranslation& out_result);
    bool GetMountPoints(std::vector<BrokerClientMountPoint>& out_mounts);
    bool GetSystemSnapshot(BrokerClientSnapshot& out_snapshot);
    bool SetVolume(double value);
    bool SetBrightness(double value);
    bool GetPerformanceProfile(BrokerClientPerformanceProfile& out_profile);
    bool SetPerformanceProfile(const std::string& profile);
    bool GetCapabilities(std::vector<std::string>& out_caps);
    bool GetWindowSnapshot(std::string& out_snapshot_json);
    bool ExecuteWindowCommand(
        const std::string& action,
        uint64_t hwnd,
        int x = 0,
        int y = 0,
        int width = 0,
        int height = 0,
        int workspace = 1,
        const std::string& snap = "",
        bool fullscreen = false);

private:
    CloudOSBrokerClientV21() = default;
    ~CloudOSBrokerClientV21();

    bool GetFilesByCapability(
        const char* method,
        const char* argument_name,
        const std::string& argument,
        std::vector<BrokerClientFileItem>& out_files)
    {
        if (!EnsureConnected() || argument.empty()) return false;

        JsonObject payload;
        payload[argument_name] = JsonValue(argument);

        BrokerRequest request;
        request.protocol = kProtocolVersion;
        request.id = "get-files-" + std::to_string(next_req_id_.fetch_add(1));
        request.method = method;
        request.payload = std::move(payload);

        std::string raw_response;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
            {
                state_.store(BrokerConnectionState::Degraded);
                return false;
            }
        }

        BrokerResponse response;
        std::string parse_error;
        if (!ParseResponse(raw_response, response, parse_error) || !response.ok) return false;
        return ParseFilesPayload(response, out_files);
    }

    static bool ParseFilesPayload(
        const BrokerResponse& response,
        std::vector<BrokerClientFileItem>& out_files)
    {
        const auto files_it = response.payload.find("files");
        if (files_it == response.payload.end() || !files_it->second.IsArray()) return false;

        std::vector<BrokerClientFileItem> parsed;
        parsed.reserve(files_it->second.AsArray().size());
        for (const JsonValue& value : files_it->second.AsArray())
        {
            if (!value.IsObject()) continue;
            const JsonObject& object = value.AsObject();

            const auto string_field = [&object](const char* key) -> std::string
            {
                const auto it = object.find(key);
                return it != object.end() && it->second.IsString()
                    ? it->second.AsString()
                    : std::string{};
            };

            const std::string name = string_field("name");
            const std::string path = string_field("path");
            const std::string entry_id = string_field("entryId");
            if (name.empty() || path.empty() || entry_id.empty()) continue;

            BrokerClientFileItem item;
            item.name = name;
            item.path = path;
            const auto folder_it = object.find("isFolder");
            item.is_folder = folder_it != object.end() && folder_it->second.IsBool()
                ? folder_it->second.AsBool()
                : false;
            item.size_formatted = string_field("sizeFormatted");
            item.modified_formatted = string_field("modifiedFormatted");
            item.source = string_field("source");
            item.extension = string_field("extension");
            item.entry_id = entry_id;
            parsed.push_back(std::move(item));
        }

        out_files = std::move(parsed);
        return true;
    }

    bool TryConnectPipe();
    bool PerformHandshake();
    void SpawnBrokerIfNeeded();

    bool SendFrame(const std::string& payload);
    bool ReadFrame(std::string& payload);

    mutable std::mutex mutex_;
    HANDLE pipe_{INVALID_HANDLE_VALUE};
    std::atomic<BrokerConnectionState> state_{BrokerConnectionState::Disconnected};
    std::atomic_uint64_t next_req_id_{1};
    std::atomic_uint64_t last_spawn_attempt_ms_{0};
    std::string client_id_;
    std::string server_instance_id_;
    std::vector<std::string> capabilities_;
};

} // namespace CloudOS
