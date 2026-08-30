#pragma once

#include <Windows.h>

#include <cwchar>
#include <vector>

#include "native_health_bootstrap_v9.h"

namespace CloudOS
{
class NativeWatchdog final
{
public:
    static bool IsWatchdogInvocation();
    static int RunWatchdogInvocation();

    // The UI process owns this mutex for the full lifetime of the shell. A
    // second manual launch waits briefly, then only surfaces the existing shell.
    static HANDLE AcquireSessionMutex(DWORD wait_milliseconds = 2500);
    static void ReleaseSessionMutex(HANDLE mutex) noexcept;

    // Launches a tiny helper instance of CloudOS.exe that waits on the current
    // process handle and relaunches the shell only after an abnormal exit.
    // Explicit --stability-probe launches skip the helper so crashes remain
    // visible to the automated soak harness instead of being auto-recovered.
    static bool StartForCurrentProcess();
};
} // namespace CloudOS
