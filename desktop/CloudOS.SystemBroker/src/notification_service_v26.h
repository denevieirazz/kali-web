#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct NotificationItemV26 final
{
    uint64_t id{0};
    std::string timestamp;
    std::string title;
    std::string message;
    std::string severity{"info"}; // "info", "warning", "error", "system"
    std::string app_id;
    bool read{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class NotificationServiceV26 final
{
public:
    static NotificationServiceV26& Instance();

    NotificationServiceV26(const NotificationServiceV26&) = delete;
    NotificationServiceV26& operator=(const NotificationServiceV26&) = delete;

    uint64_t Post(
        const std::string& title,
        const std::string& message,
        const std::string& severity = "info",
        const std::string& app_id = "");

    [[nodiscard]] std::vector<NotificationItemV26> GetNotifications() const;
    [[nodiscard]] size_t GetUnreadCount() const;
    bool Dismiss(uint64_t id);
    void Clear();
    bool MarkRead(uint64_t id);
    void MarkAllRead();

private:
    NotificationServiceV26() = default;
    ~NotificationServiceV26() = default;

    mutable std::mutex mutex_;
    std::deque<NotificationItemV26> notifications_;
    std::atomic<uint64_t> next_id_{1};

    static constexpr size_t kMaxNotifications = 64;
};

} // namespace CloudOS
