#include "native_control_plane_service.h"

#include "native_notification_center.h"
#include "native_toast_overlay.h"

#include <algorithm>
#include <limits>
#include <mutex>

namespace CloudOS
{
namespace
{
constexpr wchar_t kServiceClass[] = L"CloudOS.NativeShell.ControlPlaneService.v4";
constexpr UINT_PTR kRefreshTimer = 0x7401;
constexpr UINT kRefreshMessage = WM_APP + 0x7402;
constexpr UINT kRefreshIntervalMs = 5000;

std::mutex g_snapshot_mutex;
NativeControlPlaneSnapshot g_snapshot{};

unsigned FreePercent(const NativeDriveInfo& drive)
{
    if (drive.total_bytes == 0) return 100u;
    return static_cast<unsigned>(std::min<std::uint64_t>(
        100u, drive.free_bytes * 100u / drive.total_bytes));
}

bool LowBattery(const NativePowerState& power)
{
    return power.battery_present && !power.on_ac && power.battery_percent <= 15u;
}

bool CriticalBattery(const NativePowerState& power)
{
    return power.battery_present && !power.on_ac && power.battery_percent <= 7u;
}
}

NativeControlPlaneService& NativeControlPlaneService::Instance()
{
    static NativeControlPlaneService instance;
    return instance;
}

bool NativeControlPlaneService::Start(HINSTANCE instance)
{
    if (window_ != nullptr && IsWindow(window_)) return true;
    instance_ = instance;
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeControlPlaneService::WindowProcedure;
    window_class.hInstance = instance;
    window_class.lpszClassName = kServiceClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    window_ = CreateWindowExW(0, kServiceClass, L"", 0,
        0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, this);
    if (window_ == nullptr) return false;
    RefreshInternal(false);
    SetTimer(window_, kRefreshTimer, kRefreshIntervalMs, nullptr);
    return true;
}

void NativeControlPlaneService::Stop() noexcept
{
    if (window_ != nullptr && IsWindow(window_))
    {
        KillTimer(window_, kRefreshTimer);
        DestroyWindow(window_);
    }
    window_ = nullptr;
    instance_ = nullptr;
}

NativeControlPlaneSnapshot NativeControlPlaneService::Snapshot() const
{
    std::scoped_lock lock(g_snapshot_mutex);
    return g_snapshot;
}

void NativeControlPlaneService::RefreshNow()
{
    if (window_ != nullptr && IsWindow(window_))
        PostMessageW(window_, kRefreshMessage, 0, 0);
}

void NativeControlPlaneService::RefreshInternal(bool allow_alerts)
{
    NativeControlPlaneSnapshot next{};
    next.audio = NativeSystemControlBackend::QueryAudio();
    next.brightness = NativeSystemControlBackend::QueryBrightness();
    next.power = NativeSystemControlBackend::QueryPower();

    const auto wifi = NativeSystemControlBackend::ScanWifi();
    next.wifi_available = !wifi.empty();
    for (const auto& network : wifi)
    {
        if (!network.connected) continue;
        next.wifi_connected = true;
        next.wifi_ssid = network.ssid;
        next.wifi_signal = network.signal_quality;
        break;
    }

    const auto summary = NativeSystemControlBackend::QuerySummary();
    next.monitor_count = summary.monitor_count;
    next.process_count = summary.process_count;

    const auto drives = NativeSystemControlBackend::QueryDrives();
    next.lowest_drive_free_bytes = std::numeric_limits<std::uint64_t>::max();
    next.lowest_drive_free_percent = 100u;
    for (const auto& drive : drives)
    {
        if (drive.total_bytes == 0) continue;
        next.lowest_drive_free_bytes = std::min(next.lowest_drive_free_bytes, drive.free_bytes);
        next.lowest_drive_free_percent = std::min(next.lowest_drive_free_percent, FreePercent(drive));
    }
    if (next.lowest_drive_free_bytes == std::numeric_limits<std::uint64_t>::max())
        next.lowest_drive_free_bytes = 0;

    if (CriticalBattery(next.power))
    {
        next.health_severity = 2;
        next.health_text = L"Bateria critica";
    }
    else if (LowBattery(next.power))
    {
        next.health_severity = 1;
        next.health_text = L"Bateria baixa";
    }
    else if (!drives.empty() && next.lowest_drive_free_percent <= 5u)
    {
        next.health_severity = 2;
        next.health_text = L"Armazenamento critico";
    }
    else if (!drives.empty() && next.lowest_drive_free_percent <= 10u)
    {
        next.health_severity = 1;
        next.health_text = L"Pouco espaco em disco";
    }
    else
    {
        next.health_severity = 0;
        next.health_text = L"Sistema normal";
    }

    NativeControlPlaneSnapshot previous{};
    {
        std::scoped_lock lock(g_snapshot_mutex);
        previous = g_snapshot;
        next.generation = previous.generation + 1u;
        g_snapshot = next;
    }
    if (allow_alerts) EvaluateAlerts(previous, next);
}

void NativeControlPlaneService::EvaluateAlerts(
    const NativeControlPlaneSnapshot& previous,
    const NativeControlPlaneSnapshot& current)
{
    if (current.health_severity > 0 &&
        (previous.health_severity != current.health_severity ||
         previous.health_text != current.health_text))
    {
        std::wstring detail;
        if (current.health_text.find(L"Bateria") != std::wstring::npos)
        {
            detail = L"Bateria em " + std::to_wstring(current.power.battery_percent) +
                L"%. Conecte o carregador quando possivel.";
        }
        else
        {
            detail = L"O menor volume livre esta em " +
                std::to_wstring(current.lowest_drive_free_percent) + L"%.";
        }
        CloudOSNativeNotificationCenter::Post(
            current.health_text, detail, current.health_severity);
        NativeToastOverlay::Post(
            current.health_text, detail, current.health_severity, 6500u);
    }

    if (!previous.wifi_connected && current.wifi_connected && !current.wifi_ssid.empty())
    {
        const std::wstring detail = L"Conectado a " + current.wifi_ssid + L" · " +
            std::to_wstring(current.wifi_signal) + L"% de sinal.";
        NativeToastOverlay::Post(L"Wi-Fi conectado", detail, 0, 3600u);
    }
}

LRESULT NativeControlPlaneService::HandleMessage(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            RefreshInternal(true);
            return 0;
        }
        break;
    case kRefreshMessage:
        RefreshInternal(false);
        return 0;
    case WM_NCDESTROY:
        if (window_ == window) window_ = nullptr;
        break;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK NativeControlPlaneService::WindowProcedure(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeControlPlaneService*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = reinterpret_cast<NativeControlPlaneService*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
