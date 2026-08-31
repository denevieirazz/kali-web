#include "native_render_cache_v12.h"
#include "native_icon_cache_v12.h"
#include "native_desktop_window.h"

#include "native_app_launcher.h"
#include "native_desktop_context_menu.h"
#include "native_desktop_drop_target.h"
#include "native_icon_renderer.h"
#include "native_media_control_v7.h"
#include "native_monitor_manager.h"
#include "native_shell_platform.h"
#include "native_wallpaper_manager.h"

#include <shellapi.h>
#include <shlobj.h>

#include "../../CloudOS.NativeCommon/native_supervisor_protocol_v11.h"

#include <algorithm>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
std::vector<RECT> g_file_rects;
std::vector<std::wstring> g_file_paths;
std::vector<std::wstring> g_file_names;
std::vector<std::size_t> g_selected_files;
bool g_is_box_selecting = false;
POINT g_box_start{};
POINT g_box_current{};
RECT g_media_previous_rect{};
RECT g_media_toggle_rect{};
RECT g_media_next_rect{};

int FindApp(std::wstring_view id)
{
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
        if (id == kAllApps[index].id) return static_cast<int>(index);
    return -1;
}

std::vector<int> DesktopApps()
{
    std::vector<int> result;
    for (std::wstring_view id : {L"files", L"projects", L"terminal", L"drive", L"control", L"settings"})
    {
        const int index = FindApp(id);
        if (index >= 0) result.push_back(index);
    }
    return result;
}

void DrawCenteredText(Graphics& graphics, const std::wstring& text, const Font& font, const RectF& rectangle, const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentCenter);
    format.SetLineAlignment(StringAlignmentNear);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    format.SetFormatFlags(StringFormatFlagsLineLimit);
    graphics.DrawString(text.c_str(), -1, &font, rectangle, &format, &brush);
}

RECT SelectionDirtyV12()
{
    RECT dirty{std::min(g_box_start.x,g_box_current.x),std::min(g_box_start.y,g_box_current.y),std::max(g_box_start.x,g_box_current.x)+1,std::max(g_box_start.y,g_box_current.y)+1};
    for(auto index:g_selected_files) if(index<g_file_rects.size()) UnionRect(&dirty,&dirty,&g_file_rects[index]);
    InflateRect(&dirty,3,3);return dirty;
}
void InvalidateSelectionV12(HWND window,const RECT& previous)
{
    auto next=SelectionDirtyV12();UnionRect(&next,&next,&previous);InvalidateRect(window,&next,FALSE);
}

RECT g_primary_bounds_v12{};
RECT QueryPrimaryBoundsInClient(HWND window)
{
    RECT bounds{};
    RECT window_bounds{};
    GetWindowRect(window, &window_bounds);
    const auto monitors = NativeMonitorManager::Enumerate();
    for (const auto& monitor : monitors)
    {
        if (!monitor.primary) continue;
        bounds.left = monitor.monitor.left - window_bounds.left;
        bounds.top = monitor.monitor.top - window_bounds.top;
        bounds.right = monitor.monitor.right - window_bounds.left;
        bounds.bottom = monitor.monitor.bottom - window_bounds.top;
        return bounds;
    }
    GetClientRect(window, &bounds);
    return bounds;
}

std::wstring LocalTimeText()
{
    SYSTEMTIME now{};
    GetLocalTime(&now);
    wchar_t buffer[64]{};
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            TIME_NOSECONDS,
            &now,
            nullptr,
            buffer,
            static_cast<int>(std::size(buffer))) == 0)
        return L"--:--";
    return buffer;
}

std::wstring LocalDateText()
{
    SYSTEMTIME now{};
    GetLocalTime(&now);
    wchar_t buffer[96]{};
    if (GetDateFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            DATE_LONGDATE,
            &now,
            nullptr,
            buffer,
            static_cast<int>(std::size(buffer)),
            nullptr) == 0)
        return {};
    return buffer;
}

void DrawRing(
    Graphics& graphics,
    const RectF& bounds,
    int percent,
    Color accent,
    const std::wstring& label,
    const Font& value_font,
    const Font& label_font,
    const Brush& primary,
    const Brush& secondary)
{
    const REAL stroke = std::max<REAL>(5.0f, bounds.Width * 0.075f);
    Pen track(Color(72, 120, 132, 158), stroke);
    Pen progress(accent, stroke);
    track.SetStartCap(LineCapRound);
    track.SetEndCap(LineCapRound);
    progress.SetStartCap(LineCapRound);
    progress.SetEndCap(LineCapRound);
    RectF arc = bounds;
    arc.Inflate(-stroke, -stroke);
    graphics.DrawArc(&track, arc, -90.0f, 360.0f);
    graphics.DrawArc(
        &progress,
        arc,
        -90.0f,
        360.0f * static_cast<REAL>(std::clamp(percent, 0, 100)) / 100.0f);

    StringFormat centered;
    centered.SetAlignment(StringAlignmentCenter);
    centered.SetLineAlignment(StringAlignmentCenter);
    const std::wstring value = std::to_wstring(std::clamp(percent, 0, 100)) + L"%";
    graphics.DrawString(value.c_str(), -1, &value_font, bounds, &centered, &primary);
    graphics.DrawString(
        label.c_str(),
        -1,
        &label_font,
        RectF(bounds.X, bounds.GetBottom() + 3.0f, bounds.Width, 18.0f),
        &centered,
        &secondary);
}

void DrawDesktopWidgets(
    Graphics& graphics,
    UINT dpi,
    const RECT& monitor,
    const SystemStats& stats,
    const NativeMediaSnapshot& media)
{
    const int margin = Scale(24, dpi);
    const int card_width = Scale(330, dpi);
    const int x = monitor.right - margin - card_width;
    int y = monitor.top + Scale(24, dpi);

    Font clock_font(L"Segoe UI Variable Display", static_cast<REAL>(Scale(38, dpi)), FontStyleBold, UnitPixel);
    Font heading_font(L"Segoe UI Variable Display", static_cast<REAL>(Scale(13, dpi)), FontStyleBold, UnitPixel);
    Font text_font(L"Segoe UI Variable Text", static_cast<REAL>(Scale(11, dpi)), FontStyleRegular, UnitPixel);
    Font small_font(L"Segoe UI Variable Text", static_cast<REAL>(Scale(9, dpi)), FontStyleRegular, UnitPixel);
    Font ring_font(L"Segoe UI Variable Display", static_cast<REAL>(Scale(15, dpi)), FontStyleBold, UnitPixel);
    SolidBrush primary(WebSkin::GdiColor(WebSkin::TextPrimary));
    SolidBrush secondary(WebSkin::GdiColor(WebSkin::TextSecondary));
    SolidBrush tertiary(WebSkin::GdiColor(WebSkin::TextTertiary));

    // Clock / calendar card.
    RectF clock_card(
        static_cast<REAL>(x), static_cast<REAL>(y),
        static_cast<REAL>(card_width), static_cast<REAL>(Scale(132, dpi)));
    WebSkin::DrawElevatedPanel(
        graphics, clock_card, static_cast<REAL>(Scale(WebSkin::RadiusXL, dpi)),
        WebSkin::GdiColor(WebSkin::BgSecondary, 226),
        WebSkin::GdiColor(WebSkin::BorderStrong, 160), true);
    graphics.DrawString(LocalTimeText().c_str(), -1, &clock_font,
        PointF(clock_card.X + Scale(20, dpi), clock_card.Y + Scale(15, dpi)), &primary);
    graphics.DrawString(LocalDateText().c_str(), -1, &text_font,
        RectF(clock_card.X + Scale(22, dpi), clock_card.Y + Scale(82, dpi),
            clock_card.Width - Scale(44, dpi), static_cast<REAL>(Scale(28, dpi))),
        nullptr, &secondary);
    y += Scale(148, dpi);

    // CPU / RAM activity-rings card.
    RectF performance_card(
        static_cast<REAL>(x), static_cast<REAL>(y),
        static_cast<REAL>(card_width), static_cast<REAL>(Scale(184, dpi)));
    WebSkin::DrawElevatedPanel(
        graphics, performance_card, static_cast<REAL>(Scale(WebSkin::RadiusXL, dpi)),
        WebSkin::GdiColor(WebSkin::BgSecondary, 226),
        WebSkin::GdiColor(WebSkin::BorderStrong, 150));
    graphics.DrawString(L"Desempenho", -1, &heading_font,
        PointF(performance_card.X + Scale(20, dpi), performance_card.Y + Scale(16, dpi)), &primary);
    graphics.DrawString(stats.uptime_str.c_str(), -1, &small_font,
        RectF(performance_card.X + Scale(20, dpi), performance_card.Y + Scale(40, dpi),
            performance_card.Width - Scale(40, dpi), static_cast<REAL>(Scale(20, dpi))),
        nullptr, &tertiary);

    const REAL ring_size = static_cast<REAL>(Scale(82, dpi));
    const REAL ring_y = performance_card.Y + Scale(66, dpi);
    DrawRing(
        graphics,
        RectF(performance_card.X + Scale(44, dpi), ring_y, ring_size, ring_size),
        stats.cpu_available ? stats.cpu_percent : 0,
        WebSkin::GdiColor(WebSkin::AccentHover),
        L"CPU",
        ring_font, small_font, primary, secondary);
    DrawRing(
        graphics,
        RectF(performance_card.X + performance_card.Width - Scale(44, dpi) - ring_size,
            ring_y, ring_size, ring_size),
        stats.ram_available ? stats.ram_percent : 0,
        WebSkin::GdiColor(WebSkin::AccentCyan),
        L"RAM",
        ring_font, small_font, primary, secondary);
    y += Scale(200, dpi);

    // GSMTC media card. Even without album art the card is live and controls
    // Spotify/browser/player sessions without opening another application.
    RectF media_card(
        static_cast<REAL>(x), static_cast<REAL>(y),
        static_cast<REAL>(card_width), static_cast<REAL>(Scale(142, dpi)));
    WebSkin::DrawElevatedPanel(
        graphics, media_card, static_cast<REAL>(Scale(WebSkin::RadiusXL, dpi)),
        WebSkin::GdiColor(WebSkin::BgSecondary, 232),
        WebSkin::GdiColor(media.available ? WebSkin::AccentHover : WebSkin::BorderStrong, 155),
        media.available && media.playing);
    graphics.DrawString(L"Agora tocando", -1, &heading_font,
        PointF(media_card.X + Scale(20, dpi), media_card.Y + Scale(14, dpi)), &primary);

    const std::wstring media_title = media.available && !media.title.empty()
        ? media.title : std::wstring(L"Nenhuma sessao de midia ativa");
    const std::wstring media_subtitle = media.available
        ? (!media.artist.empty() ? media.artist : media.source_app_id)
        : std::wstring(L"Spotify, navegador e players via GSMTC");
    graphics.DrawString(media_title.c_str(), -1, &text_font,
        RectF(media_card.X + Scale(20, dpi), media_card.Y + Scale(42, dpi),
            media_card.Width - Scale(40, dpi), static_cast<REAL>(Scale(24, dpi))),
        nullptr, &primary);
    graphics.DrawString(media_subtitle.c_str(), -1, &small_font,
        RectF(media_card.X + Scale(20, dpi), media_card.Y + Scale(68, dpi),
            media_card.Width - Scale(40, dpi), static_cast<REAL>(Scale(18, dpi))),
        nullptr, &secondary);

    const int button_w = Scale(46, dpi);
    const int button_h = Scale(34, dpi);
    const int button_gap = Scale(10, dpi);
    const int controls_w = button_w * 3 + button_gap * 2;
    const int controls_x = x + (card_width - controls_w) / 2;
    const int controls_y = y + Scale(96, dpi);
    g_media_previous_rect = RECT{controls_x, controls_y, controls_x + button_w, controls_y + button_h};
    g_media_toggle_rect = RECT{controls_x + button_w + button_gap, controls_y,
        controls_x + button_w * 2 + button_gap, controls_y + button_h};
    g_media_next_rect = RECT{controls_x + (button_w + button_gap) * 2, controls_y,
        controls_x + (button_w + button_gap) * 2 + button_w, controls_y + button_h};

    auto draw_media_button = [&](const RECT& rect, const wchar_t* glyph, bool enabled, bool accent)
    {
        RectF panel(
            static_cast<REAL>(rect.left), static_cast<REAL>(rect.top),
            static_cast<REAL>(Width(rect)), static_cast<REAL>(Height(rect)));
        WebSkin::DrawRoundedPanel(
            graphics, panel, static_cast<REAL>(Scale(12, dpi)),
            WebSkin::GdiColor(
                accent ? WebSkin::Accent : WebSkin::BgTertiary,
                enabled ? static_cast<BYTE>(245) : static_cast<BYTE>(130)),
            WebSkin::GdiColor(accent ? WebSkin::AccentHover : WebSkin::BorderStrong, 180), 1.0f);
        StringFormat format;
        format.SetAlignment(StringAlignmentCenter);
        format.SetLineAlignment(StringAlignmentCenter);
        graphics.DrawString(glyph, -1, &text_font, panel, &format,
            enabled ? &primary : &tertiary);
    };
    draw_media_button(g_media_previous_rect, L"◀", media.available && media.can_previous, false);
    draw_media_button(g_media_toggle_rect, media.playing ? L"Ⅱ" : L"▶", media.available && media.can_toggle, true);
    draw_media_button(g_media_next_rect, L"▶", media.available && media.can_next, false);
}
}

CloudOSNativeDesktopWindow::~CloudOSNativeDesktopWindow() { Destroy(); }

bool CloudOSNativeDesktopWindow::Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager)
{
    instance_ = instance;
    window_manager_ = window_manager;
    quick_launch_app_indices_ = DesktopApps();


    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.lpfnWndProc = &CloudOSNativeDesktopWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kDesktopClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;

    hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW, kDesktopClass, L"CloudOS Desktop",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 0, 0,
        nullptr, nullptr, instance_, this);
    if (hwnd_ == nullptr) return false;

    desktop_model_.Start(hwnd_);
    NativeWallpaperManager::Prepare();
    DarkWindow(hwnd_, false);
    (void)NativeDesktopDropTarget::Register(hwnd_);
    return true;
}

void CloudOSNativeDesktopWindow::Destroy()
{
    desktop_model_.Stop();
    if(hwnd_) NativeWallpaperManager::Stop();
    if (hwnd_ != nullptr)
    {
        NativeDesktopDropTarget::Unregister(hwnd_);
        if (IsWindow(hwnd_)) DestroyWindow(hwnd_);
    }
    hwnd_ = nullptr;
    quick_launch_rects_.clear(); quick_launch_app_indices_.clear();
    g_file_rects.clear(); g_file_paths.clear();
    g_media_previous_rect = {};
    g_media_toggle_rect = {};
    g_media_next_rect = {};
}

void CloudOSNativeDesktopWindow::UpdateLayout(const RECT& work_area)
{
    if (hwnd_ == nullptr) return;
    SetWindowPos(hwnd_, HWND_BOTTOM, work_area.left, work_area.top,
        std::max(1, Width(work_area)), std::max(1, Height(work_area)), SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void CloudOSNativeDesktopWindow::Redraw() { if (hwnd_ != nullptr) InvalidateRect(hwnd_, nullptr, FALSE); }
void CloudOSNativeDesktopWindow::FocusSearch() { if (on_hotkey_) on_hotkey_(HotSearch); }
void CloudOSNativeDesktopWindow::RefreshWorkArea() { g_primary_bounds_v12 = QueryPrimaryBoundsInClient(hwnd_); NativeWallpaperManager::Prepare(); Redraw(); }

void CloudOSNativeDesktopWindow::ActivateAppIndex(int app_index)
{
    if (app_index < 0 || app_index >= static_cast<int>(kAllApps.size())) return;
    if (on_action_) on_action_(app_index + 1);
    else NativeAppLauncher::Launch(instance_, hwnd_, kAllApps[static_cast<std::size_t>(app_index)]);
}

void CloudOSNativeDesktopWindow::Paint()
{
    PerformanceV12::PaintScope perf(PerformanceV12::DesktopPaint);
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(hwnd_, &paint);
    RECT client{}; GetClientRect(hwnd_, &client);
    const int width = Width(client); const int height = Height(client);
    if (width <= 0 || height <= 0) { EndPaint(hwnd_, &paint); return; }

    HDC memory_dc = NativeBackbufferV12::Acquire(hwnd_, screen_dc, width, height);
    if (!memory_dc) { EndPaint(hwnd_, &paint); return; }
    const int saved_dc = SaveDC(memory_dc);
    IntersectClipRect(memory_dc, paint.rcPaint.left, paint.rcPaint.top, paint.rcPaint.right, paint.rcPaint.bottom);
    if (EqualRect(&client, &paint.rcPaint)) PerformanceV12::Add(PerformanceV12::DesktopFullPaint);
    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(hwnd_);

    if (!NativeWallpaperManager::Draw(graphics, width, height))
    {
        LinearGradientBrush background(
            PointF(0.0f, 0.0f), PointF(static_cast<REAL>(width), static_cast<REAL>(height)),
            WebSkin::GdiColor(WebSkin::BgPrimary), WebSkin::GdiColor(WebSkin::BgPrimary));
        graphics.FillRectangle(&background, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));


    }

    SolidBrush overlay(Color(18, 0, 0, 0));
    graphics.FillRectangle(&overlay, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    Font small_font(L"Segoe UI Variable Text", static_cast<REAL>(Scale(12, dpi)), FontStyleRegular, UnitPixel);
    SolidBrush white(WebSkin::GdiColor(WebSkin::TextPrimary));
    const RECT primary_bounds = g_primary_bounds_v12;
    const POINT primary{primary_bounds.left, primary_bounds.top};

    quick_launch_rects_.clear();
    const int shortcut_width = Scale(96, dpi);
    const int shortcut_height = Scale(92, dpi);
    const int icon_size = Scale(46, dpi);
    const int left = primary.x + Scale(20, dpi);
    int y = primary.y + Scale(24, dpi);

    for (std::size_t index = 0; index < quick_launch_app_indices_.size(); ++index)
    {
        const int app_index = quick_launch_app_indices_[index];
        RECT hit{left, y, left + shortcut_width, y + shortcut_height};
        quick_launch_rects_.push_back(hit);
        NativeIconRenderer::DrawAetherSquircle(graphics, kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            left + (shortcut_width - icon_size) / 2, y + Scale(3, dpi), icon_size);
        DrawCenteredText(graphics, kAllApps[static_cast<std::size_t>(app_index)].name, small_font,
            RectF(static_cast<REAL>(left), static_cast<REAL>(y + Scale(56, dpi)),
                static_cast<REAL>(shortcut_width), static_cast<REAL>(Scale(30, dpi))), white);
        y += shortcut_height + Scale(6, dpi);
    }

    g_file_rects.clear();
    const int file_start_x = left + shortcut_width + Scale(26, dpi);
    const int file_start_y = primary.y + Scale(24, dpi);
    const int file_columns = 5;
    const int file_cell_width = Scale(116, dpi);
    const int file_cell_height = Scale(100, dpi);

    for (std::size_t index = 0; index < g_file_paths.size(); ++index)
    {
        const int column = static_cast<int>(index % static_cast<std::size_t>(file_columns));
        const int row = static_cast<int>(index / static_cast<std::size_t>(file_columns));
        const int x = file_start_x + column * file_cell_width;
        const int file_y = file_start_y + row * file_cell_height;
        RECT hit{x, file_y, x + file_cell_width, file_y + file_cell_height};
        g_file_rects.push_back(hit);

        const bool is_selected = std::find(g_selected_files.begin(), g_selected_files.end(), index) != g_selected_files.end();
        if (is_selected)
        {
            SolidBrush sel_bg(Color(45, 99, 102, 241));
            graphics.FillRectangle(&sel_bg, RectF(static_cast<REAL>(x), static_cast<REAL>(file_y),
                static_cast<REAL>(file_cell_width), static_cast<REAL>(file_cell_height)));
            Pen sel_border(Color(180, 129, 140, 248), 1.0f);
            graphics.DrawRectangle(&sel_border, RectF(static_cast<REAL>(x), static_cast<REAL>(file_y),
                static_cast<REAL>(file_cell_width), static_cast<REAL>(file_cell_height)));
        }

        const auto icon = NativeIconCacheV12::Instance().Get(g_file_paths[index]);
        if (icon && icon->handle)
            DrawIconEx(memory_dc, x + (file_cell_width - Scale(42, dpi)) / 2, file_y + Scale(4, dpi), icon->handle, Scale(42, dpi), Scale(42, dpi), 0, nullptr, DI_NORMAL);
        DrawCenteredText(graphics, g_file_names[index], small_font,
            RectF(static_cast<REAL>(x + Scale(3, dpi)), static_cast<REAL>(file_y + Scale(54, dpi)),
                static_cast<REAL>(file_cell_width - Scale(6, dpi)), static_cast<REAL>(Scale(40, dpi))), white);
    }

    if (g_is_box_selecting)
    {
        const int box_left = std::min(g_box_start.x, g_box_current.x);
        const int box_top = std::min(g_box_start.y, g_box_current.y);
        const int box_right = std::max(g_box_start.x, g_box_current.x);
        const int box_bottom = std::max(g_box_start.y, g_box_current.y);
        const int box_w = box_right - box_left;
        const int box_h = box_bottom - box_top;
        if (box_w > 1 && box_h > 1)
        {
            SolidBrush box_fill(Color(35, 99, 102, 241));
            graphics.FillRectangle(&box_fill, RectF(static_cast<REAL>(box_left), static_cast<REAL>(box_top),
                static_cast<REAL>(box_w), static_cast<REAL>(box_h)));
            Pen box_pen(Color(180, 129, 140, 248), 1.0f);
            graphics.DrawRectangle(&box_pen, RectF(static_cast<REAL>(box_left), static_cast<REAL>(box_top),
                static_cast<REAL>(box_w), static_cast<REAL>(box_h)));
        }
    }

    if (widgets_enabled_)
        DrawDesktopWidgets(graphics, dpi, primary_bounds, current_stats_, NativeMediaControlV7::Snapshot());

    graphics.Flush();
    BitBlt(screen_dc, paint.rcPaint.left, paint.rcPaint.top, paint.rcPaint.right-paint.rcPaint.left, paint.rcPaint.bottom-paint.rcPaint.top, memory_dc, paint.rcPaint.left, paint.rcPaint.top, SRCCOPY);
    RestoreDC(memory_dc, saved_dc); EndPaint(hwnd_, &paint);
}

LRESULT CloudOSNativeDesktopWindow::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_CLOUDOS_DESKTOP_MODEL_V12:
    {
        std::vector<std::wstring> selected;
        for (auto index : g_selected_files) if (index < g_file_paths.size()) selected.push_back(g_file_paths[index]);
        g_file_paths.clear(); g_file_names.clear(); g_selected_files.clear();
        for (const auto& item : desktop_model_.Snapshot())
        {
            if (std::find(selected.begin(), selected.end(), item.path) != selected.end()) g_selected_files.push_back(g_file_paths.size());
            g_file_paths.push_back(item.path); g_file_names.push_back(item.name);
        }
        Redraw(); return 0;
    }
    case WM_CLOUDOS_ICON_READY_V12: for(const auto& rect:g_file_rects) InvalidateRect(hwnd_,&rect,FALSE); return 0;
    case WM_CLOUDOS_WIDGETS_V12:
        widgets_enabled_ = !widgets_enabled_;
        SetPropW(window, L"CloudOS.Widgets.V12", reinterpret_cast<HANDLE>(static_cast<INT_PTR>(widgets_enabled_)));
        if (widgets_enabled_) SetTimer(window, kMetricsTimer, 2000, nullptr); else KillTimer(window, kMetricsTimer);
        g_media_previous_rect = {}; g_media_toggle_rect = {}; g_media_next_rect = {};
        Redraw(); return 0;
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_TIMER:
        if (w_param == kMetricsTimer)
        {
            if (!widgets_enabled_ || !IsWindowVisible(window)) return 0;
            if (metrics_future_.valid() && metrics_future_.wait_for(std::chrono::seconds(0)) == std::future_status::ready)
            {
                current_stats_ = metrics_future_.get();
                RECT widget = g_primary_bounds_v12; widget.left = std::max(widget.left, widget.right - Scale(370, GetDpiForWindow(hwnd_)));
                InvalidateRect(hwnd_, &widget, FALSE);
            }
            if (!metrics_future_.valid()) metrics_future_ = std::async(std::launch::async, []{ return NativeSystemStats::Query(); });
            NativeMediaControlV7::RefreshAsync();
            return 0;
        }
        if (w_param == kReconcileTimer)
        {
            if (on_timer_) on_timer_();
            return 0;
        }
        break;
    case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
        if (window_manager_ != nullptr)
            window_manager_->HandleRuntimeEvent(static_cast<cloudos_native_window_event_kind>(w_param), reinterpret_cast<HWND>(l_param));
        return 0;
    case WM_HOTKEY:
        if (on_hotkey_) on_hotkey_(static_cast<int>(w_param));
        return 0;
    case WM_SIZE: g_primary_bounds_v12 = QueryPrimaryBoundsInClient(hwnd_); NativeWallpaperManager::Prepare(hwnd_,LOWORD(l_param),HIWORD(l_param)); return 0;
    case WM_APP+0x61D: Redraw(); return 0;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
    case WM_SETTINGCHANGE:
        RefreshWorkArea(); return 0;
    case WM_LBUTTONDOWN:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const NativeMediaSnapshot media = NativeMediaControlV7::Snapshot();
        if ((media.available && media.can_previous && Contains(g_media_previous_rect, point)) ||
            (media.available && media.can_toggle && Contains(g_media_toggle_rect, point)) ||
            (media.available && media.can_next && Contains(g_media_next_rect, point)))
        {
            break;
        }
        for (const auto& r : quick_launch_rects_)
        {
            if (Contains(r, point)) return 0;
        }
        const auto previous=SelectionDirtyV12();
        g_is_box_selecting = true;
        g_box_start = point;
        g_box_current = point;
        g_selected_files.clear();
        for (std::size_t i = 0; i < g_file_rects.size(); ++i)
        {
            if (Contains(g_file_rects[i], point))
            {
                g_selected_files.push_back(i);
                break;
            }
        }
        SetCapture(hwnd_);
        InvalidateSelectionV12(hwnd_,previous);
        return 0;
    }
    case WM_MOUSEMOVE:
    {
        if (g_is_box_selecting)
        {
            const auto previous=SelectionDirtyV12();
            g_box_current = POINT{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            const int bl = std::min(g_box_start.x, g_box_current.x);
            const int bt = std::min(g_box_start.y, g_box_current.y);
            const int br = std::max(g_box_start.x, g_box_current.x);
            const int bb = std::max(g_box_start.y, g_box_current.y);
            const RECT box_rc{bl, bt, br, bb};

            g_selected_files.clear();
            for (std::size_t i = 0; i < g_file_rects.size(); ++i)
            {
                RECT intersect{};
                if (IntersectRect(&intersect, &box_rc, &g_file_rects[i]))
                {
                    g_selected_files.push_back(i);
                }
            }
            InvalidateSelectionV12(hwnd_,previous);
            return 0;
        }
        break;
    }
    case WM_LBUTTONUP:
    {
        if (g_is_box_selecting)
        {
            const auto previous=SelectionDirtyV12();
            g_is_box_selecting = false;
            if (GetCapture() == hwnd_) ReleaseCapture();
            InvalidateSelectionV12(hwnd_,previous);
            return 0;
        }
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const NativeMediaSnapshot media = NativeMediaControlV7::Snapshot();
        if (media.available && media.can_previous && Contains(g_media_previous_rect, point))
        {
            NativeMediaControlV7::PreviousAsync();
            return 0;
        }
        if (media.available && media.can_toggle && Contains(g_media_toggle_rect, point))
        {
            NativeMediaControlV7::TogglePlayPauseAsync();
            return 0;
        }
        if (media.available && media.can_next && Contains(g_media_next_rect, point))
        {
            NativeMediaControlV7::NextAsync();
            return 0;
        }
        break;
    }
    case WM_LBUTTONDBLCLK:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        for (std::size_t index = 0; index < quick_launch_rects_.size() && index < quick_launch_app_indices_.size(); ++index)
            if (Contains(quick_launch_rects_[index], point)) { ActivateAppIndex(quick_launch_app_indices_[index]); return 0; }
        for (std::size_t index = 0; index < g_file_rects.size() && index < g_file_paths.size(); ++index)
            if (Contains(g_file_rects[index], point))
            { (void)ShellExecuteW(hwnd_, L"open", g_file_paths[index].c_str(), nullptr, nullptr, SW_SHOWNORMAL); return 0; }
        break;
    }
    case WM_RBUTTONUP:
    {
        POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        ClientToScreen(hwnd_, &point);
        if (NativeDesktopContextMenu::Show(instance_, hwnd_, point)) Redraw();
        return 0;
    }
    case WM_KEYDOWN:
        if (w_param == VK_F5) { desktop_model_.Refresh(); NativeWallpaperManager::Prepare(); Redraw(); return 0; }
        break;
    case SupervisorProtocolV11::RequestGracefulExitMessage:
        PostQuitMessage(0);
        return 0;
    case WM_DESTROY:
        NativeDesktopDropTarget::Unregister(hwnd_); hwnd_ = nullptr; return 0;
    default: break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeDesktopWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeDesktopWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->hwnd_ = window;
    }
    return self != nullptr ? self->HandleMessage(window, message, w_param, l_param)
                           : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
