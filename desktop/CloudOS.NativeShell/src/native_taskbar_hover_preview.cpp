#include "native_taskbar_hover_preview.h"

#include "native_theme.h"
#include "native_window_manager.h"

#include <commctrl.h>
#include <dwmapi.h>

#include <algorithm>
#include <new>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kPreviewClass[] = L"CloudOS.NativeShell.TaskPreview.v1";
constexpr UINT_PTR kSubclassId = 0xA901;
constexpr UINT_PTR kHoverTimer = 0xA902;
constexpr UINT_PTR kHideTimer = 0xA903;
constexpr int kPinnedCount = 5;

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
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kPreviewClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    preview_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
        kPreviewClass,
        L"",
        WS_POPUP | WS_BORDER,
        0,
        0,
        360,
        260,
        nullptr,
        nullptr,
        instance_,
        this);
    if (preview_ == nullptr)
    {
        return false;
    }
    DarkWindow(preview_, false);

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
    if (taskbar_ == nullptr || window_manager_ == nullptr)
    {
        return nullptr;
    }

    RECT client{};
    GetClientRect(taskbar_, &client);
    const UINT dpi = GetDpiForWindow(taskbar_);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));
    const int margin = Scale(10, dpi);
    const int button = Scale(38, dpi);
    const int gap = Scale(7, dpi);
    const int y = (height - button) / 2;

    const int workspace_end = margin + 4 * Scale(35, dpi);
    const int center_group = button + Scale(10, dpi) +
        kPinnedCount * (button + gap) - gap;
    const int task_left = workspace_end + Scale(8, dpi);
    const int task_right = std::max(task_left, (width - center_group) / 2 - Scale(18, dpi));
    const int available = std::max(0, task_right - task_left);
    const int task_width = Scale(112, dpi);
    const int task_gap = Scale(6, dpi);
    const int capacity = available / std::max(1, task_width + task_gap);

    std::vector<CloudOSManagedWindow> windows = window_manager_->CurrentWorkspaceWindows();
    windows.erase(
        std::remove_if(
            windows.begin(),
            windows.end(),
            [this](const CloudOSManagedWindow& item)
            {
                return item.hwnd == nullptr || !IsWindow(item.hwnd) ||
                    MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST) != monitor_;
            }),
        windows.end());

    const int count = std::min<int>(static_cast<int>(windows.size()), capacity);
    for (int index = 0; index < count; ++index)
    {
        const int left = task_left + index * (task_width + task_gap);
        RECT rect{
            left,
            y + Scale(3, dpi),
            left + task_width,
            y + button - Scale(3, dpi)};
        if (PtInRect(&rect, client_point))
        {
            if (task_rect != nullptr)
            {
                *task_rect = rect;
            }
            return windows[static_cast<std::size_t>(index)].hwnd;
        }
    }
    return nullptr;
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
        SetTimer(taskbar_, kHoverTimer, 420, nullptr);
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
    const int preview_width = Scale(360, dpi);
    const int preview_height = Scale(260, dpi);
    int x = top_left.x + (bottom_right.x - top_left.x - preview_width) / 2;
    int y = top_left.y - preview_height - Scale(8, dpi);

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    const HMONITOR monitor = MonitorFromWindow(taskbar_, MONITOR_DEFAULTTONEAREST);
    if (monitor != nullptr && GetMonitorInfoW(monitor, &info))
    {
        x = std::clamp<int>(x, info.rcWork.left, std::max<int>(info.rcWork.left, info.rcWork.right - preview_width));
        y = std::clamp<int>(y, info.rcWork.top, std::max<int>(info.rcWork.top, info.rcWork.bottom - preview_height));
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
    const int margin = Scale(10, dpi);
    const int title_height = Scale(38, dpi);
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
        client.right - Scale(34, dpi),
        Scale(6, dpi),
        client.right - Scale(8, dpi),
        Scale(32, dpi)};
}

void NativeTaskbarHoverPreview::PaintPreview()
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(preview_, &paint);
    RECT client{};
    GetClientRect(preview_, &client);

    HBRUSH background = CreateSolidBrush(RGB(24, 27, 33));
    HBRUSH border = CreateSolidBrush(RGB(74, 80, 92));
    if (background != nullptr)
    {
        FillRect(dc, &client, background);
        DeleteObject(background);
    }
    if (border != nullptr)
    {
        FrameRect(dc, &client, border);
        DeleteObject(border);
    }

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
    HFONT font = CreateFontW(
        -Scale(14, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(241, 244, 248));
    RECT title_rect{
        Scale(12, dpi),
        Scale(4, dpi),
        std::max<LONG>(Scale(20, dpi), client.right - Scale(42, dpi)),
        Scale(36, dpi)};
    DrawTextW(dc, title.c_str(), -1, &title_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    SetTextColor(dc, RGB(230, 110, 116));
    DrawTextW(dc, L"×", -1, &close_rect_, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

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
            TrackMouseEvent(&tracking);
            self->tracking_taskbar_ = true;
        }
        KillTimer(window, kHideTimer);
        self->UpdateHover(POINT{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)});
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
        return 0;
    case WM_MOUSELEAVE:
        self->tracking_preview_ = false;
        if (self->taskbar_ != nullptr)
        {
            SetTimer(self->taskbar_, kHideTimer, 220, nullptr);
        }
        return 0;
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
