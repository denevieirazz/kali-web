#pragma once

#include <cstdint>

namespace CloudOS::ShellActivationV21
{
inline constexpr std::uint32_t kSchema = 21;
inline constexpr std::uintptr_t kCopyDataTag = static_cast<std::uintptr_t>(0x434F535641323100ull);
inline constexpr std::uintptr_t kSurfaceCopyDataTag = static_cast<std::uintptr_t>(0x434F535653323100ull);
inline constexpr std::uintptr_t kWorkspaceCopyDataTag = static_cast<std::uintptr_t>(0x434F535657323100ull);
inline constexpr wchar_t kWindowClass[] = L"CloudOS.NativeShell.Activation.v21";
inline constexpr std::int32_t kWorkspaceCount = 4;

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

enum class WorkspaceAction : std::uint32_t
{
    Query = 1,
    Switch = 2,
};

// Workspace indices are always zero-based on the native side (0..3). The
// Flutter bridge converts them to the presentation contract (1..4).
struct WorkspaceRequest final
{
    std::uint32_t schema{kSchema};
    WorkspaceAction action{WorkspaceAction::Query};
    std::int32_t workspace{0};
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

[[nodiscard]] constexpr bool IsSupported(WorkspaceAction action) noexcept
{
    return action == WorkspaceAction::Query ||
        action == WorkspaceAction::Switch;
}

[[nodiscard]] constexpr bool IsSupportedWorkspace(std::int32_t workspace) noexcept
{
    return workspace >= 0 && workspace < kWorkspaceCount;
}

// Zero is reserved for rejected/unavailable. Successful workspace responses are
// encoded as 1..4 so a single LRESULT remains sufficient and no raw HWND/state
// pointer crosses the process boundary.
[[nodiscard]] constexpr std::uintptr_t EncodeWorkspaceResponse(
    std::int32_t workspace) noexcept
{
    return IsSupportedWorkspace(workspace)
        ? static_cast<std::uintptr_t>(workspace + 1)
        : static_cast<std::uintptr_t>(0);
}

[[nodiscard]] constexpr bool DecodeWorkspaceResponse(
    std::uintptr_t response,
    std::int32_t* workspace) noexcept
{
    if (workspace == nullptr || response < 1 ||
        response > static_cast<std::uintptr_t>(kWorkspaceCount))
    {
        return false;
    }
    *workspace = static_cast<std::int32_t>(response - 1);
    return true;
}
} // namespace CloudOS::ShellActivationV21
