#pragma once

#include "cloudos_broker_client_v21.h"

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <Windows.h>

#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct NativeAppItem final
{
    std::string id;
    std::string name;
    std::string platform; // "windows", "linux", "cloudos"
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    bool can_launch{true};
    bool pinned{false};
    bool recent{false};
};

struct NativeSystemSnapshot final
{
    std::string device_name;
    std::string network_name;
    double volume{0.0};
    double brightness{0.0};
    int battery_percent{-1};
    bool wsl_available{false};
    std::vector<std::string> distros;
    int current_workspace{1};
};

class CloudOSFlutterBridgeV20 final
{
public:
    static void RegisterWithMessenger(
        flutter::BinaryMessenger* messenger,
        HWND window_handle);

    static CloudOSFlutterBridgeV20& Instance();

    CloudOSFlutterBridgeV20(const CloudOSFlutterBridgeV20&) = delete;
    CloudOSFlutterBridgeV20& operator=(const CloudOSFlutterBridgeV20&) = delete;

    void Initialize(HWND window_handle);

    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    std::vector<NativeAppItem> GetApps();
    NativeSystemSnapshot GetSystemSnapshot();
    bool LaunchApp(const std::string& app_id);
    bool SetVolume(double volume);
    bool SetBrightness(double brightness);

    [[nodiscard]] bool IsRegistered() const noexcept { return is_registered_.load(); }
    [[nodiscard]] bool IsEventStreamActive() const noexcept { return event_stream_active_.load(); }
    [[nodiscard]] uint64_t DroppedBrokerEventCount() const noexcept { return dropped_broker_events_.load(); }

private:
    CloudOSFlutterBridgeV20() = default;
    ~CloudOSFlutterBridgeV20();

    bool StartBrokerEventStream();
    void QueueBrokerEvent(const std::string& event_name, const std::string& serialized_event);
    void DrainBrokerEventsOnPlatformThread();
    static VOID CALLBACK EventDrainTimerProc(HWND hwnd, UINT message, UINT_PTR timer_id, DWORD time);

    void RefreshAppCatalog();
    void RefreshSystemSnapshot();

    HWND window_handle_{nullptr};
    std::atomic_bool is_registered_{false};
    std::atomic_bool event_stream_active_{false};
    std::atomic_bool event_drain_scheduled_{false};
    std::atomic_uint64_t dropped_broker_events_{0};

    mutable std::mutex mutex_;
    mutable std::mutex event_queue_mutex_;
    std::vector<NativeAppItem> cached_apps_;
    NativeSystemSnapshot cached_snapshot_;
    std::deque<std::string> broker_event_queue_;

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

    static constexpr size_t kMaxQueuedBrokerEvents = 256;
};

} // namespace CloudOS
