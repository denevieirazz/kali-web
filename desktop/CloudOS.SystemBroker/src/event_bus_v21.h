#pragma once

#include "protocol_v21.h"

#include <deque>
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

    void RegisterClient(const std::string& client_id, EventSenderCallback sender);
    void UnregisterClient(const std::string& client_id);

    bool Subscribe(const std::string& client_id, const std::string& pattern);
    bool Unsubscribe(const std::string& client_id, const std::string& pattern);

    void Publish(const std::string& event_name, const JsonObject& payload);

    [[nodiscard]] size_t GetSubscriberCount(const std::string& event_name) const;
    [[nodiscard]] size_t GetActiveClientCount() const;

    void Reset(); // For testing

private:
    EventBusV21() = default;
    ~EventBusV21() = default;

    bool MatchesPattern(const std::string& pattern, const std::string& event_name) const;

    mutable std::mutex mutex_;
    std::unordered_map<std::string, EventSenderCallback> client_senders_;
    std::unordered_map<std::string, std::set<std::string>> client_subscriptions_;
};

} // namespace CloudOS
