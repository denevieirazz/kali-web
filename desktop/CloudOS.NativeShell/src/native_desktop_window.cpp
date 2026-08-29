#include "native_desktop_window.h"
#include "native_icon_renderer.h"
#include "native_search_engine.h"
#include "native_app_launcher.h"

using namespace Gdiplus;

namespace CloudOS
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.AetherDesktop.v18";
constexpr UINT_PTR kSearchSubclassId = 301;

CloudOSNativeDesktopWindow::~CloudOSNativeDesktopWindow()
{
    Destroy();
}

bool CloudOSNativeDesktopWindow::Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager)
{
    instance_ = instance;
    window_manager_ = window_manager;
    edit_bg_brush_ = CreateSolidBrush(RGB(24, 34, 58));

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &CloudOSNativeDesktopWindow::WindowProcedure;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kDesktopClass;
    if (RegisterClassExW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kDesktopClass, L"AETHER OS Desktop", WS_POPUP,
        0, 0, 0, 0, nullptr, nullptr, instance, this);

    if (hwnd_ == nullptr) return false;

    // Real Native Interactive Search Edit Control
    search_edit_ = CreateWindowExW(
        0, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_LEFT | ES_AUTOHSCROLL,
        0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(501), instance, nullptr);

    if (search_edit_ != nullptr)
    {
        SetWindowSubclass(search_edit_, &CloudOSNativeDesktopWindow::SearchSubclass, kSearchSubclassId, reinterpret_cast<DWORD_PTR>(this));
        SendMessageW(search_edit_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"Search Apps, Files, Settings..."));
    }

    filtered_indices_ = NativeSearchEngine::FilterApps(L"");
    current_stats_ = NativeSystemStats::Query();

    DarkWindow(hwnd_, false);
    return true;
}

void CloudOSNativeDesktopWindow::Destroy()
{
    if (search_font_ != nullptr)
    {
        DeleteObject(search_font_);
        search_font_ = nullptr;
    }
    if (edit_bg_brush_ != nullptr)
    {
        DeleteObject(edit_bg_brush_);
        edit_bg_brush_ = nullptr;
    }
    if (hwnd_ != nullptr && IsWindow(hwnd_))
    {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
}

void CloudOSNativeDesktopWindow::UpdateLayout(const RECT& work_area)
{
    if (hwnd_ == nullptr) return;
    const UINT dpi = GetDpiForWindow(hwnd_);
    const int work_w = static_cast<int>(work_area.right - work_area.left);
    const int work_h = static_cast<int>(work_area.bottom - work_area.top);

    SetWindowPos(
        hwnd_, HWND_BOTTOM,
        work_area.left, work_area.top,
        work_w, work_h,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);

    // Position search EDIT control inside the glass header
    const int dash_w = Scale(1020, dpi);
    const int dash_h = Scale(630, dpi);
    const int dash_x = (work_w - dash_w) / 2;
    const int dash_y = (work_h - dash_h) / 2 - Scale(15, dpi);

    const int search_x = dash_x + Scale(270, dpi);
    const int search_y = dash_y + Scale(34, dpi);
    const int search_w = Scale(310, dpi);
    const int search_h = Scale(24, dpi);

    if (search_edit_ != nullptr)
    {
        SetWindowPos(search_edit_, nullptr, search_x, search_y, search_w, search_h, SWP_NOZORDER | SWP_SHOWWINDOW);
        if (search_font_ != nullptr) DeleteObject(search_font_);
        search_font_ = CreateFontW(
            -MulDiv(10, static_cast<int>(dpi), 72),
            0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        SendMessageW(search_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(search_font_), TRUE);
    }
}

void CloudOSNativeDesktopWindow::Redraw()
{
    if (hwnd_ != nullptr) InvalidateRect(hwnd_, nullptr, FALSE);
}

void CloudOSNativeDesktopWindow::OnSearchChanged()
{
    if (search_edit_ == nullptr) return;
    wchar_t buffer[256]{};
    GetWindowTextW(search_edit_, buffer, 256);
    search_query_ = buffer;
    filtered_indices_ = NativeSearchEngine::FilterApps(search_query_);
    focused_app_index_ = 0;
    Redraw();
}

void CloudOSNativeDesktopWindow::SelectFocusedApp()
{
    if (filtered_indices_.empty()) return;
    int idx = std::clamp(focused_app_index_, 0, static_cast<int>(filtered_indices_.size()) - 1);
    int app_idx = filtered_indices_[static_cast<std::size_t>(idx)];
    NativeAppLauncher::Launch(instance_, hwnd_, kAllApps[static_cast<std::size_t>(app_idx)]);
}

void CloudOSNativeDesktopWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(hwnd_, &paint);
    RECT client{};
    GetClientRect(hwnd_, &client);
    const UINT dpi = GetDpiForWindow(hwnd_);
    const int width = Width(client);
    const int height = Height(client);

    // Double buffering for 60 FPS ultra-smooth graphics
    HDC device = CreateCompatibleDC(screen_dc);
    HBITMAP mem_bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bmp = SelectObject(device, mem_bitmap);

    Graphics g(device);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    // 1. Cyberpunk Atmospheric Wallpaper
    RectF fullBg(0.0f, 0.0f, static_cast<float>(width), static_cast<float>(height));
    LinearGradientBrush bgGrad(PointF(0.0f, 0.0f), PointF(0.0f, static_cast<float>(height)), Color(255, 10, 14, 26), Color(255, 4, 6, 12));
    g.FillRectangle(&bgGrad, fullBg);

    // Ambient Volumetric Hologram Glows
    SolidBrush cyanGlow(Color(30, 56, 189, 248));
    SolidBrush purpleGlow(Color(25, 168, 85, 247));
    g.FillEllipse(&cyanGlow, static_cast<float>(width / 2 - Scale(480, dpi)), static_cast<float>(height / 2 - Scale(400, dpi)), static_cast<float>(Scale(960, dpi)), static_cast<float>(Scale(800, dpi)));
    g.FillEllipse(&purpleGlow, static_cast<float>(width - Scale(600, dpi)), static_cast<float>(Scale(30, dpi)), static_cast<float>(Scale(700, dpi)), static_cast<float>(Scale(600, dpi)));

    // 2. Main Central Glass Dashboard ("AETHER OS")
    const int dash_w = Scale(1020, dpi);
    const int dash_h = Scale(630, dpi);
    const int dash_x = (width - dash_w) / 2;
    const int dash_y = (height - dash_h) / 2 - Scale(15, dpi);

    RectF mainGlass(static_cast<float>(dash_x), static_cast<float>(dash_y), static_cast<float>(dash_w), static_cast<float>(dash_h));
    NativeIconRenderer::DrawGlassPanel(g, mainGlass, static_cast<float>(Scale(28, dpi)), Color(210, 15, 23, 40), Color(180, 56, 189, 248), 1.5f);

    // Fonts & Brushes
    Font titleFont(L"Segoe UI", static_cast<REAL>(Scale(16, dpi)), FontStyleBold, UnitPixel);
    Font subFont(L"Segoe UI", static_cast<REAL>(Scale(11, dpi)), FontStyleBold, UnitPixel);
    Font bodyFont(L"Segoe UI", static_cast<REAL>(Scale(10, dpi)), FontStyleRegular, UnitPixel);
    Font microFont(L"Segoe UI", static_cast<REAL>(Scale(8, dpi)), FontStyleRegular, UnitPixel);

    SolidBrush whiteBr(Color(255, 255, 255, 255));
    SolidBrush cyanBr(Color(255, 56, 189, 248));
    SolidBrush textSecBr(Color(255, 180, 200, 230));
    SolidBrush textMutedBr(Color(255, 120, 145, 180));

    // Logo Text "AETHER OS"
    g.DrawString(L"AETHER  OS", -1, &titleFont, PointF(static_cast<float>(dash_x + Scale(36, dpi)), static_cast<float>(dash_y + Scale(32, dpi))), &whiteBr);

    // Search Pill Container
    const int search_x = dash_x + Scale(240, dpi);
    const int search_y = dash_y + Scale(28, dpi);
    const int search_w = Scale(410, dpi);
    const int search_h = Scale(38, dpi);
    RectF searchRect(static_cast<float>(search_x), static_cast<float>(search_y), static_cast<float>(search_w), static_cast<float>(search_h));
    NativeIconRenderer::DrawGlassPanel(g, searchRect, static_cast<float>(Scale(19, dpi)), Color(160, 24, 34, 58), search_query_.empty() ? Color(100, 56, 189, 248) : Color(255, 56, 189, 248), 1.2f);
    g.DrawString(L"🔍", -1, &bodyFont, PointF(static_cast<float>(search_x + Scale(12, dpi)), static_cast<float>(search_y + Scale(10, dpi))), &textMutedBr);
    g.DrawString(L"🎙   ⚙", -1, &bodyFont, PointF(static_cast<float>(search_x + search_w - Scale(56, dpi)), static_cast<float>(search_y + Scale(10, dpi))), &cyanBr);

    // =========================================================================
    // LEFT SIDE: 3x6 Vibrant Squircles App Grid
    // =========================================================================
    const int grid_left = dash_x + Scale(36, dpi);
    const int grid_top = dash_y + Scale(90, dpi);
    const int item_w = Scale(104, dpi);
    const int item_h = Scale(96, dpi);
    const int squircle_sz = Scale(52, dpi);
    const int cols = 6;

    app_grid_rects_.clear();
    filtered_indices_ = NativeSearchEngine::FilterApps(search_query_);

    for (std::size_t i = 0; i < 18; ++i)
    {
        const int col = static_cast<int>(i % cols);
        const int row = static_cast<int>(i / cols);
        const int ix = grid_left + col * (item_w + Scale(4, dpi));
        const int iy = grid_top + row * (item_h + Scale(6, dpi));
        RECT tile_r{ix, iy, ix + item_w, iy + item_h};
        app_grid_rects_.push_back(tile_r);

        if (i < filtered_indices_.size())
        {
            const int app_idx = filtered_indices_[i];
            const auto& app = kAllApps[static_cast<std::size_t>(app_idx)];
            const bool is_hovered = (hovered_app_index_ == static_cast<int>(i));
            const bool is_focused = (focused_app_index_ == static_cast<int>(i) && !search_query_.empty());

            if (is_hovered || is_focused)
            {
                RectF hoverPill(static_cast<float>(ix + Scale(4, dpi)), static_cast<float>(iy - Scale(2, dpi)), static_cast<float>(item_w - Scale(8, dpi)), static_cast<float>(item_h + Scale(4, dpi)));
                NativeIconRenderer::DrawGlassPanel(g, hoverPill, static_cast<float>(Scale(16, dpi)), Color(100, 56, 189, 248), Color(200, 56, 189, 248), 1.0f);
            }

            // Draw Squircle Icon
            NativeIconRenderer::DrawAetherSquircle(g, app.icon_id, ix + (item_w - squircle_sz) / 2, iy, squircle_sz);

            // Label Below
            StringFormat sf;
            sf.SetAlignment(StringAlignmentCenter);
            sf.SetLineAlignment(StringAlignmentCenter);
            RectF labelRect(static_cast<float>(ix), static_cast<float>(iy + squircle_sz + Scale(4, dpi)), static_cast<float>(item_w), static_cast<float>(Scale(24, dpi)));
            g.DrawString(app.name, -1, &microFont, labelRect, &sf, is_hovered ? &whiteBr : &textSecBr);
        }
    }

    // Recent Activity & Quick Launch Footer
    const int rec_y = dash_y + Scale(475, dpi);
    g.DrawString(L"RECENT ACTIVITY", -1, &subFont, PointF(static_cast<float>(dash_x + Scale(36, dpi)), static_cast<float>(rec_y)), &textMutedBr);
    g.DrawString(L"11:30  Nebula Browser", -1, &microFont, PointF(static_cast<float>(dash_x + Scale(36, dpi)), static_cast<float>(rec_y + Scale(22, dpi))), &textSecBr);
    g.DrawString(L"Orion Projects (WSL Kali)", -1, &microFont, PointF(static_cast<float>(dash_x + Scale(36, dpi)), static_cast<float>(rec_y + Scale(38, dpi))), &cyanBr);

    g.DrawString(L"QUICK LAUNCH", -1, &subFont, PointF(static_cast<float>(dash_x + Scale(360, dpi)), static_cast<float>(rec_y)), &textMutedBr);
    int q_x = dash_x + Scale(360, dpi);
    for (int q = 1; q <= 6; ++q)
    {
        NativeIconRenderer::DrawAetherSquircle(g, q, q_x, rec_y + Scale(20, dpi), Scale(26, dpi));
        q_x += Scale(34, dpi);
    }

    // =========================================================================
    // RIGHT SIDE: Sidebar Interactive Widgets
    // =========================================================================
    const int side_x = dash_x + Scale(700, dpi);
    const int side_w = Scale(285, dpi);
    int widget_y = dash_y + Scale(26, dpi);

    // 1. User Profile Widget (Click opens Quick Menu)
    profile_rect_ = RECT{side_x, widget_y, side_x + side_w, widget_y + Scale(64, dpi)};
    RectF profRect(static_cast<float>(side_x), static_cast<float>(widget_y), static_cast<float>(side_w), static_cast<float>(Scale(64, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, profRect, static_cast<float>(Scale(16, dpi)), (hovered_widget_id_ == 1) ? Color(200, 36, 48, 78) : Color(160, 24, 34, 58), Color(80, 56, 189, 248), 1.0f);

    const float av_sz = static_cast<float>(Scale(40, dpi));
    const float av_x = static_cast<float>(side_x + Scale(12, dpi));
    const float av_y = static_cast<float>(widget_y + Scale(12, dpi));
    LinearGradientBrush avBr(PointF(av_x, av_y), PointF(av_x + av_sz, av_y + av_sz), Color(255, 56, 189, 248), Color(255, 168, 85, 247));
    g.FillEllipse(&avBr, av_x, av_y, av_sz, av_sz);
    Pen avPen(Color(255, 56, 189, 248), 2.0f);
    g.DrawEllipse(&avPen, av_x, av_y, av_sz, av_sz);

    wchar_t username[256]{};
    DWORD u_len = 256;
    GetUserNameW(username, &u_len);
    wchar_t init_char[2] = { username[0] != L'\0' ? username[0] : L'A', L'\0' };
    StringFormat avSf;
    avSf.SetAlignment(StringAlignmentCenter);
    avSf.SetLineAlignment(StringAlignmentCenter);
    g.DrawString(init_char, -1, &subFont, RectF(av_x, av_y, av_sz, av_sz), &avSf, &whiteBr);

    g.DrawString(username, -1, &subFont, PointF(static_cast<float>(side_x + Scale(60, dpi)), static_cast<float>(widget_y + Scale(14, dpi))), &whiteBr);
    g.DrawString(L"● ACTIVE", -1, &microFont, PointF(static_cast<float>(side_x + Scale(60, dpi)), static_cast<float>(widget_y + Scale(34, dpi))), &cyanBr);

    widget_y += Scale(74, dpi);

    // 2. Weather Widget
    weather_rect_ = RECT{side_x, widget_y, side_x + side_w, widget_y + Scale(72, dpi)};
    RectF wthRect(static_cast<float>(side_x), static_cast<float>(widget_y), static_cast<float>(side_w), static_cast<float>(Scale(72, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, wthRect, static_cast<float>(Scale(16, dpi)), (hovered_widget_id_ == 2) ? Color(200, 36, 48, 78) : Color(160, 24, 34, 58), Color(80, 56, 189, 248), 1.0f);
    g.DrawString(L"Weather  ›", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(10, dpi))), &textMutedBr);
    g.DrawString(L"🌤  São Paulo / Neo-Tokyo", -1, &bodyFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(34, dpi))), &whiteBr);
    g.DrawString(L"22°C", -1, &titleFont, PointF(static_cast<float>(side_x + side_w - Scale(70, dpi)), static_cast<float>(widget_y + Scale(24, dpi))), &whiteBr);

    widget_y += Scale(82, dpi);

    // 3. Calendar Widget
    calendar_rect_ = RECT{side_x, widget_y, side_x + side_w, widget_y + Scale(72, dpi)};
    RectF calRect(static_cast<float>(side_x), static_cast<float>(widget_y), static_cast<float>(side_w), static_cast<float>(Scale(72, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, calRect, static_cast<float>(Scale(16, dpi)), (hovered_widget_id_ == 3) ? Color(200, 36, 48, 78) : Color(160, 24, 34, 58), Color(80, 56, 189, 248), 1.0f);
    g.DrawString(L"Calendar  ›", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(10, dpi))), &textMutedBr);
    g.DrawString(L"10:30 AM", -1, &subFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(30, dpi))), &cyanBr);
    g.DrawString(L"CloudOS Architecture Sync", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(48, dpi))), &textSecBr);

    widget_y += Scale(82, dpi);

    // 4. Performance Widget (Real-time Live Telemetry)
    perf_rect_ = RECT{side_x, widget_y, side_x + side_w, widget_y + Scale(86, dpi)};
    RectF perfRect(static_cast<float>(side_x), static_cast<float>(widget_y), static_cast<float>(side_w), static_cast<float>(Scale(86, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, perfRect, static_cast<float>(Scale(16, dpi)), (hovered_widget_id_ == 4) ? Color(200, 36, 48, 78) : Color(160, 24, 34, 58), Color(80, 56, 189, 248), 1.0f);
    g.DrawString(L"Performance (Clique para Gerenciador)  ›", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(10, dpi))), &textMutedBr);

    wchar_t perfText[128]{};
    swprintf_s(perfText, L"CPU %d%%  |  RAM %d%%  |  SSD C: %lluGB", current_stats_.cpu_percent, current_stats_.ram_percent, current_stats_.disk_free_gb);
    g.DrawString(perfText, -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(32, dpi))), &whiteBr);

    const float bar_w = static_cast<float>(side_w - Scale(28, dpi));
    const float bar_y = static_cast<float>(widget_y + Scale(56, dpi));
    RectF track(static_cast<float>(side_x + Scale(14, dpi)), bar_y, bar_w, static_cast<float>(Scale(6, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, track, static_cast<float>(Scale(3, dpi)), Color(255, 30, 41, 59), Color(0, 0, 0, 0));

    RectF fillBar(static_cast<float>(side_x + Scale(14, dpi)), bar_y, bar_w * (current_stats_.cpu_percent / 100.0f), static_cast<float>(Scale(6, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, fillBar, static_cast<float>(Scale(3, dpi)), Color(255, 56, 189, 248), Color(255, 168, 85, 247));

    widget_y += Scale(96, dpi);

    // 5. News / System Status Feed
    news_rect_ = RECT{side_x, widget_y, side_x + side_w, widget_y + Scale(110, dpi)};
    RectF newsRect(static_cast<float>(side_x), static_cast<float>(widget_y), static_cast<float>(side_w), static_cast<float>(Scale(110, dpi)));
    NativeIconRenderer::DrawGlassPanel(g, newsRect, static_cast<float>(Scale(16, dpi)), (hovered_widget_id_ == 5) ? Color(200, 36, 48, 78) : Color(160, 24, 34, 58), Color(80, 56, 189, 248), 1.0f);
    g.DrawString(L"System News & Uptime  ›", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(10, dpi))), &textMutedBr);
    
    wchar_t uptimeText[128]{};
    swprintf_s(uptimeText, L"CloudOS Native Kernel v2.0\nUptime Ativo: %s\nWin32 C++ Hardware High-Perf", current_stats_.uptime_str.c_str());
    g.DrawString(uptimeText, -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(32, dpi))), &textSecBr);
    g.DrawString(L"● Sistema 100% Operacional", -1, &microFont, PointF(static_cast<float>(side_x + Scale(14, dpi)), static_cast<float>(widget_y + Scale(86, dpi))), &cyanBr);

    // =========================================================================
    // 3. AETHER OS Bottom Taskbar & Centered Dock
    // =========================================================================
    const int bar_h = Scale(kBottomBarHeight, dpi);
    const int bar_y_pos = height - bar_h;

    RectF bottomBar(0.0f, static_cast<float>(bar_y_pos), static_cast<float>(width), static_cast<float>(bar_h));
    NativeIconRenderer::DrawGlassPanel(g, bottomBar, 0.0f, Color(240, 8, 12, 20), Color(100, 45, 90, 140), 1.0f);

    // Left Logo "⯌ AETHER OS"
    g.DrawString(L"⯌  AETHER  OS", -1, &subFont, PointF(static_cast<float>(Scale(24, dpi)), static_cast<float>(bar_y_pos + Scale(12, dpi))), &cyanBr);

    // Center Dock Glass Pill
    const int dock_w = Scale(180, dpi);
    const int dock_h = Scale(36, dpi);
    const int dock_x = (width - dock_w) / 2;
    const int dock_y = bar_y_pos + (bar_h - dock_h) / 2;
    RectF dockRect(static_cast<float>(dock_x), static_cast<float>(dock_y), static_cast<float>(dock_w), static_cast<float>(dock_h));
    NativeIconRenderer::DrawGlassPanel(g, dockRect, static_cast<float>(Scale(12, dpi)), Color(180, 24, 34, 58), Color(120, 56, 189, 248), 1.0f);

    dock_rects_.clear();
    int d_icon_x = dock_x + Scale(12, dpi);
    for (int d = 1; d <= 4; ++d)
    {
        RECT d_r{d_icon_x, dock_y, d_icon_x + Scale(32, dpi), dock_y + dock_h};
        dock_rects_.push_back(d_r);
        NativeIconRenderer::DrawAetherSquircle(g, d, d_icon_x, dock_y + Scale(4, dpi), Scale(28, dpi));
        d_icon_x += Scale(38, dpi);
    }

    // Right: Date & Clock "🖥 11:42 AM | OCT 26, 2045"
    SYSTEMTIME st{};
    GetLocalTime(&st);
    wchar_t timeBuf[64]{};
    swprintf_s(timeBuf, L"🖥  %02u:%02u %s  |  OCT 26, 2045", st.wHour > 12 ? st.wHour - 12 : st.wHour, st.wMinute, st.wHour >= 12 ? L"PM" : L"AM");
    StringFormat rightSf;
    rightSf.SetAlignment(StringAlignmentFar);
    g.DrawString(timeBuf, -1, &subFont, PointF(static_cast<float>(width - Scale(24, dpi)), static_cast<float>(bar_y_pos + Scale(12, dpi))), &rightSf, &textSecBr);

    BitBlt(screen_dc, 0, 0, width, height, device, 0, 0, SRCCOPY);
    SelectObject(device, old_bmp);
    DeleteObject(mem_bitmap);
    DeleteDC(device);
    EndPaint(hwnd_, &paint);
}

LRESULT CloudOSNativeDesktopWindow::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORSTATIC:
    {
        if (reinterpret_cast<HWND>(l_param) == search_edit_)
        {
            HDC edit_dc = reinterpret_cast<HDC>(w_param);
            SetTextColor(edit_dc, RGB(255, 255, 255));
            SetBkColor(edit_dc, RGB(24, 34, 58));
            return reinterpret_cast<LRESULT>(edit_bg_brush_);
        }
        break;
    }
    case WM_COMMAND:
        if (LOWORD(w_param) == 501 && HIWORD(w_param) == EN_CHANGE)
        {
            OnSearchChanged();
            return 0;
        }
        break;
    case WM_TIMER:
        if (w_param == kMetricsTimer)
        {
            current_stats_ = NativeSystemStats::Query();
            Redraw();
            return 0;
        }
        if (on_timer_) on_timer_();
        return 0;
    case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
        if (window_manager_ != nullptr)
        {
            window_manager_->HandleRuntimeEvent(
                static_cast<cloudos_native_window_event_kind>(w_param),
                reinterpret_cast<HWND>(l_param));
        }
        Redraw();
        return 0;
    case WM_HOTKEY:
        if (on_hotkey_) on_hotkey_(static_cast<int>(w_param));
        return 0;
    case WM_MOUSEMOVE:
    {
        const POINT pt{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        if (!tracking_mouse_)
        {
            TRACKMOUSEEVENT tme{sizeof(tme), TME_LEAVE, hwnd_, 0};
            TrackMouseEvent(&tme);
            tracking_mouse_ = true;
        }

        int prev_app = hovered_app_index_;
        int prev_widget = hovered_widget_id_;
        int prev_dock = hovered_dock_id_;

        hovered_app_index_ = -1;
        hovered_widget_id_ = -1;
        hovered_dock_id_ = -1;

        for (std::size_t i = 0; i < app_grid_rects_.size(); ++i)
        {
            if (Contains(app_grid_rects_[i], pt))
            {
                hovered_app_index_ = static_cast<int>(i);
                break;
            }
        }

        if (Contains(profile_rect_, pt)) hovered_widget_id_ = 1;
        else if (Contains(weather_rect_, pt)) hovered_widget_id_ = 2;
        else if (Contains(calendar_rect_, pt)) hovered_widget_id_ = 3;
        else if (Contains(perf_rect_, pt)) hovered_widget_id_ = 4;
        else if (Contains(news_rect_, pt)) hovered_widget_id_ = 5;

        for (std::size_t d = 0; d < dock_rects_.size(); ++d)
        {
            if (Contains(dock_rects_[d], pt))
            {
                hovered_dock_id_ = static_cast<int>(d + 1);
                break;
            }
        }

        if (prev_app != hovered_app_index_ || prev_widget != hovered_widget_id_ || prev_dock != hovered_dock_id_)
        {
            Redraw();
        }
        return 0;
    }
    case WM_MOUSELEAVE:
        tracking_mouse_ = false;
        hovered_app_index_ = -1;
        hovered_widget_id_ = -1;
        hovered_dock_id_ = -1;
        Redraw();
        return 0;
    case WM_LBUTTONUP:
    {
        const POINT pt{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};

        // 1. Click App Grid
        for (std::size_t i = 0; i < app_grid_rects_.size(); ++i)
        {
            if (Contains(app_grid_rects_[i], pt))
            {
                if (i < filtered_indices_.size())
                {
                    int app_idx = filtered_indices_[i];
                    NativeAppLauncher::Launch(instance_, hwnd_, kAllApps[static_cast<std::size_t>(app_idx)]);
                    return 0;
                }
            }
        }

        // 2. Click Widgets
        if (Contains(profile_rect_, pt))
        {
            POINT screen_pt = pt;
            ClientToScreen(hwnd_, &screen_pt);
            NativeAppLauncher::ShowQuickPowerMenu(hwnd_, screen_pt);
            return 0;
        }
        if (Contains(perf_rect_, pt))
        {
            NativeAppLauncher::LaunchById(instance_, hwnd_, L"sysmon");
            return 0;
        }
        if (Contains(calendar_rect_, pt))
        {
            ShellExecuteW(nullptr, L"open", L"control.exe", L"timedate.cpl", nullptr, SW_SHOWNORMAL);
            return 0;
        }
        if (Contains(weather_rect_, pt))
        {
            ShellExecuteW(nullptr, L"open", L"https://weather.com", nullptr, nullptr, SW_SHOWNORMAL);
            return 0;
        }

        // 3. Click Dock
        for (std::size_t d = 0; d < dock_rects_.size(); ++d)
        {
            if (Contains(dock_rects_[d], pt))
            {
                if (d == 0) NativeAppLauncher::LaunchById(instance_, hwnd_, L"browser");
                else if (d == 1) NativeAppLauncher::LaunchById(instance_, hwnd_, L"projects");
                else if (d == 2) NativeAppLauncher::LaunchById(instance_, hwnd_, L"terminal");
                else if (d == 3) NativeAppLauncher::LaunchById(instance_, hwnd_, L"powershell");
                return 0;
            }
        }

        SetWindowPos(hwnd_, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        return 0;
    }
    case WM_RBUTTONUP:
    {
        POINT pt{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        ClientToScreen(hwnd_, &pt);
        NativeAppLauncher::ShowQuickPowerMenu(hwnd_, pt);
        return 0;
    }
    case WM_DESTROY:
        hwnd_ = nullptr;
        return 0;
    default: break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::SearchSubclass(HWND window, UINT message, WPARAM w_param, LPARAM l_param, UINT_PTR uIdSubclass, DWORD_PTR dwRefData)
{
    (void)uIdSubclass;
    auto* self = reinterpret_cast<CloudOSNativeDesktopWindow*>(dwRefData);
    if (self != nullptr)
    {
        if (message == WM_KEYDOWN)
        {
            if (w_param == VK_RETURN)
            {
                self->SelectFocusedApp();
                return 0;
            }
            if (w_param == VK_LEFT || w_param == VK_RIGHT || w_param == VK_UP || w_param == VK_DOWN)
            {
                const int cols = 6;
                const int total = static_cast<int>(self->filtered_indices_.size());
                if (total > 0)
                {
                    if (w_param == VK_RIGHT) self->focused_app_index_ = (self->focused_app_index_ + 1) % total;
                    else if (w_param == VK_LEFT) self->focused_app_index_ = (self->focused_app_index_ - 1 + total) % total;
                    else if (w_param == VK_DOWN) self->focused_app_index_ = std::min(self->focused_app_index_ + cols, total - 1);
                    else if (w_param == VK_UP) self->focused_app_index_ = std::max(self->focused_app_index_ - cols, 0);
                    self->Redraw();
                }
                return 0;
            }
        }
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    CloudOSNativeDesktopWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* cs = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeDesktopWindow*>(cs->lpCreateParams);
        if (self != nullptr)
        {
            self->hwnd_ = window;
        }
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        return DefWindowProcW(window, message, w_param, l_param);
    }
    self = reinterpret_cast<CloudOSNativeDesktopWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    return self != nullptr ? self->HandleMessage(window, message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
}

} // namespace CloudOS
