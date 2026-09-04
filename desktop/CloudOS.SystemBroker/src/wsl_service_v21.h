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

    // Passive registration/storage evidence. This does not mean the distro
    // completed first-run provisioning; it only proves that the registered
    // BasePath currently resolves to a directory on disk.
    bool base_path_present{false};

    // Conservative security-runtime candidate: Kali identity + WSL2 + a
    // present registered BasePath. This is still not an active health probe.
    bool is_security_candidate{false};
};

struct WslRuntimeSnapshotV21 final
{
    bool engine_available{false};

    // Legacy V21 meaning: wsl.exe exists and at least one distro is registered.
    // Do not reinterpret this as a successful Linux boot/health check.
    bool usable{false};

    // Stronger passive evidence which still does not launch Linux.
    bool passive_ready{false};

    std::vector<WslDistributionInfoV21> distributions;
    std::string default_distribution;
    std::string preferred_security_distribution;

    uint32_t registered_count{0};
    uint32_t launch_candidate_count{0};
    uint32_t wsl1_count{0};
    uint32_t wsl2_count{0};
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
    // Windows registration/storage metadata and never starts a distribution.
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
    bool passive_ready_{false};
    std::vector<WslDistributionInfoV21> distro_infos_;
    std::vector<std::string> distros_;
    std::string default_distro_;
    std::string preferred_security_distro_;
    uint32_t launch_candidate_count_{0};
    uint32_t wsl1_count_{0};
    uint32_t wsl2_count_{0};
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS
