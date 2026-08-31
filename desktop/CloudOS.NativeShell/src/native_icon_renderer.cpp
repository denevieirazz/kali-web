#include "native_icon_renderer.h"
#include <array>

using namespace Gdiplus;

namespace CloudOS
{

void NativeIconRenderer::DrawGlassPanel(Graphics& g, const RectF& rect, float radius, Color bg, Color border, float borderWidth)
{
    GraphicsPath path;
    const float d = radius * 2.0f;
    path.AddArc(rect.X, rect.Y, d, d, 180, 90);
    path.AddArc(rect.X + rect.Width - d, rect.Y, d, d, 270, 90);
    path.AddArc(rect.X + rect.Width - d, rect.Y + rect.Height - d, d, d, 0, 90);
    path.AddArc(rect.X, rect.Y + rect.Height - d, d, d, 90, 90);
    path.CloseFigure();

    SolidBrush brush(bg);
    g.FillPath(&brush, &path);

    if (border.GetAlpha() > 0)
    {
        Pen pen(border, borderWidth);
        g.DrawPath(&pen, &path);
    }
}

void NativeIconRenderer::DrawAppIcon(HDC, Graphics& g, const AppItem& app, int x, int y, int size)
{
    DrawAetherSquircle(g, app.icon_id, x, y, size);
}

void NativeIconRenderer::DrawAetherSquircle(Graphics& g, int icon_id, int x, int y, int size)
{
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetInterpolationMode(InterpolationModeHighQualityBicubic);

    const float sz = static_cast<float>(size);
    const float fx = static_cast<float>(x);
    const float fy = static_cast<float>(y);
    // Shared monochrome first-party vector family; no glossy tile behind every icon.
    // Crisp White Vector Icon inside
    Pen whitePen(WebSkin::GdiColor(WebSkin::TextPrimary), std::max(1.4f, sz / 22.0f));
    whitePen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
    SolidBrush whiteBr(WebSkin::GdiColor(WebSkin::TextPrimary));

    switch (icon_id)
    {
    case 1: // Browser / Globe Orbit
        g.DrawEllipse(&whitePen, fx + sz * 0.28f, fy + sz * 0.28f, sz * 0.44f, sz * 0.44f);
        g.DrawArc(&whitePen, fx + sz * 0.16f, fy + sz * 0.38f, sz * 0.68f, sz * 0.24f, 0, 360);
        break;
    case 2: // Planet / Orion
        g.FillEllipse(&whiteBr, fx + sz * 0.32f, fy + sz * 0.32f, sz * 0.36f, sz * 0.36f);
        g.DrawArc(&whitePen, fx + sz * 0.18f, fy + sz * 0.38f, sz * 0.64f, sz * 0.24f, 15, 330);
        break;
    case 3: // Terminal / Comms
        g.DrawLine(&whitePen, fx + sz * 0.30f, fy + sz * 0.36f, fx + sz * 0.46f, fy + sz * 0.50f);
        g.DrawLine(&whitePen, fx + sz * 0.46f, fy + sz * 0.50f, fx + sz * 0.30f, fy + sz * 0.64f);
        g.DrawLine(&whitePen, fx + sz * 0.52f, fy + sz * 0.64f, fx + sz * 0.70f, fy + sz * 0.64f);
        break;
    case 4: // PowerShell / Message Bubble
        g.DrawLine(&whitePen, fx + sz * 0.28f, fy + sz * 0.38f, fx + sz * 0.42f, fy + sz * 0.50f);
        g.DrawLine(&whitePen, fx + sz * 0.42f, fy + sz * 0.50f, fx + sz * 0.28f, fy + sz * 0.62f);
        g.DrawLine(&whitePen, fx + sz * 0.46f, fy + sz * 0.38f, fx + sz * 0.60f, fy + sz * 0.50f);
        g.DrawLine(&whitePen, fx + sz * 0.60f, fy + sz * 0.50f, fx + sz * 0.46f, fy + sz * 0.62f);
        break;
    case 5: // Mail Envelope
        g.DrawRectangle(&whitePen, fx + sz * 0.24f, fy + sz * 0.32f, sz * 0.52f, sz * 0.36f);
        g.DrawLine(&whitePen, fx + sz * 0.24f, fy + sz * 0.32f, fx + sz * 0.50f, fy + sz * 0.52f);
        g.DrawLine(&whitePen, fx + sz * 0.76f, fy + sz * 0.32f, fx + sz * 0.50f, fy + sz * 0.52f);
        break;
    case 6: // Drive SSD
        g.DrawRectangle(&whitePen, fx + sz * 0.24f, fy + sz * 0.30f, sz * 0.52f, sz * 0.40f);
        g.FillEllipse(&whiteBr, fx + sz * 0.60f, fy + sz * 0.52f, sz * 0.08f, sz * 0.08f);
        break;
    case 7: // Folder
        g.DrawRectangle(&whitePen, fx + sz * 0.24f, fy + sz * 0.36f, sz * 0.52f, sz * 0.36f);
        g.DrawLine(&whitePen, fx + sz * 0.24f, fy + sz * 0.36f, fx + sz * 0.44f, fy + sz * 0.36f);
        g.DrawLine(&whitePen, fx + sz * 0.44f, fy + sz * 0.36f, fx + sz * 0.52f, fy + sz * 0.30f);
        break;
    case 8: // Pencil / Art
        g.DrawLine(&whitePen, fx + sz * 0.65f, fy + sz * 0.28f, fx + sz * 0.35f, fy + sz * 0.65f);
        g.DrawLine(&whitePen, fx + sz * 0.35f, fy + sz * 0.65f, fx + sz * 0.28f, fy + sz * 0.72f);
        g.DrawLine(&whitePen, fx + sz * 0.28f, fy + sz * 0.72f, fx + sz * 0.35f, fy + sz * 0.65f);
        break;
    case 9: // Play Button
        g.DrawEllipse(&whitePen, fx + sz * 0.24f, fy + sz * 0.24f, sz * 0.52f, sz * 0.52f);
        {
            PointF tri[3] = {{fx + sz * 0.44f, fy + sz * 0.38f}, {fx + sz * 0.62f, fy + sz * 0.50f}, {fx + sz * 0.44f, fy + sz * 0.62f}};
            g.FillPolygon(&whiteBr, tri, 3);
        }
        break;
    case 10: // VS Code Editor
        g.DrawLine(&whitePen, fx + sz * 0.68f, fy + sz * 0.28f, fx + sz * 0.32f, fy + sz * 0.45f);
        g.DrawLine(&whitePen, fx + sz * 0.32f, fy + sz * 0.45f, fx + sz * 0.68f, fy + sz * 0.72f);
        g.DrawLine(&whitePen, fx + sz * 0.68f, fy + sz * 0.28f, fx + sz * 0.68f, fy + sz * 0.72f);
        break;
    case 11: // Gear Settings
        g.DrawEllipse(&whitePen, fx + sz * 0.32f, fy + sz * 0.32f, sz * 0.36f, sz * 0.36f);
        g.FillEllipse(&whiteBr, fx + sz * 0.42f, fy + sz * 0.42f, sz * 0.16f, sz * 0.16f);
        break;
    case 12: // Calc
        g.DrawRectangle(&whitePen, fx + sz * 0.28f, fy + sz * 0.26f, sz * 0.44f, sz * 0.48f);
        g.DrawLine(&whitePen, fx + sz * 0.36f, fy + sz * 0.36f, fx + sz * 0.64f, fy + sz * 0.36f);
        break;
    case 13: // Pulse / Sysmon
        g.DrawLine(&whitePen, fx + sz * 0.22f, fy + sz * 0.50f, fx + sz * 0.38f, fy + sz * 0.50f);
        g.DrawLine(&whitePen, fx + sz * 0.38f, fy + sz * 0.50f, fx + sz * 0.46f, fy + sz * 0.28f);
        g.DrawLine(&whitePen, fx + sz * 0.46f, fy + sz * 0.28f, fx + sz * 0.54f, fy + sz * 0.72f);
        g.DrawLine(&whitePen, fx + sz * 0.54f, fy + sz * 0.72f, fx + sz * 0.78f, fy + sz * 0.50f);
        break;
    default:
        g.FillEllipse(&whiteBr, fx + sz * 0.32f, fy + sz * 0.48f, sz * 0.08f, sz * 0.08f);
        g.FillEllipse(&whiteBr, fx + sz * 0.46f, fy + sz * 0.48f, sz * 0.08f, sz * 0.08f);
        g.FillEllipse(&whiteBr, fx + sz * 0.60f, fy + sz * 0.48f, sz * 0.08f, sz * 0.08f);
        break;
    }
}

} // namespace CloudOS
