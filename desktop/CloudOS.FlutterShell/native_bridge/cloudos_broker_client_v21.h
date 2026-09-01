#pragma once

#include <Windows.h>

#include <atomic>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
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
    bool battery_available{false};
    int battery_percent{-1};
    bool network_available{false};
    std::string network_name;
    bool volume_available{false};
    double volume{0.0};
    bool brightness_available{false};
    double brightness{0.0};
    bool wsl_available{false};
    std::vector<std::string> distros;
    int current_workspace{1};
    uint64_t timestamp_ms{0};
};

using BrokerEventCallback = std::function<void(
    const std::string& event_name,
    const std::string& serialized_event)>;

class CloudOSBrokerClientV21 final
{
public:
    static CloudOSBrokerClientV21& Instance();

    CloudOSBrokerClientV21(const CloudOSBrokerClientV21&) = delete;
    CloudOSBrokerClientV21& operator=(const CloudOSBrokerClientV21&) = delete;

    bool EnsureConnected();
    void Disconnect();

    [[nodiscard]] bool IsConnected() const noexcept
    {
        return state_.load() == BrokerConnectionState::Connected;
    }
    [[nodiscard]] BrokerConnectionState GetConnectionState() const noexcept
    {
        return state_.load();
    }

    bool GetApps(std::vector<BrokerClientAppItem>& out_apps);
    bool LaunchApp(const std::string& app_id, std::string& err);
    bool GetSystemSnapshot(BrokerClientSnapshot& out_snapshot);
    bool SetVolume(double value);
    bool SetBrightness(double value);
    bool GetCapabilities(std::vector<std::string>& out_caps);
    bool InvokeBrokerRpc(
        const std::string& method,
        const std::string& payload_json,
        std::string& out_resp_json);

    // V23 reactive transport. Subscriptions are retained as desired state and
    // automatically reconciled after a successful reconnect. The callback is
    // invoked on the dedicated broker reader thread and therefore must marshal
    // UI work to the Flutter/Win32 platform thread.
    void SetEventCallback(BrokerEventCallback callback);
    bool ConfigureEventSubscriptions(const std::vector<std::string>& patterns);
    [[nodiscard]] size_t DesiredEventSubscriptionCount() const;

private:
    CloudOSBrokerClientV21() = default;
    ~CloudOSBrokerClientV21();

    struct PendingResponse final
    {
        std::mutex mutex;
        std::condition_variable cv;
        bool completed{false};
        bool failed{false};
        std::string response;
    };

    bool TryConnectPipeLocked();
    bool PerformHandshakeLocked();
    void SpawnBrokerIfNeeded();
    void CloseConnectionLocked();
    void StartReaderLocked();
    void ReaderLoop(HANDLE pipe);
    void HandleIncomingFrame(const std::string& frame);
    void FailAllPending();

    bool WriteFrame(HANDLE pipe, const std::string& payload) const;
    bool ReadFrame(HANDLE pipe, std::string& payload) const;

    bool ReconcileEventSubscriptions();
    bool SendSubscriptionRpc(const char* method, const std::string& pattern);

    mutable std::mutex connection_mutex_;
    mutable std::mutex write_mutex_;
    mutable std::mutex pending_mutex_;
    mutable std::mutex event_callback_mutex_;
    mutable std::mutex subscriptions_mutex_;

    HANDLE pipe_{INVALID_HANDLE_VALUE};
    std::thread reader_thread_;
    std::atomic_bool reader_stop_{false};
    std::atomic<BrokerConnectionState> state_{BrokerConnectionState::Disconnected};
    std::atomic_uint64_t next_req_id_{1};
    std::atomic_uint64_t last_spawn_attempt_ms_{0};

    std::unordered_map<std::string, std::shared_ptr<PendingResponse>> pending_responses_;
    BrokerEventCallback event_callback_;
    std::vector<std::string> desired_subscriptions_;
    std::unordered_set<std::string> active_subscriptions_;

    static constexpr size_t kMaxPendingResponses = 128;
    static constexpr DWORD kRpcTimeoutMs = 10000;
};

} // namespace CloudOS
