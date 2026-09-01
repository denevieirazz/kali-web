#pragma once

#include <Windows.h>

#include <cstdint>

namespace CloudOS
{
inline constexpr wchar_t kNativeShellDispatchWindowClassV21[] =
    L"CloudOS.NativeShell.Dispatch.v21";
inline constexpr UINT kNativeShellDispatchMessageV21 = WM_APP + 0x721;

enum class NativeShellDispatchCommandV21 : std::uint32_t
{
    Browser = 1,
    Files = 2,
    Terminal = 3,
    Calculator = 4,
    Settings = 5,
    Drive = 6,
};

inline constexpr bool IsValidNativeShellDispatchCommandV21(
    NativeShellDispatchCommandV21 command) noexcept
{
    switch (command)
    {
    case NativeShellDispatchCommandV21::Browser:
    case NativeShellDispatchCommandV21::Files:
    case NativeShellDispatchCommandV21::Terminal:
    case NativeShellDispatchCommandV21::Calculator:
    case NativeShellDispatchCommandV21::Settings:
    case NativeShellDispatchCommandV21::Drive:
        return true;
    default:
        return false;
    }
}
} // namespace CloudOS
