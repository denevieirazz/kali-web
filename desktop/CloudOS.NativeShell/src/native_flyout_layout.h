#pragma once
#include <windows.h>
#include <algorithm>

namespace CloudOS
{
inline RECT FitFlyout(const RECT& anchor, const RECT& work, int width, int height, int gap, bool centered = false)
{
    const int available_width = std::max(1L, work.right - work.left);
    const int available_height = std::max(1L, work.bottom - work.top);
    width = std::clamp(width, 1, available_width);
    height = std::clamp(height, 1, available_height);
    const int x = centered ? anchor.left + (anchor.right - anchor.left - width) / 2 : anchor.right - width;
    const int y = anchor.top - height - gap;
    const int left = std::clamp<int>(x, work.left, work.right - width);
    const int top = std::clamp<int>(y, work.top, work.bottom - height);
    return {left, top, left + width, top + height};
}

inline RECT FitSuggestedFlyout(const RECT& suggested)
{
    MONITORINFO monitor{sizeof(monitor)};
    if (!GetMonitorInfoW(MonitorFromRect(&suggested, MONITOR_DEFAULTTONEAREST), &monitor)) return suggested;
    const RECT anchor{suggested.left, suggested.bottom, suggested.right, suggested.bottom};
    return FitFlyout(anchor, monitor.rcWork, suggested.right-suggested.left, suggested.bottom-suggested.top, 0);
}

// Pixel offsets; page and range are recomputed on resize and DPI changes.
struct NativeScrollState final
{
    int position{};
    int extent{};
    int page{};
    int wheel_remainder{};
    void Clamp() { position = std::clamp(position, 0, std::max(0, extent - page)); }
    void Update(HWND window, int content, int viewport)
    {
        extent = std::max(0, content); page = std::max(1, viewport); Clamp();
        SCROLLINFO info{sizeof(info), SIF_RANGE | SIF_PAGE | SIF_POS};
        info.nMax = std::max(0, extent - 1); info.nPage = page; info.nPos = position;
        SetScrollInfo(window, SB_VERT, &info, TRUE);
    }
    void Scroll(HWND window, WPARAM command, int line)
    {
        switch (LOWORD(command))
        {
        case SB_LINEUP: position -= line; break;
        case SB_LINEDOWN: position += line; break;
        case SB_PAGEUP: position -= page; break;
        case SB_PAGEDOWN: position += page; break;
        case SB_TOP: position = 0; break;
        case SB_BOTTOM: position = extent; break;
        case SB_THUMBTRACK: case SB_THUMBPOSITION:
        {
            SCROLLINFO info{sizeof(info), SIF_TRACKPOS};
            GetScrollInfo(window, SB_VERT, &info); position = info.nTrackPos; break;
        }
        default: break;
        }
        Clamp();
    }
    void Wheel(short delta, int line)
    {
        UINT lines = 3;
        SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
        wheel_remainder += delta;
        position -= (wheel_remainder / WHEEL_DELTA) * (lines == WHEEL_PAGESCROLL ? page : static_cast<int>(lines) * line);
        wheel_remainder %= WHEEL_DELTA; Clamp();
    }
};
}
