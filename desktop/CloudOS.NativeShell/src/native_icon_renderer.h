#pragma once

#include <windows.h>
#include <gdiplus.h>
#include "native_theme.h"

namespace CloudOS
{
class NativeIconRenderer final
{
public:
    static void DrawAetherSquircle(Gdiplus::Graphics& g, int icon_id, int x, int y, int size);
    static void DrawAppIcon(HDC hdc, Gdiplus::Graphics& g, const AppItem& app, int x, int y, int size);
    static void DrawGlassPanel(Gdiplus::Graphics& g, const Gdiplus::RectF& rect, float radius, Gdiplus::Color bg, Gdiplus::Color border, float borderWidth = 1.0f);
};
} // namespace CloudOS
