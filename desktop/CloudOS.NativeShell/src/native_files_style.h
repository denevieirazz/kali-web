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

// Files V5 uses a deeper graphite/indigo hierarchy than the early WebSkin.
// The Windows namespace itself is still provided by IExplorerBrowser; these
// tokens only own the CloudOS chrome around it.
inline constexpr Palette kPalette{
    RGB(6, 8, 14),      // base: deep graphite
    RGB(11, 15, 24),    // sidebar
    RGB(13, 18, 28),    // toolbar
    RGB(22, 29, 43),    // address / input surface
    RGB(15, 20, 31),    // content
    RGB(24, 31, 46),    // button
    RGB(31, 40, 58),    // hover
    RGB(40, 37, 86),    // pressed/accent subtle
    RGB(34, 34, 78),    // selection
    RGB(48, 58, 78),    // border
    RGB(124, 92, 255),  // accent
    RGB(97, 70, 224),   // accent pressed
    RGB(244, 246, 252), // text
    RGB(151, 161, 184), // muted
    RGB(235, 92, 108),  // danger
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
