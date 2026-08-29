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
    if (web_.Create(instance, window_manager))
    {
        web_active_ = true;
        return true;
    }

    web_active_ = false;
    return fallback_.Create(instance, window_manager);
}

void CloudOSDesktopSurface::Destroy()
{
    web_.Destroy();
    fallback_.Destroy();
    web_active_ = false;
}

void CloudOSDesktopSurface::UpdateLayout(const RECT& work_area)
{
    if (web_active_)
    {
        web_.UpdateLayout(work_area);
    }
    else
    {
        fallback_.UpdateLayout(work_area);
    }
}

void CloudOSDesktopSurface::Redraw()
{
    if (web_active_)
    {
        web_.Redraw();
    }
    else
    {
        fallback_.Redraw();
    }
}

void CloudOSDesktopSurface::FocusSearch()
{
    if (web_active_)
    {
        web_.FocusSearch();
    }
    else
    {
        fallback_.FocusSearch();
    }
}

void CloudOSDesktopSurface::SetActionCallback(ActionCallback callback)
{
    web_.SetActionCallback(callback);
    fallback_.SetActionCallback(std::move(callback));
}

void CloudOSDesktopSurface::SetHotKeyCallback(HotKeyCallback callback)
{
    web_.SetHotKeyCallback(callback);
    fallback_.SetHotKeyCallback(std::move(callback));
}

void CloudOSDesktopSurface::SetTimerCallback(TimerCallback callback)
{
    web_.SetTimerCallback(callback);
    fallback_.SetTimerCallback(std::move(callback));
}

HWND CloudOSDesktopSurface::Hwnd() const noexcept
{
    return web_active_ ? web_.Hwnd() : fallback_.Hwnd();
}
} // namespace CloudOS
