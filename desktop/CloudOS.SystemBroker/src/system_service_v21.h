#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct SystemSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{1};
    bool battery_available{false};
    int battery_percent{-1};
    bool network_available{false};
    std::string network_name;
    bool volume_available{false};
    double volume{0.0};
    bool brightness_available{false};
    double brightness{0.0};
    bool wsl_available{false};
    std::vector<std::string> distros;
    std::string default_distro;
    int current_workspace{1};
    uint64_t timestamp_ms{0};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class SystemServiceV21 final
{
public:
    static SystemServiceV21& Instance();

    SystemServiceV21(const SystemServiceV21&) = delete;
    SystemServiceV21& operator=(const SystemServiceV21&) = delete;

    SystemSnapshot GetSnapshot();
    bool SetVolume(double value);
    bool SetBrightness(double value);
    std::vector<std::string> GetCapabilities();

    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }

    void Invalidate();

private:
    SystemServiceV21() = default;
    ~SystemServiceV21() = default;

    void Refresh();

    mutable std::mutex mutex_;
    SystemSnapshot snapshot_;
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS
