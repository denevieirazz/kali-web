#include <windows.h>

#include "cloudos_native_runtime.h"

namespace
{
constexpr DWORD kCloudOSShutdownLevel = 0x300u;

struct NativeRuntimeBootstrap final
{
    NativeRuntimeBootstrap() noexcept
    {
        previous_error_mode_ = SetErrorMode(
            SEM_FAILCRITICALERRORS |
            SEM_NOGPFAULTERRORBOX |
            SEM_NOOPENFILEERRORBOX);

        // CloudOS is the user shell authority. During Windows logoff/update it
        // should receive its shutdown phase before the late Supervisor authority,
        // giving Session Continuity a deterministic chance to checkpoint state.
        // 0x300 is inside the documented application-reserved "first" band.
        shutdown_order_succeeded_ = SetProcessShutdownParameters(
            kCloudOSShutdownLevel,
            SHUTDOWN_NORETRY) != FALSE;

        if (!shutdown_order_succeeded_)
        {
            OutputDebugStringW(
                L"[CloudOS Bootstrap V22] Early application shutdown ordering unavailable; Windows default ordering remains active.\n");
        }

        const auto abi = cloudos_native_runtime_abi();
        if (abi == CLOUDOS_NATIVE_RUNTIME_ABI)
        {
            OutputDebugStringW(
                L"[CloudOS Bootstrap V22] Native runtime ABI verified.\n");
            return;
        }

        MessageBoxW(
            nullptr,
            L"O CloudOS Native encontrou uma versao incompatível do CloudOS.NativeRuntime.dll.",
            L"CloudOS Native",
            MB_OK | MB_ICONERROR | MB_SYSTEMMODAL);
        ExitProcess(ERROR_REVISION_MISMATCH);
    }

    ~NativeRuntimeBootstrap() noexcept
    {
        (void)SetErrorMode(previous_error_mode_);
    }

    UINT previous_error_mode_{};
    bool shutdown_order_succeeded_{};
};

[[maybe_unused]] const NativeRuntimeBootstrap nativeRuntimeBootstrap{};
}
