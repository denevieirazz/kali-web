#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct AppItem final
{
    std::string id;
    std::string name;
    std::string platform; // "windows", "linux", "cloudos"
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    bool can_launch{true};
    bool can_uninstall{false};
    bool can_update{false};
    std::string icon_key;
    bool pinned{false};
    bool recent{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class AppServiceV21 final
{
public:
    static AppServiceV21& Instance();

    AppServiceV21(const AppServiceV21&) = delete;
    AppServiceV21& operator=(const AppServiceV21&) = delete;

    std::vector<AppItem> GetApps();
    bool LaunchApp(const std::string& app_id, std::string& err);
    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }

    void Invalidate();

private:
    AppServiceV21() = default;
    ~AppServiceV21() = default;

    void Refresh();

    mutable std::mutex mutex_;
    std::vector<AppItem> apps_;
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS
