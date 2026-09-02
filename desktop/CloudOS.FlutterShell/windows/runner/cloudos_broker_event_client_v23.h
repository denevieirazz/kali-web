#pragma once

#include <Windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace CloudOS
{

class CloudOSBrokerEventClientV23 final
{
public:
    static constexpr UINT kDispatchMessage = WM_APP + 0x442;
    static constexpr size_t kMaxPendingUiEvents = 256;
    static constexpr size_t kMaxPendingUiBytes = 4 * 1024 * 1024;

    static CloudOSBrokerEventClientV23& Instance();

    CloudOSBrokerEventClientV23(const CloudOSBrokerEventClientV23&) = delete;
    CloudOSBrokerEventClientV23& operator=(const CloudOSBrokerEventClientV23&) = delete;

    // Initializes only the dedicated MethodChannel. The worker intentionally
    // starts after Dart invokes `start`, so the Dart handler is installed first
    // and the initial connection-state frame cannot be lost during engine boot.
    void Initialize(flutter::BinaryMessenger* messenger, HWND platform_window);
    void Shutdown();
    void DrainPlatformEvents();

    [[nodiscard]] bool IsRunning() const noexcept { return running_.load(); }
    [[nodiscard]] bool IsConnected() const noexcept { return connected_.load(); }
    [[nodiscard]] uint64_t DroppedEventCount() const noexcept { return dropped_events_.load(); }

private:
    CloudOSBrokerEventClientV23() = default;
    ~CloudOSBrokerEventClientV23();

    enum class UiEventKind
    {
        broker_event,
        connection_state,
    };

    struct UiEvent final
    {
        UiEventKind kind{UiEventKind::broker_event};
        std::string payload;
        uint64_t dropped_events{0};
    };

    bool StartWorker();
    void StopWorker();
    void WorkerLoop();
    bool ConnectAndSubscribe();
    void DisconnectPipe();
    bool SendFrame(HANDLE pipe, const std::string& payload);
    bool ReadFrame(HANDLE pipe, std::string& payload);

    void QueueBrokerEvent(std::string raw_json);
    void QueueConnectionState(const std::string& state);
    void QueueUiEvent(UiEvent event);
    void PostDrainMessage();

    std::mutex lifecycle_mutex_;
    std::thread worker_;
    std::atomic_bool running_{false};
    std::atomic_bool stop_requested_{false};
    std::atomic_bool connected_{false};

    std::mutex pipe_mutex_;
    HANDLE pipe_{INVALID_HANDLE_VALUE};

    std::mutex ui_mutex_;
    std::deque<UiEvent> pending_ui_events_;
    size_t pending_ui_bytes_{0};
    std::atomic_uint64_t dropped_events_{0};

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> event_channel_;
    HWND platform_window_{nullptr};
};

} // namespace CloudOS
