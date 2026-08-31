#pragma once

#include <windows.h>

#include <cstdint>
#include <string>
#include <thread>
#include <atomic>

#include "native_system_control_backend.h"

namespace CloudOS
{
struct NativeControlPlaneSnapshot final
{
    NativeAudioState audio{};
    NativeBrightnessState brightness{};
    NativePowerState power{};
    bool wifi_available{};
    bool wifi_connected{};
    std::wstring wifi_ssid;
    unsigned wifi_signal{};
    std::wstring health_text{L"Sistema normal"};
    int health_severity{};
    std::uint64_t lowest_drive_free_bytes{};
    unsigned lowest_drive_free_percent{100u};
    unsigned monitor_count{};
    unsigned process_count{};
    std::uint64_t generation{};
};

class NativeControlPlaneService final
{
public:
    static NativeControlPlaneService& Instance();

    bool Start(HINSTANCE instance);
    void Stop() noexcept;
    void RefreshNow();
    [[nodiscard]] NativeControlPlaneSnapshot Snapshot() const;
    [[nodiscard]] HWND EngineWindow() const noexcept { return window_; }

private:
    NativeControlPlaneService() = default;
    ~NativeControlPlaneService() { Stop(); }
    NativeControlPlaneService(const NativeControlPlaneService&) = delete;
    NativeControlPlaneService& operator=(const NativeControlPlaneService&) = delete;

    void RefreshInternal(bool allow_alerts);
    void RequestRefresh(bool allow_alerts);
    std::thread worker_v12_;
    std::atomic_bool busy_v12_{};
    NativeControlPlaneSnapshot pending_previous_v12_, pending_current_v12_;
    void EvaluateAlerts(const NativeControlPlaneSnapshot& previous,
        const NativeControlPlaneSnapshot& current);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
};
} // namespace CloudOS
