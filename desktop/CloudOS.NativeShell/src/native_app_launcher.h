#pragma once

#include <windows.h>
#include <string>
#include "native_theme.h"

namespace CloudOS
{
class NativeAppLauncher final
{
public:
    static void Launch(HINSTANCE instance, HWND parent_hwnd, const AppItem& app);
    static void LaunchById(HINSTANCE instance, HWND parent_hwnd, const std::wstring& id);
    static void ShowQuickPowerMenu(HWND parent_hwnd, POINT screen_pt);
};
} // namespace CloudOS
