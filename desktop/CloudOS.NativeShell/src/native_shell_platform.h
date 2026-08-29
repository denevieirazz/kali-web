#pragma once

#include <string>

namespace CloudOS
{
class NativeShellPlatform final
{
public:
    static std::wstring WindowsVolumeRoot();
    static std::wstring FormatLocalTime();
    static std::wstring FormatLocalDate(bool long_format);
};
} // namespace CloudOS
