#include "event_bus_v21.h"

#include <chrono>
#include <cctype>

namespace CloudOS
{

namespace
{
constexpr size_t kMaxSubscriptionsPerClient = 64;
constexpr size_t kMaxPatternLength = 128;
constexpr size_t kMaxEventNameLength = 128;

bool IsEventTokenChar(char c)
{
    const unsigned char uc = static_cast<unsigned char>(c);
    return std::isalnum(uc) != 0 || c == '.' || c == '_' || c == '-';
}

bool IsValidEventName(const std::string& event_name)
{
    if (event_name.empty() || event_name.size() > kMaxEventNameLength)
    {
        return false;
    }

    for (const char c : event_name)
    {
        if (!IsEventTokenChar(c)) return false;
    }
    return true;
}

bool IsValidPattern(const std::string& pattern)
{
    if (pattern.empty() || pattern.size() > kMaxPatternLength)
    {
        return false;
    }
    if (pattern == "*") return true;

    size_t wildcard_count = 0;
    for (size_t i = 0; i < pattern.size(); ++i)
    {
        const char c = pattern[i];
        if (c == '*')
        {
            ++wildcard_count;
            if (i + 1 != pattern.size()) return false;
            continue;
        }
        if (!IsEventTokenChar(c)) return false;
    }

    if (wildcard_count > 1) return false;
    if (wildcard_count == 1 && pattern.size() == 1) return true;

    // Prefix subscriptions such as "system.*" are permitted, while a bare
    // suffix wildcard with no stable prefix is rejected.
    if (wildcard_count == 1 && pattern.size() < 3)
    {
        return false;
    }
    return true;
}
} // namespace

EventBusV21& EventBusV21::Instance()
{
    static EventBusV21 instance;
    return instance;
}

void EventBusV21::RegisterClient(const std::string& client_id, EventSenderCallback sender)
{
    if (client_id.empty() || !sender) return;

    std::lock_guard<std::mutex> lock(mutex_);
    client_subscriptions_.erase(client_id);
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
    if (!IsValidPattern(pattern)) return false;

    std::lock_guard<std::mutex> lock(mutex_);
    if (client_senders_.find(client_id) == client_senders_.end())
    {
        return false;
    }

    auto& subscriptions = client_subscriptions_[client_id];
    if (subscriptions.find(pattern) != subscriptions.end())
    {
        return true;
    }
    if (subscriptions.size() >= kMaxSubscriptionsPerClient)
    {
        return false;
    }

    subscriptions.insert(pattern);
    return true;
}

bool EventBusV21::Unsubscribe(const std::string& client_id, const std::string& pattern)
{
    if (!IsValidPattern(pattern)) return false;

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = client_subscriptions_.find(client_id);
    if (it == client_subscriptions_.end())
    {
        return false;
    }

    const bool removed = it->second.erase(pattern) > 0;
    if (it->second.empty())
    {
        client_subscriptions_.erase(it);
    }
    return removed;
}

void EventBusV21::Publish(const std::string& event_name, const JsonObject& payload)
{
    if (!IsValidEventName(event_name)) return;

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
        matched_senders.reserve(client_subscriptions_.size());
        for (const auto& [client_id, patterns] : client_subscriptions_)
        {
            for (const auto& pattern : patterns)
            {
                if (!MatchesPattern(pattern, event_name)) continue;

                auto it_sender = client_senders_.find(client_id);
                if (it_sender != client_senders_.end() && it_sender->second)
                {
                    matched_senders.push_back(it_sender->second);
                }
                break;
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
    if (!IsValidEventName(event_name)) return 0;

    std::lock_guard<std::mutex> lock(mutex_);
    size_t count = 0;
    for (const auto& [client_id, patterns] : client_subscriptions_)
    {
        (void)client_id;
        for (const auto& pattern : patterns)
        {
            if (MatchesPattern(pattern, event_name))
            {
                ++count;
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
    if (pattern.size() > 1 && pattern.back() == '*')
    {
        const std::string prefix = pattern.substr(0, pattern.size() - 1);
        return event_name.compare(0, prefix.size(), prefix) == 0;
    }
    return false;
}

} // namespace CloudOS
