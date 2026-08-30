#pragma once

#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <new>
#include <string>

#include "native_media_control_v7.h"
#include "native_theme.h"

namespace CloudOS
{
namespace QuickSettingsMediaV8
{
constexpr UINT_PTR kSubclassId = 0xC10D8808u;
constexpr wchar_t kQuickSettingsClass[] = L"CloudOS.NativeShell.QuickSettings.v4";

struct State final
{
    RECT timeline_rect{};
    bool timeline_visible{};
    bool timeline_hot{};
};

inline bool IsQuickSettings(HWND window) noexcept
{
    if (window == nullptr || !IsWindow(window)) return false;
    wchar_t class_name[128]{};
    if (GetClassNameW(window, class_name, static_cast<int>(std::size(class_name))) <= 0)
        return false;
    return _wcsicmp(class_name, kQuickSettingsClass) == 0;
}

inline std::wstring FormatTicks(std::int64_t ticks)
{
    constexpr std::int64_t ticks_per_second = 10'000'000;
    const std::int64_t total_seconds = std::max<std::int64_t>(0, ticks / ticks_per_second);
    const std::int64_t hours = total_seconds / 3600;
    const std::int64_t minutes = (total_seconds / 60) % 60;
    const std::int64_t seconds = total_seconds % 60;
    wchar_t buffer[32]{};
    if (hours > 0)
        swprintf_s(buffer, L"%lld:%02lld:%02lld", hours, minutes, seconds);
    else
        swprintf_s(buffer, L"%lld:%02lld", minutes, seconds);
    return buffer;
}

inline RECT TimelineRect(HWND window, UINT dpi) noexcept
{
    RECT client{};
    GetClientRect(window, &client);
    const int margin = Scale(22, dpi);
    const int label_space = Scale(102, dpi);
    const int top = Scale(178, dpi);
    return RECT{
        margin + label_space,
        top,
        std::max<LONG>(margin + label_space + 1, client.right - margin),
        top + Scale(11, dpi)};
}

inline void Draw(HWND window, State* state)
{
    if (window == nullptr || state == nullptr || !IsWindow(window)) return;
    const NativeMediaSnapshot media = NativeMediaControlV7::Snapshot();
    const UINT dpi = GetDpiForWindow(window);
    state->timeline_rect = TimelineRect(window, dpi);
    state->timeline_visible = media.available && media.timeline_available;
    if (!state->timeline_visible) return;

    const std::int64_t span = media.timeline_end_ticks - media.timeline_start_ticks;
    if (span <= 0) return;
    const std::int64_t offset = std::clamp(
        media.position_ticks - media.timeline_start_ticks,
        static_cast<std::int64_t>(0),
        span);
    const double progress = std::clamp(
        static_cast<double>(offset) / static_cast<double>(span),
        0.0,
        1.0);

    HDC dc = GetDC(window);
    if (dc == nullptr) return;
    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);

    RECT track = state->timeline_rect;
    const int track_height = std::max(2, Scale(state->timeline_hot ? 5 : 4, dpi));
    const int center_y = (track.top + track.bottom) / 2;
    track.top = center_y - track_height / 2;
    track.bottom = track.top + track_height;

    WebSkin::DrawRoundedPanel(
        graphics,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(track.left),
            static_cast<Gdiplus::REAL>(track.top),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, track.right - track.left)),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, track.bottom - track.top))),
        static_cast<Gdiplus::REAL>(Scale(4, dpi)),
        WebSkin::GdiColor(WebSkin::BgElevated, 245),
        WebSkin::GdiColor(state->timeline_hot ? WebSkin::BorderStrong : WebSkin::BorderDefault, 225),
        1.0f);

    const int track_width = std::max<LONG>(1, track.right - track.left);
    const int progress_width = std::clamp(
        static_cast<int>(static_cast<double>(track_width) * progress),
        0,
        track_width);
    if (progress_width > 0)
    {
        Gdiplus::RectF progress_rect(
            static_cast<Gdiplus::REAL>(track.left),
            static_cast<Gdiplus::REAL>(track.top),
            static_cast<Gdiplus::REAL>(progress_width),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, track.bottom - track.top)));
        Gdiplus::LinearGradientBrush gradient(
            Gdiplus::PointF(progress_rect.X, progress_rect.Y),
            Gdiplus::PointF(progress_rect.GetRight(), progress_rect.Y),
            WebSkin::GdiColor(WebSkin::Accent),
            WebSkin::GdiColor(WebSkin::AccentCyan));
        Gdiplus::GraphicsPath path;
        path.AddRectangle(progress_rect);
        graphics.FillPath(&gradient, &path);
    }

    const int thumb_x = track.left + progress_width;
    const int thumb_radius = Scale(state->timeline_hot ? 5 : 4, dpi);
    Gdiplus::SolidBrush thumb(WebSkin::GdiColor(WebSkin::TextPrimary));
    Gdiplus::SolidBrush glow(WebSkin::GdiColor(WebSkin::AccentCyan, state->timeline_hot ? 70 : 36));
    graphics.FillEllipse(
        &glow,
        static_cast<Gdiplus::REAL>(thumb_x - thumb_radius * 2),
        static_cast<Gdiplus::REAL>(center_y - thumb_radius * 2),
        static_cast<Gdiplus::REAL>(thumb_radius * 4),
        static_cast<Gdiplus::REAL>(thumb_radius * 4));
    graphics.FillEllipse(
        &thumb,
        static_cast<Gdiplus::REAL>(thumb_x - thumb_radius),
        static_cast<Gdiplus::REAL>(center_y - thumb_radius),
        static_cast<Gdiplus::REAL>(thumb_radius * 2),
        static_cast<Gdiplus::REAL>(thumb_radius * 2));

    const std::wstring position = FormatTicks(offset);
    const std::wstring duration = FormatTicks(span);
    const std::wstring time_text = position + L" / " + duration;
    Gdiplus::Font time_font(
        L"Segoe UI Variable Text",
        static_cast<Gdiplus::REAL>(Scale(8, dpi)),
        Gdiplus::FontStyleRegular,
        Gdiplus::UnitPixel);
    Gdiplus::SolidBrush time_brush(WebSkin::GdiColor(WebSkin::TextTertiary));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentNear);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    graphics.DrawString(
        time_text.c_str(),
        -1,
        &time_font,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(Scale(22, dpi)),
            static_cast<Gdiplus::REAL>(Scale(170, dpi)),
            static_cast<Gdiplus::REAL>(Scale(96, dpi)),
            static_cast<Gdiplus::REAL>(Scale(22, dpi))),
        &format,
        &time_brush);

    ReleaseDC(window, dc);
}

inline LRESULT CALLBACK SubclassProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference)
{
    auto* state = reinterpret_cast<State*>(reference);
    if (state == nullptr) return DefSubclassProc(window, message, w_param, l_param);

    if (message == WM_MOUSEMOVE)
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const bool hot = state->timeline_visible && PtInRect(&state->timeline_rect, point) != FALSE;
        if (hot != state->timeline_hot)
        {
            state->timeline_hot = hot;
            InvalidateRect(window, &state->timeline_rect, FALSE);
        }
    }
    else if (message == WM_LBUTTONUP && state->timeline_visible)
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        if (PtInRect(&state->timeline_rect, point) != FALSE)
        {
            const int width = std::max<LONG>(1, state->timeline_rect.right - state->timeline_rect.left);
            const int relative = std::clamp<int>(point.x - state->timeline_rect.left, 0, width);
            NativeMediaControlV7::SeekNormalizedAsync(
                static_cast<double>(relative) / static_cast<double>(width));
            return 0;
        }
    }

    const LRESULT result = DefSubclassProc(window, message, w_param, l_param);
    if (message == WM_PAINT)
    {
        Draw(window, state);
    }
    else if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, SubclassProcedure, subclass_id);
        delete state;
    }
    return result;
}

inline void Attach(HWND window) noexcept
{
    if (!IsQuickSettings(window)) return;
    DWORD_PTR existing = 0;
    if (GetWindowSubclass(window, SubclassProcedure, kSubclassId, &existing) != FALSE) return;
    State* state = new (std::nothrow) State{};
    if (state == nullptr) return;
    if (SetWindowSubclass(
            window,
            SubclassProcedure,
            kSubclassId,
            reinterpret_cast<DWORD_PTR>(state)) == FALSE)
    {
        delete state;
    }
}

inline void CALLBACK WinEventCallback(
    HWINEVENTHOOK,
    DWORD event,
    HWND window,
    LONG object_id,
    LONG child_id,
    DWORD,
    DWORD)
{
    if ((event == EVENT_OBJECT_CREATE || event == EVENT_OBJECT_SHOW) &&
        object_id == OBJID_WINDOW && child_id == CHILDID_SELF)
    {
        Attach(window);
    }
}

class Bootstrap final
{
public:
    Bootstrap() noexcept
    {
        hook_ = SetWinEventHook(
            EVENT_OBJECT_CREATE,
            EVENT_OBJECT_SHOW,
            nullptr,
            &WinEventCallback,
            GetCurrentProcessId(),
            0,
            WINEVENT_OUTOFCONTEXT);
    }
    ~Bootstrap()
    {
        if (hook_ != nullptr) UnhookWinEvent(hook_);
    }
    Bootstrap(const Bootstrap&) = delete;
    Bootstrap& operator=(const Bootstrap&) = delete;
private:
    HWINEVENTHOOK hook_{};
};

inline Bootstrap bootstrap;
} // namespace QuickSettingsMediaV8
} // namespace CloudOS
