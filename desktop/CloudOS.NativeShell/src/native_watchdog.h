#pragma once

#include <Windows.h>

namespace CloudOS
{
class NativeWatchdog final
{
public:
    static bool HasSessionArgument();
    static int Run();
};
} // namespace CloudOS
