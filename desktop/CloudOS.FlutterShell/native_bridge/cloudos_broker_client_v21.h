#pragma once

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

struct BrokerClientSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{1};
    bool battery_available{true};
    int battery_percent{100};
    bool network_available{true};
    std::string network_name;
    double volume{0.72};
    bool brightness_available{true};
    double brightness{0.85};
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
    bool LaunchApp(const std::string& app_id, std::string& err);
    bool GetSystemSnapshot(BrokerClientSnapshot& out_snapshot);
    bool SetVolume(double value);
    bool SetBrightness(double value);
    bool GetCapabilities(std::vector<std::string>& out_caps);

private:
    CloudOSBrokerClientV21() = default;
    ~CloudOSBrokerClientV21();

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
