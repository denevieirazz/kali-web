#include "native_shell_platform.h"

#include <windows.h>

#include <array>
#include <cwchar>

namespace CloudOS
{
std::wstring NativeShellPlatform::WindowsVolumeRoot()
{
    std::array<wchar_t, 32768> windows_directory{};
    const UINT length = GetWindowsDirectoryW(
        windows_directory.data(),
        static_cast<UINT>(windows_directory.size()));
    if (length == 0 || length >= windows_directory.size())
    {
        return {};
    }

    std::array<wchar_t, 32768> volume_path{};
    if (!GetVolumePathNameW(
            windows_directory.data(),
            volume_path.data(),
            static_cast<DWORD>(volume_path.size())))
    {
        return {};
    }
    return volume_path.data();
}

std::wstring NativeShellPlatform::FormatLocalTime()
{
    SYSTEMTIME local_time{};
    GetLocalTime(&local_time);

    std::array<wchar_t, 128> buffer{};
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            TIME_NOSECONDS,
            &local_time,
            nullptr,
            buffer.data(),
            static_cast<int>(buffer.size())) > 0)
    {
        return buffer.data();
    }

    swprintf_s(
        buffer.data(),
        buffer.size(),
        L"%02u:%02u",
        local_time.wHour,
        local_time.wMinute);
    return buffer.data();
}

std::wstring NativeShellPlatform::FormatLocalDate(bool long_format)
{
    SYSTEMTIME local_time{};
    GetLocalTime(&local_time);

    std::array<wchar_t, 192> buffer{};
    if (GetDateFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            long_format ? DATE_LONGDATE : DATE_SHORTDATE,
            &local_time,
            nullptr,
            buffer.data(),
            static_cast<int>(buffer.size()),
            nullptr) > 0)
    {
        return buffer.data();
    }

    swprintf_s(
        buffer.data(),
        buffer.size(),
        L"%02u/%02u/%04u",
        local_time.wDay,
        local_time.wMonth,
        local_time.wYear);
    return buffer.data();
}

} // namespace CloudOS
