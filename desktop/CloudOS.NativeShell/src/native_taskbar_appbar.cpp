#include "native_taskbar_appbar.h"

#include "native_app_launcher.h"
#include "native_icon_renderer.h"
#include "native_notification_center.h"
#include "native_shell_platform.h"
#include "native_theme.h"

#include <shellapi.h>
#include <gdiplus.h>

#include <algorithm>
#include <array>
#include <string>
#include <string_view>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kTaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v2";
constexpr UINT kAppBarCallback = WM_APP + 0x461;
constexpr UINT_PTR kRefreshTimer = 8901;
constexpr int kTaskbarHeightDip = 56;

int FindApp(std::wstring_view id)
{
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
    {
        if (id == kAllApps[index].id)
        {
            return static_cast<int>(index);
        }
    }
    return -1;
}

std::vector<int> PinnedApps()
{
    std::vector<int> result;
    for (std::wstring_view id : {L"files", L"terminal", L"browser", L"projects", L"control"})
    {
        const int index = FindApp(id);
        if (index >= 0)
        {
            result.push_back(index);
        }
    }
    return result;
}

void DrawCenteredText(
    Graphics& graphics,
    const std::wstring& text,
    const Font& font,
    const RectF& rect,
    const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentCenter);
    format.SetLineAlignment(StringAlignmentCenter);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    graphics.DrawString(text.c_str(), -1, &font, rect, &format, &brush);
}

std::wstring Shorten(std::wstring value, std::size_t maximum)
{
    if (value.size() <= maximum)
    {
        return value;
    }
    if (maximum <= 3)
    {
        value.resize(maximum);
        return value;
    }
    value.resize(maximum - 3);
    value += L"...";
    return value;
}
}

CloudOSTaskbarAppBar::~CloudOSTaskbarAppBar()
{
    Destroy();
}

bool CloudOSTaskbarAppBar::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager,
    HMONITOR monitor,
    bool primary)
{
    instance_ = instance;
    window_manager_ = window_manager;
    monitor_ = monitor;
    primary_ = primary;
    pinned_app_indices_ = PinnedApps();

    if (monitor_ == nullptr)
    {
        monitor_ = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.lpfnWndProc = &CloudOSTaskbarAppBar::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kTaskbarClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor_, &info);

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kTaskbarClass,
        primary_ ? L"CloudOS Taskbar" : L"CloudOS Taskbar secundaria",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        info.rcMonitor.left,
        info.rcMonitor.bottom - kTaskbarHeightDip,
        std::max(1L, info.rcMonitor.right - info.rcMonitor.left),
        kTaskbarHeightDip,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    APPBARDATA data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uCallbackMessage = kAppBarCallback;
    registered_ = SHAppBarMessage(ABM_NEW, &data) != FALSE;
    if (!registered_)
    {
        Destroy();
        return false;
    }

    DarkWindow(window_, false);
    PositionAppBar();
    SetTimer(window_, kRefreshTimer, 1000, nullptr);
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    UpdateWindow(window_);
    return true;
}

void CloudOSTaskbarAppBar::Destroy()
{
    if (window_ != nullptr)
    {
        KillTimer(window_, kRefreshTimer);
        if (registered_)
        {
            APPBARDATA data{};
            data.cbSize = sizeof(data);
            data.hWnd = window_;
            (void)SHAppBarMessage(ABM_REMOVE, &data);
            registered_ = false;
        }
        if (IsWindow(window_))
        {
            DestroyWindow(window_);
        }
    }
    window_ = nullptr;
    workspace_rects_.clear();
    pinned_rects_.clear();
    task_rects_.clear();
    task_windows_.clear();
}

RECT CloudOSTaskbarAppBar::Bounds() const noexcept
{
    RECT bounds{};
    if (window_ != nullptr)
    {
        GetWindowRect(window_, &bounds);
    }
    return bounds;
}

void CloudOSTaskbarAppBar::PositionAppBar()
{
    if (window_ == nullptr || monitor_ == nullptr)
    {
        return;
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor_, &info))
    {
        return;
    }

    const UINT dpi = GetDpiForWindow(window_);
    const int height = Scale(kTaskbarHeightDip, dpi);

    APPBARDATA data{};
    data.cbSize = sizeof(data);
    data.hWnd = window_;
    data.uEdge = ABE_BOTTOM;
    data.rc = info.rcMonitor;
    data.rc.top = data.rc.bottom - height;

    (void)SHAppBarMessage(ABM_QUERYPOS, &data);
    data.rc.top = data.rc.bottom - height;
    (void)SHAppBarMessage(ABM_SETPOS, &data);

    SetWindowPos(
        window_,
        HWND_TOPMOST,
        data.rc.left,
        data.rc.top,
        std::max(1L, data.rc.right - data.rc.left),
        std::max(1L, data.rc.bottom - data.rc.top),
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSTaskbarAppBar::Refresh()
{
    if (window_ != nullptr)
    {
        InvalidateRect(window_, nullptr, FALSE);
    }
}

void CloudOSTaskbarAppBar::RebuildHitTargets()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    const int margin = Scale(10, dpi);
    const int button = Scale(38, dpi);
    const int gap = Scale(7, dpi);
    const int y = (height - button) / 2;

    workspace_rects_.clear();
    int x = margin;
    for (int workspace = 0; workspace < 4; ++workspace)
    {
        workspace_rects_.push_back(RECT{x, y, x + Scale(30, dpi), y + Scale(30, dpi)});
        x += Scale(35, dpi);
    }

    const int center_group = button + Scale(10, dpi) +
        static_cast<int>(pinned_app_indices_.size()) * (button + gap) -
        (pinned_app_indices_.empty() ? 0 : gap);
    int center_x = std::max(margin, (width - center_group) / 2);
    start_rect_ = RECT{center_x, y, center_x + button, y + button};
    center_x += button + Scale(10, dpi);

    pinned_rects_.clear();
    for (std::size_t index = 0; index < pinned_app_indices_.size(); ++index)
    {
        pinned_rects_.push_back(RECT{center_x, y, center_x + button, y + button});
        center_x += button + gap;
    }

    const int right_width = Scale(260, dpi);
    int right_x = std::max(center_x + Scale(12, dpi), width - margin - right_width);
    quick_rect_ = RECT{right_x, y, right_x + Scale(116, dpi), y + button};
    right_x += Scale(122, dpi);
    notification_rect_ = RECT{right_x, y, right_x + Scale(42, dpi), y + button};
    right_x += Scale(48, dpi);
    clock_rect_ = RECT{right_x, y, width - margin, y + button};

    task_rects_.clear();
    task_windows_.clear();
    if (window_manager_ == nullptr)
    {
        return;
    }

    std::vector<CloudOSManagedWindow> windows = window_manager_->CurrentWorkspaceWindows();
    windows.erase(
        std::remove_if(
            windows.begin(),
            windows.end(),
            [this](const CloudOSManagedWindow& item)
            {
                return item.hwnd == nullptr ||
                    MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST) != monitor_;
            }),
        windows.end());

    const int task_left = x + Scale(8, dpi);
    const int task_right = std::max(task_left, (width - center_group) / 2 - Scale(18, dpi));
    const int available = std::max(0, task_right - task_left);
    const int task_width = Scale(112, dpi);
    const int task_gap = Scale(6, dpi);
    const int capacity = available / std::max(1, task_width + task_gap);
    const int count = std::min(static_cast<int>(windows.size()), capacity);
    int task_x = task_left;
    for (int index = 0; index < count; ++index)
    {
        task_rects_.push_back(RECT{task_x, y + Scale(3, dpi), task_x + task_width, y + button - Scale(3, dpi)});
        task_windows_.push_back(windows[static_cast<std::size_t>(index)].hwnd);
        task_x += task_width + task_gap;
    }
}

void CloudOSTaskbarAppBar::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);

    HDC memory_dc = CreateCompatibleDC(screen_dc);
    HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(window_);

    SolidBrush background(Color(248, 20, 22, 27));
    graphics.FillRectangle(&background, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));
    Pen top_border(Color(90, 95, 103, 118), 1.0f);
    graphics.DrawLine(&top_border, 0.0f, 0.0f, static_cast<REAL>(width), 0.0f);

    RebuildHitTargets();

    Font small_font(L"Segoe UI", static_cast<REAL>(Scale(9, dpi)), FontStyleRegular, UnitPixel);
    Font bold_font(L"Segoe UI", static_cast<REAL>(Scale(9, dpi)), FontStyleBold, UnitPixel);
    SolidBrush white(Color(255, 244, 247, 251));
    SolidBrush secondary(Color(255, 188, 195, 207));

    for (std::size_t index = 0; index < workspace_rects_.size(); ++index)
    {
        const RECT& rect = workspace_rects_[index];
        const bool active = window_manager_ != nullptr &&
            window_manager_->CurrentWorkspace() == static_cast<int>(index);
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(static_cast<REAL>(rect.left), static_cast<REAL>(rect.top), static_cast<REAL>(Width(rect)), static_cast<REAL>(Height(rect))),
            static_cast<REAL>(Scale(8, dpi)),
            active ? Color(255, 61, 98, 148) : Color(105, 42, 45, 53),
            active ? Color(205, 116, 178, 250) : Color(45, 110, 116, 128),
            1.0f);
        DrawCenteredText(graphics, std::to_wstring(index + 1u), bold_font,
            RectF(static_cast<REAL>(rect.left), static_cast<REAL>(rect.top), static_cast<REAL>(Width(rect)), static_cast<REAL>(Height(rect))),
            active ? white : secondary);
    }

    for (std::size_t index = 0; index < task_rects_.size() && index < task_windows_.size(); ++index)
    {
        const RECT& rect = task_rects_[index];
        std::wstring title = L"Aplicativo";
        const auto windows = window_manager_ != nullptr ? window_manager_->CurrentWorkspaceWindows() : std::vector<CloudOSManagedWindow>{};
        const auto iterator = std::find_if(windows.begin(), windows.end(), [this, index](const CloudOSManagedWindow& item)
        {
            return item.hwnd == task_windows_[index];
        });
        if (iterator != windows.end() && !iterator->title.empty())
        {
            title = iterator->title;
        }
        const bool active = window_manager_ != nullptr && window_manager_->ActiveManagedWindow() == task_windows_[index];
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(static_cast<REAL>(rect.left), static_cast<REAL>(rect.top), static_cast<REAL>(Width(rect)), static_cast<REAL>(Height(rect))),
            static_cast<REAL>(Scale(8, dpi)),
            active ? Color(205, 47, 52, 62) : Color(95, 36, 39, 46),
            active ? Color(180, 103, 165, 246) : Color(45, 95, 102, 116),
            1.0f);
        DrawCenteredText(graphics, Shorten(title, 17), small_font,
            RectF(static_cast<REAL>(rect.left + Scale(5, dpi)), static_cast<REAL>(rect.top), static_cast<REAL>(Width(rect) - Scale(10, dpi)), static_cast<REAL>(Height(rect))),
            active ? white : secondary);
    }

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(static_cast<REAL>(start_rect_.left), static_cast<REAL>(start_rect_.top), static_cast<REAL>(Width(start_rect_)), static_cast<REAL>(Height(start_rect_))),
        static_cast<REAL>(Scale(10, dpi)),
        hovered_kind_ == 1 ? Color(230, 55, 64, 78) : Color(145, 37, 41, 49),
        Color(80, 110, 174, 250),
        1.0f);
    DrawCenteredText(graphics, L"C", bold_font,
        RectF(static_cast<REAL>(start_rect_.left), static_cast<REAL>(start_rect_.top), static_cast<REAL>(Width(start_rect_)), static_cast<REAL>(Height(start_rect_))),
        white);

    for (std::size_t index = 0; index < pinned_rects_.size() && index < pinned_app_indices_.size(); ++index)
    {
        const RECT& rect = pinned_rects_[index];
        if (hovered_kind_ == 2 && hovered_index_ == static_cast<int>(index))
        {
            NativeIconRenderer::DrawGlassPanel(
                graphics,
                RectF(static_cast<REAL>(rect.left - Scale(2, dpi)), static_cast<REAL>(rect.top - Scale(2, dpi)), static_cast<REAL>(Width(rect) + Scale(4, dpi)), static_cast<REAL>(Height(rect) + Scale(4, dpi))),
                static_cast<REAL>(Scale(10, dpi)),
                Color(180, 48, 52, 61),
                Color(70, 108, 171, 247),
                1.0f);
        }
        const int app_index = pinned_app_indices_[index];
        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            rect.left + Scale(3, dpi),
            rect.top + Scale(3, dpi),
            std::max(16, Width(rect) - Scale(6, dpi)));
    }

    SYSTEM_POWER_STATUS power{};
    std::wstring quick_text = L"Som  Rede";
    if (GetSystemPowerStatus(&power) && power.BatteryFlag != 128 && power.BatteryLifePercent != 255)
    {
        quick_text += L"  ";
        quick_text += std::to_wstring(power.BatteryLifePercent);
        quick_text += L"%";
    }
    DrawCenteredText(graphics, quick_text, small_font,
        RectF(static_cast<REAL>(quick_rect_.left), static_cast<REAL>(quick_rect_.top), static_cast<REAL>(Width(quick_rect_)), static_cast<REAL>(Height(quick_rect_))),
        secondary);

    const std::size_t unread = CloudOSNativeNotificationCenter::UnreadCount();
    DrawCenteredText(graphics, unread == 0 ? L"○" : std::to_wstring(unread), bold_font,
        RectF(static_cast<REAL>(notification_rect_.left), static_cast<REAL>(notification_rect_.top), static_cast<REAL>(Width(notification_rect_)), static_cast<REAL>(Height(notification_rect_))),
        unread == 0 ? secondary : white);

    std::wstring clock = NativeShellPlatform::FormatLocalTime();
    clock += L"\n";
    clock += NativeShellPlatform::FormatLocalDate(false);
    DrawCenteredText(graphics, clock, small_font,
        RectF(static_cast<REAL>(clock_rect_.left), static_cast<REAL>(clock_rect_.top), static_cast<REAL>(Width(clock_rect_)), static_cast<REAL>(Height(clock_rect_))),
        white);

    BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    EndPaint(window_, &paint);
}

void CloudOSTaskbarAppBar::LaunchPinned(std::size_t index)
{
    if (index >= pinned_app_indices_.size())
    {
        return;
    }
    const int app_index = pinned_app_indices_[index];
    if (app_index >= 0 && app_index < static_cast<int>(kAllApps.size()))
    {
        NativeAppLauncher::Launch(instance_, window_, kAllApps[static_cast<std::size_t>(app_index)]);
        if (window_manager_ != nullptr)
        {
            window_manager_->Reconcile();
        }
        Refresh();
    }
}

LRESULT CloudOSTaskbarAppBar::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    if (message == kAppBarCallback)
    {
        if (w_param == ABN_POSCHANGED)
        {
            PositionAppBar();
        }
        return 0;
    }

    switch (message)
    {
    case WM_PAINT:
        Paint();
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            Refresh();
            return 0;
        }
        break;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
        PositionAppBar();
        return 0;
    case WM_MOUSEMOVE:
    {
        if (!tracking_mouse_)
        {
            TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window_, 0};
            TrackMouseEvent(&tracking);
            tracking_mouse_ = true;
        }
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const int previous_kind = hovered_kind_;
        const int previous_index = hovered_index_;
        hovered_kind_ = -1;
        hovered_index_ = -1;
        if (Contains(start_rect_, point))
        {
            hovered_kind_ = 1;
        }
        for (std::size_t index = 0; index < pinned_rects_.size(); ++index)
        {
            if (Contains(pinned_rects_[index], point))
            {
                hovered_kind_ = 2;
                hovered_index_ = static_cast<int>(index);
                break;
            }
        }
        if (Contains(quick_rect_, point)) hovered_kind_ = 3;
        if (Contains(notification_rect_, point)) hovered_kind_ = 4;
        if (Contains(clock_rect_, point)) hovered_kind_ = 5;
        if (previous_kind != hovered_kind_ || previous_index != hovered_index_)
        {
            Refresh();
        }
        SetCursor(LoadCursorW(nullptr, hovered_kind_ >= 0 ? IDC_HAND : IDC_ARROW));
        return 0;
    }
    case WM_MOUSELEAVE:
        tracking_mouse_ = false;
        hovered_kind_ = -1;
        hovered_index_ = -1;
        Refresh();
        return 0;
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        const RECT anchor = Bounds();
        if (Contains(start_rect_, point))
        {
            if (on_start_) on_start_(anchor);
            return 0;
        }
        if (Contains(quick_rect_, point))
        {
            if (on_quick_settings_) on_quick_settings_(anchor);
            return 0;
        }
        if (Contains(notification_rect_, point) || Contains(clock_rect_, point))
        {
            if (on_notifications_) on_notifications_(anchor);
            return 0;
        }
        for (std::size_t index = 0; index < pinned_rects_.size(); ++index)
        {
            if (Contains(pinned_rects_[index], point))
            {
                LaunchPinned(index);
                return 0;
            }
        }
        for (std::size_t index = 0; index < workspace_rects_.size(); ++index)
        {
            if (Contains(workspace_rects_[index], point) && window_manager_ != nullptr)
            {
                window_manager_->SwitchWorkspace(static_cast<int>(index));
                Refresh();
                return 0;
            }
        }
        for (std::size_t index = 0; index < task_rects_.size() && index < task_windows_.size(); ++index)
        {
            if (Contains(task_rects_[index], point) && window_manager_ != nullptr)
            {
                window_manager_->FocusWindow(task_windows_[index]);
                Refresh();
                return 0;
            }
        }
        return 0;
    }
    case WM_RBUTTONUP:
    {
        POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        ClientToScreen(window_, &point);
        NativeAppLauncher::ShowQuickPowerMenu(window_, point);
        return 0;
    }
    case WM_DESTROY:
        window_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSTaskbarAppBar::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSTaskbarAppBar*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSTaskbarAppBar*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
