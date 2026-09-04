#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct SystemWslDistributionSnapshot final
{
    std::string name;
    int version{0}; // 0 means not proven by passive registration metadata.
    bool is_default{false};
    bool base_path_present{false};
    bool is_security_candidate{false};
};

struct SystemSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{1};
    bool battery_available{true};
    int battery_percent{100};
    bool network_available{true};
    std::string network_name;
    bool volume_available{false};
    double volume{0.0};
    bool brightness_available{false};
    double brightness{0.0};

    // Legacy V21 field: true only when WSL has a registered distro usable by
    // existing callers. Keep this behavior for backwards compatibility.
    bool wsl_available{false};
    std::vector<std::string> distros;
    std::string default_distro;

    // Additive runtime evidence. The engine field is independent from whether
    // any distro is installed, and distro version is only populated when the
    // Windows registration metadata proves it.
    bool wsl_engine_available{false};
    bool wsl_passive_ready{false};
    std::vector<SystemWslDistributionSnapshot> wsl_distros;
    std::string preferred_security_distro;
    uint32_t wsl_registered_count{0};
    uint32_t wsl_launch_candidate_count{0};
    uint32_t wsl1_count{0};
    uint32_t wsl2_count{0};

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
