#include "event_bus_v21.h"

#include <chrono>

namespace CloudOS
{

EventBusV21& EventBusV21::Instance()
{
    static EventBusV21 instance;
    return instance;
}

void EventBusV21::RegisterClient(const std::string& client_id, EventSenderCallback sender)
{
    std::lock_guard<std::mutex> lock(mutex_);
    client_senders_[client_id] = std::move(sender);
}

void EventBusV21::UnregisterClient(const std::string& client_id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    client_senders_.erase(client_id);
    client_subscriptions_.erase(client_id);
}

bool EventBusV21::Subscribe(const std::string& client_id, const std::string& pattern)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (client_senders_.find(client_id) == client_senders_.end())
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

    std::vector<EventSenderCallback> matched_senders;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& [client_id, patterns] : client_subscriptions_)
        {
            for (const auto& pattern : patterns)
            {
                if (MatchesPattern(pattern, event_name))
                {
                    auto it_sender = client_senders_.find(client_id);
                    if (it_sender != client_senders_.end() && it_sender->second)
                    {
                        matched_senders.push_back(it_sender->second);
                    }
                    break;
                }
            }
        }
    }

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
}

bool EventBusV21::MatchesPattern(const std::string& pattern, const std::string& event_name) const
{
    if (pattern == "*" || pattern == event_name) return true;
    if (pattern.size() > 2 && pattern.back() == '*')
    {
        std::string prefix = pattern.substr(0, pattern.size() - 1);
        if (event_name.compare(0, prefix.size(), prefix) == 0) return true;
    }
    return false;
}

} // namespace CloudOS
