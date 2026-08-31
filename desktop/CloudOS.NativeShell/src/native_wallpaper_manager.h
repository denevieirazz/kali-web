#pragma once

#include <windows.h>
#include <gdiplus.h>

#include <string>

namespace CloudOS
{
class NativeWallpaperManager final
{
public:
    static void Prepare(HWND target=nullptr,int width=0,int height=0,bool force=false);
    static void Stop();
    static std::wstring CurrentPath();
    static bool PickAndApply(HWND owner);
    static bool Apply(const std::wstring& path);
    static void Reset();
    static bool Draw(Gdiplus::Graphics& graphics, int width, int height);
};
} // namespace CloudOS
