#include "native_desktop_window.h"

#include "cloudos_native_runtime.h"
#include "native_app_launcher.h"
#include "native_icon_renderer.h"
#include "native_search_engine.h"
#include "native_shell_platform.h"
#include "native_start_menu_mru.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwchar>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.CloudOSDesktop.v20";
constexpr UINT_PTR kSearchSubclassId = 301;
constexpr int kSearchControlId = 501;
constexpr int kStartGridColumns = 4;
constexpr int kStartGridRows = 3;
constexpr int kStartGridCapacity = kStartGridColumns * kStartGridRows;

struct ShellMetrics final
{
    UINT dpi{96};
    int width{};
    int height{};
    int taskbar_height{};
    int taskbar_y{};
    int taskbar_margin{};
    int start_x{};
    int start_y{};
    int start_width{};
    int start_height{};
    int search_x{};
    int search_y{};
    int search_width{};
    int search_height{};
};

ShellMetrics ComputeMetrics(HWND window, int width, int height)
{
    ShellMetrics metrics{};
    metrics.width = std::max(1, width);
    metrics.height = std::max(1, height);
    metrics.dpi = window != nullptr ? GetDpiForWindow(window) : 96u;
    if (metrics.dpi == 0)
    {
        metrics.dpi = 96u;
    }

    metrics.taskbar_height = Scale(kBottomBarHeight, metrics.dpi);
    metrics.taskbar_y = std::max(0, metrics.height - metrics.taskbar_height);
    metrics.taskbar_margin = Scale(10, metrics.dpi);

    const int outer_margin = Scale(18, metrics.dpi);
    const int maximum_start_width = Scale(700, metrics.dpi);
    const int maximum_start_height = Scale(590, metrics.dpi);
    metrics.start_width = std::max(
        1,
        std::min(
            maximum_start_width,
            metrics.width - outer_margin * 2));
    metrics.start_height = std::max(
        1,
        std::min(
            maximum_start_height,
            metrics.taskbar_y - outer_margin * 2));

    metrics.start_x = std::max(outer_margin, (metrics.width - metrics.start_width) / 2);
    metrics.start_y = std::max(
        outer_margin,
        metrics.taskbar_y - metrics.start_height - Scale(12, metrics.dpi));

    metrics.search_x = metrics.start_x + Scale(28, metrics.dpi);
    metrics.search_y = metrics.start_y + Scale(28, metrics.dpi);
    metrics.search_width = std::max(1, metrics.start_width - Scale(56, metrics.dpi));
    metrics.search_height = Scale(38, metrics.dpi);
    return metrics;
}

int FindAppIndex(std::wstring_view id)
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

std::vector<int> BuildIds(std::initializer_list<std::wstring_view> ids)
{
    std::vector<int> result;
    result.reserve(ids.size());
    for (const std::wstring_view id : ids)
    {
        const int index = FindAppIndex(id);
        if (index >= 0)
        {
            result.push_back(index);
        }
    }
    return result;
}

std::vector<int> BuildDesktopShortcuts()
{
    return BuildIds({
        L"files",
        L"projects",
        L"terminal",
        L"drive",
        L"wsl",
        L"settings",
    });
}

std::vector<int> BuildDockApps()
{
    return BuildIds({
        L"files",
        L"terminal",
        L"projects",
        L"browser",
        L"code",
        L"settings",
    });
}

std::vector<int> BuildStartApps(const std::wstring& query)
{
    if (!query.empty())
    {
        return NativeSearchEngine::FilterApps(query);
    }

    return BuildIds({
        L"files",
        L"projects",
        L"terminal",
        L"browser",
        L"drive",
        L"wsl",
        L"code",
        L"notepad",
        L"calc",
        L"sysmon",
        L"apps",
        L"settings",
    });
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

void DrawCenteredText(
    Graphics& graphics,
    const std::wstring& text,
    const Font& font,
    const RectF& rectangle,
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
        rectangle,
        &format,
        &brush);
}

std::wstring CurrentUserName()
{
    std::array<wchar_t, 256> username{};
    DWORD length = static_cast<DWORD>(username.size());
    if (!GetUserNameW(username.data(), &length) || username[0] == L'\0')
    {
        return L"Usuario";
    }
    return username.data();
}

std::wstring FormatPercent(bool available, unsigned int value)
{
    return available ? std::to_wstring(value) + L"%" : L"--";
}

} // namespace

CloudOSNativeDesktopWindow::~CloudOSNativeDesktopWindow()
{
    Destroy();
}

bool CloudOSNativeDesktopWindow::Create(
    HINSTANCE instance,
    CloudOSNativeWindowManager* window_manager)
{
    instance_ = instance;
    window_manager_ = window_manager;
    edit_bg_brush_ = CreateSolidBrush(RGB(29, 31, 36));

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeDesktopWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kDesktopClass;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        kDesktopClass,
        L"CloudOS Desktop",
        WS_POPUP | WS_CLIPCHILDREN,
        0,
        0,
        0,
        0,
        nullptr,
        nullptr,
        instance_,
        this);
    if (hwnd_ == nullptr)
    {
        return false;
    }

    search_edit_ = CreateWindowExW(
        0,
        L"EDIT",
        L"",
        WS_CHILD | ES_LEFT | ES_AUTOHSCROLL,
        0,
        0,
        0,
        0,
        hwnd_,
        reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(kSearchControlId)),
        instance_,
        nullptr);
    if (search_edit_ == nullptr)
    {
        Destroy();
        return false;
    }

    if (!SetWindowSubclass(
            search_edit_,
            &CloudOSNativeDesktopWindow::SearchSubclass,
            kSearchSubclassId,
            reinterpret_cast<DWORD_PTR>(this)))
    {
        Destroy();
        return false;
    }

    SendMessageW(
        search_edit_,
        EM_SETCUEBANNER,
        TRUE,
        reinterpret_cast<LPARAM>(
            L"Pesquisar aplicativos e ferramentas do CloudOS"));

    filtered_indices_ = BuildStartApps(L"");
    current_stats_ = NativeSystemStats::Query();

    DarkWindow(hwnd_, false);
    ShowWindow(search_edit_, SW_HIDE);
    return true;
}

void CloudOSNativeDesktopWindow::Destroy()
{
    if (search_edit_ != nullptr && IsWindow(search_edit_))
    {
        (void)RemoveWindowSubclass(
            search_edit_,
            &CloudOSNativeDesktopWindow::SearchSubclass,
            kSearchSubclassId);
    }

    if (hwnd_ != nullptr && IsWindow(hwnd_))
    {
        DestroyWindow(hwnd_);
    }
    hwnd_ = nullptr;
    search_edit_ = nullptr;

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
}

void CloudOSNativeDesktopWindow::UpdateLayout(const RECT& work_area)
{
    if (hwnd_ == nullptr)
    {
        return;
    }

    const int work_width = std::max(1, Width(work_area));
    const int work_height = std::max(1, Height(work_area));

    SetWindowPos(
        hwnd_,
        HWND_BOTTOM,
        work_area.left,
        work_area.top,
        work_width,
        work_height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);

    const ShellMetrics metrics = ComputeMetrics(
        hwnd_,
        work_width,
        work_height);

    SetWindowPos(
        search_edit_,
        nullptr,
        metrics.search_x,
        metrics.search_y,
        metrics.search_width,
        metrics.search_height,
        SWP_NOZORDER | SWP_NOACTIVATE);

    ShowWindow(
        search_edit_,
        start_menu_open_ ? SW_SHOWNA : SW_HIDE);

    if (search_font_ != nullptr)
    {
        DeleteObject(search_font_);
        search_font_ = nullptr;
    }

    search_font_ = CreateFontW(
        -Scale(14, metrics.dpi),
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI");
    if (search_font_ != nullptr)
    {
        SendMessageW(
            search_edit_,
            WM_SETFONT,
            reinterpret_cast<WPARAM>(search_font_),
            TRUE);
    }
}

void CloudOSNativeDesktopWindow::Redraw()
{
    if (hwnd_ != nullptr)
    {
        InvalidateRect(hwnd_, nullptr, FALSE);
    }
}

void CloudOSNativeDesktopWindow::SetStartMenuOpen(
    bool open,
    bool focus_search)
{
    if (hwnd_ == nullptr || search_edit_ == nullptr)
    {
        return;
    }

    start_menu_open_ = open;
    if (!open)
    {
        SetWindowTextW(search_edit_, L"");
        search_query_.clear();
        filtered_indices_ = BuildStartApps(L"");
        focused_app_index_ = 0;
        ShowWindow(search_edit_, SW_HIDE);
        SetFocus(hwnd_);
        Redraw();
        return;
    }

    RECT client{};
    GetClientRect(hwnd_, &client);
    const ShellMetrics metrics = ComputeMetrics(
        hwnd_,
        Width(client),
        Height(client));

    SetWindowPos(
        search_edit_,
        HWND_TOP,
        metrics.search_x,
        metrics.search_y,
        metrics.search_width,
        metrics.search_height,
        SWP_SHOWWINDOW);
    ShowWindow(search_edit_, SW_SHOW);
    SetForegroundWindow(hwnd_);
    if (focus_search)
    {
        SetFocus(search_edit_);
        SendMessageW(search_edit_, EM_SETSEL, 0, -1);
    }
    Redraw();
}

void CloudOSNativeDesktopWindow::ToggleStartMenu()
{
    SetStartMenuOpen(!start_menu_open_, true);
}

void CloudOSNativeDesktopWindow::FocusSearch()
{
    SetStartMenuOpen(true, true);
}

void CloudOSNativeDesktopWindow::RefreshWorkArea()
{
    RECT work_area{};
    if (SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0))
    {
        UpdateLayout(work_area);
        Redraw();
    }
}

void CloudOSNativeDesktopWindow::OnSearchChanged()
{
    if (search_edit_ == nullptr)
    {
        return;
    }

    std::array<wchar_t, 512> buffer{};
    GetWindowTextW(
        search_edit_,
        buffer.data(),
        static_cast<int>(buffer.size()));

    search_query_ = buffer.data();
    filtered_indices_ = BuildStartApps(search_query_);
    focused_app_index_ = 0;
    Redraw();
}

void CloudOSNativeDesktopWindow::ActivateAppIndex(int app_index)
{
    if (app_index < 0 ||
        app_index >= static_cast<int>(kAllApps.size()))
    {
        return;
    }

    if (on_action_)
    {
        on_action_(app_index + 1);
    }
    else
    {
        NativeAppLauncher::Launch(
            instance_,
            hwnd_,
            kAllApps[static_cast<std::size_t>(app_index)]);
    }
}

void CloudOSNativeDesktopWindow::SelectFocusedApp()
{
    if (filtered_indices_.empty())
    {
        return;
    }

    const int visible_total = std::min(
        static_cast<int>(filtered_indices_.size()),
        kStartGridCapacity);
    if (visible_total <= 0)
    {
        return;
    }

    const int index = std::clamp(
        focused_app_index_,
        0,
        visible_total - 1);
    const int app_index =
        filtered_indices_[static_cast<std::size_t>(index)];

    SetStartMenuOpen(false, false);
    ActivateAppIndex(app_index);
}

bool CloudOSNativeDesktopWindow::IsPointClickable(POINT point) const
{
    if (Contains(start_button_rect_, point) ||
        Contains(desktop_status_rect_, point) ||
        Contains(system_button_rect_, point) ||
        Contains(clock_rect_, point) ||
        Contains(power_button_rect_, point))
    {
        return true;
    }

    for (const RECT& rectangle : quick_launch_rects_)
    {
        if (Contains(rectangle, point))
        {
            return true;
        }
    }

    for (const RECT& rectangle : dock_rects_)
    {
        if (Contains(rectangle, point))
        {
            return true;
        }
    }

    for (const RECT& rectangle : workspace_rects_)
    {
        if (Contains(rectangle, point))
        {
            return true;
        }
    }

    for (const TaskHit& hit : task_hits_)
    {
        if (Contains(hit.bounds, point))
        {
            return true;
        }
    }

    if (start_menu_open_)
    {
        const std::size_t visible_apps = std::min(
            app_grid_rects_.size(),
            static_cast<std::size_t>(kStartGridCapacity));
        for (std::size_t index = 0; index < visible_apps; ++index)
        {
            if (Contains(app_grid_rects_[index], point))
            {
                return true;
            }
        }
    }

    return false;
}

void CloudOSNativeDesktopWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(hwnd_, &paint);

    RECT client{};
    GetClientRect(hwnd_, &client);
    const int width = Width(client);
    const int height = Height(client);
    if (width <= 0 || height <= 0)
    {
        EndPaint(hwnd_, &paint);
        return;
    }

    HDC device = CreateCompatibleDC(screen_dc);
    HBITMAP memory_bitmap =
        CreateCompatibleBitmap(screen_dc, width, height);
    if (device == nullptr || memory_bitmap == nullptr)
    {
        if (memory_bitmap != nullptr)
        {
            DeleteObject(memory_bitmap);
        }
        if (device != nullptr)
        {
            DeleteDC(device);
        }
        EndPaint(hwnd_, &paint);
        return;
    }

    HGDIOBJ old_bitmap = SelectObject(device, memory_bitmap);

    Graphics graphics(device);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    const ShellMetrics metrics = ComputeMetrics(hwnd_, width, height);
    const UINT dpi = metrics.dpi;

    LinearGradientBrush wallpaper(
        PointF(0.0f, 0.0f),
        PointF(
            static_cast<float>(width),
            static_cast<float>(height)),
        Color(255, 17, 20, 29),
        Color(255, 8, 11, 17));
    graphics.FillRectangle(
        &wallpaper,
        RectF(
            0.0f,
            0.0f,
            static_cast<float>(width),
            static_cast<float>(height)));

    SolidBrush wallpaper_light(Color(26, 88, 150, 235));
    SolidBrush wallpaper_shadow(Color(24, 58, 72, 98));
    graphics.FillEllipse(
        &wallpaper_light,
        static_cast<float>(width - Scale(760, dpi)),
        static_cast<float>(-Scale(280, dpi)),
        static_cast<float>(Scale(850, dpi)),
        static_cast<float>(Scale(650, dpi)));
    graphics.FillEllipse(
        &wallpaper_shadow,
        static_cast<float>(-Scale(260, dpi)),
        static_cast<float>(height - Scale(520, dpi)),
        static_cast<float>(Scale(700, dpi)),
        static_cast<float>(Scale(600, dpi)));

    Pen grid_pen(Color(16, 255, 255, 255), 1.0f);
    const int grid_step = std::max(Scale(72, dpi), 24);
    for (int x = 0; x < width; x += grid_step)
    {
        graphics.DrawLine(
            &grid_pen,
            static_cast<REAL>(x),
            0.0f,
            static_cast<REAL>(x),
            static_cast<REAL>(metrics.taskbar_y));
    }
    for (int y = 0; y < metrics.taskbar_y; y += grid_step)
    {
        graphics.DrawLine(
            &grid_pen,
            0.0f,
            static_cast<REAL>(y),
            static_cast<REAL>(width),
            static_cast<REAL>(y));
    }

    Font brand_font(
        L"Segoe UI Variable Display",
        static_cast<REAL>(Scale(24, dpi)),
        FontStyleBold,
        UnitPixel);
    Font title_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(15, dpi)),
        FontStyleBold,
        UnitPixel);
    Font section_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(11, dpi)),
        FontStyleBold,
        UnitPixel);
    Font body_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(10, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font small_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(9, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font small_bold_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(9, dpi)),
        FontStyleBold,
        UnitPixel);

    SolidBrush white(Color(255, 245, 247, 250));
    SolidBrush secondary(Color(255, 194, 199, 208));
    SolidBrush muted(Color(255, 139, 146, 158));
    SolidBrush accent_soft(Color(255, 150, 193, 252));

    const int workspace =
        window_manager_ != nullptr
            ? window_manager_->CurrentWorkspace() + 1
            : 1;

    graphics.DrawString(
        L"CloudOS",
        -1,
        &brand_font,
        PointF(
            static_cast<float>(Scale(24, dpi)),
            static_cast<float>(Scale(20, dpi))),
        &white);

    std::wstring session_line =
        L"Desktop  ·  Workspace " +
        std::to_wstring(workspace);
    graphics.DrawString(
        session_line.c_str(),
        -1,
        &small_font,
        PointF(
            static_cast<float>(Scale(26, dpi)),
            static_cast<float>(Scale(54, dpi))),
        &secondary);

    quick_launch_rects_.clear();
    quick_launch_app_indices_ = BuildDesktopShortcuts();

    const int desktop_left = Scale(20, dpi);
    const int desktop_top = Scale(92, dpi);
    const int shortcut_width = Scale(92, dpi);
    const int shortcut_height = Scale(86, dpi);
    const int shortcut_gap = Scale(8, dpi);
    const int shortcut_icon = Scale(44, dpi);

    for (std::size_t index = 0;
         index < quick_launch_app_indices_.size();
         ++index)
    {
        const int app_index = quick_launch_app_indices_[index];
        const int row = static_cast<int>(index);
        const int x = desktop_left;
        const int y = desktop_top + row * (shortcut_height + shortcut_gap);

        const RECT hit{
            x,
            y,
            x + shortcut_width,
            y + shortcut_height,
        };
        quick_launch_rects_.push_back(hit);

        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            x + (shortcut_width - shortcut_icon) / 2,
            y + Scale(4, dpi),
            shortcut_icon);

        DrawCenteredText(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].name,
            small_font,
            RectF(
                static_cast<float>(x),
                static_cast<float>(y + Scale(52, dpi)),
                static_cast<float>(shortcut_width),
                static_cast<float>(Scale(28, dpi))),
            white);
    }

    const int status_width = Scale(250, dpi);
    const int status_height = Scale(64, dpi);
    const int status_x = width - status_width - Scale(20, dpi);
    const int status_y = Scale(20, dpi);
    desktop_status_rect_ = RECT{
        status_x,
        status_y,
        status_x + status_width,
        status_y + status_height,
    };

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(status_x),
            static_cast<float>(status_y),
            static_cast<float>(status_width),
            static_cast<float>(status_height)),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 5
            ? Color(235, 37, 40, 47)
            : Color(220, 27, 30, 36),
        Color(100, 89, 95, 108),
        1.0f);

    std::wstring cpu =
        FormatPercent(
            current_stats_.cpu_available,
            current_stats_.cpu_percent);
    std::wstring ram =
        FormatPercent(
            current_stats_.ram_available,
            current_stats_.ram_percent);

    graphics.DrawString(
        L"SISTEMA",
        -1,
        &small_bold_font,
        PointF(
            static_cast<float>(status_x + Scale(16, dpi)),
            static_cast<float>(status_y + Scale(10, dpi))),
        &muted);

    std::wstring system_line =
        L"CPU " + cpu + L"   RAM " + ram +
        L"   W" + std::to_wstring(workspace);
    graphics.DrawString(
        system_line.c_str(),
        -1,
        &body_font,
        PointF(
            static_cast<float>(status_x + Scale(16, dpi)),
            static_cast<float>(status_y + Scale(32, dpi))),
        &white);

    const int taskbar_x = metrics.taskbar_margin;
    const int taskbar_y = metrics.taskbar_y + Scale(5, dpi);
    const int taskbar_width = width - metrics.taskbar_margin * 2;
    const int taskbar_height = metrics.taskbar_height - Scale(10, dpi);

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(taskbar_x),
            static_cast<float>(taskbar_y),
            static_cast<float>(taskbar_width),
            static_cast<float>(taskbar_height)),
        static_cast<float>(Scale(17, dpi)),
        Color(238, 24, 26, 31),
        Color(120, 71, 76, 86),
        1.0f);

    workspace_rects_.fill(RECT{});
    int workspace_x = taskbar_x + Scale(14, dpi);
    for (int index = 0; index < 4; ++index)
    {
        const int button_width = Scale(28, dpi);
        const int button_height = Scale(28, dpi);
        const int button_y =
            taskbar_y + (taskbar_height - button_height) / 2;
        const RECT hit{
            workspace_x,
            button_y,
            workspace_x + button_width,
            button_y + button_height,
        };
        workspace_rects_[static_cast<std::size_t>(index)] = hit;

        const bool active =
            window_manager_ != nullptr &&
            window_manager_->CurrentWorkspace() == index;

        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(hit.left),
                static_cast<float>(hit.top),
                static_cast<float>(Width(hit)),
                static_cast<float>(Height(hit))),
            static_cast<float>(Scale(9, dpi)),
            active
                ? Color(255, 68, 113, 170)
                : Color(115, 38, 40, 47),
            active
                ? Color(220, 120, 181, 255)
                : Color(65, 100, 105, 114),
            1.0f);

        DrawCenteredText(
            graphics,
            std::to_wstring(index + 1),
            small_bold_font,
            RectF(
                static_cast<float>(hit.left),
                static_cast<float>(hit.top),
                static_cast<float>(Width(hit)),
                static_cast<float>(Height(hit))),
            active ? white : secondary);

        workspace_x += Scale(34, dpi);
    }

    task_hits_.clear();
    if (window_manager_ != nullptr)
    {
        const std::vector<CloudOSManagedWindow> windows =
            window_manager_->CurrentWorkspaceWindows();

        const int task_start = workspace_x + Scale(8, dpi);
        const int task_limit = std::max(
            task_start,
            width / 2 - Scale(220, dpi));
        const int available = std::max(0, task_limit - task_start);
        const int task_width = Scale(112, dpi);
        const int task_gap = Scale(6, dpi);
        const int capacity =
            available > 0
                ? available / std::max(1, task_width + task_gap)
                : 0;
        const int task_count = std::min(
            static_cast<int>(windows.size()),
            std::min(3, capacity));

        int task_x = task_start;
        for (int index = 0; index < task_count; ++index)
        {
            const CloudOSManagedWindow& managed =
                windows[static_cast<std::size_t>(index)];
            const int task_h = Scale(30, dpi);
            const int task_y =
                taskbar_y + (taskbar_height - task_h) / 2;
            const RECT hit{
                task_x,
                task_y,
                task_x + task_width,
                task_y + task_h,
            };
            task_hits_.push_back(TaskHit{managed.hwnd, hit});

            const bool active =
                window_manager_->ActiveManagedWindow() ==
                managed.hwnd;
            NativeIconRenderer::DrawGlassPanel(
                graphics,
                RectF(
                    static_cast<float>(hit.left),
                    static_cast<float>(hit.top),
                    static_cast<float>(Width(hit)),
                    static_cast<float>(Height(hit))),
                static_cast<float>(Scale(9, dpi)),
                active
                    ? Color(210, 51, 57, 68)
                    : Color(105, 38, 40, 47),
                active
                    ? Color(180, 103, 165, 246)
                    : Color(60, 92, 97, 108),
                1.0f);

            DrawCenteredText(
                graphics,
                Shorten(
                    managed.title.empty()
                        ? L"Aplicativo"
                        : managed.title,
                    18),
                small_font,
                RectF(
                    static_cast<float>(hit.left + Scale(6, dpi)),
                    static_cast<float>(hit.top),
                    static_cast<float>(Width(hit) - Scale(12, dpi)),
                    static_cast<float>(Height(hit))),
                active ? white : secondary);

            task_x += task_width + task_gap;
        }
    }

    dock_app_indices_ = BuildDockApps();
    dock_rects_.clear();

    const int start_size = Scale(36, dpi);
    const int icon_size = Scale(34, dpi);
    const int icon_gap = Scale(8, dpi);
    const int center_cluster_width =
        start_size +
        Scale(12, dpi) +
        static_cast<int>(dock_app_indices_.size()) *
            (icon_size + icon_gap) -
        (dock_app_indices_.empty() ? 0 : icon_gap);

    int center_x = (width - center_cluster_width) / 2;
    const int center_y =
        taskbar_y + (taskbar_height - start_size) / 2;

    start_button_rect_ = RECT{
        center_x,
        center_y,
        center_x + start_size,
        center_y + start_size,
    };

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(start_button_rect_.left),
            static_cast<float>(start_button_rect_.top),
            static_cast<float>(Width(start_button_rect_)),
            static_cast<float>(Height(start_button_rect_))),
        static_cast<float>(Scale(11, dpi)),
        start_menu_open_ || hovered_widget_id_ == 1
            ? Color(255, 64, 105, 160)
            : Color(150, 39, 42, 49),
        start_menu_open_
            ? Color(230, 126, 184, 255)
            : Color(80, 103, 165, 246),
        1.0f);

    const int logo_inset = Scale(9, dpi);
    SolidBrush logo_brush(Color(255, 235, 240, 247));
    graphics.FillRectangle(
        &logo_brush,
        static_cast<float>(start_button_rect_.left + logo_inset),
        static_cast<float>(start_button_rect_.top + logo_inset),
        static_cast<float>(Scale(7, dpi)),
        static_cast<float>(Scale(7, dpi)));
    graphics.FillRectangle(
        &logo_brush,
        static_cast<float>(start_button_rect_.left + logo_inset + Scale(9, dpi)),
        static_cast<float>(start_button_rect_.top + logo_inset),
        static_cast<float>(Scale(7, dpi)),
        static_cast<float>(Scale(7, dpi)));
    graphics.FillRectangle(
        &logo_brush,
        static_cast<float>(start_button_rect_.left + logo_inset),
        static_cast<float>(start_button_rect_.top + logo_inset + Scale(9, dpi)),
        static_cast<float>(Scale(7, dpi)),
        static_cast<float>(Scale(7, dpi)));
    graphics.FillRectangle(
        &logo_brush,
        static_cast<float>(start_button_rect_.left + logo_inset + Scale(9, dpi)),
        static_cast<float>(start_button_rect_.top + logo_inset + Scale(9, dpi)),
        static_cast<float>(Scale(7, dpi)),
        static_cast<float>(Scale(7, dpi)));

    center_x += start_size + Scale(12, dpi);
    for (std::size_t index = 0;
         index < dock_app_indices_.size();
         ++index)
    {
        const int app_index = dock_app_indices_[index];
        const int icon_y =
            taskbar_y + (taskbar_height - icon_size) / 2;
        const RECT hit{
            center_x,
            icon_y,
            center_x + icon_size,
            icon_y + icon_size,
        };
        dock_rects_.push_back(hit);

        if (hovered_dock_id_ == static_cast<int>(index))
        {
            NativeIconRenderer::DrawGlassPanel(
                graphics,
                RectF(
                    static_cast<float>(hit.left - Scale(3, dpi)),
                    static_cast<float>(hit.top - Scale(3, dpi)),
                    static_cast<float>(Width(hit) + Scale(6, dpi)),
                    static_cast<float>(Height(hit) + Scale(6, dpi))),
                static_cast<float>(Scale(10, dpi)),
                Color(185, 48, 51, 59),
                Color(80, 110, 174, 250),
                1.0f);
        }

        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            hit.left,
            hit.top,
            icon_size);

        center_x += icon_size + icon_gap;
    }

    const int right_area = Scale(300, dpi);
    const int right_x = width - metrics.taskbar_margin - right_area;
    const int tray_y = taskbar_y + Scale(8, dpi);
    const int tray_height = std::max(
        Scale(30, dpi),
        taskbar_height - Scale(16, dpi));

    system_button_rect_ = RECT{
        right_x,
        tray_y,
        right_x + Scale(156, dpi),
        tray_y + tray_height,
    };
    clock_rect_ = RECT{
        right_x + Scale(160, dpi),
        tray_y,
        width - metrics.taskbar_margin - Scale(8, dpi),
        tray_y + tray_height,
    };

    if (hovered_widget_id_ == 2)
    {
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(system_button_rect_.left),
                static_cast<float>(system_button_rect_.top),
                static_cast<float>(Width(system_button_rect_)),
                static_cast<float>(Height(system_button_rect_))),
            static_cast<float>(Scale(9, dpi)),
            Color(170, 46, 49, 57),
            Color(70, 103, 165, 246),
            1.0f);
    }

    std::wstring tray_system =
        L"CPU " + cpu + L"  RAM " + ram;
    DrawCenteredText(
        graphics,
        tray_system,
        small_font,
        RectF(
            static_cast<float>(system_button_rect_.left),
            static_cast<float>(system_button_rect_.top),
            static_cast<float>(Width(system_button_rect_)),
            static_cast<float>(Height(system_button_rect_))),
        secondary);

    if (hovered_widget_id_ == 3)
    {
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(clock_rect_.left),
                static_cast<float>(clock_rect_.top),
                static_cast<float>(Width(clock_rect_)),
                static_cast<float>(Height(clock_rect_))),
            static_cast<float>(Scale(9, dpi)),
            Color(170, 46, 49, 57),
            Color(70, 103, 165, 246),
            1.0f);
    }

    std::wstring clock_text =
        NativeShellPlatform::FormatLocalTime() +
        L"   " +
        NativeShellPlatform::FormatLocalDate(false);
    DrawCenteredText(
        graphics,
        clock_text,
        small_bold_font,
        RectF(
            static_cast<float>(clock_rect_.left),
            static_cast<float>(clock_rect_.top),
            static_cast<float>(Width(clock_rect_)),
            static_cast<float>(Height(clock_rect_))),
        white);

    app_grid_rects_.clear();
    start_menu_rect_ = RECT{};
    power_button_rect_ = RECT{};

    if (start_menu_open_)
    {
        start_menu_rect_ = RECT{
            metrics.start_x,
            metrics.start_y,
            metrics.start_x + metrics.start_width,
            metrics.start_y + metrics.start_height,
        };

        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(metrics.start_x),
                static_cast<float>(metrics.start_y),
                static_cast<float>(metrics.start_width),
                static_cast<float>(metrics.start_height)),
            static_cast<float>(Scale(22, dpi)),
            Color(248, 26, 28, 33),
            Color(145, 72, 77, 88),
            1.2f);

        const int content_x = metrics.start_x + Scale(28, dpi);
        const int content_width =
            metrics.start_width - Scale(56, dpi);
        const int grid_top =
            metrics.search_y + metrics.search_height + Scale(30, dpi);

        graphics.DrawString(
            search_query_.empty()
                ? L"Fixados"
                : L"Resultados",
            -1,
            &section_font,
            PointF(
                static_cast<float>(content_x),
                static_cast<float>(
                    grid_top - Scale(24, dpi))),
            &white);

        const int grid_gap = Scale(10, dpi);
        const int item_width = std::max(
            Scale(90, dpi),
            (content_width - grid_gap * (kStartGridColumns - 1)) /
                kStartGridColumns);
        const int item_height = Scale(86, dpi);
        const int grid_icon = Scale(38, dpi);
        const std::size_t visible_count = std::min(
            filtered_indices_.size(),
            static_cast<std::size_t>(kStartGridCapacity));

        for (std::size_t slot = 0;
             slot < visible_count;
             ++slot)
        {
            const int column =
                static_cast<int>(slot % kStartGridColumns);
            const int row =
                static_cast<int>(slot / kStartGridColumns);
            const int x =
                content_x +
                column * (item_width + grid_gap);
            const int y =
                grid_top +
                row * (item_height + Scale(6, dpi));

            const RECT hit{
                x,
                y,
                x + item_width,
                y + item_height,
            };
            app_grid_rects_.push_back(hit);

            const bool hovered =
                hovered_app_index_ ==
                static_cast<int>(slot);
            const bool focused =
                focused_app_index_ ==
                static_cast<int>(slot) &&
                GetFocus() == search_edit_;

            if (hovered || focused)
            {
                NativeIconRenderer::DrawGlassPanel(
                    graphics,
                    RectF(
                        static_cast<float>(hit.left),
                        static_cast<float>(hit.top),
                        static_cast<float>(Width(hit)),
                        static_cast<float>(Height(hit))),
                    static_cast<float>(Scale(13, dpi)),
                    Color(205, 47, 51, 60),
                    focused
                        ? Color(170, 103, 165, 246)
                        : Color(75, 91, 97, 108),
                    1.0f);
            }

            const int app_index =
                filtered_indices_[slot];
            NativeIconRenderer::DrawAetherSquircle(
                graphics,
                kAllApps[
                    static_cast<std::size_t>(app_index)].icon_id,
                x + (item_width - grid_icon) / 2,
                y + Scale(6, dpi),
                grid_icon);

            DrawCenteredText(
                graphics,
                kAllApps[
                    static_cast<std::size_t>(app_index)].name,
                small_font,
                RectF(
                    static_cast<float>(x + Scale(4, dpi)),
                    static_cast<float>(y + Scale(50, dpi)),
                    static_cast<float>(item_width - Scale(8, dpi)),
                    static_cast<float>(Scale(28, dpi))),
                hovered || focused ? white : secondary);
        }

        if (visible_count == 0)
        {
            graphics.DrawString(
                L"Nenhum aplicativo encontrado.",
                -1,
                &body_font,
                PointF(
                    static_cast<float>(content_x),
                    static_cast<float>(
                        grid_top + Scale(32, dpi))),
                &secondary);
        }

        const int grid_bottom =
            grid_top +
            kStartGridRows *
                (item_height + Scale(6, dpi));
        const int footer_height = Scale(58, dpi);
        const int footer_y =
            metrics.start_y +
            metrics.start_height -
            footer_height;

        if (search_query_.empty() &&
            grid_bottom + Scale(84, dpi) < footer_y)
        {
            const int recent_y =
                grid_bottom + Scale(10, dpi);
            graphics.DrawString(
                L"Recentes",
                -1,
                &section_font,
                PointF(
                    static_cast<float>(content_x),
                    static_cast<float>(recent_y)),
                &white);

            const std::vector<std::wstring> recent_ids =
                StartMenuMRUTracker::Instance().GetTopApps(3);
            int recent_line = 0;
            for (const std::wstring& id : recent_ids)
            {
                const int app_index = FindAppIndex(id);
                if (app_index < 0)
                {
                    continue;
                }

                const AppItem& app =
                    kAllApps[
                        static_cast<std::size_t>(app_index)];
                const std::uint32_t launches =
                    StartMenuMRUTracker::Instance().GetLaunchCount(
                        app.id);

                std::wstring line = app.name;
                line += L"  ·  ";
                line += std::to_wstring(launches);
                line += launches == 1
                    ? L" abertura"
                    : L" aberturas";

                graphics.DrawString(
                    line.c_str(),
                    -1,
                    &small_font,
                    PointF(
                        static_cast<float>(content_x),
                        static_cast<float>(
                            recent_y +
                            Scale(25 + recent_line * 20, dpi))),
                    recent_line == 0
                        ? &accent_soft
                        : &secondary);

                if (++recent_line >= 3)
                {
                    break;
                }
            }

            if (recent_line == 0)
            {
                graphics.DrawString(
                    L"Os aplicativos usados aparecem aqui.",
                    -1,
                    &small_font,
                    PointF(
                        static_cast<float>(content_x),
                        static_cast<float>(
                            recent_y + Scale(25, dpi))),
                    &muted);
            }
        }

        Pen footer_line(Color(75, 110, 114, 124), 1.0f);
        graphics.DrawLine(
            &footer_line,
            static_cast<REAL>(metrics.start_x + Scale(18, dpi)),
            static_cast<REAL>(footer_y),
            static_cast<REAL>(
                metrics.start_x +
                metrics.start_width -
                Scale(18, dpi)),
            static_cast<REAL>(footer_y));

        const std::wstring username = CurrentUserName();
        graphics.DrawString(
            username.c_str(),
            -1,
            &small_bold_font,
            PointF(
                static_cast<float>(
                    content_x + Scale(36, dpi)),
                static_cast<float>(
                    footer_y + Scale(18, dpi))),
            &white);

        const int avatar_size = Scale(28, dpi);
        const int avatar_x = content_x;
        const int avatar_y =
            footer_y +
            (footer_height - avatar_size) / 2;
        SolidBrush avatar(Color(255, 72, 109, 160));
        graphics.FillEllipse(
            &avatar,
            static_cast<float>(avatar_x),
            static_cast<float>(avatar_y),
            static_cast<float>(avatar_size),
            static_cast<float>(avatar_size));

        std::wstring initial(
            1,
            username.empty() ? L'C' : username[0]);
        DrawCenteredText(
            graphics,
            initial,
            small_bold_font,
            RectF(
                static_cast<float>(avatar_x),
                static_cast<float>(avatar_y),
                static_cast<float>(avatar_size),
                static_cast<float>(avatar_size)),
            white);

        const bool tiling =
            window_manager_ != nullptr &&
            window_manager_->TilingEnabled();
        std::wstring shell_state =
            tiling
                ? L"Tiling ativo"
                : L"Tiling manual";
        shell_state += L"  ·  ABI ";
        shell_state +=
            std::to_wstring(cloudos_native_runtime_abi());

        DrawCenteredText(
            graphics,
            shell_state,
            small_font,
            RectF(
                static_cast<float>(
                    metrics.start_x +
                    metrics.start_width / 2 -
                    Scale(110, dpi)),
                static_cast<float>(
                    footer_y + Scale(14, dpi)),
                static_cast<float>(Scale(220, dpi)),
                static_cast<float>(Scale(30, dpi))),
            muted);

        const int power_size = Scale(34, dpi);
        const int power_x =
            metrics.start_x +
            metrics.start_width -
            Scale(28, dpi) -
            power_size;
        const int power_y =
            footer_y +
            (footer_height - power_size) / 2;
        power_button_rect_ = RECT{
            power_x,
            power_y,
            power_x + power_size,
            power_y + power_size,
        };

        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(power_x),
                static_cast<float>(power_y),
                static_cast<float>(power_size),
                static_cast<float>(power_size)),
            static_cast<float>(Scale(10, dpi)),
            hovered_widget_id_ == 4
                ? Color(220, 69, 48, 51)
                : Color(130, 42, 44, 51),
            Color(80, 134, 88, 95),
            1.0f);

        DrawCenteredText(
            graphics,
            L"\x23FB",
            title_font,
            RectF(
                static_cast<float>(power_x),
                static_cast<float>(power_y - Scale(1, dpi)),
                static_cast<float>(power_size),
                static_cast<float>(power_size)),
            white);
    }

    BitBlt(
        screen_dc,
        0,
        0,
        width,
        height,
        device,
        0,
        0,
        SRCCOPY);

    SelectObject(device, old_bitmap);
    DeleteObject(memory_bitmap);
    DeleteDC(device);
    EndPaint(hwnd_, &paint);
}

LRESULT CloudOSNativeDesktopWindow::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_PAINT:
        Paint();
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_CTLCOLOREDIT:
        if (reinterpret_cast<HWND>(l_param) == search_edit_)
        {
            HDC edit_dc = reinterpret_cast<HDC>(w_param);
            SetTextColor(edit_dc, RGB(245, 247, 250));
            SetBkColor(edit_dc, RGB(29, 31, 36));
            return reinterpret_cast<LRESULT>(edit_bg_brush_);
        }
        break;

    case WM_COMMAND:
        if (LOWORD(w_param) == kSearchControlId &&
            HIWORD(w_param) == EN_CHANGE)
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
        if (w_param == kReconcileTimer)
        {
            if (on_timer_)
            {
                on_timer_();
            }
            Redraw();
            return 0;
        }
        break;

    case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
        if (window_manager_ != nullptr)
        {
            window_manager_->HandleRuntimeEvent(
                static_cast<cloudos_native_window_event_kind>(
                    w_param),
                reinterpret_cast<HWND>(l_param));
        }
        Redraw();
        return 0;

    case WM_HOTKEY:
        if (on_hotkey_)
        {
            on_hotkey_(static_cast<int>(w_param));
        }
        return 0;

    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
        RefreshWorkArea();
        return 0;

    case WM_SETTINGCHANGE:
        if (w_param == SPI_SETWORKAREA)
        {
            RefreshWorkArea();
            return 0;
        }
        break;

    case WM_MOUSEMOVE:
    {
        const POINT point{
            GET_X_LPARAM(l_param),
            GET_Y_LPARAM(l_param),
        };

        if (!tracking_mouse_)
        {
            TRACKMOUSEEVENT tracking{
                sizeof(tracking),
                TME_LEAVE,
                hwnd_,
                0,
            };
            TrackMouseEvent(&tracking);
            tracking_mouse_ = true;
        }

        const int previous_app = hovered_app_index_;
        const int previous_widget = hovered_widget_id_;
        const int previous_dock = hovered_dock_id_;

        hovered_app_index_ = -1;
        hovered_widget_id_ = -1;
        hovered_dock_id_ = -1;

        if (start_menu_open_)
        {
            const std::size_t visible_apps = std::min(
                app_grid_rects_.size(),
                static_cast<std::size_t>(kStartGridCapacity));
            for (std::size_t index = 0;
                 index < visible_apps;
                 ++index)
            {
                if (Contains(app_grid_rects_[index], point))
                {
                    hovered_app_index_ =
                        static_cast<int>(index);
                    break;
                }
            }
        }

        if (Contains(start_button_rect_, point))
        {
            hovered_widget_id_ = 1;
        }
        else if (Contains(desktop_status_rect_, point))
        {
            hovered_widget_id_ = 5;
        }
        else if (Contains(system_button_rect_, point))
        {
            hovered_widget_id_ = 2;
        }
        else if (Contains(clock_rect_, point))
        {
            hovered_widget_id_ = 3;
        }
        else if (Contains(power_button_rect_, point))
        {
            hovered_widget_id_ = 4;
        }

        for (std::size_t index = 0;
             index < dock_rects_.size();
             ++index)
        {
            if (Contains(dock_rects_[index], point))
            {
                hovered_dock_id_ =
                    static_cast<int>(index);
                break;
            }
        }

        SetCursor(
            LoadCursorW(
                nullptr,
                IsPointClickable(point)
                    ? IDC_HAND
                    : IDC_ARROW));

        if (previous_app != hovered_app_index_ ||
            previous_widget != hovered_widget_id_ ||
            previous_dock != hovered_dock_id_)
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
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
        Redraw();
        return 0;

    case WM_LBUTTONUP:
    {
        const POINT point{
            GET_X_LPARAM(l_param),
            GET_Y_LPARAM(l_param),
        };

        if (Contains(start_button_rect_, point))
        {
            ToggleStartMenu();
            return 0;
        }

        if (start_menu_open_)
        {
            const std::size_t visible_apps = std::min(
                app_grid_rects_.size(),
                filtered_indices_.size());
            for (std::size_t index = 0;
                 index < visible_apps;
                 ++index)
            {
                if (Contains(app_grid_rects_[index], point))
                {
                    const int app_index =
                        filtered_indices_[index];
                    SetStartMenuOpen(false, false);
                    ActivateAppIndex(app_index);
                    return 0;
                }
            }

            if (Contains(power_button_rect_, point))
            {
                POINT screen_point = point;
                ClientToScreen(hwnd_, &screen_point);
                NativeAppLauncher::ShowQuickPowerMenu(
                    hwnd_,
                    screen_point);
                return 0;
            }
        }

        if (Contains(desktop_status_rect_, point) ||
            Contains(system_button_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"sysmon");
            return 0;
        }

        if (Contains(clock_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"datetime");
            return 0;
        }

        for (std::size_t index = 0;
             index < quick_launch_rects_.size() &&
             index < quick_launch_app_indices_.size();
             ++index)
        {
            if (Contains(quick_launch_rects_[index], point))
            {
                SetStartMenuOpen(false, false);
                ActivateAppIndex(
                    quick_launch_app_indices_[index]);
                return 0;
            }
        }

        for (std::size_t index = 0;
             index < dock_rects_.size() &&
             index < dock_app_indices_.size();
             ++index)
        {
            if (Contains(dock_rects_[index], point))
            {
                SetStartMenuOpen(false, false);
                ActivateAppIndex(
                    dock_app_indices_[index]);
                return 0;
            }
        }

        for (std::size_t index = 0;
             index < workspace_rects_.size();
             ++index)
        {
            if (Contains(workspace_rects_[index], point))
            {
                if (window_manager_ != nullptr)
                {
                    window_manager_->SwitchWorkspace(
                        static_cast<int>(index));
                    SetStartMenuOpen(false, false);
                    Redraw();
                }
                return 0;
            }
        }

        for (const TaskHit& hit : task_hits_)
        {
            if (Contains(hit.bounds, point))
            {
                if (window_manager_ != nullptr)
                {
                    window_manager_->FocusWindow(hit.window);
                    SetStartMenuOpen(false, false);
                    Redraw();
                }
                return 0;
            }
        }

        if (start_menu_open_ &&
            !Contains(start_menu_rect_, point))
        {
            SetStartMenuOpen(false, false);
            return 0;
        }

        SetWindowPos(
            hwnd_,
            HWND_BOTTOM,
            0,
            0,
            0,
            0,
            SWP_NOMOVE |
                SWP_NOSIZE |
                SWP_NOACTIVATE);
        return 0;
    }

    case WM_RBUTTONUP:
    {
        POINT point{
            GET_X_LPARAM(l_param),
            GET_Y_LPARAM(l_param),
        };
        ClientToScreen(hwnd_, &point);
        NativeAppLauncher::ShowQuickPowerMenu(
            hwnd_,
            point);
        return 0;
    }

    case WM_DESTROY:
        hwnd_ = nullptr;
        search_edit_ = nullptr;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(
        window,
        message,
        w_param,
        l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::SearchSubclass(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data)
{
    (void)subclass_id;

    auto* self =
        reinterpret_cast<CloudOSNativeDesktopWindow*>(
            reference_data);
    if (self != nullptr &&
        message == WM_KEYDOWN)
    {
        if (w_param == VK_RETURN)
        {
            self->SelectFocusedApp();
            return 0;
        }

        if (w_param == VK_ESCAPE)
        {
            self->SetStartMenuOpen(false, false);
            return 0;
        }

        if (w_param == VK_LEFT ||
            w_param == VK_RIGHT ||
            w_param == VK_UP ||
            w_param == VK_DOWN)
        {
            const int total = std::min(
                static_cast<int>(
                    self->filtered_indices_.size()),
                kStartGridCapacity);
            if (total > 0)
            {
                if (w_param == VK_RIGHT)
                {
                    self->focused_app_index_ =
                        (self->focused_app_index_ + 1) %
                        total;
                }
                else if (w_param == VK_LEFT)
                {
                    self->focused_app_index_ =
                        (self->focused_app_index_ - 1 + total) %
                        total;
                }
                else if (w_param == VK_DOWN)
                {
                    self->focused_app_index_ =
                        std::min(
                            self->focused_app_index_ +
                                kStartGridColumns,
                            total - 1);
                }
                else
                {
                    self->focused_app_index_ =
                        std::max(
                            self->focused_app_index_ -
                                kStartGridColumns,
                            0);
                }
                self->Redraw();
            }
            return 0;
        }
    }

    return DefSubclassProc(
        window,
        message,
        w_param,
        l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeDesktopWindow* self =
        reinterpret_cast<CloudOSNativeDesktopWindow*>(
            GetWindowLongPtrW(
                window,
                GWLP_USERDATA));

    if (message == WM_NCCREATE)
    {
        const auto* create =
            reinterpret_cast<const CREATESTRUCTW*>(
                l_param);
        self =
            static_cast<CloudOSNativeDesktopWindow*>(
                create->lpCreateParams);
        if (self == nullptr)
        {
            return FALSE;
        }

        self->hwnd_ = window;
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(self));
        return TRUE;
    }

    return self != nullptr
        ? self->HandleMessage(
            window,
            message,
            w_param,
            l_param)
        : DefWindowProcW(
            window,
            message,
            w_param,
            l_param);
}

} // namespace CloudOS
