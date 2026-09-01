#pragma once

#include <cstdint>

namespace CloudOS::ShellActivationV21
{
inline constexpr std::uint32_t kSchema = 21;
inline constexpr std::uintptr_t kCopyDataTag = static_cast<std::uintptr_t>(0x434F535641323100ull);
inline constexpr wchar_t kWindowClass[] = L"CloudOS.NativeShell.Activation.v21";

enum class App : std::uint32_t
{
    Browser = 1,
    Terminal = 2,
};

struct Request final
{
    std::uint32_t schema{kSchema};
    App app{App::Browser};
};

[[nodiscard]] constexpr bool IsSupported(App app) noexcept
{
    return app == App::Browser || app == App::Terminal;
}
} // namespace CloudOS::ShellActivationV21
