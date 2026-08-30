#include "native_taskbar_hover_preview.h"

#include "native_taskbar_appbar.h"
#include "native_theme.h"
#include "native_window_manager.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <gdiplus.h>

#include <algorithm>
#include <new>
#include <string>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kPreviewClass[] = L"CloudOS.NativeShell.TaskPreview.v3";
constexpr UINT_PTR kSubclassId = 0xA901;
constexpr UINT_PTR kHoverTimer = 0xA902;
constexpr UINT_PTR kHideTimer = 0xA903;

HICON ResolveWindowIcon(HWND window)
{
    if (window == nullptr || !IsWindow(window))
    {
        return nullptr;
    }

    HICON icon = reinterpret_cast<HICON>(
        SendMessageW(window, WM_GETICON, ICON_SMALL2, 0));
    if (icon == nullptr)
    {
        icon = reinterpret_cast<HICON>(
            SendMessageW(window, WM_GETICON, ICON_SMALL, 0));
    }
    if (icon == nullptr)
    {
        icon = reinterpret_cast<HICON>(
            GetClassLongPtrW(window, GCLP_HICONSM));
    }
    if (icon == nullptr)
    {
        icon = reinterpret_cast<HICON>(
            GetClassLongPtrW(window, GCLP_HICON));
    }
    return icon;
}

int WrappedWorkspace(int current, int direction) noexcept
{
    constexpr int kWorkspaceCount = 4;
    if (current < 0 || current >= kWorkspaceCount)
    {
        current = 0;
    }
    return (current + direction + kWorkspaceCount) % kWorkspaceCount;
}
}

NativeTaskbarHoverPreview::NativeTaskbarHoverPreview(
    HINSTANCE instance,
    HWND taskbar,
    HMONITOR monitor,
    CloudOSNativeWindowManager* window_manager) noexcept
    : instance_(instance),
      taskbar_(taskbar),
      monitor_(monitor),
      window_manager_(window_manager)
{
}

NativeTaskbarHoverPreview::~NativeTaskbarHoverPreview()
{
    Detach();
}

bool NativeTaskbarHoverPreview::Attach(
    HINSTANCE instance,
    HWND taskbar,
    HMONITOR monitor,
    CloudOSNativeWindowManager* window_manager)
{
    if (instance == nullptr || taskbar == nullptr || !IsWindow(taskbar) || window_manager == nullptr)
    {
        return false;
    }

    auto* preview = new (std::nothrow) NativeTaskbarHoverPreview(
        instance,
        taskbar,
        monitor,
        window_manager);
    if (preview == nullptr)
    {
        return false;
    }
    if (!preview->Initialize())
    {
        delete preview;
        return false;
    }
    return true;
}

bool NativeTaskbarHoverPreview::Initialize()
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeTaskbarHoverPreview::PreviewProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_HAND);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kPreviewClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    preview_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
        kPreviewClass,
        L"",
        WS_POPUP,
        0,
        0,
        360,
        278,
        nullptr,
        nullptr,
        instance_,
        this);
    if (preview_ == nullptr)
    {
        return false;
    }
    ApplyWebFlyoutMaterial(preview_);

    if (!SetWindowSubclass(
            taskbar_,
            &NativeTaskbarHoverPreview::TaskbarSubclass,
            kSubclassId,
            reinterpret_cast<DWORD_PTR>(this)))
    {
        DestroyWindow(preview_);
        preview_ = nullptr;
        return false;
    }
    return true;
}

void NativeTaskbarHoverPreview::Detach() noexcept
{
    if (taskbar_ != nullptr && IsWindow(taskbar_))
    {
        KillTimer(taskbar_, kHoverTimer);
        KillTimer(taskbar_, kHideTimer);
        RemoveWindowSubclass(taskbar_, &NativeTaskbarHoverPreview::TaskbarSubclass, kSubclassId);
    }
    taskbar_ = nullptr;
    HidePreview();
    if (preview_ != nullptr && IsWindow(preview_))
    {
        DestroyWindow(preview_);
    }
    preview_ = nullptr;
    window_manager_ = nullptr;
}

HWND NativeTaskbarHoverPreview::HitTaskWindow(
    POINT client_point,
    RECT* task_rect) const
{
    if (taskbar_ == nullptr || !IsWindow(taskbar_))
    {
        return nullptr;
    }

    CloudOSTaskbarHitQuery query{};
    query.client_point = client_point;
    if (SendMessageW(
            taskbar_,
            CLOUDOS_WM_TASKBAR_QUERY_HIT,
            0,
            reinterpret_cast<LPARAM>(&query)) == FALSE ||
        query.window == nullptr)
    {
        return nullptr;
    }
    if (task_rect != nullptr)
    {
        *task_rect = query.task_rect;
    }
    return query.window;
}

void NativeTaskbarHoverPreview::UpdateHover(POINT client_point)
{
    RECT task_rect{};
    const HWND hit = HitTaskWindow(client_point, &task_rect);
    if (hit == pending_source_)
    {
        return;
    }

    pending_source_ = hit;
    pending_task_rect_ = task_rect;
    if (taskbar_ != nullptr)
    {
        KillTimer(taskbar_, kHoverTimer);
    }

    if (hit == nullptr)
    {
        if (!tracking_preview_)
        {
            HidePreview();
        }
        return;
    }

    if (taskbar_ != nullptr)
    {
        SetTimer(taskbar_, kHoverTimer, 360, nullptr);
    }
}

void NativeTaskbarHoverPreview::ShowPreview(
    HWND source,
    const RECT& task_rect)
{
    if (preview_ == nullptr || source == nullptr || !IsWindow(source))
    {
        return;
    }

    HidePreview();
    source_ = source;
    source_task_rect_ = task_rect;

    POINT top_left{task_rect.left, task_rect.top};
    POINT bottom_right{task_rect.right, task_rect.bottom};
    ClientToScreen(taskbar_, &top_left);
    ClientToScreen(taskbar_, &bottom_right);

    const UINT dpi = GetDpiForWindow(taskbar_);
    const int preview_width = Scale(372, dpi);
    const int preview_height = Scale(278, dpi);
    int x = top_left.x + (bottom_right.x - top_left.x - preview_width) / 2;
    int y = top_left.y - preview_height - Scale(10, dpi);

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const HMONITOR monitor = MonitorFromWindow(taskbar_, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        x = std::clamp<int>(
            x,
            info.rcWork.left,
            std::max<int>(info.rcWork.left, info.rcWork.right - preview_width));
        y = std::clamp<int>(
            y,
            info.rcWork.top,
            std::max<int>(info.rcWork.top, info.rcWork.bottom - preview_height));
    }

    SetWindowPos(
        preview_,
        HWND_TOPMOST,
        x,
        y,
        preview_width,
        preview_height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);

    if (SUCCEEDED(DwmRegisterThumbnail(preview_, source_, &thumbnail_)))
    {
        LayoutThumbnail();
    }
    InvalidateRect(preview_, nullptr, TRUE);
}

void NativeTaskbarHoverPreview::HidePreview() noexcept
{
    if (thumbnail_ != nullptr)
    {
        DwmUnregisterThumbnail(thumbnail_);
        thumbnail_ = nullptr;
    }
    if (preview_ != nullptr && IsWindow(preview_))
    {
        KillTimer(preview_, kHideTimer);
        ShowWindow(preview_, SW_HIDE);
    }
    source_ = nullptr;
}

void NativeTaskbarHoverPreview::LayoutThumbnail()
{
    if (thumbnail_ == nullptr || preview_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(preview_, &client);
    const UINT dpi = GetDpiForWindow(preview_);
    const int margin = Scale(12, dpi);
    const int title_height = Scale(52, dpi);
    RECT available{
        margin,
        title_height,
        client.right - margin,
        client.bottom - margin};

    SIZE source_size{};
    if (FAILED(DwmQueryThumbnailSourceSize(thumbnail_, &source_size)) ||
        source_size.cx <= 0 || source_size.cy <= 0)
    {
        return;
    }

    int destination_width = Width(available);
    int destination_height = MulDiv(destination_width, source_size.cy, source_size.cx);
    if (destination_height > Height(available))
    {
        destination_height = Height(available);
        destination_width = MulDiv(destination_height, source_size.cx, source_size.cy);
    }

    RECT destination{
        available.left + (Width(available) - destination_width) / 2,
        available.top + (Height(available) - destination_height) / 2,
        0,
        0};
    destination.right = destination.left + destination_width;
    destination.bottom = destination.top + destination_height;

    DWM_THUMBNAIL_PROPERTIES properties{};
    properties.dwFlags =
        DWM_TNP_RECTDESTINATION |
        DWM_TNP_VISIBLE |
        DWM_TNP_OPACITY |
        DWM_TNP_SOURCECLIENTAREAONLY;
    properties.rcDestination = destination;
    properties.fVisible = TRUE;
    properties.opacity = 255;
    properties.fSourceClientAreaOnly = FALSE;
    DwmUpdateThumbnailProperties(thumbnail_, &properties);

    close_rect_ = RECT{
        client.right - Scale(40, dpi),
        Scale(10, dpi),
        client.right - Scale(9, dpi),
        Scale(41, dpi)};
}

void NativeTaskbarHoverPreview::PaintPreview()
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(preview_, &paint);
    RECT client{};
    GetClientRect(preview_, &client);

    Graphics graphics(dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    LinearGradientBrush background(
        PointF(0.0f, 0.0f),
        PointF(static_cast<REAL>(client.right), static_cast<REAL>(client.bottom)),
        WebSkin::GdiColor(WebSkin::BgSecondary, 252),
        WebSkin::GdiColor(WebSkin::BgSolid, 252));
    graphics.FillRectangle(
        &background,
        RectF(0.0f, 0.0f, static_cast<REAL>(client.right), static_cast<REAL>(client.bottom)));

    std::wstring title = L"Janela";
    if (source_ != nullptr && IsWindow(source_))
    {
        const int length = GetWindowTextLengthW(source_);
        if (length > 0)
        {
            std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
            const int copied = GetWindowTextW(source_, value.data(), length + 1);
            if (copied > 0)
            {
                value.resize(static_cast<std::size_t>(copied));
                title = std::move(value);
            }
        }
    }

    const UINT dpi = GetDpiForWindow(preview_);
    const int icon_size = Scale(24, dpi);
    const int icon_x = Scale(14, dpi);
    const int icon_y = Scale(14, dpi);
    HICON icon = ResolveWindowIcon(source_);
    if (icon != nullptr)
    {
        (void)DrawIconEx(
            dc,
            icon_x,
            icon_y,
            icon,
            icon_size,
            icon_size,
            0,
            nullptr,
            DI_NORMAL);
    }

    HFONT font = CreateFontW(
        -Scale(13, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, WebSkin::TextPrimary);
    RECT title_rect{
        icon != nullptr ? icon_x + icon_size + Scale(10, dpi) : Scale(14, dpi),
        Scale(6, dpi),
        std::max<LONG>(Scale(20, dpi), client.right - Scale(48, dpi)),
        Scale(48, dpi)};
    (void)DrawTextW(
        dc,
        title.c_str(),
        -1,
        &title_rect,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    POINT cursor{};
    bool close_hot = false;
    if (GetCursorPos(&cursor) && ScreenToClient(preview_, &cursor))
    {
        close_hot = PtInRect(&close_rect_, cursor) != FALSE;
    }

    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(close_rect_.left),
            static_cast<REAL>(close_rect_.top),
            static_cast<REAL>(Width(close_rect_)),
            static_cast<REAL>(Height(close_rect_))),
        static_cast<REAL>(Scale(8, dpi)),
        close_hot
            ? WebSkin::GdiColor(WebSkin::Danger, 72)
            : WebSkin::GdiColor(WebSkin::BgTertiary),
        close_hot
            ? WebSkin::GdiColor(WebSkin::Danger)
            : WebSkin::GdiColor(WebSkin::BorderDefault),
        1.0f);
    SetTextColor(dc, close_hot ? RGB(255, 224, 228) : WebSkin::Danger);
    (void)DrawTextW(dc, L"×", -1, &close_rect_, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    if (old_font != nullptr)
    {
        SelectObject(dc, old_font);
    }
    if (font != nullptr)
    {
        DeleteObject(font);
    }
    EndPaint(preview_, &paint);
}

LRESULT CALLBACK NativeTaskbarHoverPreview::TaskbarSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data)
{
    auto* self = reinterpret_cast<NativeTaskbarHoverPreview*>(reference_data);
    if (self == nullptr)
    {
        return DefSubclassProc(window, message, w_param, l_param);
    }

    switch (message)
    {
    case WM_MOUSEMOVE:
    {
        if (!self->tracking_taskbar_)
        {
            TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window, 0};
            (void)TrackMouseEvent(&tracking);
            self->tracking_taskbar_ = true;
        }
        KillTimer(window, kHideTimer);
        self->UpdateHover(POINT{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)});
        break;
    }
    case WM_MBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const HWND target = self->HitTaskWindow(point, nullptr);
        if (target != nullptr && IsWindow(target))
        {
            self->HidePreview();
            PostMessageW(target, WM_CLOSE, 0, 0);
            return 0;
        }
        break;
    }
    case WM_MOUSEWHEEL:
    {
        if (self->window_manager_ == nullptr)
        {
            break;
        }
        const int wheel = GET_WHEEL_DELTA_WPARAM(w_param);
        if (wheel == 0)
        {
            return 0;
        }
        const int direction = wheel > 0 ? -1 : 1;
        const int current = self->window_manager_->CurrentWorkspace();
        const int next = WrappedWorkspace(current, direction);
        const bool move_active = (GET_KEYSTATE_WPARAM(w_param) & MK_CONTROL) != 0;
        if (move_active && self->window_manager_->ActiveManagedWindow() != nullptr)
        {
            self->window_manager_->MoveActiveToWorkspace(next);
        }
        self->window_manager_->SwitchWorkspace(next);
        self->HidePreview();
        InvalidateRect(window, nullptr, FALSE);
        return 0;
    }
    case WM_XBUTTONUP:
    {
        if (self->window_manager_ == nullptr)
        {
            break;
        }
        const WORD button = GET_XBUTTON_WPARAM(w_param);
        const int direction = button == XBUTTON1 ? -1 : button == XBUTTON2 ? 1 : 0;
        if (direction != 0)
        {
            const int current = self->window_manager_->CurrentWorkspace();
            self->window_manager_->SwitchWorkspace(WrappedWorkspace(current, direction));
            self->HidePreview();
            InvalidateRect(window, nullptr, FALSE);
            return TRUE;
        }
        break;
    }
    case WM_MOUSELEAVE:
        self->tracking_taskbar_ = false;
        self->pending_source_ = nullptr;
        KillTimer(window, kHoverTimer);
        SetTimer(window, kHideTimer, 260, nullptr);
        break;
    case WM_TIMER:
        if (w_param == kHoverTimer)
        {
            KillTimer(window, kHoverTimer);
            if (self->pending_source_ != nullptr)
            {
                self->ShowPreview(self->pending_source_, self->pending_task_rect_);
            }
            return 0;
        }
        if (w_param == kHideTimer)
        {
            KillTimer(window, kHideTimer);
            if (!self->tracking_taskbar_ && !self->tracking_preview_)
            {
                self->HidePreview();
            }
            return 0;
        }
        break;
    case WM_NCDESTROY:
    {
        RemoveWindowSubclass(window, &NativeTaskbarHoverPreview::TaskbarSubclass, subclass_id);
        self->taskbar_ = nullptr;
        self->HidePreview();
        if (self->preview_ != nullptr && IsWindow(self->preview_))
        {
            DestroyWindow(self->preview_);
            self->preview_ = nullptr;
        }
        const LRESULT result = DefSubclassProc(window, message, w_param, l_param);
        delete self;
        return result;
    }
    default:
        break;
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK NativeTaskbarHoverPreview::PreviewProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    NativeTaskbarHoverPreview* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<NativeTaskbarHoverPreview*>(create->lpCreateParams);
        if (self != nullptr)
        {
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<NativeTaskbarHoverPreview*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    if (self == nullptr)
    {
        return DefWindowProcW(window, message, w_param, l_param);
    }

    switch (message)
    {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_MOUSEMOVE:
        if (!self->tracking_preview_)
        {
            TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window, 0};
            TrackMouseEvent(&tracking);
            self->tracking_preview_ = true;
        }
        if (self->taskbar_ != nullptr)
        {
            KillTimer(self->taskbar_, kHideTimer);
        }
        InvalidateRect(window, nullptr, FALSE);
        return 0;
    case WM_MOUSELEAVE:
        self->tracking_preview_ = false;
        InvalidateRect(window, nullptr, FALSE);
        if (self->taskbar_ != nullptr)
        {
            SetTimer(self->taskbar_, kHideTimer, 220, nullptr);
        }
        return 0;
    case WM_MBUTTONUP:
    {
        const HWND source = self->source_;
        if (source != nullptr && IsWindow(source))
        {
            PostMessageW(source, WM_CLOSE, 0, 0);
        }
        self->HidePreview();
        return 0;
    }
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const HWND source = self->source_;
        if (source != nullptr && IsWindow(source))
        {
            if (PtInRect(&self->close_rect_, point))
            {
                PostMessageW(source, WM_CLOSE, 0, 0);
            }
            else if (self->window_manager_ != nullptr)
            {
                if (IsIconic(source))
                {
                    ShowWindow(source, SW_RESTORE);
                }
                self->window_manager_->FocusWindow(source);
            }
        }
        self->HidePreview();
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT:
        self->PaintPreview();
        return 0;
    case WM_SIZE:
        self->LayoutThumbnail();
        return 0;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        return DefWindowProcW(window, message, w_param, l_param);
    default:
        return DefWindowProcW(window, message, w_param, l_param);
    }
}
} // namespace CloudOS