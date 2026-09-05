#include "notification_service_v26.h"
#include "event_bus_v21.h"

#include <Windows.h>

#include <chrono>
#include <iomanip>
#include <sstream>

namespace CloudOS
{

namespace
{

std::string CurrentIsoTime()
{
    SYSTEMTIME st{};
    GetLocalTime(&st);
    std::ostringstream oss;
    oss << std::setfill('0')
        << std::setw(4) << st.wYear << "-"
        << std::setw(2) << st.wMonth << "-"
        << std::setw(2) << st.wDay << "T"
        << std::setw(2) << st.wHour << ":"
        << std::setw(2) << st.wMinute << ":"
        << std::setw(2) << st.wSecond;
    return oss.str();
}

} // namespace

JsonObject NotificationItemV26::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = JsonValue(static_cast<int64_t>(id));
    obj["timestamp"] = JsonValue(timestamp);
    obj["title"] = JsonValue(title);
    obj["message"] = JsonValue(message);
    obj["severity"] = JsonValue(severity);
    obj["app_id"] = JsonValue(app_id);
    obj["read"] = JsonValue(read);
    return obj;
}

NotificationServiceV26& NotificationServiceV26::Instance()
{
    static NotificationServiceV26 instance;
    return instance;
}

uint64_t NotificationServiceV26::Post(
    const std::string& title,
    const std::string& message,
    const std::string& severity,
    const std::string& app_id)
{
    NotificationItemV26 item;
    item.id = next_id_.fetch_add(1);
    item.timestamp = CurrentIsoTime();
    item.title = title;
    item.message = message;
    item.severity = severity.empty() ? "info" : severity;
    item.app_id = app_id;
    item.read = false;

    JsonObject event_payload = item.ToJsonObject();

    {
        std::lock_guard<std::mutex> lock(mutex_);
        notifications_.push_front(item);
        if (notifications_.size() > kMaxNotifications)
        {
            notifications_.pop_back();
        }
    }

    EventBusV21::Instance().Publish("notification.posted", event_payload);
    return item.id;
}

std::vector<NotificationItemV26> NotificationServiceV26::GetNotifications() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return std::vector<NotificationItemV26>(notifications_.begin(), notifications_.end());
}

size_t NotificationServiceV26::GetUnreadCount() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    size_t count = 0;
    for (const auto& item : notifications_)
    {
        if (!item.read) count++;
    }
    return count;
}

bool NotificationServiceV26::Dismiss(uint64_t id)
{
    bool found = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto it = notifications_.begin(); it != notifications_.end(); ++it)
        {
            if (it->id == id)
            {
                notifications_.erase(it);
                found = true;
                break;
            }
        }
    }

    if (found)
    {
        JsonObject payload;
        payload["id"] = JsonValue(static_cast<int64_t>(id));
        EventBusV21::Instance().Publish("notification.dismissed", payload);
    }
    return found;
}

void NotificationServiceV26::Clear()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        notifications_.clear();
    }

    JsonObject payload;
    payload["cleared"] = JsonValue(true);
    EventBusV21::Instance().Publish("notification.cleared", payload);
}

bool NotificationServiceV26::MarkRead(uint64_t id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& item : notifications_)
    {
        if (item.id == id)
        {
            item.read = true;
            return true;
        }
    }
    return false;
}

void NotificationServiceV26::MarkAllRead()
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& item : notifications_)
    {
        item.read = true;
    }
}

} // namespace CloudOS
