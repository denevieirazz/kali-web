#pragma once

#include <windows.h>

namespace CloudOS
{
class NativeDesktopContextMenu final
{
public:
    // Returns true when the desktop should redraw.
    static bool Show(HINSTANCE instance, HWND owner, POINT screen_point);
};
} // namespace CloudOS
