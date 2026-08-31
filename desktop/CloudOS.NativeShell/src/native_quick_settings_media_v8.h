#pragma once

#include <windows.h>
#include <commctrl.h>
#include <objidl.h>

#include <gdiplus.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>
#include <future>
#include <memory>
#include "native_render_cache_v12.h"

#include "native_flyout_motion_v8.h"
#include "native_media_control_v7.h"
#include "native_theme.h"

namespace CloudOS::QuickSettingsMediaV8
{
constexpr wchar_t PanelClass[] = L"CloudOS.NativeShell.QuickMedia.v8";
constexpr wchar_t QuickSettingsClass[] = L"CloudOS.NativeShell.QuickSettings.v4";
constexpr UINT_PTR RefreshTimerId = 0xC118;
constexpr UINT_PTR ParentSubclassId = 0xC118A11;
constexpr int ExistingPreviousId = 8813;
constexpr int ExistingToggleId = 8814;
constexpr int ExistingNextId = 8815;

inline HWND panel{};
inline HWND parent_window{};
inline NativeMediaSnapshot snapshot{};
inline bool dragging_timeline{};
inline HWINEVENTHOOK show_hook{};
inline std::shared_ptr<Gdiplus::Bitmap> artwork_v12;
inline std::future<std::shared_ptr<Gdiplus::Bitmap>> artwork_future_v12;
inline std::vector<std::uint8_t> artwork_key_v12;

inline int ScaleDip(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

inline int RectWidth(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.right - rect.left));
}

inline int RectHeight(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.bottom - rect.top));
}

inline std::wstring FormatTime(std::int64_t milliseconds)
{
    const std::int64_t total = std::max<std::int64_t>(0, milliseconds) / 1000;
    const std::int64_t hours = total / 3600;
    const std::int64_t minutes = (total / 60) % 60;
    const std::int64_t seconds = total % 60;
    wchar_t buffer[32]{};
    if (hours > 0)
        swprintf_s(buffer, L"%lld:%02lld:%02lld", hours, minutes, seconds);
    else
        swprintf_s(buffer, L"%lld:%02lld", minutes, seconds);
    return buffer;
}

struct PanelRects final
{
    RECT artwork{};
    RECT previous{};
    RECT toggle{};
    RECT next{};
    RECT timeline{};
};

inline PanelRects Rects(HWND window)
{
    RECT client{};
    GetClientRect(window, &client);
    const UINT dpi = GetDpiForWindow(window);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));
    const int margin = ScaleDip(8, dpi);
    const int artwork_size = std::max(1, height - margin * 2);
    const int button = ScaleDip(28, dpi);
    const int gap = ScaleDip(5, dpi);

    PanelRects rects{};
    rects.artwork = RECT{margin, margin, margin + artwork_size, margin + artwork_size};
    rects.next = RECT{width - margin - button, margin, width - margin, margin + button};
    rects.toggle = RECT{rects.next.left - gap - button, margin, rects.next.left - gap, margin + button};
    rects.previous = RECT{rects.toggle.left - gap - button, margin, rects.toggle.left - gap, margin + button};
    rects.timeline = RECT{
        rects.artwork.right + ScaleDip(10, dpi),
        height - ScaleDip(27, dpi),
        width - margin,
        height - ScaleDip(17, dpi)};
    return rects;
}

inline bool ContainsRect(const RECT& rect, POINT point) noexcept
{
    return point.x >= rect.left && point.x < rect.right && point.y >= rect.top && point.y < rect.bottom;
}

inline std::shared_ptr<Gdiplus::Bitmap> DecodeArtworkV12(const std::vector<std::uint8_t>& bytes)
{
    if(bytes.empty()) return {};
    HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,bytes.size()); if(!memory) return {};
    void* target=GlobalLock(memory); if(!target) {GlobalFree(memory); return {};}
    std::memcpy(target,bytes.data(),bytes.size()); GlobalUnlock(memory);
    IStream* stream{};
    if(CreateStreamOnHGlobal(memory,TRUE,&stream)!=S_OK) {GlobalFree(memory);return {};}
    std::shared_ptr<Gdiplus::Bitmap> result;
    { Gdiplus::Bitmap decoded(stream,FALSE);
      if(decoded.GetLastStatus()==Gdiplus::Ok) result.reset(decoded.Clone(0,0,static_cast<INT>(decoded.GetWidth()),static_cast<INT>(decoded.GetHeight()),PixelFormat32bppPARGB)); }
    stream->Release();return result;
}
inline bool DrawArtworkBytes(Gdiplus::Graphics& graphics,const RECT& destination)
{
    if(!artwork_v12) return false;
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    return graphics.DrawImage(artwork_v12.get(),destination.left,destination.top,RectWidth(destination),RectHeight(destination))==Gdiplus::Ok;
}

inline void RefreshSnapshot()
{
    if(!panel || !IsWindowVisible(panel)) return;
    snapshot = NativeMediaControlV7::Snapshot();
    if(artwork_future_v12.valid() && artwork_future_v12.wait_for(std::chrono::seconds(0))==std::future_status::ready)
        artwork_v12=artwork_future_v12.get();
    if(!artwork_future_v12.valid() && artwork_key_v12!=snapshot.artwork)
    { artwork_key_v12=snapshot.artwork; auto bytes=artwork_key_v12; artwork_future_v12=std::async(std::launch::async,[bytes=std::move(bytes)]{return DecodeArtworkV12(bytes);}); }
    if (panel != nullptr && IsWindow(panel))
        InvalidateRect(panel, nullptr, FALSE);
}

inline void SeekFromPoint(POINT point, bool commit)
{
    if (panel == nullptr || snapshot.duration_ms <= 0) return;
    const PanelRects rects = Rects(panel);
    const int width = std::max<int>(1, RectWidth(rects.timeline));
    const double ratio = std::clamp(
        static_cast<double>(static_cast<int>(point.x - rects.timeline.left)) / static_cast<double>(width),
        0.0,
        1.0);
    snapshot.position_ms = static_cast<std::int64_t>(ratio * static_cast<double>(snapshot.duration_ms));
    InvalidateRect(panel, nullptr, FALSE);
    if (commit && snapshot.can_seek)
        NativeMediaControlV7::SeekAsync(snapshot.position_ms);
}

inline void DrawControl(
    Gdiplus::Graphics& graphics,
    const RECT& rect,
    const wchar_t* glyph,
    bool accent,
    bool enabled)
{
    WebSkin::DrawRoundedPanel(
        graphics,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(rect.left),
            static_cast<Gdiplus::REAL>(rect.top),
            static_cast<Gdiplus::REAL>(RectWidth(rect)),
            static_cast<Gdiplus::REAL>(RectHeight(rect))),
        8.0f,
        WebSkin::GdiColor(accent ? WebSkin::Accent : WebSkin::BgTertiary, enabled ? 245 : 150),
        WebSkin::GdiColor(accent ? WebSkin::AccentHover : WebSkin::BorderStrong, enabled ? 255 : 120),
        1.0f);
    Gdiplus::Font font(L"Segoe UI Symbol", 13.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush brush(WebSkin::GdiColor(enabled ? WebSkin::TextPrimary : WebSkin::TextDisabled));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    graphics.DrawString(
        glyph,
        -1,
        &font,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(rect.left),
            static_cast<Gdiplus::REAL>(rect.top),
            static_cast<Gdiplus::REAL>(RectWidth(rect)),
            static_cast<Gdiplus::REAL>(RectHeight(rect))),
        &format,
        &brush);
}

inline void PaintPanel(HWND window)
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    RECT client{};
    GetClientRect(window, &client);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));

    PerformanceV12::PaintScope telemetry(PerformanceV12::QuickPaint);
    HDC memory_dc=NativeBackbufferV12::Acquire(window,dc,width,height);
    if(!memory_dc) { EndPaint(window,&paint); return; }

    Gdiplus::Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    Gdiplus::SolidBrush background(WebSkin::GdiColor(WebSkin::BgSecondary, 255));
    graphics.FillRectangle(&background, 0, 0, width, height);

    const PanelRects rects = Rects(window);
    if (!DrawArtworkBytes(graphics, rects.artwork))
    {
        WebSkin::DrawRoundedPanel(
            graphics,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(rects.artwork.left),
                static_cast<Gdiplus::REAL>(rects.artwork.top),
                static_cast<Gdiplus::REAL>(RectWidth(rects.artwork)),
                static_cast<Gdiplus::REAL>(RectHeight(rects.artwork))),
            12.0f,
            WebSkin::GdiColor(WebSkin::AccentSubtle, 255),
            WebSkin::GdiColor(WebSkin::BorderStrong, 255),
            1.0f);
        Gdiplus::Font icon_font(L"Segoe UI Symbol", 25.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
        Gdiplus::SolidBrush icon_brush(WebSkin::GdiColor(WebSkin::AccentHover));
        Gdiplus::StringFormat center;
        center.SetAlignment(Gdiplus::StringAlignmentCenter);
        center.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        graphics.DrawString(
            L"♫",
            -1,
            &icon_font,
            Gdiplus::RectF(
                static_cast<Gdiplus::REAL>(rects.artwork.left),
                static_cast<Gdiplus::REAL>(rects.artwork.top),
                static_cast<Gdiplus::REAL>(RectWidth(rects.artwork)),
                static_cast<Gdiplus::REAL>(RectHeight(rects.artwork))),
            &center,
            &icon_brush);
    }

    const int text_left = static_cast<int>(rects.artwork.right) + 10;
    const int text_right = std::max<int>(text_left + 1, static_cast<int>(rects.previous.left) - 8);
    Gdiplus::Font title_font(L"Segoe UI Variable Text", 12.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::Font meta_font(L"Segoe UI Variable Text", 9.5f, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush title_brush(WebSkin::GdiColor(WebSkin::TextPrimary));
    Gdiplus::SolidBrush meta_brush(WebSkin::GdiColor(WebSkin::TextSecondary));
    Gdiplus::StringFormat ellipsis;
    ellipsis.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    ellipsis.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    const std::wstring title = snapshot.available
        ? (snapshot.title.empty() ? std::wstring(L"Reproducao ativa") : snapshot.title)
        : std::wstring(L"Nenhuma midia ativa");
    std::wstring meta;
    if (snapshot.available)
    {
        if (!snapshot.artist.empty()) meta = snapshot.artist;
        if (!snapshot.album.empty()) meta += (meta.empty() ? L"" : L"  ·  ") + snapshot.album;
        if (meta.empty()) meta = L"Reproducao do Windows";
    }
    else
    {
        meta = L"Spotify, navegadores e players via GSMTC";
    }

    graphics.DrawString(
        title.c_str(),
        -1,
        &title_font,
        Gdiplus::RectF(static_cast<Gdiplus::REAL>(text_left), 8.0f,
            static_cast<Gdiplus::REAL>(text_right - text_left), 19.0f),
        &ellipsis,
        &title_brush);
    graphics.DrawString(
        meta.c_str(),
        -1,
        &meta_font,
        Gdiplus::RectF(static_cast<Gdiplus::REAL>(text_left), 30.0f,
            static_cast<Gdiplus::REAL>(std::max(1, width - text_left - 8)), 18.0f),
        &ellipsis,
        &meta_brush);

    DrawControl(graphics, rects.previous, L"‹", false, snapshot.can_previous);
    DrawControl(graphics, rects.toggle, snapshot.playing ? L"Ⅱ" : L"▶", true, snapshot.can_toggle);
    DrawControl(graphics, rects.next, L"›", false, snapshot.can_next);

    const int timeline_width = std::max<int>(1, RectWidth(rects.timeline));
    const double ratio = snapshot.duration_ms > 0
        ? std::clamp(static_cast<double>(snapshot.position_ms) / static_cast<double>(snapshot.duration_ms), 0.0, 1.0)
        : 0.0;
    const int progress = static_cast<int>(ratio * static_cast<double>(timeline_width));
    const int track_height = std::max<int>(2, RectHeight(rects.timeline) - 4);
    Gdiplus::SolidBrush track(WebSkin::GdiColor(WebSkin::BgActive, 255));
    Gdiplus::SolidBrush fill(WebSkin::GdiColor(WebSkin::AccentHover, 255));
    graphics.FillRectangle(
        &track,
        static_cast<INT>(rects.timeline.left),
        static_cast<INT>(rects.timeline.top + 2),
        timeline_width,
        track_height);
    if (progress > 0)
    {
        graphics.FillRectangle(
            &fill,
            static_cast<INT>(rects.timeline.left),
            static_cast<INT>(rects.timeline.top + 2),
            progress,
            track_height);
    }

    const std::wstring time = FormatTime(snapshot.position_ms) + L" / " + FormatTime(snapshot.duration_ms);
    graphics.DrawString(
        time.c_str(),
        -1,
        &meta_font,
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(rects.timeline.left), static_cast<Gdiplus::REAL>(height - 16)),
        &meta_brush);

    BitBlt(dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);

    EndPaint(window, &paint);
}

inline LRESULT CALLBACK PanelProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_PAINT:
        PaintPanel(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_TIMER:
        if (w_param == RefreshTimerId)
        {
            RefreshSnapshot();
            return 0;
        }
        break;
    case WM_LBUTTONDOWN:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const PanelRects rects = Rects(window);
        if (ContainsRect(rects.timeline, point) && snapshot.duration_ms > 0)
        {
            dragging_timeline = true;
            SetCapture(window);
            SeekFromPoint(point, false);
            return 0;
        }
        break;
    }
    case WM_MOUSEMOVE:
        if (dragging_timeline && GetCapture() == window)
        {
            SeekFromPoint(POINT{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)}, false);
            return 0;
        }
        break;
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const PanelRects rects = Rects(window);
        if (dragging_timeline)
        {
            dragging_timeline = false;
            if (GetCapture() == window) ReleaseCapture();
            SeekFromPoint(point, true);
            return 0;
        }
        if (ContainsRect(rects.previous, point) && snapshot.can_previous)
            NativeMediaControlV7::PreviousAsync();
        else if (ContainsRect(rects.toggle, point) && snapshot.can_toggle)
            NativeMediaControlV7::TogglePlayPauseAsync();
        else if (ContainsRect(rects.next, point) && snapshot.can_next)
            NativeMediaControlV7::NextAsync();
        else
            return 0;
        RefreshSnapshot();
        return 0;
    }
    case WM_CAPTURECHANGED:
        dragging_timeline = false;
        return 0;
    case WM_DESTROY:
        KillTimer(window, RefreshTimerId);
        if (panel == window) panel = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

inline void Layout(HWND parent)
{
    if (panel == nullptr || !IsWindow(panel) || parent == nullptr || !IsWindow(parent)) return;
    RECT client{};
    GetClientRect(parent, &client);
    const UINT dpi = GetDpiForWindow(parent);
    const int margin = ScaleDip(22, dpi);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left) - margin * 2);
    const int scroll=static_cast<int>(reinterpret_cast<INT_PTR>(GetPropW(parent,L"CloudOS.QuickScroll.V12")));
    MoveWindow(panel,margin,ScaleDip(872,dpi)-scroll,width,ScaleDip(140,dpi),TRUE);
    SetWindowPos(panel, HWND_TOP, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

inline LRESULT CALLBACK ParentSubclass(
    HWND parent,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR)
{
    switch (message)
    {
    case WM_SIZE:
    case WM_DPICHANGED:
        Layout(parent);
        break;
    case WM_SHOWWINDOW:
        if (w_param != FALSE)
        {
            Layout(parent);
            RefreshSnapshot();

        }
        else if (panel != nullptr)
        {
            KillTimer(panel, RefreshTimerId);
        }
        break;
    case WM_NCDESTROY:
        if (panel != nullptr && IsWindow(panel)) DestroyWindow(panel);
        panel = nullptr;
        parent_window = nullptr;
        RemoveWindowSubclass(parent, ParentSubclass, subclass_id);
        break;
    default:
        break;
    }
    return DefSubclassProc(parent, message, w_param, l_param);
}

inline bool EnsurePanelClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &PanelProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_HAND);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = PanelClass;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

inline void Attach(HWND parent)
{
    if (parent == nullptr || !IsWindow(parent)) return;
    if (parent_window == parent && panel != nullptr && IsWindow(panel))
    {
        Layout(parent);
        RefreshSnapshot();
        return;
    }

    HINSTANCE instance = reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(parent, GWLP_HINSTANCE));
    if (!EnsurePanelClass(instance)) return;

    parent_window = parent;
    panel = CreateWindowExW(
        0,
        PanelClass,
        L"CloudOS Media V8",
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        0, 0, 1, 1,
        parent,
        nullptr,
        instance,
        nullptr);
    if (panel == nullptr) return;

    (void)SetWindowSubclass(parent, ParentSubclass, ParentSubclassId, 0);
    Layout(parent);
    RefreshSnapshot();

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
    if (event != EVENT_OBJECT_SHOW || object_id != OBJID_WINDOW || child_id != CHILDID_SELF ||
        window == nullptr || !IsWindow(window))
        return;

    wchar_t class_name[128]{};
    const int length = GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
    if (length <= 0) return;
    if (std::wstring_view(class_name, static_cast<std::size_t>(length)) == QuickSettingsClass)
        Attach(window);
}

class Bootstrap final
{
public:
    Bootstrap() noexcept
    {
        show_hook = SetWinEventHook(
            EVENT_OBJECT_SHOW,
            EVENT_OBJECT_SHOW,
            nullptr,
            &WinEventCallback,
            GetCurrentProcessId(),
            0,
            WINEVENT_OUTOFCONTEXT);
    }
    ~Bootstrap()
    {
        if (show_hook != nullptr) UnhookWinEvent(show_hook);
        show_hook = nullptr;
    }
    Bootstrap(const Bootstrap&) = delete;
    Bootstrap& operator=(const Bootstrap&) = delete;
};

// V12: the advanced view attaches explicitly; no global show hook.
} // namespace CloudOS::QuickSettingsMediaV8
