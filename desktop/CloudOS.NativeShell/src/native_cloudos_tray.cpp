#include "native_cloudos_tray.h"

#include "native_appearance_manager.h"
#include "native_control_plane_service.h"
#include "native_system_control_backend.h"
#include "native_system_control_window.h"
#include "native_theme.h"

#include <commctrl.h>
#include <gdiplus.h>

#include <algorithm>
#include <iterator>

namespace CloudOS
{
namespace
{
constexpr wchar_t kTaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v4";
constexpr wchar_t kEngineClass[] = L"CloudOS.NativeShell.TrayService.v4";
constexpr UINT_PTR kTraySubclass = 0x7A4101;
constexpr UINT_PTR kAttachTimer = 0x7A4102;

RECT QuickRect(HWND window)
{
    RECT client{};
    GetClientRect(window, &client);
    const UINT dpi = GetDpiForWindow(window);
    const int width = std::max<LONG>(1, client.right - client.left);
    const int height = std::max<LONG>(1, client.bottom - client.top);
    const int margin = Scale(12, dpi);
    const int button = Scale(46, dpi);
    const int gap = Scale(8, dpi);
    const int clock_width = Scale(122, dpi);
    const int notify_width = Scale(46, dpi);
    const int quick_width = Scale(106, dpi);
    const int y = (height - button) / 2;
    int right_x = width - margin - clock_width;
    right_x -= gap + notify_width;
    right_x -= gap + quick_width;
    return RECT{right_x, y, right_x + quick_width, y + button};
}

bool TrayContains(const RECT& rect, POINT point) noexcept
{
    return point.x >= rect.left && point.x < rect.right &&
        point.y >= rect.top && point.y < rect.bottom;
}

void DrawSpeaker(Gdiplus::Graphics& graphics, Gdiplus::REAL x, Gdiplus::REAL y,
    COLORREF color, bool muted)
{
    Gdiplus::Pen pen(WebSkin::GdiColor(color), 1.7f);
    graphics.DrawLine(&pen, x, y + 7.0f, x + 5.0f, y + 7.0f);
    graphics.DrawLine(&pen, x + 5.0f, y + 7.0f, x + 11.0f, y + 2.0f);
    graphics.DrawLine(&pen, x + 11.0f, y + 2.0f, x + 11.0f, y + 12.0f);
    graphics.DrawLine(&pen, x + 11.0f, y + 12.0f, x + 5.0f, y + 7.0f);
    if (muted)
    {
        graphics.DrawLine(&pen, x + 15.0f, y + 3.0f, x + 24.0f, y + 12.0f);
        graphics.DrawLine(&pen, x + 24.0f, y + 3.0f, x + 15.0f, y + 12.0f);
    }
    else
    {
        graphics.DrawArc(&pen, x + 8.0f, y + 1.0f, 16.0f, 12.0f, -55.0f, 110.0f);
    }
}

void DrawWifi(Gdiplus::Graphics& graphics, Gdiplus::REAL x, Gdiplus::REAL y,
    COLORREF color, bool connected)
{
    Gdiplus::Pen pen(WebSkin::GdiColor(color), 1.7f);
    Gdiplus::SolidBrush brush(WebSkin::GdiColor(color));
    if (connected)
    {
        graphics.DrawArc(&pen, x, y, 24.0f, 17.0f, 205.0f, 130.0f);
        graphics.DrawArc(&pen, x + 4.0f, y + 5.0f, 16.0f, 10.0f, 205.0f, 130.0f);
        graphics.FillEllipse(&brush, x + 10.0f, y + 14.0f, 4.0f, 4.0f);
    }
    else
    {
        graphics.DrawEllipse(&pen, x + 6.0f, y + 3.0f, 12.0f, 12.0f);
        graphics.DrawLine(&pen, x + 4.0f, y + 1.0f, x + 20.0f, y + 17.0f);
    }
}

void DrawBattery(Gdiplus::Graphics& graphics, Gdiplus::REAL x, Gdiplus::REAL y,
    COLORREF color, unsigned percent, bool present)
{
    Gdiplus::Pen pen(WebSkin::GdiColor(color), 1.5f);
    Gdiplus::SolidBrush brush(WebSkin::GdiColor(color));
    graphics.DrawRectangle(&pen, x, y + 3.0f, 21.0f, 12.0f);
    graphics.FillRectangle(&brush, x + 21.5f, y + 6.0f, 2.5f, 6.0f);
    if (!present)
    {
        graphics.DrawLine(&pen, x + 3.0f, y + 13.0f, x + 18.0f, y + 5.0f);
        return;
    }
    const Gdiplus::REAL fill = 17.0f * static_cast<Gdiplus::REAL>(std::min(percent, 100u)) / 100.0f;
    if (fill > 0.5f)
        graphics.FillRectangle(&brush, x + 2.0f, y + 5.0f, fill, 8.0f);
}

void PaintTray(HWND window)
{
    const RECT rect = QuickRect(window);
    HDC dc = GetDC(window);
    if (dc == nullptr) return;

    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    const UINT dpi = GetDpiForWindow(window);
    const auto snapshot = NativeControlPlaneService::Instance().Snapshot();
    const COLORREF accent = NativeAppearanceManager::Accent();
    const COLORREF icon = snapshot.health_severity > 0
        ? (snapshot.health_severity >= 2 ? WebSkin::Danger : RGB(245, 158, 11))
        : WebSkin::TextSecondary;

    WebSkin::DrawRoundedPanel(
        graphics,
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(rect.left),
            static_cast<Gdiplus::REAL>(rect.top),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.right - rect.left)),
            static_cast<Gdiplus::REAL>(std::max<LONG>(1, rect.bottom - rect.top))),
        static_cast<Gdiplus::REAL>(Scale(12, dpi)),
        WebSkin::GdiColor(WebSkin::BgSecondary, 246),
        WebSkin::GdiColor(snapshot.health_severity > 0 ? icon : WebSkin::BorderDefault),
        1.0f);

    const Gdiplus::REAL top = static_cast<Gdiplus::REAL>(rect.top + Scale(14, dpi));
    DrawSpeaker(graphics, static_cast<Gdiplus::REAL>(rect.left + Scale(10, dpi)), top,
        snapshot.audio.available ? icon : WebSkin::TextDisabled,
        snapshot.audio.available && snapshot.audio.muted);
    DrawWifi(graphics, static_cast<Gdiplus::REAL>(rect.left + Scale(42, dpi)), top,
        snapshot.wifi_connected ? accent : WebSkin::TextDisabled,
        snapshot.wifi_connected);
    DrawBattery(graphics, static_cast<Gdiplus::REAL>(rect.left + Scale(74, dpi)), top,
        snapshot.power.battery_present && snapshot.power.battery_percent <= 15u
            ? WebSkin::Danger : icon,
        snapshot.power.battery_percent,
        snapshot.power.battery_present);
    ReleaseDC(window, dc);
}

void AdjustVolume(int delta)
{
    const NativeAudioState audio = NativeSystemControlBackend::QueryAudio();
    if (!audio.available) return;
    const int target = std::clamp<int>(static_cast<int>(audio.volume_percent) + delta, 0, 100);
    (void)NativeSystemControlBackend::SetMasterVolume(static_cast<unsigned>(target), nullptr);
    if (audio.muted && target > 0)
        (void)NativeSystemControlBackend::SetMasterMute(false, nullptr);
    NativeControlPlaneService::Instance().RefreshNow();
}
} // namespace

NativeCloudOSTrayService& NativeCloudOSTrayService::Instance()
{
    static NativeCloudOSTrayService instance;
    return instance;
}

bool NativeCloudOSTrayService::Start(HINSTANCE instance)
{
    if (engine_window_ != nullptr && IsWindow(engine_window_)) return true;
    instance_ = instance;
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeCloudOSTrayService::EngineProcedure;
    window_class.hInstance = instance;
    window_class.lpszClassName = kEngineClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    engine_window_ = CreateWindowExW(0, kEngineClass, L"", 0,
        0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, this);
    if (engine_window_ == nullptr) return false;
    AttachExistingTaskbars();
    SetTimer(engine_window_, kAttachTimer, 1800, nullptr);
    return true;
}

void NativeCloudOSTrayService::Stop() noexcept
{
    if (engine_window_ != nullptr && IsWindow(engine_window_))
    {
        KillTimer(engine_window_, kAttachTimer);
        DestroyWindow(engine_window_);
    }
    engine_window_ = nullptr;
    instance_ = nullptr;
}

void NativeCloudOSTrayService::Refresh()
{
    AttachExistingTaskbars();
    EnumWindows(
        [](HWND window, LPARAM) -> BOOL
        {
            wchar_t class_name[128]{};
            GetClassNameW(window, class_name, static_cast<int>(std::size(class_name)));
            if (_wcsicmp(class_name, kTaskbarClass) == 0)
                InvalidateRect(window, nullptr, FALSE);
            return TRUE;
        }, 0);
}

BOOL CALLBACK NativeCloudOSTrayService::EnumerateWindow(HWND window, LPARAM parameter)
{
    auto* self = reinterpret_cast<NativeCloudOSTrayService*>(parameter);
    if (self == nullptr) return TRUE;
    wchar_t class_name[128]{};
    if (GetClassNameW(window, class_name, static_cast<int>(std::size(class_name))) <= 0)
        return TRUE;
    if (_wcsicmp(class_name, kTaskbarClass) != 0) return TRUE;
    (void)SetWindowSubclass(window, &NativeCloudOSTrayService::TaskbarSubclass,
        kTraySubclass, reinterpret_cast<DWORD_PTR>(self));
    return TRUE;
}

void NativeCloudOSTrayService::AttachExistingTaskbars()
{
    EnumWindows(&NativeCloudOSTrayService::EnumerateWindow, reinterpret_cast<LPARAM>(this));
}

LRESULT CALLBACK NativeCloudOSTrayService::TaskbarSubclass(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param,
    UINT_PTR subclass_id, DWORD_PTR reference_data)
{
    auto* self = reinterpret_cast<NativeCloudOSTrayService*>(reference_data);
    return self != nullptr
        ? self->HandleTaskbar(window, message, w_param, l_param, subclass_id)
        : DefSubclassProc(window, message, w_param, l_param);
}

LRESULT NativeCloudOSTrayService::HandleTaskbar(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param, UINT_PTR subclass_id)
{
    if (message == WM_PAINT)
    {
        const LRESULT result = DefSubclassProc(window, message, w_param, l_param);
        PaintTray(window);
        return result;
    }

    if (message == WM_RBUTTONUP || message == WM_MBUTTONUP || message == WM_MOUSEWHEEL)
    {
        POINT point{};
        if (message == WM_MOUSEWHEEL)
        {
            point.x = GET_X_LPARAM(l_param);
            point.y = GET_Y_LPARAM(l_param);
            ScreenToClient(window, &point);
        }
        else
        {
            point.x = GET_X_LPARAM(l_param);
            point.y = GET_Y_LPARAM(l_param);
        }

        if (TrayContains(QuickRect(window), point))
        {
            if (message == WM_RBUTTONUP)
            {
                (void)CloudOSNativeSystemControlWindow::Open(instance_, window);
                return 0;
            }
            if (message == WM_MBUTTONUP)
            {
                const auto audio = NativeSystemControlBackend::QueryAudio();
                if (audio.available)
                    (void)NativeSystemControlBackend::SetMasterMute(!audio.muted, nullptr);
                NativeControlPlaneService::Instance().RefreshNow();
                Refresh();
                return 0;
            }
            AdjustVolume(GET_WHEEL_DELTA_WPARAM(w_param) > 0 ? 5 : -5);
            Refresh();
            return 0;
        }
    }

    if (message == WM_NCDESTROY)
    {
        RemoveWindowSubclass(window, &NativeCloudOSTrayService::TaskbarSubclass, subclass_id);
        return DefSubclassProc(window, message, w_param, l_param);
    }
    return DefSubclassProc(window, message, w_param, l_param);
}

LRESULT CALLBACK NativeCloudOSTrayService::EngineProcedure(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeCloudOSTrayService*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = reinterpret_cast<NativeCloudOSTrayService*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self != nullptr && message == WM_TIMER && w_param == kAttachTimer)
    {
        self->AttachExistingTaskbars();
        self->Refresh();
        return 0;
    }
    if (self != nullptr && message == WM_NCDESTROY && self->engine_window_ == window)
        self->engine_window_ = nullptr;
    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
