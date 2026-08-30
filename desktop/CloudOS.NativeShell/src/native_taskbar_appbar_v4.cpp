#include "native_taskbar_appbar.h"

#include "native_app_launcher.h"
#include "native_icon_renderer.h"
#include "native_notification_center.h"
#include "native_shell_platform.h"
#include "native_theme.h"

#include <gdiplus.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cwchar>
#include <string>
#include <string_view>
#include <vector>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kTaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v4";
constexpr UINT kAppBarCallback = WM_APP + 0x461;
constexpr UINT_PTR kRefreshTimer = 8901;
constexpr int kTaskbarHeightDip = 68;

constexpr UINT kPinOpen = 9401;
constexpr UINT kPinToggleStart = 9402;
constexpr UINT kPinRemove = 9403;
constexpr UINT kPinMoveLeft = 9404;
constexpr UINT kPinMoveRight = 9405;

constexpr UINT kTaskRestore = 9501;
constexpr UINT kTaskMinimize = 9502;
constexpr UINT kTaskMaximize = 9503;
constexpr UINT kTaskToggleFloating = 9504;
constexpr UINT kTaskWorkspace1 = 9511;
constexpr UINT kTaskWorkspace2 = 9512;
constexpr UINT kTaskWorkspace3 = 9513;
constexpr UINT kTaskWorkspace4 = 9514;
constexpr UINT kTaskChooseWindow = 9520;
constexpr UINT kTaskClose = 9521;
constexpr UINT kTaskCloseAll = 9522;
constexpr UINT kGroupWindowBase = 9600;
constexpr UINT kOverflowPinBase = 9700;
constexpr UINT kOverflowTaskBase = 9800;

std::wstring Truncate(std::wstring value, std::size_t maximum)
{
    if (value.size() <= maximum)
    {
        return value;
    }
    if (maximum <= 3u)
    {
        value.resize(maximum);
        return value;
    }
    value.resize(maximum - 3u);
    value += L"...";
    return value;
}

std::wstring ReadWindowTitle(HWND window)
{
    if (window == nullptr || !IsWindow(window))
    {
        return {};
    }
    const int length = GetWindowTextLengthW(window);
    if (length <= 0)
    {
        return {};
    }
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(window, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return value;
}

std::wstring ReadWindowClass(HWND window)
{
    std::array<wchar_t, 256> value{};
    if (window == nullptr ||
        GetClassNameW(window, value.data(), static_cast<int>(value.size())) <= 0)
    {
        return {};
    }
    return value.data();
}

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

HWND RepresentativeWindow(const std::vector<HWND>& windows, HWND active)
{
    if (active != nullptr &&
        std::find(windows.begin(), windows.end(), active) != windows.end())
    {
        return active;
    }
    for (HWND window : windows)
    {
        if (window != nullptr && IsWindow(window))
        {
            return window;
        }
    }
    return nullptr;
}

void DrawCenteredText(
    Graphics& graphics,
    const std::wstring& text,
    const Font& font,
    const RECT& rect,
    const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentCenter);
    format.SetLineAlignment(StringAlignmentCenter);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    graphics.DrawString(
        text.c_str(),
        -1,
        &font,
        RectF(
            static_cast<REAL>(rect.left),
            static_cast<REAL>(rect.top),
            static_cast<REAL>(Width(rect)),
            static_cast<REAL>(Height(rect))),
        &format,
        &brush);
}

void DrawLeftText(
    Graphics& graphics,
    const std::wstring& text,
    const Font& font,
    const RECT& rect,
    const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentNear);
    format.SetLineAlignment(StringAlignmentCenter);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    format.SetFormatFlags(StringFormatFlagsNoWrap);
    graphics.DrawString(
        text.c_str(),
        -1,
        &font,
        RectF(
            static_cast<REAL>(rect.left),
            static_cast<REAL>(rect.top),
            static_cast<REAL>(Width(rect)),
            static_cast<REAL>(Height(rect))),
        &format,
        &brush);
}

void DrawPanel(
    Graphics& graphics,
    const RECT& rect,
    UINT dpi,
    COLORREF fill,
    COLORREF border,
    BYTE alpha = 230)
{
    WebSkin::DrawRoundedPanel(
        graphics,
        RectF(
            static_cast<REAL>(rect.left),
            static_cast<REAL>(rect.top),
            static_cast<REAL>(std::max<int>(1, Width(rect))),
            static_cast<REAL>(std::max<int>(1, Height(rect)))),
        static_cast<REAL>(Scale(12, dpi)),
        WebSkin::GdiColor(fill, alpha),
        WebSkin::GdiColor(border),
        1.0f);
}

bool DrawWindowsPinIcon(
    HDC dc,
    const ShellPinItem& pin,
    int x,
    int y,
    int size)
{
    if (dc == nullptr ||
        pin.kind != ShellPinKind::WindowsTarget ||
        pin.target.empty())
    {
        return false;
    }

    SHFILEINFOW info{};
    if (SHGetFileInfoW(
            pin.target.c_str(),
            0,
            &info,
            sizeof(info),
            SHGFI_ICON | SHGFI_LARGEICON) == 0 ||
        info.hIcon == nullptr)
    {
        return false;
    }

    const BOOL drawn = DrawIconEx(
        dc,
        x,
        y,
        info.hIcon,
        size,
        size,
        0,
        nullptr,
        DI_NORMAL);
    DestroyIcon(info.hIcon);
    return drawn != FALSE;
}

void DrawFallbackIcon(
    Graphics& graphics,
    const std::wstring& title,
    const RECT& rect,
    UINT dpi)
{
    RECT tile = rect;
    InflateRect(&tile, -Scale(5, dpi), -Scale(5, dpi));
    DrawPanel(
        graphics,
        tile,
        dpi,
        WebSkin::BgElevated,
        WebSkin::BorderStrong,
        245);

    Font font(
        L"Segoe UI Variable Display",
        static_cast<REAL>(Scale(14, dpi)),
        FontStyleBold,
        UnitPixel);
    SolidBrush text(WebSkin::GdiColor(WebSkin::TextSecondary));
    std::wstring initial = title.empty()
        ? std::wstring(L"•")
        : std::wstring(1u, title.front());
    DrawCenteredText(graphics, initial, font, rect, text);
}

void DrawStartGlyph(Graphics& graphics, const RECT& rect, UINT dpi, bool hot)
{
    const int cell = Scale(9, dpi);
    const int gap = Scale(4, dpi);
    const int total = cell * 2 + gap;
    const int x = rect.left + (Width(rect) - total) / 2;
    const int y = rect.top + (Height(rect) - total) / 2;
    SolidBrush first(WebSkin::GdiColor(
        hot ? WebSkin::TextPrimary : WebSkin::AccentHover));
    SolidBrush second(WebSkin::GdiColor(WebSkin::TextPrimary));
    graphics.FillRectangle(&first, Rect(x, y, cell, cell));
    graphics.FillRectangle(&second, Rect(x + cell + gap, y, cell, cell));
    graphics.FillRectangle(&second, Rect(x, y + cell + gap, cell, cell));
    graphics.FillRectangle(&first, Rect(x + cell + gap, y + cell + gap, cell, cell));
}

void DrawQuickGlyph(Graphics& graphics, const RECT& rect, UINT dpi, bool hot)
{
    const Color color = WebSkin::GdiColor(
        hot ? WebSkin::TextPrimary : WebSkin::TextSecondary);
    Pen pen(color, 1.8f);
    SolidBrush brush(color);

    const REAL middle = static_cast<REAL>((rect.top + rect.bottom) / 2);
    const REAL speaker_x = static_cast<REAL>(rect.left + Scale(18, dpi));
    graphics.DrawLine(&pen, speaker_x, middle - 4.0f, speaker_x + 5.0f, middle - 4.0f);
    graphics.DrawLine(&pen, speaker_x + 5.0f, middle - 4.0f, speaker_x + 11.0f, middle - 9.0f);
    graphics.DrawLine(&pen, speaker_x + 11.0f, middle - 9.0f, speaker_x + 11.0f, middle + 9.0f);
    graphics.DrawLine(&pen, speaker_x + 11.0f, middle + 9.0f, speaker_x + 5.0f, middle + 4.0f);
    graphics.DrawLine(&pen, speaker_x + 5.0f, middle + 4.0f, speaker_x, middle + 4.0f);
    graphics.DrawArc(&pen, speaker_x + 7.0f, middle - 9.0f, 16.0f, 18.0f, -55.0f, 110.0f);

    const REAL net_x = static_cast<REAL>(rect.left + Scale(61, dpi));
    graphics.DrawArc(&pen, net_x - 12.0f, middle - 11.0f, 24.0f, 18.0f, 205.0f, 130.0f);
    graphics.DrawArc(&pen, net_x - 8.0f, middle - 6.0f, 16.0f, 11.0f, 205.0f, 130.0f);
    graphics.FillEllipse(&brush, net_x - 2.0f, middle + 4.0f, 4.0f, 4.0f);
}
}

CloudOSTaskbarAppBar::~CloudOSTaskbarAppBar()
{
    Destroy();
}

int CloudOSTaskbarAppBar::FindCloudApp(std::wstring_view id) const
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

std::wstring CloudOSTaskbarAppBar::PinTitle(const ShellPinItem& pin) const
{
    if (pin.kind == ShellPinKind::CloudOSApp)
    {
        const int index = FindCloudApp(pin.id);
        if (index >= 0)
        {
            return kAllApps[static_cast<std::size_t>(index)].name;
        }
        return pin.id;
    }
    return pin.title.empty() ? std::wstring(L"Aplicativo") : pin.title;
}

void CloudOSTaskbarAppBar::ReloadPins()
{
    pinned_items_ = ShellPinStore::Instance().TaskbarPins();
}

bool CloudOSTaskbarAppBar::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager,
    HMONITOR monitor,
    bool primary)
{
    instance_ = instance;
    window_manager_ = window_manager;
    monitor_ = monitor != nullptr
        ? monitor
        : MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    primary_ = primary;
    ReloadPins();

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.lpfnWndProc = &CloudOSTaskbarAppBar::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kTaskbarClass;
    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor_, &info))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kTaskbarClass,
        primary_ ? L"CloudOS Taskbar" : L"CloudOS Taskbar secundaria",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        info.rcMonitor.left,
        info.rcMonitor.bottom - kTaskbarHeightDip,
        std::max<LONG>(1L, info.rcMonitor.right - info.rcMonitor.left),
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
    const COLORREF border = WebSkin::BorderDefault;
    (void)DwmSetWindowAttribute(
        window_,
        static_cast<DWMWINDOWATTRIBUTE>(34),
        &border,
        sizeof(border));

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
    pinned_items_.clear();
    task_rects_.clear();
    task_groups_.clear();
    visible_pin_count_ = 0;
    visible_task_group_count_ = 0;
}

RECT CloudOSTaskbarAppBar::Bounds() const noexcept
{
    RECT bounds{};
    if (window_ != nullptr && IsWindow(window_))
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
        std::max<LONG>(1L, data.rc.right - data.rc.left),
        std::max<LONG>(1L, data.rc.bottom - data.rc.top),
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSTaskbarAppBar::Refresh()
{
    if (window_ == nullptr)
    {
        return;
    }
    ReloadPins();
    InvalidateRect(window_, nullptr, FALSE);
}

void CloudOSTaskbarAppBar::RebuildHitTargets()
{
    if (window_ == nullptr)
    {
        return;
    }

    ReloadPins();
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));
    const int margin = Scale(12, dpi);
    const int button = Scale(46, dpi);
    const int gap = Scale(8, dpi);
    const int y = (height - button) / 2;

    workspace_rects_.clear();
    int workspace_x = margin;
    for (int workspace = 0; workspace < 4; ++workspace)
    {
        workspace_rects_.push_back(RECT{
            workspace_x,
            y + Scale(5, dpi),
            workspace_x + Scale(34, dpi),
            y + button - Scale(5, dpi)});
        workspace_x += Scale(40, dpi);
    }

    const std::size_t max_visible_pins = width >= Scale(1900, dpi)
        ? 8u
        : width >= Scale(1450, dpi) ? 7u : 5u;
    visible_pin_count_ = std::min(max_visible_pins, pinned_items_.size());
    const bool pin_overflow = pinned_items_.size() > visible_pin_count_;
    const int pin_width = static_cast<int>(visible_pin_count_) * (button + gap) -
        (visible_pin_count_ == 0u ? 0 : gap);
    const int pin_group_width = button + Scale(14, dpi) + pin_width +
        (pin_overflow ? button + gap : 0);
    int pin_x = std::max<int>(margin, (width - pin_group_width) / 2);
    const int center_left = pin_x;

    start_rect_ = RECT{pin_x, y, pin_x + button, y + button};
    pin_x += button + Scale(14, dpi);

    pinned_rects_.clear();
    for (std::size_t index = 0; index < visible_pin_count_; ++index)
    {
        pinned_rects_.push_back(RECT{pin_x, y, pin_x + button, y + button});
        pin_x += button + gap;
    }

    pin_overflow_rect_ = RECT{};
    if (pin_overflow)
    {
        pin_overflow_rect_ = RECT{pin_x, y, pin_x + button, y + button};
    }

    const int clock_width = Scale(122, dpi);
    const int notify_width = Scale(46, dpi);
    const int quick_width = Scale(106, dpi);
    int right_x = width - margin - clock_width;
    clock_rect_ = RECT{right_x, y, width - margin, y + button};
    right_x -= gap + notify_width;
    notification_rect_ = RECT{right_x, y, right_x + notify_width, y + button};
    right_x -= gap + quick_width;
    quick_rect_ = RECT{right_x, y, right_x + quick_width, y + button};

    task_groups_.clear();
    if (window_manager_ != nullptr)
    {
        const std::vector<CloudOSManagedWindow> managed =
            window_manager_->CurrentWorkspaceWindows();
        for (const CloudOSManagedWindow& item : managed)
        {
            if (item.hwnd == nullptr || !IsWindow(item.hwnd) ||
                MonitorFromWindow(item.hwnd, MONITOR_DEFAULTTONEAREST) != monitor_)
            {
                continue;
            }

            const std::wstring class_name = ReadWindowClass(item.hwnd);
            auto group = std::find_if(
                task_groups_.begin(),
                task_groups_.end(),
                [&item, &class_name](const TaskGroup& candidate)
                {
                    return item.process_id != 0 &&
                        candidate.process_id == item.process_id &&
                        _wcsicmp(candidate.class_name.c_str(), class_name.c_str()) == 0;
                });
            if (group == task_groups_.end())
            {
                TaskGroup created{};
                created.process_id = item.process_id;
                created.class_name = class_name;
                created.title = item.title.empty()
                    ? ReadWindowTitle(item.hwnd)
                    : item.title;
                if (created.title.empty())
                {
                    created.title = L"Aplicativo";
                }
                created.windows.push_back(item.hwnd);
                task_groups_.push_back(std::move(created));
            }
            else
            {
                group->windows.push_back(item.hwnd);
            }
        }
    }

    const int task_left = workspace_x + Scale(10, dpi);
    const int task_right = std::max<int>(task_left, center_left - Scale(18, dpi));
    const int available = std::max<int>(0, task_right - task_left);
    const int task_width = Scale(146, dpi);
    const int task_gap = Scale(7, dpi);
    const int overflow_width = Scale(46, dpi);
    int capacity = available > 0
        ? (available + task_gap) / (task_width + task_gap)
        : 0;
    capacity = std::max<int>(0, capacity);

    const bool task_overflow = task_groups_.size() > static_cast<std::size_t>(capacity);
    int visible_capacity = capacity;
    if (task_overflow && visible_capacity > 0)
    {
        const int reserve = overflow_width + task_gap;
        visible_capacity = std::max<int>(
            0,
            (std::max<int>(0, available - reserve) + task_gap) /
                (task_width + task_gap));
    }
    visible_task_group_count_ = std::min<std::size_t>(
        task_groups_.size(),
        static_cast<std::size_t>(visible_capacity));

    task_rects_.clear();
    int task_x = task_left;
    for (std::size_t index = 0; index < visible_task_group_count_; ++index)
    {
        task_rects_.push_back(RECT{
            task_x,
            y + Scale(3, dpi),
            task_x + task_width,
            y + button - Scale(3, dpi)});
        task_x += task_width + task_gap;
    }

    task_overflow_rect_ = RECT{};
    if (task_groups_.size() > visible_task_group_count_ &&
        task_x + overflow_width <= task_right)
    {
        task_overflow_rect_ = RECT{
            task_x,
            y + Scale(3, dpi),
            task_x + overflow_width,
            y + button - Scale(3, dpi)};
    }
}

HWND CloudOSTaskbarAppBar::HitTaskWindow(POINT point, RECT* bounds) const
{
    const HWND active = window_manager_ != nullptr
        ? window_manager_->ActiveManagedWindow()
        : nullptr;
    for (std::size_t index = 0;
         index < task_rects_.size() && index < task_groups_.size();
         ++index)
    {
        if (!Contains(task_rects_[index], point))
        {
            continue;
        }
        if (bounds != nullptr)
        {
            *bounds = task_rects_[index];
        }
        return RepresentativeWindow(task_groups_[index].windows, active);
    }
    return nullptr;
}

void CloudOSTaskbarAppBar::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(window_, &paint);
    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));

    HDC memory_dc = CreateCompatibleDC(screen_dc);
    HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(window_);

    LinearGradientBrush background(
        PointF(0.0f, 0.0f),
        PointF(static_cast<REAL>(width), static_cast<REAL>(height)),
        WebSkin::GdiColor(WebSkin::BgPrimary, 252),
        WebSkin::GdiColor(WebSkin::BgSolid, 252));
    graphics.FillRectangle(
        &background,
        RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));
    Pen top_border(WebSkin::GdiColor(WebSkin::BorderDefault, 190), 1.0f);
    graphics.DrawLine(&top_border, 0.0f, 0.0f, static_cast<REAL>(width), 0.0f);

    RebuildHitTargets();

    Font normal_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(10, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font small_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(9, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font bold_font(
        L"Segoe UI Variable Text",
        static_cast<REAL>(Scale(10, dpi)),
        FontStyleBold,
        UnitPixel);
    SolidBrush primary(WebSkin::GdiColor(WebSkin::TextPrimary));
    SolidBrush secondary(WebSkin::GdiColor(WebSkin::TextSecondary));
    SolidBrush tertiary(WebSkin::GdiColor(WebSkin::TextTertiary));

    for (std::size_t index = 0; index < workspace_rects_.size(); ++index)
    {
        const RECT& rect = workspace_rects_[index];
        const bool active = window_manager_ != nullptr &&
            window_manager_->CurrentWorkspace() == static_cast<int>(index);
        const bool hot = hovered_kind_ == 8 &&
            hovered_index_ == static_cast<int>(index);
        DrawPanel(
            graphics,
            rect,
            dpi,
            active ? WebSkin::Accent : hot ? WebSkin::BgHover : WebSkin::BgTertiary,
            active ? WebSkin::AccentHover : hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
            active ? 255 : 225);
        DrawCenteredText(
            graphics,
            std::to_wstring(index + 1u),
            bold_font,
            rect,
            active ? primary : secondary);
    }

    const HWND active_window = window_manager_ != nullptr
        ? window_manager_->ActiveManagedWindow()
        : nullptr;
    for (std::size_t index = 0;
         index < task_rects_.size() && index < task_groups_.size();
         ++index)
    {
        const RECT& rect = task_rects_[index];
        const TaskGroup& group = task_groups_[index];
        const bool active = active_window != nullptr &&
            std::find(group.windows.begin(), group.windows.end(), active_window) !=
                group.windows.end();
        const bool hot = hovered_kind_ == 6 &&
            hovered_index_ == static_cast<int>(index);
        DrawPanel(
            graphics,
            rect,
            dpi,
            active ? WebSkin::BgActive : hot ? WebSkin::BgHover : WebSkin::BgSecondary,
            active ? WebSkin::Accent : hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
            238);

        HWND representative = RepresentativeWindow(group.windows, active_window);
        const int icon_size = Scale(24, dpi);
        const int icon_x = rect.left + Scale(10, dpi);
        const int icon_y = rect.top + (Height(rect) - icon_size) / 2;
        HICON icon = ResolveWindowIcon(representative);
        if (icon != nullptr)
        {
            (void)DrawIconEx(
                memory_dc,
                icon_x,
                icon_y,
                icon,
                icon_size,
                icon_size,
                0,
                nullptr,
                DI_NORMAL);
        }

        const int text_x = icon != nullptr
            ? icon_x + icon_size + Scale(8, dpi)
            : rect.left + Scale(10, dpi);
        const int reserve = group.windows.size() > 1u
            ? Scale(38, dpi)
            : Scale(10, dpi);
        RECT text_rect{
            text_x,
            rect.top,
            std::max<LONG>(
                static_cast<LONG>(text_x + 1),
                rect.right - static_cast<LONG>(reserve)),
            rect.bottom};
        DrawLeftText(
            graphics,
            Truncate(group.title, 32u),
            normal_font,
            text_rect,
            active ? primary : secondary);

        if (group.windows.size() > 1u)
        {
            const int badge = Scale(22, dpi);
            RECT badge_rect{
                rect.right - badge - Scale(7, dpi),
                rect.top + (Height(rect) - badge) / 2,
                rect.right - Scale(7, dpi),
                rect.top + (Height(rect) - badge) / 2 + badge};
            DrawPanel(
                graphics,
                badge_rect,
                dpi,
                active ? WebSkin::Accent : WebSkin::BgElevated,
                active ? WebSkin::AccentHover : WebSkin::BorderStrong,
                255);
            DrawCenteredText(
                graphics,
                std::to_wstring(group.windows.size()),
                small_font,
                badge_rect,
                primary);
        }
    }

    if (task_overflow_rect_.right > task_overflow_rect_.left)
    {
        const bool hot = hovered_kind_ == 9;
        DrawPanel(
            graphics,
            task_overflow_rect_,
            dpi,
            hot ? WebSkin::BgHover : WebSkin::BgSecondary,
            hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
            235);
        DrawCenteredText(
            graphics,
            L"+" + std::to_wstring(task_groups_.size() - visible_task_group_count_),
            bold_font,
            task_overflow_rect_,
            secondary);
    }

    const bool start_hot = hovered_kind_ == 1;
    DrawPanel(
        graphics,
        start_rect_,
        dpi,
        start_hot ? WebSkin::AccentHover : WebSkin::Accent,
        WebSkin::AccentHover,
        255);
    DrawStartGlyph(graphics, start_rect_, dpi, start_hot);

    for (std::size_t index = 0;
         index < pinned_rects_.size() && index < pinned_items_.size();
         ++index)
    {
        const RECT& rect = pinned_rects_[index];
        const bool hot = hovered_kind_ == 2 &&
            hovered_index_ == static_cast<int>(index);
        if (hot || drag_pin_index_ == static_cast<int>(index))
        {
            RECT hover_rect = rect;
            InflateRect(&hover_rect, Scale(2, dpi), Scale(2, dpi));
            DrawPanel(
                graphics,
                hover_rect,
                dpi,
                drag_pin_index_ == static_cast<int>(index)
                    ? WebSkin::AccentSubtle
                    : WebSkin::BgHover,
                drag_pin_index_ == static_cast<int>(index)
                    ? WebSkin::Accent
                    : WebSkin::BorderStrong,
                235);
        }

        const ShellPinItem& pin = pinned_items_[index];
        const int app_index = pin.kind == ShellPinKind::CloudOSApp
            ? FindCloudApp(pin.id)
            : -1;
        const int icon_size = std::max<int>(18, Width(rect) - Scale(10, dpi));
        const int icon_x = rect.left + (Width(rect) - icon_size) / 2;
        const int icon_y = rect.top + (Height(rect) - icon_size) / 2;
        if (app_index >= 0)
        {
            NativeIconRenderer::DrawAetherSquircle(
                graphics,
                kAllApps[static_cast<std::size_t>(app_index)].icon_id,
                icon_x,
                icon_y,
                icon_size);
        }
        else if (!DrawWindowsPinIcon(memory_dc, pin, icon_x, icon_y, icon_size))
        {
            DrawFallbackIcon(graphics, PinTitle(pin), rect, dpi);
        }
    }

    if (pin_overflow_rect_.right > pin_overflow_rect_.left)
    {
        const bool hot = hovered_kind_ == 7;
        DrawPanel(
            graphics,
            pin_overflow_rect_,
            dpi,
            hot ? WebSkin::BgHover : WebSkin::BgTertiary,
            hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
            235);
        DrawCenteredText(
            graphics,
            L"+" + std::to_wstring(pinned_items_.size() - visible_pin_count_),
            bold_font,
            pin_overflow_rect_,
            secondary);
    }

    const bool quick_hot = hovered_kind_ == 3;
    DrawPanel(
        graphics,
        quick_rect_,
        dpi,
        quick_hot ? WebSkin::BgHover : WebSkin::BgSecondary,
        quick_hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
        220);
    DrawQuickGlyph(graphics, quick_rect_, dpi, quick_hot);

    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power) &&
        power.BatteryFlag != 128 &&
        power.BatteryLifePercent != 255)
    {
        RECT battery_rect{
            quick_rect_.right - Scale(39, dpi),
            quick_rect_.top,
            quick_rect_.right - Scale(3, dpi),
            quick_rect_.bottom};
        DrawCenteredText(
            graphics,
            std::to_wstring(power.BatteryLifePercent) + L"%",
            small_font,
            battery_rect,
            secondary);
    }

    const std::size_t unread = CloudOSNativeNotificationCenter::UnreadCount();
    const bool notification_hot = hovered_kind_ == 4;
    DrawPanel(
        graphics,
        notification_rect_,
        dpi,
        notification_hot ? WebSkin::BgHover : WebSkin::BgSecondary,
        notification_hot ? WebSkin::BorderStrong : WebSkin::BorderDefault,
        220);
    DrawCenteredText(
        graphics,
        unread == 0u ? L"○" : std::to_wstring(unread),
        bold_font,
        notification_rect_,
        unread == 0u ? secondary : primary);

    const bool clock_hot = hovered_kind_ == 5;
    if (clock_hot)
    {
        DrawPanel(
            graphics,
            clock_rect_,
            dpi,
            WebSkin::BgHover,
            WebSkin::BorderStrong,
            225);
    }
    RECT time_rect = clock_rect_;
    time_rect.bottom = time_rect.top + Scale(24, dpi);
    time_rect.top += Scale(3, dpi);
    RECT date_rect = clock_rect_;
    date_rect.top += Scale(23, dpi);
    DrawCenteredText(
        graphics,
        NativeShellPlatform::FormatLocalTime(),
        bold_font,
        time_rect,
        primary);
    DrawCenteredText(
        graphics,
        NativeShellPlatform::FormatLocalDate(false),
        small_font,
        date_rect,
        tertiary);

    BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    EndPaint(window_, &paint);
}

void CloudOSTaskbarAppBar::LaunchPin(const ShellPinItem& pin)
{
    if (pin.kind == ShellPinKind::CloudOSApp)
    {
        const int app_index = FindCloudApp(pin.id);
        if (app_index >= 0)
        {
            NativeAppLauncher::Launch(
                instance_,
                window_,
                kAllApps[static_cast<std::size_t>(app_index)]);
        }
    }
    else if (!pin.target.empty())
    {
        (void)ShellExecuteW(
            window_,
            L"open",
            pin.target.c_str(),
            nullptr,
            nullptr,
            SW_SHOWNORMAL);
    }

    if (window_manager_ != nullptr)
    {
        window_manager_->Reconcile();
    }
    Refresh();
}

void CloudOSTaskbarAppBar::LaunchPinned(std::size_t index)
{
    if (index < pinned_items_.size())
    {
        LaunchPin(pinned_items_[index]);
    }
}

void CloudOSTaskbarAppBar::ShowPinnedContextMenu(
    std::size_t index,
    POINT screen_point)
{
    if (index >= pinned_items_.size())
    {
        return;
    }

    const ShellPinItem pin = pinned_items_[index];
    ShellPinStore& store = ShellPinStore::Instance();
    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    AppendMenuW(menu, MF_STRING, kPinOpen, L"Abrir");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        menu,
        MF_STRING,
        kPinToggleStart,
        store.IsStartPinned(pin) ? L"Desafixar do Iniciar" : L"Fixar no Iniciar");
    AppendMenuW(menu, MF_STRING, kPinRemove, L"Desafixar da barra");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        menu,
        index > 0u ? MF_STRING : MF_STRING | MF_GRAYED,
        kPinMoveLeft,
        L"Mover para a esquerda");
    AppendMenuW(
        menu,
        index + 1u < pinned_items_.size() ? MF_STRING : MF_STRING | MF_GRAYED,
        kPinMoveRight,
        L"Mover para a direita");

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case kPinOpen:
        LaunchPin(pin);
        break;
    case kPinToggleStart:
        store.ToggleStart(pin);
        Refresh();
        break;
    case kPinRemove:
        store.UnpinTaskbar(pin);
        Refresh();
        break;
    case kPinMoveLeft:
        if (index > 0u)
        {
            store.MoveTaskbar(index, index - 1u);
            Refresh();
        }
        break;
    case kPinMoveRight:
        if (index + 1u < pinned_items_.size())
        {
            store.MoveTaskbar(index, index + 1u);
            Refresh();
        }
        break;
    default:
        break;
    }
}

void CloudOSTaskbarAppBar::ShowPinOverflowMenu(POINT screen_point)
{
    if (visible_pin_count_ >= pinned_items_.size())
    {
        return;
    }

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    const std::size_t hidden = std::min<std::size_t>(
        pinned_items_.size() - visible_pin_count_,
        100u);
    for (std::size_t offset = 0; offset < hidden; ++offset)
    {
        const std::size_t index = visible_pin_count_ + offset;
        AppendMenuW(
            menu,
            MF_STRING,
            kOverflowPinBase + static_cast<UINT>(offset),
            PinTitle(pinned_items_[index]).c_str());
    }

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    const int first = static_cast<int>(kOverflowPinBase);
    const int last = first + static_cast<int>(hidden);
    if (command >= first && command < last)
    {
        LaunchPinned(
            visible_pin_count_ + static_cast<std::size_t>(command - first));
    }
}

void CloudOSTaskbarAppBar::MoveTaskToWorkspace(HWND window, int workspace)
{
    if (window_manager_ == nullptr ||
        window == nullptr ||
        !IsWindow(window) ||
        workspace < 0 || workspace > 3)
    {
        return;
    }
    window_manager_->FocusWindow(window);
    window_manager_->MoveActiveToWorkspace(workspace);
}

void CloudOSTaskbarAppBar::CloseTaskGroup(const TaskGroup& group)
{
    for (HWND window : group.windows)
    {
        if (window != nullptr && IsWindow(window))
        {
            PostMessageW(window, WM_CLOSE, 0, 0);
        }
    }
}

void CloudOSTaskbarAppBar::ShowTaskGroupPicker(
    std::size_t index,
    POINT screen_point)
{
    if (index >= task_groups_.size())
    {
        return;
    }

    const TaskGroup group = task_groups_[index];
    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    const std::size_t count = std::min<std::size_t>(group.windows.size(), 100u);
    for (std::size_t item = 0; item < count; ++item)
    {
        std::wstring title = ReadWindowTitle(group.windows[item]);
        if (title.empty())
        {
            title = L"Janela";
        }
        AppendMenuW(
            menu,
            MF_STRING,
            kGroupWindowBase + static_cast<UINT>(item),
            Truncate(std::move(title), 64u).c_str());
    }
    if (group.windows.size() > 1u)
    {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kTaskCloseAll, L"Fechar todas as janelas");
    }

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    const int first = static_cast<int>(kGroupWindowBase);
    const int last = first + static_cast<int>(count);
    if (command >= first && command < last)
    {
        const std::size_t item = static_cast<std::size_t>(command - first);
        if (window_manager_ != nullptr && item < group.windows.size())
        {
            window_manager_->FocusWindow(group.windows[item]);
            Refresh();
        }
    }
    else if (command == static_cast<int>(kTaskCloseAll))
    {
        CloseTaskGroup(group);
    }
}

void CloudOSTaskbarAppBar::ShowTaskOverflowMenu(POINT screen_point)
{
    if (visible_task_group_count_ >= task_groups_.size())
    {
        return;
    }

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    const std::size_t hidden = std::min<std::size_t>(
        task_groups_.size() - visible_task_group_count_,
        100u);
    for (std::size_t offset = 0; offset < hidden; ++offset)
    {
        const TaskGroup& group = task_groups_[visible_task_group_count_ + offset];
        std::wstring label = Truncate(group.title, 54u);
        if (group.windows.size() > 1u)
        {
            label += L"  (" + std::to_wstring(group.windows.size()) + L")";
        }
        AppendMenuW(
            menu,
            MF_STRING,
            kOverflowTaskBase + static_cast<UINT>(offset),
            label.c_str());
    }

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    const int first = static_cast<int>(kOverflowTaskBase);
    const int last = first + static_cast<int>(hidden);
    if (command >= first && command < last)
    {
        const std::size_t index = visible_task_group_count_ +
            static_cast<std::size_t>(command - first);
        ActivateTaskGroup(index);
    }
}

void CloudOSTaskbarAppBar::ActivateTaskGroup(std::size_t index)
{
    if (index >= task_groups_.size() || window_manager_ == nullptr)
    {
        return;
    }

    const TaskGroup& group = task_groups_[index];
    if (group.windows.empty())
    {
        return;
    }

    if (group.windows.size() > 1u)
    {
        POINT point{};
        if (index < task_rects_.size())
        {
            const RECT& rect = task_rects_[index];
            point.x = (rect.left + rect.right) / 2;
            point.y = rect.top;
            ClientToScreen(window_, &point);
        }
        else
        {
            GetCursorPos(&point);
        }
        ShowTaskGroupPicker(index, point);
        return;
    }

    HWND target = group.windows.front();
    if (target == nullptr || !IsWindow(target))
    {
        return;
    }

    if (window_manager_->ActiveManagedWindow() == target && !IsIconic(target))
    {
        ShowWindow(target, SW_MINIMIZE);
    }
    else
    {
        if (IsIconic(target))
        {
            ShowWindow(target, SW_RESTORE);
        }
        window_manager_->FocusWindow(target);
    }
    Refresh();
}

void CloudOSTaskbarAppBar::ShowTaskContextMenu(
    std::size_t index,
    POINT screen_point)
{
    if (index >= task_groups_.size() || window_manager_ == nullptr)
    {
        return;
    }

    const TaskGroup group = task_groups_[index];
    HWND target = RepresentativeWindow(
        group.windows,
        window_manager_->ActiveManagedWindow());
    if (target == nullptr)
    {
        return;
    }

    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    if (group.windows.size() > 1u)
    {
        AppendMenuW(menu, MF_STRING, kTaskChooseWindow, L"Escolher janela...");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    }
    AppendMenuW(menu, MF_STRING, kTaskRestore, L"Restaurar");
    AppendMenuW(menu, MF_STRING, kTaskMinimize, L"Minimizar");
    AppendMenuW(menu, MF_STRING, kTaskMaximize, L"Maximizar");

    HMENU workspace_menu = CreatePopupMenu();
    if (workspace_menu != nullptr)
    {
        AppendMenuW(workspace_menu, MF_STRING, kTaskWorkspace1, L"Area 1");
        AppendMenuW(workspace_menu, MF_STRING, kTaskWorkspace2, L"Area 2");
        AppendMenuW(workspace_menu, MF_STRING, kTaskWorkspace3, L"Area 3");
        AppendMenuW(workspace_menu, MF_STRING, kTaskWorkspace4, L"Area 4");
        AppendMenuW(
            menu,
            MF_POPUP,
            reinterpret_cast<UINT_PTR>(workspace_menu),
            L"Mover para area de trabalho");
    }

    AppendMenuW(menu, MF_STRING, kTaskToggleFloating, L"Alternar modo flutuante");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kTaskClose, L"Fechar janela");
    if (group.windows.size() > 1u)
    {
        AppendMenuW(menu, MF_STRING, kTaskCloseAll, L"Fechar todas");
    }

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screen_point.x,
        screen_point.y,
        0,
        window_,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case kTaskChooseWindow:
        ShowTaskGroupPicker(index, screen_point);
        break;
    case kTaskRestore:
        ShowWindow(target, SW_RESTORE);
        window_manager_->FocusWindow(target);
        break;
    case kTaskMinimize:
        ShowWindow(target, SW_MINIMIZE);
        break;
    case kTaskMaximize:
        ShowWindow(target, SW_MAXIMIZE);
        window_manager_->FocusWindow(target);
        break;
    case kTaskToggleFloating:
    {
        bool floating = false;
        const std::vector<CloudOSManagedWindow> managed =
            window_manager_->AllManagedWindows();
        const auto found = std::find_if(
            managed.begin(),
            managed.end(),
            [target](const CloudOSManagedWindow& item)
            {
                return item.hwnd == target;
            });
        if (found != managed.end())
        {
            floating = found->floating;
        }
        for (HWND grouped : group.windows)
        {
            window_manager_->SetWindowFloating(grouped, !floating);
        }
        break;
    }
    case kTaskWorkspace1:
    case kTaskWorkspace2:
    case kTaskWorkspace3:
    case kTaskWorkspace4:
    {
        const int workspace = command - static_cast<int>(kTaskWorkspace1);
        for (HWND grouped : group.windows)
        {
            MoveTaskToWorkspace(grouped, workspace);
        }
        break;
    }
    case kTaskClose:
        PostMessageW(target, WM_CLOSE, 0, 0);
        break;
    case kTaskCloseAll:
        CloseTaskGroup(group);
        break;
    default:
        break;
    }

    window_manager_->Reconcile();
    Refresh();
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

    if (message == CLOUDOS_WM_TASKBAR_QUERY_HIT)
    {
        auto* query = reinterpret_cast<CloudOSTaskbarHitQuery*>(l_param);
        if (query == nullptr)
        {
            return FALSE;
        }
        query->window = HitTaskWindow(query->client_point, &query->task_rect);
        return query->window != nullptr ? TRUE : FALSE;
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
            (void)TrackMouseEvent(&tracking);
            tracking_mouse_ = true;
        }

        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        if (drag_pin_index_ >= 0 && (w_param & MK_LBUTTON) != 0)
        {
            for (std::size_t index = 0; index < pinned_rects_.size(); ++index)
            {
                if (Contains(pinned_rects_[index], point) &&
                    static_cast<int>(index) != drag_pin_index_)
                {
                    ShellPinStore::Instance().MoveTaskbar(
                        static_cast<std::size_t>(drag_pin_index_),
                        index);
                    drag_pin_index_ = static_cast<int>(index);
                    drag_pin_moved_ = true;
                    ReloadPins();
                    RebuildHitTargets();
                    InvalidateRect(window_, nullptr, FALSE);
                    break;
                }
            }
        }

        const int old_kind = hovered_kind_;
        const int old_index = hovered_index_;
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
        if (Contains(quick_rect_, point))
        {
            hovered_kind_ = 3;
        }
        if (Contains(notification_rect_, point))
        {
            hovered_kind_ = 4;
        }
        if (Contains(clock_rect_, point))
        {
            hovered_kind_ = 5;
        }
        for (std::size_t index = 0; index < task_rects_.size(); ++index)
        {
            if (Contains(task_rects_[index], point))
            {
                hovered_kind_ = 6;
                hovered_index_ = static_cast<int>(index);
                break;
            }
        }
        if (pin_overflow_rect_.right > pin_overflow_rect_.left &&
            Contains(pin_overflow_rect_, point))
        {
            hovered_kind_ = 7;
        }
        for (std::size_t index = 0; index < workspace_rects_.size(); ++index)
        {
            if (Contains(workspace_rects_[index], point))
            {
                hovered_kind_ = 8;
                hovered_index_ = static_cast<int>(index);
                break;
            }
        }
        if (task_overflow_rect_.right > task_overflow_rect_.left &&
            Contains(task_overflow_rect_, point))
        {
            hovered_kind_ = 9;
        }

        if (old_kind != hovered_kind_ || old_index != hovered_index_)
        {
            InvalidateRect(window_, nullptr, FALSE);
        }
        SetCursor(LoadCursorW(nullptr, hovered_kind_ >= 0 ? IDC_HAND : IDC_ARROW));
        return 0;
    }
    case WM_MOUSELEAVE:
        tracking_mouse_ = false;
        hovered_kind_ = -1;
        hovered_index_ = -1;
        InvalidateRect(window_, nullptr, FALSE);
        return 0;
    case WM_LBUTTONDOWN:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        for (std::size_t index = 0; index < pinned_rects_.size(); ++index)
        {
            if (Contains(pinned_rects_[index], point))
            {
                drag_pin_index_ = static_cast<int>(index);
                drag_pin_moved_ = false;
                SetCapture(window_);
                return 0;
            }
        }
        break;
    }
    case WM_LBUTTONUP:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        if (drag_pin_index_ >= 0)
        {
            const int index = drag_pin_index_;
            const bool moved = drag_pin_moved_;
            drag_pin_index_ = -1;
            drag_pin_moved_ = false;
            if (GetCapture() == window_)
            {
                ReleaseCapture();
            }
            if (!moved &&
                index >= 0 &&
                index < static_cast<int>(pinned_items_.size()))
            {
                LaunchPinned(static_cast<std::size_t>(index));
            }
            Refresh();
            return 0;
        }

        const RECT anchor = Bounds();
        if (Contains(start_rect_, point))
        {
            if (on_start_)
            {
                on_start_(anchor);
            }
            return 0;
        }
        if (Contains(quick_rect_, point))
        {
            if (on_quick_settings_)
            {
                on_quick_settings_(anchor);
            }
            return 0;
        }
        if (Contains(notification_rect_, point) || Contains(clock_rect_, point))
        {
            if (on_notifications_)
            {
                on_notifications_(anchor);
            }
            return 0;
        }
        if (pin_overflow_rect_.right > pin_overflow_rect_.left &&
            Contains(pin_overflow_rect_, point))
        {
            POINT screen = point;
            ClientToScreen(window_, &screen);
            ShowPinOverflowMenu(screen);
            return 0;
        }
        if (task_overflow_rect_.right > task_overflow_rect_.left &&
            Contains(task_overflow_rect_, point))
        {
            POINT screen = point;
            ClientToScreen(window_, &screen);
            ShowTaskOverflowMenu(screen);
            return 0;
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
        for (std::size_t index = 0; index < task_rects_.size(); ++index)
        {
            if (Contains(task_rects_[index], point))
            {
                ActivateTaskGroup(index);
                return 0;
            }
        }
        return 0;
    }
    case WM_RBUTTONUP:
    {
        const POINT client_point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        POINT screen_point = client_point;
        ClientToScreen(window_, &screen_point);

        for (std::size_t index = 0; index < pinned_rects_.size(); ++index)
        {
            if (Contains(pinned_rects_[index], client_point))
            {
                ShowPinnedContextMenu(index, screen_point);
                return 0;
            }
        }
        if (pin_overflow_rect_.right > pin_overflow_rect_.left &&
            Contains(pin_overflow_rect_, client_point))
        {
            ShowPinOverflowMenu(screen_point);
            return 0;
        }
        for (std::size_t index = 0; index < task_rects_.size(); ++index)
        {
            if (Contains(task_rects_[index], client_point))
            {
                ShowTaskContextMenu(index, screen_point);
                return 0;
            }
        }
        if (task_overflow_rect_.right > task_overflow_rect_.left &&
            Contains(task_overflow_rect_, client_point))
        {
            ShowTaskOverflowMenu(screen_point);
            return 0;
        }

        NativeAppLauncher::ShowQuickPowerMenu(window_, screen_point);
        return 0;
    }
    case WM_CAPTURECHANGED:
        drag_pin_index_ = -1;
        drag_pin_moved_ = false;
        InvalidateRect(window_, nullptr, FALSE);
        return 0;
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
    auto* self = reinterpret_cast<CloudOSTaskbarAppBar*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSTaskbarAppBar*>(create->lpCreateParams);
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(self));
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
