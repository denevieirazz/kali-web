#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

class WslServiceV21 final
{
public:
    static WslServiceV21& Instance();

    WslServiceV21(const WslServiceV21&) = delete;
    WslServiceV21& operator=(const WslServiceV21&) = delete;

    [[nodiscard]] bool IsWslAvailable();
    [[nodiscard]] std::vector<std::string> GetDistributions();
    [[nodiscard]] uint64_t GetGeneration() const noexcept { return generation_.load(); }

    void Invalidate();

private:
    WslServiceV21() = default;
    ~WslServiceV21() = default;

    void Refresh();

    mutable std::mutex mutex_;
    bool wsl_available_{false};
    std::vector<std::string> distros_;
    std::atomic_bool initialized_{false};
    std::atomic_uint64_t generation_{1};
};

} // namespace CloudOS
