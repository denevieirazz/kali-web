#include "native_files_style.h"

#include <dwmapi.h>

#include <algorithm>

#pragma comment(lib, "dwmapi.lib")

namespace CloudOS::FilesStyle
{
namespace
{
COLORREF Lift(COLORREF color, int amount) noexcept
{
    const auto lift = [amount](BYTE channel) -> BYTE
    {
        return static_cast<BYTE>((std::min)(255, static_cast<int>(channel) + amount));
    };
    return RGB(lift(GetRValue(color)), lift(GetGValue(color)), lift(GetBValue(color)));
}
}

void ApplyWindowChrome(HWND window) noexcept
{
    if (window == nullptr) return;

    const BOOL dark = TRUE;
    (void)DwmSetWindowAttribute(
        window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, static_cast<DWORD>(sizeof(dark)));

    const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    (void)DwmSetWindowAttribute(
        window, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, static_cast<DWORD>(sizeof(corner)));

    const DWM_SYSTEMBACKDROP_TYPE backdrop = DWMSBT_MAINWINDOW;
    (void)DwmSetWindowAttribute(
        window, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, static_cast<DWORD>(sizeof(backdrop)));

    const COLORREF border = kPalette.border;
    (void)DwmSetWindowAttribute(
        window, static_cast<DWMWINDOWATTRIBUTE>(34), &border, static_cast<DWORD>(sizeof(border)));

    const COLORREF caption = kPalette.toolbar;
    (void)DwmSetWindowAttribute(
        window, static_cast<DWMWINDOWATTRIBUTE>(35), &caption, static_cast<DWORD>(sizeof(caption)));
}

void PaintRoundedSurface(
    HDC dc,
    const RECT& bounds,
    COLORREF fill,
    COLORREF border,
    int radius,
    int border_width) noexcept
{
    if (dc == nullptr || bounds.right <= bounds.left || bounds.bottom <= bounds.top) return;

    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    const bool elevated = radius >= 10 && width >= 72 && height >= 32;

    if (elevated)
    {
        RECT shadow = bounds;
        OffsetRect(&shadow, 0, 3);
        HBRUSH shadow_brush = CreateSolidBrush(RGB(3, 5, 10));
        HPEN shadow_pen = CreatePen(PS_NULL, 1, RGB(3, 5, 10));
        if (shadow_brush != nullptr && shadow_pen != nullptr)
        {
            HGDIOBJ old_brush = SelectObject(dc, shadow_brush);
            HGDIOBJ old_pen = SelectObject(dc, shadow_pen);
            RoundRect(dc, shadow.left, shadow.top, shadow.right, shadow.bottom, radius, radius);
            SelectObject(dc, old_pen);
            SelectObject(dc, old_brush);
        }
        if (shadow_pen != nullptr) DeleteObject(shadow_pen);
        if (shadow_brush != nullptr) DeleteObject(shadow_brush);
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
    RoundRect(dc, bounds.left, bounds.top, bounds.right, bounds.bottom, radius, radius);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);

    if (elevated)
    {
        const COLORREF highlight = Lift(fill, 18);
        HPEN highlight_pen = CreatePen(PS_SOLID, 1, highlight);
        if (highlight_pen != nullptr)
        {
            HGDIOBJ old = SelectObject(dc, highlight_pen);
            const int inset = (std::max)(6, radius / 2);
            MoveToEx(dc, bounds.left + inset, bounds.top + 1, nullptr);
            LineTo(dc, bounds.right - inset, bounds.top + 1);
            SelectObject(dc, old);
            DeleteObject(highlight_pen);
        }
    }
}

void PaintSeparator(HDC dc, int x1, int y1, int x2, int y2, COLORREF color, int thickness) noexcept
{
    if (dc == nullptr) return;
    HPEN pen = CreatePen(PS_SOLID, thickness > 0 ? thickness : 1, color);
    if (pen == nullptr) return;
    HGDIOBJ old_pen = SelectObject(dc, pen);
    MoveToEx(dc, x1, y1, nullptr);
    LineTo(dc, x2, y2);
    SelectObject(dc, old_pen);
    DeleteObject(pen);
}
} // namespace CloudOS::FilesStyle
