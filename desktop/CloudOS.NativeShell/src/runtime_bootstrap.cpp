#include <windows.h>

#include "cloudos_native_runtime.h"

namespace
{
struct NativeRuntimeBootstrap final
{
    NativeRuntimeBootstrap() noexcept
    {
        const auto abi = cloudos_native_runtime_abi();
        if (abi == CLOUDOS_NATIVE_RUNTIME_ABI)
        {
            return;
        }

        MessageBoxW(
            nullptr,
            L"O CloudOS Native encontrou uma versao incompatível do CloudOS.NativeRuntime.dll.",
            L"CloudOS Native",
            MB_OK | MB_ICONERROR | MB_SYSTEMMODAL);
        ExitProcess(ERROR_REVISION_MISMATCH);
    }
};

[[maybe_unused]] const NativeRuntimeBootstrap nativeRuntimeBootstrap{};
}
