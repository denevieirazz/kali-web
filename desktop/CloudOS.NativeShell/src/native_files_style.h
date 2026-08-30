#pragma once

#include <Windows.h>

namespace CloudOS::FilesStyle
{
struct Palette final
{
    COLORREF base;
    COLORREF sidebar;
    COLORREF toolbar;
    COLORREF address;
    COLORREF content;
    COLORREF button;
    COLORREF hover;
    COLORREF pressed;
    COLORREF selection;
    COLORREF border;
    COLORREF accent;
    COLORREF accent_pressed;
    COLORREF text;
    COLORREF muted;
    COLORREF danger;
};

// Same visual tokens used by frontend/src/index.css and native_theme.h.  The
// hosted Windows Shell view may still follow the user's system theme, but all
// CloudOS-owned chrome remains dark and consistent around it.
inline constexpr Palette kPalette{
    RGB(10, 10, 15),    // base #0a0a0f
    RGB(17, 17, 24),    // sidebar #111118
    RGB(17, 17, 24),    // toolbar
    RGB(34, 34, 46),    // address #22222e
    RGB(26, 26, 36),    // content #1a1a24
    RGB(34, 34, 46),    // button
    RGB(40, 40, 53),    // hover
    RGB(31, 31, 66),    // pressed/accent subtle
    RGB(31, 31, 66),    // selection
    RGB(55, 55, 70),    // border
    RGB(99, 102, 241),  // accent #6366f1
    RGB(79, 70, 229),   // accent pressed
    RGB(240, 240, 245), // text
    RGB(160, 160, 184), // muted
    RGB(219, 99, 106),  // danger
};

void ApplyWindowChrome(HWND window) noexcept;

void PaintRoundedSurface(
    HDC dc,
    const RECT& bounds,
    COLORREF fill,
    COLORREF border,
    int radius,
    int border_width = 1) noexcept;

void PaintSeparator(
    HDC dc,
    int x1,
    int y1,
    int x2,
    int y2,
    COLORREF color,
    int thickness = 1) noexcept;

} // namespace CloudOS::FilesStyle
