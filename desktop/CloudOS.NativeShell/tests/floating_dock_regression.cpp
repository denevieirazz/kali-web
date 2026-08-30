#include "../src/native_taskbar_appbar.h"
#include <cstdio>

namespace
{
int position_changes = 0;
LRESULT CALLBACK TestWindow(HWND window, UINT message, WPARAM wp, LPARAM lp)
{
    if (message == WM_WINDOWPOSCHANGED) ++position_changes;
    return DefWindowProcW(window, message, wp, lp);
}
bool DrainEvents()
{
    const auto deadline = GetTickCount64() + 1000;
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
    {
        DispatchMessageW(&message);
        if (GetTickCount64() >= deadline || position_changes > 100) return false;
    }
    return true;
}
}

int main()
{
    (void)SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSW wc{};
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpfnWndProc = TestWindow;
    wc.lpszClassName = L"CloudOS.NativeShell.Taskbar.v4";
    if (!RegisterClassW(&wc)) return 1;
    HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"Dock regression fixture",
        WS_POPUP, 0, 0, 800, 68, nullptr, nullptr, wc.hInstance, nullptr);
    if (!window) return 2;
    CloudOS::FloatingDockV7::Apply(window);
    if (!DrainEvents()) return 3;
    position_changes = 0;
    const DWORD gdi_before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    for (int i = 0; i < 1000; ++i) CloudOS::FloatingDockV7::Apply(window);
    if (!DrainEvents() || position_changes != 0) return 4;
    if (GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) > gdi_before) return 5;

    HRGN before = CreateRectRgn(0, 0, 0, 0);
    HRGN after = CreateRectRgn(0, 0, 0, 0);
    if (!before || !after || GetWindowRgn(window, before) == ERROR) return 6;
    SetWindowPos(window, nullptr, 0, 0, 1000, 80, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    CloudOS::FloatingDockV7::Apply(window);
    if (!DrainEvents() || GetWindowRgn(window, after) == ERROR || EqualRgn(before, after)) return 7;
    if (PtInRegion(after, 0, 0) || PtInRegion(after, 500, 79) || !PtInRegion(after, 500, 30)) return 8;
    DeleteObject(before);
    DeleteObject(after);
    DestroyWindow(window);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);
    std::puts("PASS: dock region is idempotent, event queue drains, resize updates clipping, gaps are click-through, no GDI handle growth after 1000 applications.");
    return 0;
}
