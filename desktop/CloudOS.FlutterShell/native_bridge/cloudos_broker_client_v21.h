#pragma once

#if __has_include("../../CloudOS.SystemBroker/src/protocol_v21.h")
#include "../../CloudOS.SystemBroker/src/protocol_v21.h"
#else
#include "protocol_v21.h"
#endif

#include <Windows.h>

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
    std::string platform;
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    bool can_launch{true};
    bool can_uninstall{false};
    bool can_update{false};
    std::string icon_key;
    bool pinned{false};
    bool recent{false};
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

struct BrokerClientSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{1};
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
    int current_workspace{1};
    uint64_t timestamp_ms{0};
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

    bool LaunchApp(const std::string& app_id, std::string& err);
    bool GetSystemSnapshot(BrokerClientSnapshot& out_snapshot);
    bool SetVolume(double value);
    bool SetBrightness(double value);
    bool GetCapabilities(std::vector<std::string>& out_caps);

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
    std::string client_id_;
    std::string server_instance_id_;
    std::vector<std::string> capabilities_;
};

} // namespace CloudOS
