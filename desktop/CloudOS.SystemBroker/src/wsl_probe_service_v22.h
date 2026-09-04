#pragma once

#include <cstdint>
#include <string>

namespace CloudOS
{

struct WslProbeResultV22 final
{
    std::string distro;
    bool attempted{false};
    bool success{false};
    bool timed_out{false};
    bool marker_seen{false};
    int exit_code{-1};
    uint64_t duration_ms{0};
    std::string output;
    std::string error_code;
    std::string error_message;
};

class WslProbeServiceV22 final
{
public:
    static WslProbeServiceV22& Instance();

    WslProbeServiceV22(const WslProbeServiceV22&) = delete;
    WslProbeServiceV22& operator=(const WslProbeServiceV22&) = delete;

    // Executes a fixed, non-user-controlled Linux health probe against an
    // already registered distro. This method is intentionally active and may
    // start the selected WSL distribution.
    [[nodiscard]] WslProbeResultV22 Probe(
        const std::string& requested_distro,
        uint32_t timeout_ms = 8000);

private:
    WslProbeServiceV22() = default;
    ~WslProbeServiceV22() = default;
};

} // namespace CloudOS
