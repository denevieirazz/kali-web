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
    const float radius = sz * 0.28f;

    // Gradient Background Palette per Icon
    Color col1(255, 59, 130, 246);
    Color col2(255, 147, 51, 234);

    switch (icon_id)
    {
    case 1: col1 = Color(255, 236, 72, 153); col2 = Color(255, 99, 102, 241); break; // Nebula Browser (Pink->Violet)
    case 2: col1 = Color(255, 168, 85, 247); col2 = Color(255, 99, 102, 241); break; // Orion (Purple->Indigo)
    case 3: col1 = Color(255, 56, 189, 248); col2 = Color(255, 37, 99, 235); break;  // Comms (Cyan->Blue)
    case 4: col1 = Color(255, 45, 212, 191); col2 = Color(255, 14, 165, 233); break; // Quantum Shell (Teal->Sky)
    case 5: col1 = Color(255, 129, 140, 248); col2 = Color(255, 99, 102, 241); break; // Mail (Indigo->Violet)
    case 6: col1 = Color(255, 52, 211, 153); col2 = Color(255, 13, 148, 136); break; // Synapse Drive (Emerald->Teal)
    case 7: col1 = Color(255, 96, 165, 250); col2 = Color(255, 37, 99, 235); break;  // Files (Blue)
    case 8: col1 = Color(255, 251, 146, 60); col2 = Color(255, 244, 63, 94); break;  // Art Studio (Orange->Rose)
    case 9: col1 = Color(255, 192, 132, 252); col2 = Color(255, 147, 51, 234); break; // Media (Lavender->Purple)
    case 10: col1 = Color(255, 56, 189, 248); col2 = Color(255, 30, 64, 175); break; // Code Editor (Cyan->DarkBlue)
    case 11: col1 = Color(255, 148, 163, 184); col2 = Color(255, 71, 85, 105); break; // Settings (Silver->Slate)
    case 12: col1 = Color(255, 244, 114, 182); col2 = Color(255, 219, 39, 119); break; // Calc (Pink)
    case 13: col1 = Color(255, 56, 189, 248); col2 = Color(255, 20, 184, 166); break; // Sysmon (Cyan->Teal)
    case 14: col1 = Color(255, 192, 132, 252); col2 = Color(255, 236, 72, 153); break; // Regedit (Violet->Pink)
    case 15: col1 = Color(255, 251, 191, 36); col2 = Color(255, 245, 158, 11); break; // Snip (Amber->Gold)
    case 16: col1 = Color(255, 45, 212, 191); col2 = Color(255, 59, 130, 246); break; // App Catalog (Teal->Blue)
    case 17: col1 = Color(255, 129, 140, 248); col2 = Color(255, 56, 189, 248); break; // Run (Indigo->Cyan)
    case 18: col1 = Color(255, 100, 116, 139); col2 = Color(255, 51, 65, 85); break; // More (Slate)
    default: break;
    }

    GraphicsPath squircle;
    const float d = radius * 2.0f;
    squircle.AddArc(fx, fy, d, d, 180, 90);
    squircle.AddArc(fx + sz - d, fy, d, d, 270, 90);
    squircle.AddArc(fx + sz - d, fy + sz - d, d, d, 0, 90);
    squircle.AddArc(fx, fy + sz - d, d, d, 90, 90);
    squircle.CloseFigure();

    LinearGradientBrush br(PointF(fx, fy), PointF(fx + sz, fy + sz), col1, col2);
    g.FillPath(&br, &squircle);

    // Glass top highlight shine
    LinearGradientBrush shine(PointF(fx, fy), PointF(fx, fy + sz * 0.5f), Color(140, 255, 255, 255), Color(0, 255, 255, 255));
    g.FillPath(&shine, &squircle);

    // Glowing border outline
    Pen p(Color(180, 255, 255, 255), 1.2f);
    g.DrawPath(&p, &squircle);

    // Crisp White Vector Icon inside
    Pen whitePen(Color(255, 255, 255, 255), 2.2f);
    whitePen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
    SolidBrush whiteBr(Color(255, 255, 255, 255));

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
