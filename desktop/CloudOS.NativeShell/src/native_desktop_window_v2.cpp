#include "native_desktop_window.h"

#include "native_app_launcher.h"
#include "native_desktop_context_menu.h"
#include "native_desktop_drop_target.h"
#include "native_icon_renderer.h"
#include "native_monitor_manager.h"
#include "native_shell_platform.h"
#include "native_wallpaper_manager.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

using namespace Gdiplus;

namespace CloudOS
{
namespace
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
std::vector<RECT> g_file_rects;
std::vector<std::wstring> g_file_paths;

int FindApp(std::wstring_view id)
{
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
        if (id == kAllApps[index].id) return static_cast<int>(index);
    return -1;
}

std::vector<int> DesktopApps()
{
    std::vector<int> result;
    for (std::wstring_view id : {L"files", L"projects", L"terminal", L"drive", L"control", L"settings"})
    {
        const int index = FindApp(id);
        if (index >= 0) result.push_back(index);
    }
    return result;
}

std::wstring DesktopPath()
{
    PWSTR path = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DEFAULT, nullptr, &path)) || path == nullptr) return {};
    std::wstring result(path); CoTaskMemFree(path); return result;
}

std::vector<std::wstring> DesktopFiles()
{
    std::vector<std::wstring> result;
    const std::wstring desktop = DesktopPath();
    if (desktop.empty()) return result;
    std::error_code error;
    for (std::filesystem::directory_iterator iterator(desktop, error), end;
         !error && iterator != end && result.size() < 24; iterator.increment(error))
    {
        const std::wstring name = iterator->path().filename().wstring();
        if (!name.empty() && name[0] != L'.') result.push_back(iterator->path().wstring());
    }
    std::sort(result.begin(), result.end());
    return result;
}

std::wstring FileName(const std::wstring& path)
{
    const std::filesystem::path value(path);
    const std::wstring name = value.filename().wstring();
    return name.empty() ? path : name;
}

void DrawCenteredText(Graphics& graphics, const std::wstring& text, const Font& font, const RectF& rectangle, const Brush& brush)
{
    StringFormat format;
    format.SetAlignment(StringAlignmentCenter);
    format.SetLineAlignment(StringAlignmentNear);
    format.SetTrimming(StringTrimmingEllipsisCharacter);
    format.SetFormatFlags(StringFormatFlagsLineLimit);
    graphics.DrawString(text.c_str(), -1, &font, rectangle, &format, &brush);
}

POINT PrimaryOriginInClient(HWND window)
{
    POINT origin{};
    RECT window_bounds{}; GetWindowRect(window, &window_bounds);
    const auto monitors = NativeMonitorManager::Enumerate();
    for (const auto& monitor : monitors)
    {
        if (monitor.primary)
        {
            origin.x = monitor.monitor.left - window_bounds.left;
            origin.y = monitor.monitor.top - window_bounds.top;
            return origin;
        }
    }
    return origin;
}
}

CloudOSNativeDesktopWindow::~CloudOSNativeDesktopWindow() { Destroy(); }

bool CloudOSNativeDesktopWindow::Create(HINSTANCE instance, CloudOSNativeWindowManager* window_manager)
{
    instance_ = instance;
    window_manager_ = window_manager;
    quick_launch_app_indices_ = DesktopApps();
    current_stats_ = NativeSystemStats::Query();

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.lpfnWndProc = &CloudOSNativeDesktopWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kDesktopClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;

    hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW, kDesktopClass, L"CloudOS Desktop",
        WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 0, 0,
        nullptr, nullptr, instance_, this);
    if (hwnd_ == nullptr) return false;

    DarkWindow(hwnd_, false);
    (void)NativeDesktopDropTarget::Register(hwnd_);
    return true;
}

void CloudOSNativeDesktopWindow::Destroy()
{
    if (hwnd_ != nullptr)
    {
        NativeDesktopDropTarget::Unregister(hwnd_);
        if (IsWindow(hwnd_)) DestroyWindow(hwnd_);
    }
    hwnd_ = nullptr;
    quick_launch_rects_.clear(); quick_launch_app_indices_.clear();
    g_file_rects.clear(); g_file_paths.clear();
}

void CloudOSNativeDesktopWindow::UpdateLayout(const RECT& work_area)
{
    if (hwnd_ == nullptr) return;
    SetWindowPos(hwnd_, HWND_BOTTOM, work_area.left, work_area.top,
        std::max(1, Width(work_area)), std::max(1, Height(work_area)), SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void CloudOSNativeDesktopWindow::Redraw() { if (hwnd_ != nullptr) InvalidateRect(hwnd_, nullptr, FALSE); }
void CloudOSNativeDesktopWindow::FocusSearch() { if (on_hotkey_) on_hotkey_(HotSearch); }
void CloudOSNativeDesktopWindow::RefreshWorkArea() { if (on_timer_) on_timer_(); Redraw(); }

void CloudOSNativeDesktopWindow::ActivateAppIndex(int app_index)
{
    if (app_index < 0 || app_index >= static_cast<int>(kAllApps.size())) return;
    if (on_action_) on_action_(app_index + 1);
    else NativeAppLauncher::Launch(instance_, hwnd_, kAllApps[static_cast<std::size_t>(app_index)]);
}

void CloudOSNativeDesktopWindow::Paint()
{
    PAINTSTRUCT paint{};
    HDC screen_dc = BeginPaint(hwnd_, &paint);
    RECT client{}; GetClientRect(hwnd_, &client);
    const int width = Width(client); const int height = Height(client);
    if (width <= 0 || height <= 0) { EndPaint(hwnd_, &paint); return; }

    HDC memory_dc = CreateCompatibleDC(screen_dc);
    HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
    HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);
    Graphics graphics(memory_dc);
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    const UINT dpi = GetDpiForWindow(hwnd_);

    if (!NativeWallpaperManager::Draw(graphics, width, height))
    {
        LinearGradientBrush background(
            PointF(0.0f, 0.0f), PointF(static_cast<REAL>(width), static_cast<REAL>(height)),
            WebSkin::GdiColor(WebSkin::BgPrimary), WebSkin::GdiColor(WebSkin::BgSolid));
        graphics.FillRectangle(&background, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

        // Subtle ambient accents reproduce the web desktop without the huge
        // opaque circle that dominated the previous fallback wallpaper.
        SolidBrush glow_top(Color(24, 99, 102, 241));
        graphics.FillEllipse(&glow_top,
            static_cast<REAL>(width - Scale(440, dpi)), static_cast<REAL>(-Scale(180, dpi)),
            static_cast<REAL>(Scale(520, dpi)), static_cast<REAL>(Scale(360, dpi)));
        SolidBrush glow_bottom(Color(14, 129, 140, 248));
        graphics.FillEllipse(&glow_bottom,
            static_cast<REAL>(-Scale(220, dpi)), static_cast<REAL>(height - Scale(160, dpi)),
            static_cast<REAL>(Scale(480, dpi)), static_cast<REAL>(Scale(300, dpi)));
    }

    SolidBrush overlay(Color(18, 0, 0, 0));
    graphics.FillRectangle(&overlay, RectF(0.0f, 0.0f, static_cast<REAL>(width), static_cast<REAL>(height)));

    Font brand_font(L"Segoe UI Variable Display", static_cast<REAL>(Scale(22, dpi)), FontStyleBold, UnitPixel);
    Font small_font(L"Segoe UI Variable Text", static_cast<REAL>(Scale(10, dpi)), FontStyleRegular, UnitPixel);
    Font small_bold(L"Segoe UI Variable Text", static_cast<REAL>(Scale(10, dpi)), FontStyleBold, UnitPixel);
    SolidBrush white(WebSkin::GdiColor(WebSkin::TextPrimary));
    SolidBrush secondary(WebSkin::GdiColor(WebSkin::TextSecondary));

    const POINT primary = PrimaryOriginInClient(hwnd_);
    graphics.DrawString(L"CloudOS", -1, &brand_font,
        PointF(static_cast<REAL>(primary.x + Scale(24, dpi)), static_cast<REAL>(primary.y + Scale(20, dpi))), &white);

    std::wstring workspace_text = L"Desktop  ·  Workspace ";
    workspace_text += std::to_wstring(window_manager_ != nullptr ? window_manager_->CurrentWorkspace() + 1 : 1);
    graphics.DrawString(workspace_text.c_str(), -1, &small_font,
        PointF(static_cast<REAL>(primary.x + Scale(26, dpi)), static_cast<REAL>(primary.y + Scale(54, dpi))), &secondary);

    quick_launch_rects_.clear();
    const int shortcut_width = Scale(96, dpi);
    const int shortcut_height = Scale(92, dpi);
    const int icon_size = Scale(46, dpi);
    const int left = primary.x + Scale(20, dpi);
    int y = primary.y + Scale(94, dpi);

    for (std::size_t index = 0; index < quick_launch_app_indices_.size(); ++index)
    {
        const int app_index = quick_launch_app_indices_[index];
        RECT hit{left, y, left + shortcut_width, y + shortcut_height};
        quick_launch_rects_.push_back(hit);
        NativeIconRenderer::DrawAetherSquircle(graphics, kAllApps[static_cast<std::size_t>(app_index)].icon_id,
            left + (shortcut_width - icon_size) / 2, y + Scale(3, dpi), icon_size);
        DrawCenteredText(graphics, kAllApps[static_cast<std::size_t>(app_index)].name, small_font,
            RectF(static_cast<REAL>(left), static_cast<REAL>(y + Scale(56, dpi)),
                static_cast<REAL>(shortcut_width), static_cast<REAL>(Scale(30, dpi))), white);
        y += shortcut_height + Scale(6, dpi);
    }

    g_file_paths = DesktopFiles();
    g_file_rects.clear();
    const int file_start_x = left + shortcut_width + Scale(26, dpi);
    const int file_start_y = primary.y + Scale(94, dpi);
    const int file_columns = 5;
    const int file_cell_width = Scale(116, dpi);
    const int file_cell_height = Scale(100, dpi);

    for (std::size_t index = 0; index < g_file_paths.size(); ++index)
    {
        const int column = static_cast<int>(index % static_cast<std::size_t>(file_columns));
        const int row = static_cast<int>(index / static_cast<std::size_t>(file_columns));
        const int x = file_start_x + column * file_cell_width;
        const int file_y = file_start_y + row * file_cell_height;
        RECT hit{x, file_y, x + file_cell_width, file_y + file_cell_height};
        g_file_rects.push_back(hit);

        SHFILEINFOW file_info{};
        if (SHGetFileInfoW(g_file_paths[index].c_str(), 0, &file_info, sizeof(file_info), SHGFI_ICON | SHGFI_LARGEICON) != 0 &&
            file_info.hIcon != nullptr)
        {
            DrawIconEx(memory_dc, x + (file_cell_width - Scale(42, dpi)) / 2, file_y + Scale(4, dpi),
                file_info.hIcon, Scale(42, dpi), Scale(42, dpi), 0, nullptr, DI_NORMAL);
            DestroyIcon(file_info.hIcon);
        }
        DrawCenteredText(graphics, FileName(g_file_paths[index]), small_font,
            RectF(static_cast<REAL>(x + Scale(3, dpi)), static_cast<REAL>(file_y + Scale(54, dpi)),
                static_cast<REAL>(file_cell_width - Scale(6, dpi)), static_cast<REAL>(Scale(40, dpi))), white);
    }

    current_stats_ = NativeSystemStats::Query();
    std::wstring status = L"CPU ";
    status += current_stats_.cpu_available ? std::to_wstring(current_stats_.cpu_percent) + L"%" : L"--";
    status += L"   RAM ";
    status += current_stats_.ram_available ? std::to_wstring(current_stats_.ram_percent) + L"%" : L"--";
    graphics.DrawString(status.c_str(), -1, &small_bold,
        PointF(static_cast<REAL>(primary.x + Scale(24, dpi)), static_cast<REAL>(primary.y + Scale(74, dpi))), &secondary);

    BitBlt(screen_dc, 0, 0, width, height, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap); DeleteObject(bitmap); DeleteDC(memory_dc); EndPaint(hwnd_, &paint);
}

LRESULT CloudOSNativeDesktopWindow::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_TIMER:
        if (w_param == kMetricsTimer) { current_stats_ = NativeSystemStats::Query(); Redraw(); return 0; }
        if (w_param == kReconcileTimer) { if (on_timer_) on_timer_(); Redraw(); return 0; }
        break;
    case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
        if (window_manager_ != nullptr)
            window_manager_->HandleRuntimeEvent(static_cast<cloudos_native_window_event_kind>(w_param), reinterpret_cast<HWND>(l_param));
        Redraw(); return 0;
    case WM_HOTKEY:
        if (on_hotkey_) on_hotkey_(static_cast<int>(w_param));
        return 0;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
    case WM_SETTINGCHANGE:
        RefreshWorkArea(); return 0;
    case WM_LBUTTONDBLCLK:
    {
        const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        for (std::size_t index = 0; index < quick_launch_rects_.size() && index < quick_launch_app_indices_.size(); ++index)
            if (Contains(quick_launch_rects_[index], point)) { ActivateAppIndex(quick_launch_app_indices_[index]); return 0; }
        for (std::size_t index = 0; index < g_file_rects.size() && index < g_file_paths.size(); ++index)
            if (Contains(g_file_rects[index], point))
            { (void)ShellExecuteW(hwnd_, L"open", g_file_paths[index].c_str(), nullptr, nullptr, SW_SHOWNORMAL); return 0; }
        break;
    }
    case WM_RBUTTONUP:
    {
        POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
        ClientToScreen(hwnd_, &point);
        if (NativeDesktopContextMenu::Show(instance_, hwnd_, point)) Redraw();
        return 0;
    }
    case WM_KEYDOWN:
        if (w_param == VK_F5) { Redraw(); return 0; }
        break;
    case WM_DESTROY:
        NativeDesktopDropTarget::Unregister(hwnd_); hwnd_ = nullptr; return 0;
    default: break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeDesktopWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeDesktopWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeDesktopWindow*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->hwnd_ = window;
    }
    return self != nullptr ? self->HandleMessage(window, message, w_param, l_param)
                           : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
