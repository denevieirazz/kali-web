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
#include <string>
#include <string_view>
#include <vector>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.CloudOSDesktop.v19";
constexpr UINT_PTR kSearchSubclassId = 301;
constexpr int kSearchControlId = 501;
constexpr int kBaseDashboardWidth = 1060;
constexpr int kBaseDashboardHeight = 650;

struct LayoutMetrics final
{
    UINT dpi{96};
    int width{};
    int height{};
    int dash_x{};
    int dash_y{};
    int dash_width{};
    int dash_height{};
    int bar_height{};
    int bar_y{};
    int search_x{};
    int search_y{};
    int search_width{};
    int search_height{};
};

UINT ComputeLayoutDpi(HWND window, int width, int height)
{
    UINT actual_dpi = window != nullptr ? GetDpiForWindow(window) : 96u;
    if (actual_dpi == 0)
    {
        actual_dpi = 96u;
    }

    const int actual_bar_height = Scale(kBottomBarHeight, actual_dpi);
    const int available_width = std::max(1, width - Scale(24, actual_dpi));
    const int available_height =
        std::max(1, height - actual_bar_height - Scale(24, actual_dpi));

    const UINT width_fit = static_cast<UINT>(
        std::max(72, available_width * 96 / kBaseDashboardWidth));
    const UINT height_fit = static_cast<UINT>(
        std::max(72, available_height * 96 / kBaseDashboardHeight));

    return std::max<UINT>(
        72u,
        std::min(actual_dpi, std::min(width_fit, height_fit)));
}

LayoutMetrics ComputeMetrics(HWND window, int width, int height)
{
    LayoutMetrics metrics{};
    metrics.width = width;
    metrics.height = height;
    metrics.dpi = ComputeLayoutDpi(window, width, height);
    metrics.dash_width = Scale(kBaseDashboardWidth, metrics.dpi);
    metrics.dash_height = Scale(kBaseDashboardHeight, metrics.dpi);
    metrics.bar_height = Scale(kBottomBarHeight, metrics.dpi);
    metrics.bar_y = std::max(0, height - metrics.bar_height);
    metrics.dash_x = std::max(0, (width - metrics.dash_width) / 2);
    metrics.dash_y = std::max(
        Scale(8, metrics.dpi),
        (metrics.bar_y - metrics.dash_height) / 2);

    metrics.search_x = metrics.dash_x + Scale(280, metrics.dpi);
    metrics.search_y = metrics.dash_y + Scale(31, metrics.dpi);
    metrics.search_width = Scale(330, metrics.dpi);
    metrics.search_height = Scale(27, metrics.dpi);
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

std::vector<int> BuildQuickLaunchIndices()
{
    std::vector<int> result;
    result.reserve(6);

    const auto append_unique = [&result](int app_index)
    {
        if (app_index < 0)
        {
            return;
        }
        if (std::find(result.begin(), result.end(), app_index) == result.end())
        {
            result.push_back(app_index);
        }
    };

    for (const std::wstring& id :
         StartMenuMRUTracker::Instance().GetTopApps(6))
    {
        append_unique(FindAppIndex(id));
        if (result.size() >= 6)
        {
            return result;
        }
    }

    constexpr std::array<std::wstring_view, 6> fallback_ids{{
        L"terminal",
        L"projects",
        L"files",
        L"code",
        L"sysmon",
        L"settings",
    }};
    for (const std::wstring_view id : fallback_ids)
    {
        append_unique(FindAppIndex(id));
        if (result.size() >= 6)
        {
            break;
        }
    }

    return result;
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
    edit_bg_brush_ = CreateSolidBrush(RGB(24, 34, 58));

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

    // ToolWindow keeps the shell surface out of Alt+Tab. It remains activatable
    // when the user intentionally clicks the search field.
    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        kDesktopClass,
        L"CloudOS Native Desktop",
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
        WS_CHILD | WS_VISIBLE | ES_LEFT | ES_AUTOHSCROLL,
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
            L"Pesquisar apps, arquivos e configuracoes..."));

    filtered_indices_ = NativeSearchEngine::FilterApps(L"");
    current_stats_ = NativeSystemStats::Query();

    DarkWindow(hwnd_, false);
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

    const LayoutMetrics metrics =
        ComputeMetrics(hwnd_, work_width, work_height);

    SetWindowPos(
        search_edit_,
        nullptr,
        metrics.search_x,
        metrics.search_y,
        metrics.search_width,
        metrics.search_height,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);

    if (search_font_ != nullptr)
    {
        DeleteObject(search_font_);
        search_font_ = nullptr;
    }
    search_font_ = CreateFontW(
        -Scale(13, metrics.dpi),
        0,
        0,
        0,
        FW_MEDIUM,
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

void CloudOSNativeDesktopWindow::FocusSearch()
{
    if (hwnd_ == nullptr || search_edit_ == nullptr)
    {
        return;
    }

    SetForegroundWindow(hwnd_);
    SetFocus(search_edit_);
    SendMessageW(search_edit_, EM_SETSEL, 0, -1);
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
    filtered_indices_ =
        NativeSearchEngine::FilterApps(search_query_);
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

    const int index = std::clamp(
        focused_app_index_,
        0,
        static_cast<int>(filtered_indices_.size()) - 1);
    ActivateAppIndex(
        filtered_indices_[static_cast<std::size_t>(index)]);
}

bool CloudOSNativeDesktopWindow::IsPointClickable(POINT point) const
{
    const std::size_t visible_apps =
        std::min(app_grid_rects_.size(), filtered_indices_.size());
    for (std::size_t index = 0; index < visible_apps; ++index)
    {
        if (Contains(app_grid_rects_[index], point))
        {
            return true;
        }
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

    return
        Contains(profile_rect_, point) ||
        Contains(weather_rect_, point) ||
        Contains(calendar_rect_, point) ||
        Contains(perf_rect_, point) ||
        Contains(news_rect_, point);
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

    const LayoutMetrics metrics =
        ComputeMetrics(hwnd_, width, height);
    const UINT dpi = metrics.dpi;

    LinearGradientBrush background(
        PointF(0.0f, 0.0f),
        PointF(0.0f, static_cast<float>(height)),
        Color(255, 10, 14, 26),
        Color(255, 4, 6, 12));
    graphics.FillRectangle(
        &background,
        RectF(
            0.0f,
            0.0f,
            static_cast<float>(width),
            static_cast<float>(height)));

    SolidBrush cyan_glow(Color(24, 56, 189, 248));
    SolidBrush purple_glow(Color(20, 168, 85, 247));
    graphics.FillEllipse(
        &cyan_glow,
        static_cast<float>(width / 2 - Scale(470, dpi)),
        static_cast<float>(height / 2 - Scale(360, dpi)),
        static_cast<float>(Scale(940, dpi)),
        static_cast<float>(Scale(720, dpi)));
    graphics.FillEllipse(
        &purple_glow,
        static_cast<float>(width - Scale(560, dpi)),
        static_cast<float>(Scale(20, dpi)),
        static_cast<float>(Scale(620, dpi)),
        static_cast<float>(Scale(520, dpi)));

    const RectF main_glass(
        static_cast<float>(metrics.dash_x),
        static_cast<float>(metrics.dash_y),
        static_cast<float>(metrics.dash_width),
        static_cast<float>(metrics.dash_height));
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        main_glass,
        static_cast<float>(Scale(26, dpi)),
        Color(214, 15, 23, 40),
        Color(170, 56, 189, 248),
        1.4f);

    Font title_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(17, dpi)),
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
    Font micro_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(8, dpi)),
        FontStyleRegular,
        UnitPixel);
    Font micro_bold_font(
        L"Segoe UI",
        static_cast<REAL>(Scale(8, dpi)),
        FontStyleBold,
        UnitPixel);

    SolidBrush white(Color(255, 255, 255, 255));
    SolidBrush cyan(Color(255, 56, 189, 248));
    SolidBrush secondary(Color(255, 180, 200, 230));
    SolidBrush muted(Color(255, 120, 145, 180));
    SolidBrush green(Color(255, 52, 211, 153));

    graphics.DrawString(
        L"CloudOS",
        -1,
        &title_font,
        PointF(
            static_cast<float>(
                metrics.dash_x + Scale(34, dpi)),
            static_cast<float>(
                metrics.dash_y + Scale(31, dpi))),
        &white);
    graphics.DrawString(
        L"AETHER NATIVE DESKTOP",
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                metrics.dash_x + Scale(34, dpi)),
            static_cast<float>(
                metrics.dash_y + Scale(53, dpi))),
        &cyan);

    const RectF search_panel(
        static_cast<float>(
            metrics.search_x - Scale(38, dpi)),
        static_cast<float>(
            metrics.search_y - Scale(5, dpi)),
        static_cast<float>(
            metrics.search_width + Scale(120, dpi)),
        static_cast<float>(
            metrics.search_height + Scale(10, dpi)));
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        search_panel,
        static_cast<float>(Scale(18, dpi)),
        Color(170, 24, 34, 58),
        search_query_.empty()
            ? Color(90, 56, 189, 248)
            : Color(220, 56, 189, 248),
        1.2f);
    graphics.DrawString(
        L"BUSCAR",
        -1,
        &micro_bold_font,
        PointF(
            search_panel.X + static_cast<float>(Scale(10, dpi)),
            search_panel.Y + static_cast<float>(Scale(10, dpi))),
        &muted);
    graphics.DrawString(
        L"Enter abre  |  setas navegam",
        -1,
        &micro_font,
        PointF(
            search_panel.X + search_panel.Width - static_cast<float>(Scale(150, dpi)),
            search_panel.Y + static_cast<float>(Scale(10, dpi))),
        &muted);

    const int grid_left =
        metrics.dash_x + Scale(32, dpi);
    const int grid_top =
        metrics.dash_y + Scale(88, dpi);
    const int item_width = Scale(102, dpi);
    const int item_height = Scale(98, dpi);
    const int icon_size = Scale(52, dpi);
    constexpr int columns = 6;

    app_grid_rects_.clear();
    const std::size_t visible_count =
        std::min<std::size_t>(18, filtered_indices_.size());

    for (std::size_t slot = 0; slot < 18; ++slot)
    {
        const int column =
            static_cast<int>(slot % columns);
        const int row =
            static_cast<int>(slot / columns);
        const int x =
            grid_left +
            column * (item_width + Scale(4, dpi));
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

        if (slot >= visible_count)
        {
            continue;
        }

        const int app_index = filtered_indices_[slot];
        const AppItem& app =
            kAllApps[static_cast<std::size_t>(app_index)];
        const bool hovered =
            hovered_app_index_ == static_cast<int>(slot);
        const bool focused =
            !search_query_.empty() &&
            focused_app_index_ == static_cast<int>(slot);

        if (hovered || focused)
        {
            NativeIconRenderer::DrawGlassPanel(
                graphics,
                RectF(
                    static_cast<float>(x + Scale(3, dpi)),
                    static_cast<float>(y - Scale(2, dpi)),
                    static_cast<float>(
                        item_width - Scale(6, dpi)),
                    static_cast<float>(
                        item_height + Scale(4, dpi))),
                static_cast<float>(Scale(15, dpi)),
                Color(95, 56, 189, 248),
                Color(210, 56, 189, 248),
                1.0f);
        }

        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            app.icon_id,
            x + (item_width - icon_size) / 2,
            y,
            icon_size);

        DrawCenteredText(
            graphics,
            app.name,
            micro_font,
            RectF(
                static_cast<float>(x),
                static_cast<float>(
                    y + icon_size + Scale(5, dpi)),
                static_cast<float>(item_width),
                static_cast<float>(Scale(30, dpi))),
            hovered ? white : secondary);
    }

    if (visible_count == 0)
    {
        graphics.DrawString(
            L"Nenhum aplicativo encontrado.",
            -1,
            &body_font,
            PointF(
                static_cast<float>(grid_left),
                static_cast<float>(
                    grid_top + Scale(130, dpi))),
            &muted);
    }

    const int activity_y =
        metrics.dash_y + Scale(447, dpi);
    graphics.DrawString(
        L"ATIVIDADE RECENTE",
        -1,
        &section_font,
        PointF(
            static_cast<float>(
                metrics.dash_x + Scale(34, dpi)),
            static_cast<float>(activity_y)),
        &muted);

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
            kAllApps[static_cast<std::size_t>(app_index)];
        const std::uint32_t launches =
            StartMenuMRUTracker::Instance().GetLaunchCount(app.id);

        std::wstring line = app.name;
        line += L"  ·  ";
        line += std::to_wstring(launches);
        line += launches == 1 ? L" abertura" : L" aberturas";

        graphics.DrawString(
            line.c_str(),
            -1,
            &micro_font,
            PointF(
                static_cast<float>(
                    metrics.dash_x + Scale(34, dpi)),
                static_cast<float>(
                    activity_y +
                    Scale(24 + recent_line * 18, dpi))),
            recent_line == 0 ? &cyan : &secondary);

        if (++recent_line >= 3)
        {
            break;
        }
    }

    if (recent_line == 0)
    {
        graphics.DrawString(
            L"A atividade aparece aqui conforme os apps forem usados.",
            -1,
            &micro_font,
            PointF(
                static_cast<float>(
                    metrics.dash_x + Scale(34, dpi)),
                static_cast<float>(
                    activity_y + Scale(24, dpi))),
            &secondary);
    }

    graphics.DrawString(
        L"ACESSO RAPIDO",
        -1,
        &section_font,
        PointF(
            static_cast<float>(
                metrics.dash_x + Scale(365, dpi)),
            static_cast<float>(activity_y)),
        &muted);

    quick_launch_rects_.clear();
    quick_launch_app_indices_ = BuildQuickLaunchIndices();
    int quick_x =
        metrics.dash_x + Scale(365, dpi);
    for (const int app_index : quick_launch_app_indices_)
    {
        if (app_index < 0 ||
            app_index >= static_cast<int>(kAllApps.size()))
        {
            continue;
        }

        const int size = Scale(31, dpi);
        const RECT hit{
            quick_x,
            activity_y + Scale(22, dpi),
            quick_x + size,
            activity_y + Scale(22, dpi) + size,
        };
        quick_launch_rects_.push_back(hit);

        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            quick_x,
            activity_y + Scale(22, dpi),
            size);
        quick_x += Scale(39, dpi);
    }

    const int sidebar_x =
        metrics.dash_x + Scale(714, dpi);
    const int sidebar_width = Scale(312, dpi);
    int widget_y =
        metrics.dash_y + Scale(24, dpi);

    profile_rect_ = RECT{
        sidebar_x,
        widget_y,
        sidebar_x + sidebar_width,
        widget_y + Scale(64, dpi),
    };
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(profile_rect_.left),
            static_cast<float>(profile_rect_.top),
            static_cast<float>(Width(profile_rect_)),
            static_cast<float>(Height(profile_rect_))),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 1
            ? Color(205, 36, 48, 78)
            : Color(165, 24, 34, 58),
        Color(85, 56, 189, 248),
        1.0f);

    std::array<wchar_t, 256> username{};
    DWORD username_length =
        static_cast<DWORD>(username.size());
    if (!GetUserNameW(
            username.data(),
            &username_length))
    {
        wcscpy_s(
            username.data(),
            username.size(),
            L"Usuario");
    }

    const float avatar_size =
        static_cast<float>(Scale(40, dpi));
    const float avatar_x =
        static_cast<float>(
            sidebar_x + Scale(12, dpi));
    const float avatar_y =
        static_cast<float>(
            widget_y + Scale(12, dpi));
    LinearGradientBrush avatar_brush(
        PointF(avatar_x, avatar_y),
        PointF(
            avatar_x + avatar_size,
            avatar_y + avatar_size),
        Color(255, 56, 189, 248),
        Color(255, 168, 85, 247));
    graphics.FillEllipse(
        &avatar_brush,
        avatar_x,
        avatar_y,
        avatar_size,
        avatar_size);

    wchar_t initial[2]{
        username[0] != L'\0' ? username[0] : L'C',
        L'\0',
    };
    DrawCenteredText(
        graphics,
        initial,
        section_font,
        RectF(
            avatar_x,
            avatar_y,
            avatar_size,
            avatar_size),
        white);

    graphics.DrawString(
        username.data(),
        -1,
        &section_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(62, dpi)),
            static_cast<float>(
                widget_y + Scale(13, dpi))),
        &white);
    graphics.DrawString(
        L"Sessao local ativa  ·  clique para energia",
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(62, dpi)),
            static_cast<float>(
                widget_y + Scale(36, dpi))),
        &secondary);

    widget_y += Scale(74, dpi);

    weather_rect_ = RECT{
        sidebar_x,
        widget_y,
        sidebar_x + sidebar_width,
        widget_y + Scale(70, dpi),
    };
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(weather_rect_.left),
            static_cast<float>(weather_rect_.top),
            static_cast<float>(Width(weather_rect_)),
            static_cast<float>(Height(weather_rect_))),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 2
            ? Color(205, 36, 48, 78)
            : Color(165, 24, 34, 58),
        Color(85, 56, 189, 248),
        1.0f);
    graphics.DrawString(
        L"CLIMA",
        -1,
        &micro_bold_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(10, dpi))),
        &muted);
    graphics.DrawString(
        L"Abrir previsao local",
        -1,
        &section_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(31, dpi))),
        &white);
    graphics.DrawString(
        L"Nenhuma temperatura e inventada pelo shell.",
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(50, dpi))),
        &secondary);

    widget_y += Scale(80, dpi);

    calendar_rect_ = RECT{
        sidebar_x,
        widget_y,
        sidebar_x + sidebar_width,
        widget_y + Scale(76, dpi),
    };
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(calendar_rect_.left),
            static_cast<float>(calendar_rect_.top),
            static_cast<float>(Width(calendar_rect_)),
            static_cast<float>(Height(calendar_rect_))),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 3
            ? Color(205, 36, 48, 78)
            : Color(165, 24, 34, 58),
        Color(85, 56, 189, 248),
        1.0f);

    const std::wstring local_time = NativeShellPlatform::FormatLocalTime();
    const std::wstring long_date =
        Shorten(NativeShellPlatform::FormatLocalDate(true), 34);
    graphics.DrawString(
        L"DATA E HORA",
        -1,
        &micro_bold_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(9, dpi))),
        &muted);
    graphics.DrawString(
        local_time.c_str(),
        -1,
        &section_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(29, dpi))),
        &cyan);
    graphics.DrawString(
        long_date.c_str(),
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(82, dpi)),
            static_cast<float>(
                widget_y + Scale(31, dpi))),
        &white);
    graphics.DrawString(
        L"Clique para abrir as configuracoes de data e hora.",
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(52, dpi))),
        &secondary);

    widget_y += Scale(86, dpi);

    perf_rect_ = RECT{
        sidebar_x,
        widget_y,
        sidebar_x + sidebar_width,
        widget_y + Scale(96, dpi),
    };
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(perf_rect_.left),
            static_cast<float>(perf_rect_.top),
            static_cast<float>(Width(perf_rect_)),
            static_cast<float>(Height(perf_rect_))),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 4
            ? Color(205, 36, 48, 78)
            : Color(165, 24, 34, 58),
        Color(85, 56, 189, 248),
        1.0f);
    graphics.DrawString(
        L"DESEMPENHO  ·  clique para detalhes",
        -1,
        &micro_bold_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(10, dpi))),
        &muted);

    std::wstring cpu_text =
        current_stats_.cpu_available
            ? std::to_wstring(current_stats_.cpu_percent) + L"%"
            : L"--";
    std::wstring ram_text =
        current_stats_.ram_available
            ? std::to_wstring(current_stats_.ram_percent) + L"%"
            : L"--";
    std::wstring disk_text =
        current_stats_.disk_available
            ? std::to_wstring(current_stats_.disk_free_gb) + L" GB livres"
            : L"--";

    std::wstring performance_line =
        L"CPU " + cpu_text +
        L"   RAM " + ram_text +
        L"   Disco " + disk_text;
    graphics.DrawString(
        performance_line.c_str(),
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(34, dpi))),
        &white);

    const float bar_width =
        static_cast<float>(
            sidebar_width - Scale(28, dpi));
    const float bar_y =
        static_cast<float>(
            widget_y + Scale(60, dpi));
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            bar_y,
            bar_width,
            static_cast<float>(Scale(7, dpi))),
        static_cast<float>(Scale(3, dpi)),
        Color(255, 30, 41, 59),
        Color(0, 0, 0, 0),
        0.0f);

    if (current_stats_.cpu_available)
    {
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(
                    sidebar_x + Scale(14, dpi)),
                bar_y,
                bar_width *
                    (current_stats_.cpu_percent / 100.0f),
                static_cast<float>(Scale(7, dpi))),
            static_cast<float>(Scale(3, dpi)),
            Color(255, 56, 189, 248),
            Color(255, 168, 85, 247),
            0.8f);
    }

    if (current_stats_.ram_available)
    {
        std::wstring memory_line =
            std::to_wstring(current_stats_.ram_used_mb / 1024ull) +
            L" / " +
            std::to_wstring(current_stats_.ram_total_mb / 1024ull) +
            L" GB RAM";
        graphics.DrawString(
            memory_line.c_str(),
            -1,
            &micro_font,
            PointF(
                static_cast<float>(
                    sidebar_x + Scale(14, dpi)),
                static_cast<float>(
                    widget_y + Scale(78, dpi))),
            &secondary);
    }

    widget_y += Scale(106, dpi);

    news_rect_ = RECT{
        sidebar_x,
        widget_y,
        sidebar_x + sidebar_width,
        widget_y + Scale(118, dpi),
    };
    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(news_rect_.left),
            static_cast<float>(news_rect_.top),
            static_cast<float>(Width(news_rect_)),
            static_cast<float>(Height(news_rect_))),
        static_cast<float>(Scale(16, dpi)),
        hovered_widget_id_ == 5
            ? Color(205, 36, 48, 78)
            : Color(165, 24, 34, 58),
        Color(85, 56, 189, 248),
        1.0f);

    const unsigned int runtime_abi =
        cloudos_native_runtime_abi();
    const std::size_t managed_windows =
        window_manager_ != nullptr
            ? window_manager_->ManagedWindowCount()
            : 0u;
    const int workspace =
        window_manager_ != nullptr
            ? window_manager_->CurrentWorkspace() + 1
            : 1;
    const bool tiling =
        window_manager_ != nullptr &&
        window_manager_->TilingEnabled();

    graphics.DrawString(
        L"STATUS NATIVO  ·  clique para diagnostico",
        -1,
        &micro_bold_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(10, dpi))),
        &muted);

    wchar_t runtime_line[160]{};
    swprintf_s(
        runtime_line,
        L"Runtime ABI %u  |  Workspace %d  |  HWNDs %llu",
        runtime_abi,
        workspace,
        static_cast<unsigned long long>(managed_windows));
    graphics.DrawString(
        runtime_line,
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(36, dpi))),
        &white);

    std::wstring tiling_line =
        L"Tiling: ";
    tiling_line += tiling ? L"ativo" : L"manual";
    tiling_line += L"   |   Uptime Windows: ";
    tiling_line +=
        current_stats_.uptime_str.empty()
            ? L"--"
            : current_stats_.uptime_str;
    graphics.DrawString(
        tiling_line.c_str(),
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(58, dpi))),
        &secondary);
    graphics.DrawString(
        L"ConPTY, WSL e integracoes podem ser verificados no Doctor.",
        -1,
        &micro_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(82, dpi))),
        &secondary);
    graphics.DrawString(
        L"Runtime nativo ativo",
        -1,
        &micro_bold_font,
        PointF(
            static_cast<float>(
                sidebar_x + Scale(14, dpi)),
            static_cast<float>(
                widget_y + Scale(101, dpi))),
        &green);

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            0.0f,
            static_cast<float>(metrics.bar_y),
            static_cast<float>(width),
            static_cast<float>(metrics.bar_height)),
        0.0f,
        Color(238, 8, 12, 20),
        Color(100, 45, 90, 140),
        1.0f);

    graphics.DrawString(
        L"CloudOS",
        -1,
        &section_font,
        PointF(
            static_cast<float>(Scale(18, dpi)),
            static_cast<float>(
                metrics.bar_y + Scale(13, dpi))),
        &cyan);

    workspace_rects_.fill(RECT{});
    int workspace_x = Scale(92, dpi);
    for (int index = 0; index < 4; ++index)
    {
        const int button_size = Scale(25, dpi);
        workspace_rects_[static_cast<std::size_t>(index)] = RECT{
            workspace_x,
            metrics.bar_y + Scale(9, dpi),
            workspace_x + button_size,
            metrics.bar_y + Scale(9, dpi) + button_size,
        };

        const bool active =
            window_manager_ != nullptr &&
            window_manager_->CurrentWorkspace() == index;
        NativeIconRenderer::DrawGlassPanel(
            graphics,
            RectF(
                static_cast<float>(workspace_x),
                static_cast<float>(
                    metrics.bar_y + Scale(9, dpi)),
                static_cast<float>(button_size),
                static_cast<float>(button_size)),
            static_cast<float>(Scale(7, dpi)),
            active
                ? Color(180, 56, 189, 248)
                : Color(120, 24, 34, 58),
            active
                ? Color(255, 56, 189, 248)
                : Color(90, 45, 90, 140),
            1.0f);

        DrawCenteredText(
            graphics,
            std::to_wstring(index + 1),
            micro_bold_font,
            RectF(
                static_cast<float>(workspace_x),
                static_cast<float>(
                    metrics.bar_y + Scale(9, dpi)),
                static_cast<float>(button_size),
                static_cast<float>(button_size)),
            active ? white : secondary);

        workspace_x += Scale(31, dpi);
    }

    const int dock_width = Scale(224, dpi);
    const int dock_height = Scale(36, dpi);
    const int dock_x = (width - dock_width) / 2;
    const int dock_y =
        metrics.bar_y +
        (metrics.bar_height - dock_height) / 2;

    NativeIconRenderer::DrawGlassPanel(
        graphics,
        RectF(
            static_cast<float>(dock_x),
            static_cast<float>(dock_y),
            static_cast<float>(dock_width),
            static_cast<float>(dock_height)),
        static_cast<float>(Scale(12, dpi)),
        Color(180, 24, 34, 58),
        Color(120, 56, 189, 248),
        1.0f);

    dock_rects_.clear();
    dock_app_indices_.clear();
    constexpr std::array<std::wstring_view, 5> dock_ids{{
        L"terminal",
        L"projects",
        L"files",
        L"code",
        L"apps",
    }};
    int dock_icon_x =
        dock_x + Scale(14, dpi);
    for (const std::wstring_view id : dock_ids)
    {
        const int app_index = FindAppIndex(id);
        if (app_index < 0)
        {
            continue;
        }

        const int icon_size = Scale(28, dpi);
        dock_rects_.push_back(RECT{
            dock_icon_x,
            dock_y + Scale(4, dpi),
            dock_icon_x + icon_size,
            dock_y + Scale(4, dpi) + icon_size,
        });
        dock_app_indices_.push_back(app_index);
        NativeIconRenderer::DrawAetherSquircle(
            graphics,
            kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            dock_icon_x,
            dock_y + Scale(4, dpi),
            icon_size);
        dock_icon_x += Scale(39, dpi);
    }

    task_hits_.clear();
    if (window_manager_ != nullptr)
    {
        const std::vector<CloudOSManagedWindow> windows =
            window_manager_->CurrentWorkspaceWindows();
        const int task_start = Scale(235, dpi);
        const int task_end =
            std::max(task_start, dock_x - Scale(18, dpi));
        const int available =
            std::max(0, task_end - task_start);
        const int task_width = Scale(126, dpi);
        const int task_gap = Scale(6, dpi);
        const int capacity =
            std::max(
                0,
                available /
                    std::max(1, task_width + task_gap));
        const int task_count =
            std::min(
                static_cast<int>(windows.size()),
                std::min(4, capacity));

        int task_x = task_start;
        for (int index = 0; index < task_count; ++index)
        {
            const CloudOSManagedWindow& managed =
                windows[static_cast<std::size_t>(index)];
            const RECT hit{
                task_x,
                metrics.bar_y + Scale(7, dpi),
                task_x + task_width,
                metrics.bar_y + metrics.bar_height - Scale(7, dpi),
            };
            task_hits_.push_back(
                TaskHit{managed.hwnd, hit});

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
                static_cast<float>(Scale(8, dpi)),
                active
                    ? Color(150, 36, 64, 92)
                    : Color(110, 24, 34, 58),
                active
                    ? Color(230, 56, 189, 248)
                    : Color(70, 45, 90, 140),
                1.0f);

            DrawCenteredText(
                graphics,
                Shorten(
                    managed.title.empty()
                        ? L"Aplicativo"
                        : managed.title,
                    22),
                micro_font,
                RectF(
                    static_cast<float>(
                        hit.left + Scale(5, dpi)),
                    static_cast<float>(hit.top),
                    static_cast<float>(
                        Width(hit) - Scale(10, dpi)),
                    static_cast<float>(Height(hit))),
                active ? white : secondary);

            task_x += task_width + task_gap;
        }
    }

    const std::wstring clock_text =
        NativeShellPlatform::FormatLocalTime() + L"  |  " +
        NativeShellPlatform::FormatLocalDate(false);
    StringFormat right_align;
    right_align.SetAlignment(StringAlignmentFar);
    graphics.DrawString(
        clock_text.c_str(),
        -1,
        &micro_bold_font,
        RectF(
            static_cast<float>(
                width - Scale(300, dpi)),
            static_cast<float>(
                metrics.bar_y + Scale(9, dpi)),
            static_cast<float>(Scale(282, dpi)),
            static_cast<float>(
                metrics.bar_height - Scale(10, dpi))),
        &right_align,
        &secondary);

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
    case WM_CTLCOLORSTATIC:
        if (reinterpret_cast<HWND>(l_param) == search_edit_)
        {
            HDC edit_dc =
                reinterpret_cast<HDC>(w_param);
            SetTextColor(
                edit_dc,
                RGB(255, 255, 255));
            SetBkColor(
                edit_dc,
                RGB(24, 34, 58));
            return reinterpret_cast<LRESULT>(
                edit_bg_brush_);
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
            current_stats_ =
                NativeSystemStats::Query();
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
            on_hotkey_(
                static_cast<int>(w_param));
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

        const int previous_app =
            hovered_app_index_;
        const int previous_widget =
            hovered_widget_id_;
        const int previous_dock =
            hovered_dock_id_;

        hovered_app_index_ = -1;
        hovered_widget_id_ = -1;
        hovered_dock_id_ = -1;

        const std::size_t visible_apps =
            std::min(
                app_grid_rects_.size(),
                filtered_indices_.size());
        for (std::size_t index = 0;
             index < visible_apps;
             ++index)
        {
            if (Contains(
                    app_grid_rects_[index],
                    point))
            {
                hovered_app_index_ =
                    static_cast<int>(index);
                break;
            }
        }

        if (Contains(profile_rect_, point))
        {
            hovered_widget_id_ = 1;
        }
        else if (Contains(weather_rect_, point))
        {
            hovered_widget_id_ = 2;
        }
        else if (Contains(calendar_rect_, point))
        {
            hovered_widget_id_ = 3;
        }
        else if (Contains(perf_rect_, point))
        {
            hovered_widget_id_ = 4;
        }
        else if (Contains(news_rect_, point))
        {
            hovered_widget_id_ = 5;
        }

        for (std::size_t index = 0;
             index < dock_rects_.size();
             ++index)
        {
            if (Contains(
                    dock_rects_[index],
                    point))
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

        const std::size_t visible_apps =
            std::min(
                app_grid_rects_.size(),
                filtered_indices_.size());
        for (std::size_t index = 0;
             index < visible_apps;
             ++index)
        {
            if (Contains(
                    app_grid_rects_[index],
                    point))
            {
                ActivateAppIndex(
                    filtered_indices_[index]);
                return 0;
            }
        }

        if (Contains(profile_rect_, point))
        {
            POINT screen_point = point;
            ClientToScreen(
                hwnd_,
                &screen_point);
            NativeAppLauncher::ShowQuickPowerMenu(
                hwnd_,
                screen_point);
            return 0;
        }
        if (Contains(weather_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"weather");
            return 0;
        }
        if (Contains(calendar_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"datetime");
            return 0;
        }
        if (Contains(perf_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"sysmon");
            return 0;
        }
        if (Contains(news_rect_, point))
        {
            NativeAppLauncher::LaunchById(
                instance_,
                hwnd_,
                L"health");
            return 0;
        }

        for (std::size_t index = 0;
             index < quick_launch_rects_.size() &&
             index < quick_launch_app_indices_.size();
             ++index)
        {
            if (Contains(
                    quick_launch_rects_[index],
                    point))
            {
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
            if (Contains(
                    dock_rects_[index],
                    point))
            {
                ActivateAppIndex(
                    dock_app_indices_[index]);
                return 0;
            }
        }

        for (std::size_t index = 0;
             index < workspace_rects_.size();
             ++index)
        {
            if (Contains(
                    workspace_rects_[index],
                    point))
            {
                if (window_manager_ != nullptr)
                {
                    window_manager_->SwitchWorkspace(
                        static_cast<int>(index));
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
                    window_manager_->FocusWindow(
                        hit.window);
                    Redraw();
                }
                return 0;
            }
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
            SetWindowTextW(window, L"");
            return 0;
        }

        if (w_param == VK_LEFT ||
            w_param == VK_RIGHT ||
            w_param == VK_UP ||
            w_param == VK_DOWN)
        {
            constexpr int columns = 6;
            const int total =
                static_cast<int>(
                    self->filtered_indices_.size());
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
                            self->focused_app_index_ + columns,
                            total - 1);
                }
                else
                {
                    self->focused_app_index_ =
                        std::max(
                            self->focused_app_index_ - columns,
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
