#include "native_toast_overlay.h"

#include "native_appearance_manager.h"
#include "native_theme.h"

#include <gdiplus.h>

#include <algorithm>
#include <deque>
#include <mutex>
#include <string>

namespace CloudOS
{
namespace
{
constexpr wchar_t kToastHostClass[] = L"CloudOS.NativeShell.ToastHost.v4";
constexpr wchar_t kToastClass[] = L"CloudOS.NativeShell.Toast.v4";
constexpr UINT kShowNextMessage = WM_APP + 0x721;
constexpr UINT_PTR kDismissTimer = 0x722;
constexpr UINT_PTR kFadeTimer = 0x723;
constexpr std::size_t kMaximumQueue = 12u;

struct ToastEntry final
{
    std::wstring title;
    std::wstring message;
    int severity{};
    unsigned timeout_ms{5200u};
};

std::mutex g_mutex;
std::deque<ToastEntry> g_queue;
HINSTANCE g_instance{};
HWND g_host{};
HWND g_toast{};
ToastEntry g_current{};
DWORD g_shown_tick{};
BYTE g_alpha{248};

COLORREF SeverityColor(int severity)
{
    if (severity >= 2) return WebSkin::Danger;
    if (severity == 1) return RGB(245, 158, 11);
    return NativeAppearanceManager::Accent();
}

void PositionToast(HWND window)
{
    if (window == nullptr) return;
    const HWND foreground = GetForegroundWindow();
    HMONITOR monitor = MonitorFromWindow(
        foreground != nullptr ? foreground : GetDesktopWindow(),
        MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) return;
    const UINT dpi = GetDpiForWindow(window);
    const int width = Scale(420, dpi);
    const int height = Scale(118, dpi);
    const int margin = Scale(18, dpi);
    const int x = info.rcWork.right - width - margin;
    const int y = info.rcWork.bottom - height - margin;
    SetWindowPos(window, HWND_TOPMOST, x, y, width, height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void DrawToast(HWND window)
{
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    RECT client{};
    GetClientRect(window, &client);
    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);

    const UINT dpi = GetDpiForWindow(window);
    const COLORREF accent = SeverityColor(g_current.severity);
    WebSkin::DrawRoundedPanel(
        graphics,
        Gdiplus::RectF(1.0f, 1.0f,
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, client.right - 2)),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, client.bottom - 2))),
        static_cast<Gdiplus::REAL>(Scale(16, dpi)),
        WebSkin::GdiColor(WebSkin::BgElevated, 248),
        WebSkin::GdiColor(accent, 230),
        1.25f);

    Gdiplus::SolidBrush accent_brush(WebSkin::GdiColor(accent));
    graphics.FillRectangle(&accent_brush,
        Gdiplus::RectF(static_cast<Gdiplus::REAL>(Scale(12, dpi)),
            static_cast<Gdiplus::REAL>(Scale(18, dpi)),
            static_cast<Gdiplus::REAL>(Scale(4, dpi)),
            static_cast<Gdiplus::REAL>(std::max(1, Scale(82, dpi)))));

    Gdiplus::Font title_font(L"Segoe UI Variable Display",
        static_cast<Gdiplus::REAL>(Scale(15, dpi)), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::Font body_font(L"Segoe UI Variable Text",
        static_cast<Gdiplus::REAL>(Scale(11, dpi)), Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush title_brush(WebSkin::GdiColor(WebSkin::TextPrimary));
    Gdiplus::SolidBrush body_brush(WebSkin::GdiColor(WebSkin::TextSecondary));
    Gdiplus::StringFormat format;
    format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    format.SetFormatFlags(Gdiplus::StringFormatFlagsLineLimit);
    const Gdiplus::REAL left = static_cast<Gdiplus::REAL>(Scale(28, dpi));
    const Gdiplus::REAL width = static_cast<Gdiplus::REAL>(std::max<LONG>(1, client.right - Scale(46, dpi)));
    graphics.DrawString(g_current.title.c_str(), -1, &title_font,
        Gdiplus::RectF(left, static_cast<Gdiplus::REAL>(Scale(19, dpi)), width,
            static_cast<Gdiplus::REAL>(Scale(28, dpi))), &format, &title_brush);
    graphics.DrawString(g_current.message.c_str(), -1, &body_font,
        Gdiplus::RectF(left, static_cast<Gdiplus::REAL>(Scale(51, dpi)), width,
            static_cast<Gdiplus::REAL>(Scale(48, dpi))), &format, &body_brush);
    EndPaint(window, &paint);
}

void ShowNext()
{
    if (g_toast == nullptr || !IsWindow(g_toast)) return;
    ToastEntry next{};
    {
        std::scoped_lock lock(g_mutex);
        if (g_queue.empty())
        {
            ShowWindow(g_toast, SW_HIDE);
            return;
        }
        next = std::move(g_queue.front());
        g_queue.pop_front();
    }
    g_current = std::move(next);
    g_alpha = 248;
    SetLayeredWindowAttributes(g_toast, 0, g_alpha, LWA_ALPHA);
    PositionToast(g_toast);
    InvalidateRect(g_toast, nullptr, TRUE);
    UpdateWindow(g_toast);
    g_shown_tick = GetTickCount();
    KillTimer(g_toast, kDismissTimer);
    KillTimer(g_toast, kFadeTimer);
    SetTimer(g_toast, kDismissTimer,
        std::max<unsigned>(1800u, g_current.timeout_ms), nullptr);
    SetTimer(g_toast, kFadeTimer, 50, nullptr);
}

LRESULT CALLBACK ToastProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_NCHITTEST:
        return HTCLIENT;
    case WM_LBUTTONUP:
        KillTimer(window, kDismissTimer);
        KillTimer(window, kFadeTimer);
        ShowWindow(window, SW_HIDE);
        PostMessageW(g_host, kShowNextMessage, 0, 0);
        return 0;
    case WM_TIMER:
        if (w_param == kDismissTimer)
        {
            KillTimer(window, kDismissTimer);
            KillTimer(window, kFadeTimer);
            ShowWindow(window, SW_HIDE);
            PostMessageW(g_host, kShowNextMessage, 0, 0);
            return 0;
        }
        if (w_param == kFadeTimer)
        {
            const DWORD elapsed = GetTickCount() - g_shown_tick;
            const unsigned timeout = std::max<unsigned>(1800u, g_current.timeout_ms);
            if (elapsed + 700u >= timeout && elapsed < timeout)
            {
                const unsigned remaining = timeout - elapsed;
                g_alpha = static_cast<BYTE>(std::clamp<unsigned>(40u + remaining * 208u / 700u, 40u, 248u));
                SetLayeredWindowAttributes(window, 0, g_alpha, LWA_ALPHA);
            }
            return 0;
        }
        break;
    case WM_PAINT:
        DrawToast(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK HostProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    if (message == kShowNextMessage)
    {
        if (g_toast != nullptr && !IsWindowVisible(g_toast)) ShowNext();
        return 0;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}
}

bool NativeToastOverlay::Initialize(HINSTANCE instance)
{
    if (g_host != nullptr && IsWindow(g_host)) return true;
    g_instance = instance;

    WNDCLASSEXW host_class{};
    host_class.cbSize = sizeof(host_class);
    host_class.lpfnWndProc = HostProcedure;
    host_class.hInstance = instance;
    host_class.lpszClassName = kToastHostClass;
    if (RegisterClassExW(&host_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    WNDCLASSEXW toast_class{};
    toast_class.cbSize = sizeof(toast_class);
    toast_class.style = CS_HREDRAW | CS_VREDRAW;
    toast_class.lpfnWndProc = ToastProcedure;
    toast_class.hInstance = instance;
    toast_class.hCursor = LoadCursorW(nullptr, IDC_HAND);
    toast_class.hbrBackground = nullptr;
    toast_class.lpszClassName = kToastClass;
    if (RegisterClassExW(&toast_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    g_host = CreateWindowExW(0, kToastHostClass, L"", 0,
        0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    if (g_host == nullptr) return false;
    g_toast = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_LAYERED,
        kToastClass, L"CloudOS Toast", WS_POPUP,
        0, 0, 420, 118, nullptr, nullptr, instance, nullptr);
    if (g_toast == nullptr)
    {
        DestroyWindow(g_host);
        g_host = nullptr;
        return false;
    }
    ApplyWebFlyoutMaterial(g_toast);
    SetLayeredWindowAttributes(g_toast, 0, 248, LWA_ALPHA);
    return true;
}

void NativeToastOverlay::Shutdown() noexcept
{
    if (g_toast != nullptr && IsWindow(g_toast)) DestroyWindow(g_toast);
    if (g_host != nullptr && IsWindow(g_host)) DestroyWindow(g_host);
    g_toast = nullptr;
    g_host = nullptr;
    std::scoped_lock lock(g_mutex);
    g_queue.clear();
}

void NativeToastOverlay::Post(
    const std::wstring& title,
    const std::wstring& message,
    int severity,
    unsigned timeout_ms)
{
    if (g_host == nullptr || !IsWindow(g_host)) return;
    ToastEntry entry{};
    entry.title = title.empty() ? L"CloudOS" : title;
    entry.message = message;
    entry.severity = severity;
    entry.timeout_ms = timeout_ms;
    {
        std::scoped_lock lock(g_mutex);
        g_queue.push_back(std::move(entry));
        while (g_queue.size() > kMaximumQueue) g_queue.pop_front();
    }
    PostMessageW(g_host, kShowNextMessage, 0, 0);
}

void NativeToastOverlay::Dismiss() noexcept
{
    if (g_toast != nullptr && IsWindow(g_toast))
    {
        KillTimer(g_toast, kDismissTimer);
        KillTimer(g_toast, kFadeTimer);
        ShowWindow(g_toast, SW_HIDE);
    }
}
} // namespace CloudOS
