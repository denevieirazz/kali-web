#include "native_snap_assist.h"

#include "native_theme.h"
#include "native_window_manager.h"

#include <gdiplus.h>

#include <algorithm>
#include <array>
#include <string_view>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kOverlayClass[] = L"CloudOS.NativeShell.SnapAssistOverlay.v1";
constexpr wchar_t kLayoutClass[] = L"CloudOS.NativeShell.SnapLayoutFlyout.v8";
constexpr int kLayoutWidthDip = 568;
constexpr int kLayoutHeightDip = 88;
constexpr int kLayoutTopGapDip = 8;
constexpr int kLayoutZoneCount = 8;

int ScaleDip(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

bool StartsWith(std::wstring_view value, std::wstring_view prefix) noexcept
{
    return value.size() >= prefix.size() && value.substr(0, prefix.size()) == prefix;
}

RECT WorkAreaFor(HWND window)
{
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        return info.rcWork;
    }

    RECT fallback{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
    return fallback;
}
}

NativeSnapAssist* NativeSnapAssist::active_instance_ = nullptr;

NativeSnapAssist::~NativeSnapAssist()
{
    Stop();
}

bool NativeSnapAssist::Start(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    Stop();
    if (instance == nullptr || window_manager == nullptr)
    {
        return false;
    }

    instance_ = instance;
    window_manager_ = window_manager;
    active_instance_ = this;

    move_hook_ = SetWinEventHook(
        EVENT_SYSTEM_MOVESIZESTART,
        EVENT_SYSTEM_MOVESIZEEND,
        nullptr,
        &NativeSnapAssist::WinEventCallback,
        0,
        0,
        WINEVENT_OUTOFCONTEXT);
    location_hook_ = SetWinEventHook(
        EVENT_OBJECT_LOCATIONCHANGE,
        EVENT_OBJECT_LOCATIONCHANGE,
        nullptr,
        &NativeSnapAssist::WinEventCallback,
        0,
        0,
        WINEVENT_OUTOFCONTEXT);

    if (move_hook_ == nullptr || location_hook_ == nullptr)
    {
        Stop();
        return false;
    }
    return true;
}

void NativeSnapAssist::Stop() noexcept
{
    if (move_hook_ != nullptr)
    {
        UnhookWinEvent(move_hook_);
        move_hook_ = nullptr;
    }
    if (location_hook_ != nullptr)
    {
        UnhookWinEvent(location_hook_);
        location_hook_ = nullptr;
    }

    HideOverlay();
    HideLayoutFlyout();
    if (overlay_ != nullptr && IsWindow(overlay_))
    {
        DestroyWindow(overlay_);
    }
    if (layout_flyout_ != nullptr && IsWindow(layout_flyout_))
    {
        DestroyWindow(layout_flyout_);
    }

    overlay_ = nullptr;
    layout_flyout_ = nullptr;
    moving_window_ = nullptr;
    active_zone_ = Zone::None;
    layout_zone_ = Zone::None;
    if (active_instance_ == this)
    {
        active_instance_ = nullptr;
    }
    window_manager_ = nullptr;
    instance_ = nullptr;
}

void CALLBACK NativeSnapAssist::WinEventCallback(
    HWINEVENTHOOK,
    DWORD event,
    HWND window,
    LONG object_id,
    LONG,
    DWORD,
    DWORD)
{
    NativeSnapAssist* self = active_instance_;
    if (self == nullptr || window == nullptr)
    {
        return;
    }

    if (event == EVENT_OBJECT_LOCATIONCHANGE && object_id != OBJID_WINDOW)
    {
        return;
    }

    if (event == EVENT_SYSTEM_MOVESIZESTART)
    {
        self->BeginMove(window);
    }
    else if (event == EVENT_SYSTEM_MOVESIZEEND)
    {
        self->EndMove(window);
    }
    else if (event == EVENT_OBJECT_LOCATIONCHANGE && window == self->moving_window_)
    {
        self->UpdateMove(window);
    }
}

bool NativeSnapAssist::EnsureOverlay()
{
    if (overlay_ != nullptr && IsWindow(overlay_))
    {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeSnapAssist::OverlayProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kOverlayClass;
    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    overlay_ = CreateWindowExW(
        WS_EX_LAYERED |
            WS_EX_TRANSPARENT |
            WS_EX_TOOLWINDOW |
            WS_EX_TOPMOST |
            WS_EX_NOACTIVATE,
        kOverlayClass,
        L"",
        WS_POPUP,
        0,
        0,
        1,
        1,
        nullptr,
        nullptr,
        instance_,
        this);
    if (overlay_ == nullptr)
    {
        return false;
    }
    SetLayeredWindowAttributes(overlay_, 0, 190, LWA_ALPHA);
    return true;
}

bool NativeSnapAssist::EnsureLayoutFlyout()
{
    if (layout_flyout_ != nullptr && IsWindow(layout_flyout_))
    {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeSnapAssist::LayoutProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kLayoutClass;
    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    layout_flyout_ = CreateWindowExW(
        WS_EX_LAYERED |
            WS_EX_TRANSPARENT |
            WS_EX_TOOLWINDOW |
            WS_EX_TOPMOST |
            WS_EX_NOACTIVATE,
        kLayoutClass,
        L"CloudOS Snap Layout",
        WS_POPUP,
        0,
        0,
        1,
        1,
        nullptr,
        nullptr,
        instance_,
        this);
    if (layout_flyout_ == nullptr)
    {
        return false;
    }

    SetLayeredWindowAttributes(layout_flyout_, 0, 246, LWA_ALPHA);
    return true;
}

bool NativeSnapAssist::IsCandidate(HWND window)
{
    if (window == nullptr || !IsWindow(window) || !IsWindowVisible(window) ||
        GetAncestor(window, GA_ROOT) != window)
    {
        return false;
    }

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if ((style & WS_DISABLED) != 0 ||
        (style & WS_CAPTION) == 0 ||
        (ex_style & WS_EX_TOOLWINDOW) != 0)
    {
        return false;
    }

    std::array<wchar_t, 256> class_name{};
    const int length = GetClassNameW(
        window,
        class_name.data(),
        static_cast<int>(class_name.size()));
    if (length <= 0)
    {
        return false;
    }

    const std::wstring_view name(class_name.data(), static_cast<std::size_t>(length));
    if (name == L"Progman" || name == L"WorkerW" ||
        name == L"Shell_TrayWnd" || name == L"Shell_SecondaryTrayWnd" ||
        StartsWith(name, L"CloudOS.NativeShell.Taskbar") ||
        StartsWith(name, L"CloudOS.NativeShell.Start") ||
        StartsWith(name, L"CloudOS.NativeShell.TaskPreview") ||
        StartsWith(name, L"CloudOS.NativeShell.SnapAssist") ||
        StartsWith(name, L"CloudOS.NativeShell.SnapLayout"))
    {
        return false;
    }
    return true;
}

void NativeSnapAssist::BeginMove(HWND window)
{
    if (!IsCandidate(window))
    {
        return;
    }
    moving_window_ = window;
    active_zone_ = Zone::None;
    layout_zone_ = Zone::None;
    if (window_manager_ != nullptr)
    {
        window_manager_->SetWindowFloating(window, true);
    }
    UpdateMove(window);
}

void NativeSnapAssist::UpdateMove(HWND window)
{
    if (window != moving_window_ || !IsCandidate(window))
    {
        return;
    }

    POINT cursor{};
    if (!GetCursorPos(&cursor))
    {
        HideOverlay();
        HideLayoutFlyout();
        active_zone_ = Zone::None;
        return;
    }

    RECT target{};
    bool show_layout = false;
    const Zone zone = ResolveZone(window, cursor, &target, &show_layout);
    if (zone == Zone::None)
    {
        HideOverlay();
        HideLayoutFlyout();
        active_zone_ = Zone::None;
        return;
    }

    active_zone_ = zone;
    active_target_ = target;
    ShowOverlay(target);
    if (show_layout)
    {
        ShowLayoutFlyout(WorkAreaFor(window), zone);
    }
    else
    {
        HideLayoutFlyout();
    }
}

void NativeSnapAssist::EndMove(HWND window)
{
    if (window != moving_window_)
    {
        return;
    }

    const Zone zone = active_zone_;
    const RECT target = active_target_;
    HideOverlay();
    HideLayoutFlyout();
    moving_window_ = nullptr;
    active_zone_ = Zone::None;

    if (zone != Zone::None)
    {
        (void)ApplyZone(window, zone, target);
    }
}

NativeSnapAssist::Zone NativeSnapAssist::ResolveZone(
    HWND window,
    POINT cursor,
    RECT* target,
    bool* show_layout) const
{
    if (target == nullptr || show_layout == nullptr)
    {
        return Zone::None;
    }
    *show_layout = false;

    const RECT work = WorkAreaFor(window);
    const int width = Width(work);
    const int height = Height(work);
    if (width < 240 || height < 180)
    {
        return Zone::None;
    }

    const UINT dpi = GetDpiForWindow(window);
    const int threshold = ScaleDip(30, dpi);
    const bool left = cursor.x <= work.left + threshold;
    const bool right = cursor.x >= work.right - threshold;
    const bool top = cursor.y <= work.top + threshold;
    const bool bottom = cursor.y >= work.bottom - threshold;

    if (!left && !right && !top && !bottom)
    {
        return Zone::None;
    }

    RECT result = work;
    const int half_width = width / 2;
    const int half_height = height / 2;
    const int third_width = width / 3;

    if (top && left)
    {
        result.right = work.left + half_width;
        result.bottom = work.top + half_height;
        *target = result;
        return Zone::TopLeftQuarter;
    }
    if (top && right)
    {
        result.left = work.left + half_width;
        result.bottom = work.top + half_height;
        *target = result;
        return Zone::TopRightQuarter;
    }
    if (bottom && left)
    {
        result.right = work.left + half_width;
        result.top = work.top + half_height;
        *target = result;
        return Zone::BottomLeftQuarter;
    }
    if (bottom && right)
    {
        result.left = work.left + half_width;
        result.top = work.top + half_height;
        *target = result;
        return Zone::BottomRightQuarter;
    }

    if (top)
    {
        const int maximum_layout_width = std::max(1, width - ScaleDip(24, dpi));
        const int layout_width = std::min(ScaleDip(kLayoutWidthDip, dpi), maximum_layout_width);
        const int layout_left = static_cast<int>(work.left) + (width - layout_width) / 2;
        const int layout_right = layout_left + layout_width;
        const int cursor_x = static_cast<int>(cursor.x);

        if (layout_width >= ScaleDip(320, dpi) &&
            cursor_x >= layout_left && cursor_x < layout_right)
        {
            *show_layout = true;
            const int relative = std::clamp(cursor_x - layout_left, 0, layout_width - 1);
            const int segment = std::clamp(
                (relative * kLayoutZoneCount) / std::max(1, layout_width),
                0,
                kLayoutZoneCount - 1);

            switch (segment)
            {
            case 0:
                result.right = work.left + half_width;
                *target = result;
                return Zone::LeftHalf;
            case 1:
                result.right = work.left + third_width;
                *target = result;
                return Zone::LeftThird;
            case 2:
                result.right = work.left + (width * 2) / 3;
                *target = result;
                return Zone::LeftTwoThirds;
            case 3:
                result.left = work.left + third_width;
                result.right = work.right - third_width;
                *target = result;
                return Zone::CenterThird;
            case 4:
                *target = work;
                return Zone::Maximize;
            case 5:
                result.left = work.right - (width * 2) / 3;
                *target = result;
                return Zone::RightTwoThirds;
            case 6:
                result.left = work.right - third_width;
                *target = result;
                return Zone::RightThird;
            default:
                result.left = work.left + half_width;
                *target = result;
                return Zone::RightHalf;
            }
        }

        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            const int relative_x = static_cast<int>(cursor.x - work.left);
            if (relative_x < third_width)
            {
                result.right = work.left + third_width;
                *target = result;
                return Zone::LeftThird;
            }
            if (relative_x >= width - third_width)
            {
                result.left = work.right - third_width;
                *target = result;
                return Zone::RightThird;
            }
            result.left = work.left + third_width;
            result.right = work.right - third_width;
            *target = result;
            return Zone::CenterThird;
        }
        *target = work;
        return Zone::Maximize;
    }

    if (left)
    {
        if ((GetKeyState(VK_SHIFT) & 0x8000) != 0)
        {
            result.right = work.left + (width * 2) / 3;
            *target = result;
            return Zone::LeftTwoThirds;
        }
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            result.right = work.left + third_width;
            *target = result;
            return Zone::LeftThird;
        }
        result.right = work.left + half_width;
        *target = result;
        return Zone::LeftHalf;
    }

    if (right)
    {
        if ((GetKeyState(VK_SHIFT) & 0x8000) != 0)
        {
            result.left = work.right - (width * 2) / 3;
            *target = result;
            return Zone::RightTwoThirds;
        }
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            result.left = work.right - third_width;
            *target = result;
            return Zone::RightThird;
        }
        result.left = work.left + half_width;
        *target = result;
        return Zone::RightHalf;
    }

    return Zone::None;
}

bool NativeSnapAssist::ApplyZone(
    HWND window,
    Zone zone,
    const RECT& target)
{
    if (!IsWindow(window))
    {
        return false;
    }

    if (zone == Zone::Maximize)
    {
        ShowWindow(window, SW_MAXIMIZE);
        if (window_manager_ != nullptr)
        {
            window_manager_->SetWindowFloating(window, true);
        }
        return true;
    }

    if (IsZoomed(window))
    {
        ShowWindow(window, SW_RESTORE);
    }

    SetLastError(ERROR_SUCCESS);
    const BOOL moved = SetWindowPos(
        window,
        HWND_TOP,
        target.left,
        target.top,
        Width(target),
        Height(target),
        SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
    if (moved)
    {
        if (window_manager_ != nullptr)
        {
            window_manager_->SetWindowFloating(window, true);
            window_manager_->Reconcile();
            window_manager_->FocusWindow(window);
        }
    }
    return moved != FALSE;
}

void NativeSnapAssist::ShowOverlay(const RECT& target)
{
    if (!EnsureOverlay())
    {
        return;
    }

    SetWindowPos(
        overlay_,
        HWND_TOPMOST,
        target.left,
        target.top,
        std::max(1, Width(target)),
        std::max(1, Height(target)),
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(overlay_, nullptr, TRUE);
}

void NativeSnapAssist::HideOverlay() noexcept
{
    if (overlay_ != nullptr && IsWindow(overlay_))
    {
        ShowWindow(overlay_, SW_HIDE);
    }
}

void NativeSnapAssist::ShowLayoutFlyout(const RECT& work, Zone selected)
{
    if (!EnsureLayoutFlyout())
    {
        return;
    }

    layout_work_ = work;
    layout_zone_ = selected;
    const UINT dpi = moving_window_ != nullptr && IsWindow(moving_window_)
        ? GetDpiForWindow(moving_window_)
        : 96;
    const int maximum_width = std::max(1, Width(work) - ScaleDip(24, dpi));
    const int width = std::min(ScaleDip(kLayoutWidthDip, dpi), maximum_width);
    const int height = ScaleDip(kLayoutHeightDip, dpi);
    const int x = static_cast<int>(work.left) + (Width(work) - width) / 2;
    const int y = static_cast<int>(work.top) + ScaleDip(kLayoutTopGapDip, dpi);

    HRGN region = CreateRoundRectRgn(
        0,
        0,
        width + 1,
        height + 1,
        ScaleDip(18, dpi) * 2,
        ScaleDip(18, dpi) * 2);
    if (region != nullptr && SetWindowRgn(layout_flyout_, region, FALSE) == 0)
    {
        DeleteObject(region);
    }

    SetWindowPos(
        layout_flyout_,
        HWND_TOPMOST,
        x,
        y,
        width,
        height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(layout_flyout_, nullptr, FALSE);
}

void NativeSnapAssist::HideLayoutFlyout() noexcept
{
    layout_zone_ = Zone::None;
    if (layout_flyout_ != nullptr && IsWindow(layout_flyout_))
    {
        ShowWindow(layout_flyout_, SW_HIDE);
    }
}

LRESULT CALLBACK NativeSnapAssist::OverlayProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);

        HBRUSH fill = CreateSolidBrush(RGB(42, 105, 184));
        HBRUSH border = CreateSolidBrush(RGB(126, 191, 255));
        if (fill != nullptr)
        {
            FillRect(dc, &client, fill);
            DeleteObject(fill);
        }
        if (border != nullptr)
        {
            FrameRect(dc, &client, border);
            RECT inner = client;
            InflateRect(&inner, -1, -1);
            FrameRect(dc, &inner, border);
            DeleteObject(border);
        }
        EndPaint(window, &paint);
        return 0;
    }
    default:
        return DefWindowProcW(window, message, w_param, l_param);
    }
}

LRESULT CALLBACK NativeSnapAssist::LayoutProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeSnapAssist*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<NativeSnapAssist*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }

    switch (message)
    {
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC screen_dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        const int width = std::max(1, Width(client));
        const int height = std::max(1, Height(client));
        const UINT dpi = GetDpiForWindow(window);

        HDC memory_dc = CreateCompatibleDC(screen_dc);
        HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
        HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
        WebSkin::PaintWindowBackground(memory_dc, client);

        Graphics graphics(memory_dc);
        graphics.SetSmoothingMode(SmoothingModeAntiAlias);
        graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

        const REAL outer_margin = static_cast<REAL>(ScaleDip(2, dpi));
        const RectF outer(
            outer_margin,
            outer_margin,
            static_cast<REAL>(width) - outer_margin * 2.0f,
            static_cast<REAL>(height) - outer_margin * 2.0f);
        WebSkin::DrawElevatedPanel(
            graphics,
            outer,
            static_cast<REAL>(ScaleDip(16, dpi)),
            WebSkin::GdiColor(WebSkin::BgSecondary, 248),
            WebSkin::GdiColor(WebSkin::BorderStrong, 235),
            true);

        Font title_font(
            L"Segoe UI Variable Text",
            static_cast<REAL>(ScaleDip(10, dpi)),
            FontStyleBold,
            UnitPixel);
        SolidBrush title_brush(WebSkin::GdiColor(WebSkin::TextPrimary));
        graphics.DrawString(
            L"Snap layout",
            -1,
            &title_font,
            PointF(
                static_cast<REAL>(ScaleDip(16, dpi)),
                static_cast<REAL>(ScaleDip(9, dpi))),
            &title_brush);

        constexpr std::array<Zone, kLayoutZoneCount> zones{
            Zone::LeftHalf,
            Zone::LeftThird,
            Zone::LeftTwoThirds,
            Zone::CenterThird,
            Zone::Maximize,
            Zone::RightTwoThirds,
            Zone::RightThird,
            Zone::RightHalf,
        };

        const int margin = ScaleDip(14, dpi);
        const int gap = ScaleDip(6, dpi);
        const int top = ScaleDip(30, dpi);
        const int bottom = height - ScaleDip(10, dpi);
        const int available = std::max(8, width - margin * 2 - gap * (kLayoutZoneCount - 1));
        const int button_width = std::max(1, available / kLayoutZoneCount);

        for (int index = 0; index < kLayoutZoneCount; ++index)
        {
            const Zone zone = zones[static_cast<std::size_t>(index)];
            const bool selected = self != nullptr && self->layout_zone_ == zone;
            const int left = margin + index * (button_width + gap);
            const int right = index == kLayoutZoneCount - 1
                ? width - margin
                : left + button_width;
            const RectF button_rect(
                static_cast<REAL>(left),
                static_cast<REAL>(top),
                static_cast<REAL>(std::max(1, right - left)),
                static_cast<REAL>(std::max(1, bottom - top)));
            WebSkin::DrawRoundedPanel(
                graphics,
                button_rect,
                static_cast<REAL>(ScaleDip(9, dpi)),
                WebSkin::GdiColor(
                    selected ? WebSkin::AccentSubtle : WebSkin::BgTertiary,
                    248),
                WebSkin::GdiColor(
                    selected ? WebSkin::AccentHover : WebSkin::BorderDefault,
                    255),
                selected ? 1.6f : 1.0f);

            RectF preview = button_rect;
            const REAL inset = static_cast<REAL>(ScaleDip(8, dpi));
            preview.X += inset;
            preview.Y += inset;
            preview.Width = std::max<REAL>(2.0f, preview.Width - inset * 2.0f);
            preview.Height = std::max<REAL>(2.0f, preview.Height - inset * 2.0f);
            WebSkin::DrawRoundedPanel(
                graphics,
                preview,
                static_cast<REAL>(ScaleDip(4, dpi)),
                WebSkin::GdiColor(WebSkin::BgSolid, 255),
                WebSkin::GdiColor(WebSkin::BorderStrong, 255),
                1.0f);

            RectF fill = preview;
            switch (zone)
            {
            case Zone::LeftHalf:
                fill.Width *= 0.50f;
                break;
            case Zone::RightHalf:
                fill.X += fill.Width * 0.50f;
                fill.Width *= 0.50f;
                break;
            case Zone::LeftThird:
                fill.Width *= 0.333f;
                break;
            case Zone::CenterThird:
                fill.X += fill.Width * 0.333f;
                fill.Width *= 0.334f;
                break;
            case Zone::RightThird:
                fill.X += fill.Width * 0.667f;
                fill.Width *= 0.333f;
                break;
            case Zone::LeftTwoThirds:
                fill.Width *= 0.667f;
                break;
            case Zone::RightTwoThirds:
                fill.X += fill.Width * 0.333f;
                fill.Width *= 0.667f;
                break;
            case Zone::Maximize:
                break;
            default:
                fill.Width = 0.0f;
                break;
            }

            if (fill.Width > 0.0f)
            {
                SolidBrush zone_brush(WebSkin::GdiColor(
                    selected ? WebSkin::AccentHover : WebSkin::Accent,
                    selected ? 245 : 190));
                graphics.FillRectangle(&zone_brush, fill);
            }
        }

        BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
        SelectObject(memory_dc, old_bitmap);
        DeleteObject(bitmap);
        DeleteDC(memory_dc);
        EndPaint(window, &paint);
        return 0;
    }
    default:
        return DefWindowProcW(window, message, w_param, l_param);
    }
}
} // namespace CloudOS
