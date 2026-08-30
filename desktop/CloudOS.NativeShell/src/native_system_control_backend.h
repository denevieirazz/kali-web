#pragma once

#include <windows.h>
#include <guiddef.h>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <iterator>
#include <new>
#include <string>
#include <vector>

namespace CloudOS
{
struct NativeWifiNetwork final
{
    GUID interface_guid{};
    std::wstring interface_name;
    std::wstring ssid;
    std::wstring profile_name;
    unsigned signal_quality{};
    bool secure{};
    bool connected{};
};

struct NativeNetworkAdapter final
{
    std::wstring name;
    std::wstring description;
    std::wstring status;
    std::wstring ipv4;
    std::wstring ipv6;
    std::wstring mac;
    std::uint64_t transmit_mbps{};
    std::uint64_t receive_mbps{};
};

struct NativeDriveInfo final
{
    std::wstring root;
    std::wstring label;
    std::wstring file_system;
    std::wstring type;
    std::uint64_t total_bytes{};
    std::uint64_t free_bytes{};
};

struct NativeProcessInfo final
{
    DWORD process_id{};
    std::wstring name;
    std::uint64_t working_set_bytes{};
    std::uint64_t private_bytes{};
};

struct NativeServiceInfo final
{
    std::wstring name;
    std::wstring display_name;
    std::wstring state;
};

struct NativeAudioState final
{
    bool available{};
    bool muted{};
    unsigned volume_percent{};
    std::wstring endpoint_name;
};

struct NativeBrightnessState final
{
    bool available{};
    unsigned percent{};
    std::wstring source;
    std::wstring monitor_name;
};

struct NativePowerState final
{
    bool battery_present{};
    bool on_ac{};
    unsigned battery_percent{};
    DWORD battery_life_seconds{};
    std::wstring active_plan;
};

struct NativeSystemSummary final
{
    unsigned memory_load_percent{};
    std::uint64_t total_memory_bytes{};
    std::uint64_t available_memory_bytes{};
    DWORD process_count{};
    unsigned monitor_count{};
    unsigned adapter_count{};
    unsigned drive_count{};
};

class NativeSystemControlBackend final
{
public:
    static NativeSystemSummary QuerySummary();

    static std::vector<NativeWifiNetwork> ScanWifi();
    static bool ConnectKnownWifi(const NativeWifiNetwork& network, std::wstring* error = nullptr);
    static bool DisconnectWifi(const GUID& interface_guid, std::wstring* error = nullptr);

    static NativeAudioState QueryAudio();
    static bool SetMasterVolume(unsigned percent, std::wstring* error = nullptr);
    static bool SetMasterMute(bool muted, std::wstring* error = nullptr);

    static NativeBrightnessState QueryBrightness();
    static bool SetBrightness(unsigned percent, std::wstring* error = nullptr);

    static NativePowerState QueryPower();
    static bool SetBalancedPowerPlan(std::wstring* error = nullptr);
    static bool SetPowerSaverPlan(std::wstring* error = nullptr);
    static bool SetHighPerformancePlan(std::wstring* error = nullptr);

    static std::vector<NativeNetworkAdapter> QueryAdapters();
    static std::vector<NativeDriveInfo> QueryDrives();
    static std::vector<NativeProcessInfo> QueryProcesses(std::size_t maximum = 40);
    static std::vector<NativeServiceInfo> QueryCoreServices();

    static bool OpenWindowsTarget(HWND owner, const wchar_t* target, const wchar_t* parameters = nullptr);
    static std::wstring FormatBytes(std::uint64_t bytes);
};
} // namespace CloudOS
