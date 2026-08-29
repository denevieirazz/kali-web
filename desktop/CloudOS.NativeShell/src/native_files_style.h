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

// Fluent-inspired light palette intentionally matches the native Windows
// Shell view hosted by IExplorerBrowser. Avoiding a forced dark client chrome
// prevents the hard dark/white split that made the previous Files UI look
// unfinished while keeping the rest of CloudOS free to use its dark shell.
inline constexpr Palette kPalette{
    RGB(247, 248, 251), // base
    RGB(241, 243, 247), // sidebar
    RGB(247, 248, 251), // toolbar
    RGB(238, 241, 246), // address
    RGB(252, 252, 253), // content
    RGB(246, 247, 250), // button
    RGB(233, 237, 244), // hover
    RGB(222, 229, 239), // pressed
    RGB(220, 232, 250), // selection
    RGB(214, 220, 230), // border
    RGB(0, 103, 192),   // accent
    RGB(0, 82, 153),    // accent pressed
    RGB(31, 36, 44),    // text
    RGB(100, 109, 124), // muted
    RGB(184, 40, 50),   // danger
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
