#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct WslDistributionInfoV21 final
{
    std::string name;
    int version{0}; // 0 = unknown, otherwise the registered WSL generation.
    bool is_default{false};
};

struct WslRuntimeSnapshotV21 final
{
    bool engine_available{false};
    bool usable{false};
    std::vector<WslDistributionInfoV21> distributions;
    std::string default_distribution;
};

class WslServiceV21 final
{
public:
    static WslServiceV21& Instance();

    WslServiceV21(const WslServiceV21&) = delete;
    WslServiceV21& operator=(const WslServiceV21&) = delete;

    // Legacy V21 contract: true only when the WSL executable exists and at
    // least one registered distribution is available.
    [[nodiscard]] bool IsWslAvailable();
    [[nodiscard]] std::vector<std::string> GetDistributions();
    [[nodiscard]] std::string GetDefaultDistribution();

    // Additive V22-facing inventory. This is intentionally passive: it reads
    // the Windows WSL registration metadata and never starts a distribution.
    [[nodiscard]] WslRuntimeSnapshotV21 GetRuntimeSnapshot();

    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }

    void Invalidate();

private:
    WslServiceV21() = default;
    ~WslServiceV21() = default;

    void Refresh();

    mutable std::mutex mutex_;
    bool wsl_engine_available_{false};
    bool wsl_available_{false};
    std::vector<WslDistributionInfoV21> distro_infos_;
    std::vector<std::string> distros_;
    std::string default_distro_;
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS
