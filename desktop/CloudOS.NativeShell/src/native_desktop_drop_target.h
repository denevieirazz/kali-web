#pragma once

#include <windows.h>

namespace CloudOS
{
class NativeDesktopDropTarget final
{
public:
    static bool Register(HWND window);
    static void Unregister(HWND window) noexcept;
};
} // namespace CloudOS
