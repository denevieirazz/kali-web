#pragma once

#include "protocol_v21.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct WslDistroInfo final
{
    std::string id;
    std::string name;
    std::string guid;
    uint32_t version{2};
    std::string state{"Stopped"}; // "Stopped" or "Running"
    std::string base_path;
    uint32_t default_uid{0};
    uint32_t flags{15};
    bool is_default{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class WslServiceV21 final
{
public:
    static WslServiceV21& Instance();

    WslServiceV21(const WslServiceV21&) = delete;
    WslServiceV21& operator=(const WslServiceV21&) = delete;

    [[nodiscard]] bool IsWslAvailable();
    [[nodiscard]] std::vector<std::string> GetDistributions();
    [[nodiscard]] std::string GetDefaultDistribution();
    [[nodiscard]] std::vector<WslDistroInfo> GetDistroDetails();
    [[nodiscard]] bool IsDistroRunning(const std::string& distro_name);
    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }

    void Invalidate();

private:
    WslServiceV21() = default;
    ~WslServiceV21() = default;

    void Refresh();

    mutable std::mutex mutex_;
    bool wsl_available_{false};
    std::vector<std::string> distros_;
    std::vector<WslDistroInfo> distro_details_;
    std::string default_distro_;
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS

