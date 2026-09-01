#include "native_shell_notification_server_v21.h"

namespace CloudOS
{
namespace
{
class NotificationServerLifetime final
{
public:
    NotificationServerLifetime() noexcept
    {
        (void)NativeShellNotificationServerV21::Start(GetModuleHandleW(nullptr));
    }

    ~NotificationServerLifetime()
    {
        NativeShellNotificationServerV21::Stop();
    }
};

NotificationServerLifetime g_notification_server_lifetime;
} // namespace
} // namespace CloudOS
