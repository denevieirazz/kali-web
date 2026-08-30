#include "native_snap_assist.h"

#include "native_window_manager.h"

#include <algorithm>
#include <array>
#include <string_view>

namespace CloudOS
{
namespace
{
constexpr wchar_t kOverlayClass[] = L"CloudOS.NativeShell.SnapAssistOverlay.v1";

int Width(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.right - rect.left));
}

int Height(const RECT& rect) noexcept
{
    return std::max<int>(0, static_cast<int>(rect.bottom - rect.top));
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
    if (overlay_ != nullptr && IsWindow(overlay_))
    {
        DestroyWindow(overlay_);
    }
    overlay_ = nullptr;
    moving_window_ = nullptr;
    active_zone_ = Zone::None;
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
        StartsWith(name, L"CloudOS.NativeShell.SnapAssist"))
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
        active_zone_ = Zone::None;
        return;
    }

    RECT target{};
    const Zone zone = ResolveZone(window, cursor, &target);
    if (zone == Zone::None)
    {
        HideOverlay();
        active_zone_ = Zone::None;
        return;
    }

    active_zone_ = zone;
    active_target_ = target;
    ShowOverlay(target);
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
    RECT* target) const
{
    if (target == nullptr)
    {
        return Zone::None;
    }

    const RECT work = WorkAreaFor(window);
    const int width = Width(work);
    const int height = Height(work);
    if (width < 240 || height < 180)
    {
        return Zone::None;
    }

    const UINT dpi = GetDpiForWindow(window);
    const int threshold = MulDiv(30, dpi == 0 ? 96 : static_cast<int>(dpi), 96);
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
        if ((GetKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            const int relative_x = cursor.x - work.left;
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
} // namespace CloudOS
