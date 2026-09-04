#include "event_bus_v21.h"

#include <chrono>

namespace CloudOS
{

EventBusV21& EventBusV21::Instance()
{
    static EventBusV21 instance;
    return instance;
}

void EventBusV21::RegisterClient(
    const std::string& client_id,
    EventSenderCallback sender)
{
    if (client_id.empty() || !sender) return;
    std::lock_guard<std::mutex> lock(mutex_);
    SenderRecord& record = client_senders_[client_id];
    record.legacy_rpc_sender = std::move(sender);
}

bool EventBusV21::RegisterDedicatedClientV23(
    const std::string& client_id,
    EventSenderCallback sender)
{
    if (client_id.empty() || !sender) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = client_senders_.find(client_id);
    if (it == client_senders_.end() || !it->second.legacy_rpc_sender)
    {
        // A V23 event connection is valid only while the exact RPC client id is
        // still registered. This rejects stale client ids from the same PID.
        return false;
    }
    it->second.dedicated_v23_sender = std::move(sender);
    return true;
}

void EventBusV21::UnregisterDedicatedClientV23(const std::string& client_id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = client_senders_.find(client_id);
    if (it != client_senders_.end())
    {
        it->second.dedicated_v23_sender = {};
    }
}

void EventBusV21::UnregisterClient(const std::string& client_id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    client_senders_.erase(client_id);
    client_subscriptions_.erase(client_id);
}

bool EventBusV21::Subscribe(const std::string& client_id, const std::string& pattern)
{
    if (client_id.empty() || pattern.empty() || pattern.size() > 256) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    const auto client = client_senders_.find(client_id);
    if (client == client_senders_.end() || !client->second.legacy_rpc_sender)
    {
        return false;
    }
    client_subscriptions_[client_id].insert(pattern);
    return true;
}

bool EventBusV21::Unsubscribe(const std::string& client_id, const std::string& pattern)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = client_subscriptions_.find(client_id);
    if (it != client_subscriptions_.end())
    {
        it->second.erase(pattern);
        if (it->second.empty()) client_subscriptions_.erase(it);
        return true;
    }
    return false;
}

void EventBusV21::Publish(const std::string& event_name, const JsonObject& payload)
{
    BrokerEvent ev;
    ev.protocol = kProtocolVersion;
    ev.event = event_name;
    ev.payload = payload;
    ev.timestamp_ms = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    const bool require_dedicated = dedicated_transport_required_.load();
    std::vector<EventSenderCallback> matched_senders;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& [client_id, patterns] : client_subscriptions_)
        {
            for (const auto& pattern : patterns)
            {
                if (!MatchesPattern(pattern, event_name)) continue;

                const auto sender_it = client_senders_.find(client_id);
                if (sender_it != client_senders_.end())
                {
                    const EventSenderCallback& sender = require_dedicated
                        ? sender_it->second.dedicated_v23_sender
                        : sender_it->second.legacy_rpc_sender;
                    if (sender) matched_senders.push_back(sender);
                }
                break;
            }
        }
    }

    // Callbacks are invoked without the EventBus mutex. V23 callbacks only
    // enqueue into a bounded per-client queue, so a blocked UI cannot block
    // catalog/system publishers or other event clients.
    for (const auto& sender : matched_senders)
    {
        sender(ev);
    }
}

size_t EventBusV21::GetSubscriberCount(const std::string& event_name) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    size_t count = 0;
    for (const auto& [client_id, patterns] : client_subscriptions_)
    {
        (void)client_id;
        for (const auto& pattern : patterns)
        {
            if (MatchesPattern(pattern, event_name))
            {
                count++;
                break;
            }
        }
    }
    return count;
}

size_t EventBusV21::GetActiveClientCount() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return client_senders_.size();
}

void EventBusV21::Reset()
{
    std::lock_guard<std::mutex> lock(mutex_);
    client_senders_.clear();
    client_subscriptions_.clear();
    dedicated_transport_required_.store(false);
}

bool EventBusV21::MatchesPattern(
    const std::string& pattern,
    const std::string& event_name) const
{
    if (pattern == "*" || pattern == event_name) return true;
    if (pattern.size() > 2 && pattern.back() == '*')
    {
        const std::string prefix = pattern.substr(0, pattern.size() - 1);
        if (event_name.compare(0, prefix.size(), prefix) == 0) return true;
    }
    return false;
}

} // namespace CloudOS
