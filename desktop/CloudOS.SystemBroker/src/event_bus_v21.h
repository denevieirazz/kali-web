#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <functional>
#include <mutex>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

namespace CloudOS
{

using EventSenderCallback = std::function<void(const BrokerEvent&)>;

class EventBusV21 final
{
public:
    static EventBusV21& Instance();

    EventBusV21(const EventBusV21&) = delete;
    EventBusV21& operator=(const EventBusV21&) = delete;

    // The RPC connection owns client lifetime and subscriptions. The dedicated
    // V23 event transport attaches/detaches independently so an event-pipe
    // reconnect cannot erase a still-live RPC subscription.
    void RegisterClient(const std::string& client_id, EventSenderCallback sender);
    bool RegisterDedicatedClientV23(
        const std::string& client_id,
        EventSenderCallback sender);
    void UnregisterDedicatedClientV23(const std::string& client_id);
    void UnregisterClient(const std::string& client_id);

    bool Subscribe(const std::string& client_id, const std::string& pattern);
    bool Unsubscribe(const std::string& client_id, const std::string& pattern);

    void Publish(const std::string& event_name, const JsonObject& payload);

    void SetDedicatedTransportRequired(bool required) noexcept
    {
        dedicated_transport_required_.store(required);
    }
    [[nodiscard]] bool IsDedicatedTransportRequired() const noexcept
    {
        return dedicated_transport_required_.load();
    }

    [[nodiscard]] size_t GetSubscriberCount(const std::string& event_name) const;
    [[nodiscard]] size_t GetActiveClientCount() const;

    void Reset(); // For testing

private:
    EventBusV21() = default;
    ~EventBusV21() = default;

    struct SenderRecord final
    {
        EventSenderCallback legacy_rpc_sender;
        EventSenderCallback dedicated_v23_sender;
    };

    bool MatchesPattern(const std::string& pattern, const std::string& event_name) const;

    mutable std::mutex mutex_;
    std::unordered_map<std::string, SenderRecord> client_senders_;
    std::unordered_map<std::string, std::set<std::string>> client_subscriptions_;
    std::atomic_bool dedicated_transport_required_{false};
};

} // namespace CloudOS
