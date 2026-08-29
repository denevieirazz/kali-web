#include "native_files_style.h"

#include <dwmapi.h>

#pragma comment(lib, "dwmapi.lib")

namespace CloudOS::FilesStyle
{

void ApplyWindowChrome(HWND window) noexcept
{
    if (window == nullptr)
    {
        return;
    }

    // The hosted ExplorerBrowser follows the user's Windows Shell theme. The
    // Files chrome therefore uses a light title bar instead of forcing the
    // dark CloudOS desktop treatment over a light Shell content surface.
    const BOOL dark = FALSE;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_USE_IMMERSIVE_DARK_MODE,
        &dark,
        static_cast<DWORD>(sizeof(dark)));

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        static_cast<DWORD>(sizeof(corner)));

    // Windows 11 22H2+: use the system's long-lived window backdrop (Mica).
    // Older Windows versions simply ignore the unsupported attribute and the
    // opaque fallback palette remains fully usable.
    const DWM_SYSTEMBACKDROP_TYPE backdrop = DWMSBT_MAINWINDOW;
    (void)DwmSetWindowAttribute(
        window,
        DWMWA_SYSTEMBACKDROP_TYPE,
        &backdrop,
        static_cast<DWORD>(sizeof(backdrop)));
}

void PaintRoundedSurface(
    HDC dc,
    const RECT& bounds,
    COLORREF fill,
    COLORREF border,
    int radius,
    int border_width) noexcept
{
    if (dc == nullptr || bounds.right <= bounds.left || bounds.bottom <= bounds.top)
    {
        return;
    }

    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(
        border_width > 0 ? PS_SOLID : PS_NULL,
        border_width > 0 ? border_width : 1,
        border);
    if (brush == nullptr || pen == nullptr)
    {
        if (brush != nullptr) DeleteObject(brush);
        if (pen != nullptr) DeleteObject(pen);
        return;
    }

    HGDIOBJ old_brush = SelectObject(dc, brush);
    HGDIOBJ old_pen = SelectObject(dc, pen);
    RoundRect(
        dc,
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
        radius,
        radius);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void PaintSeparator(
    HDC dc,
    int x1,
    int y1,
    int x2,
    int y2,
    COLORREF color,
    int thickness) noexcept
{
    if (dc == nullptr)
    {
        return;
    }

    HPEN pen = CreatePen(PS_SOLID, thickness > 0 ? thickness : 1, color);
    if (pen == nullptr)
    {
        return;
    }

    HGDIOBJ old_pen = SelectObject(dc, pen);
    MoveToEx(dc, x1, y1, nullptr);
    LineTo(dc, x2, y2);
    SelectObject(dc, old_pen);
    DeleteObject(pen);
}

} // namespace CloudOS::FilesStyle
