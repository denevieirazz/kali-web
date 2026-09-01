#pragma once

#include <cstdint>

namespace CloudOS::ShellActivationV21
{
inline constexpr std::uint32_t kSchema = 21;
inline constexpr std::uintptr_t kCopyDataTag = static_cast<std::uintptr_t>(0x434F535641323100ull);
inline constexpr std::uintptr_t kSurfaceCopyDataTag = static_cast<std::uintptr_t>(0x434F535653323100ull);
inline constexpr wchar_t kWindowClass[] = L"CloudOS.NativeShell.Activation.v21";

enum class App : std::uint32_t
{
    Browser = 1,
    Terminal = 2,
};

// Keep this activation request layout stable. Existing V21 launch clients depend
// on the two-field binary payload; lifecycle uses SurfaceRequest below.
struct Request final
{
    std::uint32_t schema{kSchema};
    App app{App::Browser};
};

enum class SurfaceAction : std::uint32_t
{
    Query = 1,
    Focus = 2,
    Close = 3,
};

enum class SurfaceResult : std::uint32_t
{
    Rejected = 0,
    NotRunning = 1,
    Running = 2,
    Applied = 3,
};

struct SurfaceRequest final
{
    std::uint32_t schema{kSchema};
    App app{App::Browser};
    SurfaceAction action{SurfaceAction::Query};
};

[[nodiscard]] constexpr bool IsSupported(App app) noexcept
{
    return app == App::Browser || app == App::Terminal;
}

[[nodiscard]] constexpr bool IsSupported(SurfaceAction action) noexcept
{
    return action == SurfaceAction::Query ||
        action == SurfaceAction::Focus ||
        action == SurfaceAction::Close;
}
} // namespace CloudOS::ShellActivationV21