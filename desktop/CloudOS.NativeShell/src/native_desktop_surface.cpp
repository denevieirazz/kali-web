#include "native_desktop_surface.h"

#include <utility>

namespace CloudOS
{
CloudOSDesktopSurface::~CloudOSDesktopSurface()
{
    Destroy();
}

bool CloudOSDesktopSurface::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    Destroy();
    return native_.Create(instance, window_manager);
}

void CloudOSDesktopSurface::Destroy()
{
    native_.Destroy();
}

void CloudOSDesktopSurface::UpdateLayout(const RECT& work_area)
{
    native_.UpdateLayout(work_area);
}

void CloudOSDesktopSurface::Redraw()
{
    native_.Redraw();
}

void CloudOSDesktopSurface::FocusSearch()
{
    native_.FocusSearch();
}

void CloudOSDesktopSurface::SetActionCallback(ActionCallback callback)
{
    native_.SetActionCallback(std::move(callback));
}

void CloudOSDesktopSurface::SetHotKeyCallback(HotKeyCallback callback)
{
    native_.SetHotKeyCallback(std::move(callback));
}

void CloudOSDesktopSurface::SetTimerCallback(TimerCallback callback)
{
    native_.SetTimerCallback(std::move(callback));
}

HWND CloudOSDesktopSurface::Hwnd() const noexcept
{
    return native_.Hwnd();
}
} // namespace CloudOS
