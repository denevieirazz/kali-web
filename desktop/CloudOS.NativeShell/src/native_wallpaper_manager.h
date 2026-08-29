#pragma once

#include <windows.h>
#include <gdiplus.h>

#include <string>

namespace CloudOS
{
class NativeWallpaperManager final
{
public:
    static std::wstring CurrentPath();
    static bool PickAndApply(HWND owner);
    static bool Apply(const std::wstring& path);
    static void Reset();
    static bool Draw(Gdiplus::Graphics& graphics, int width, int height);
};
} // namespace CloudOS
