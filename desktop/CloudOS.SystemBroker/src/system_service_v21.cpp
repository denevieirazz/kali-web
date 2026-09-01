#include "system_service_v21.h"
#include "event_bus_v21.h"
#include "security_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <endpointvolume.h>
#include <highlevelmonitorconfigurationapi.h>
#include <iphlpapi.h>
#include <mmdeviceapi.h>
#include <physicalmonitorenumerationapi.h>

#include <algorithm>
#include <chrono>
#include <string>
#include <vector>

namespace CloudOS
{

namespace
{
std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    const int size_needed = WideCharToMultiByte(
        CP_UTF8,
        0,
        wstr.data(),
        static_cast<int>(wstr.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (size_needed <= 0) return {};

    std::string result(size_needed, 0);
    WideCharToMultiByte(
        CP_UTF8,
        0,
        wstr.data(),
        static_cast<int>(wstr.size()),
        result.data(),
        size_needed,
        nullptr,
        nullptr);
    return result;
}

uint64_t NowMs()
{
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
}

class ScopedCom final
{
public:
    ScopedCom()
        : hr_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)),
          must_uninitialize_(SUCCEEDED(hr_))
    {
    }

    ~ScopedCom()
    {
        if (must_uninitialize_)
        {
            CoUninitialize();
        }
    }

    [[nodiscard]] bool usable() const noexcept
    {
        return SUCCEEDED(hr_) || hr_ == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT hr_{E_FAIL};
    bool must_uninitialize_{false};
};

bool TryGetMasterVolume(double& value)
{
    ScopedCom com;
    if (!com.usable()) return false;

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioEndpointVolume* endpoint = nullptr;

    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || !enumerator) goto cleanup;

    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    if (FAILED(hr) || !device) goto cleanup;

    hr = device->Activate(
        __uuidof(IAudioEndpointVolume),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&endpoint));
    if (FAILED(hr) || !endpoint) goto cleanup;

    {
        float scalar = 0.0f;
        hr = endpoint->GetMasterVolumeLevelScalar(&scalar);
        if (SUCCEEDED(hr))
        {
            value = std::clamp(static_cast<double>(scalar), 0.0, 1.0);
        }
    }

cleanup:
    if (endpoint) endpoint->Release();
    if (device) device->Release();
    if (enumerator) enumerator->Release();
    return SUCCEEDED(hr);
}

bool TrySetMasterVolume(double value)
{
    ScopedCom com;
    if (!com.usable()) return false;

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioEndpointVolume* endpoint = nullptr;

    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || !enumerator) goto cleanup;

    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    if (FAILED(hr) || !device) goto cleanup;

    hr = device->Activate(
        __uuidof(IAudioEndpointVolume),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&endpoint));
    if (FAILED(hr) || !endpoint) goto cleanup;

    hr = endpoint->SetMasterVolumeLevelScalar(
        static_cast<float>(std::clamp(value, 0.0, 1.0)),
        nullptr);

cleanup:
    if (endpoint) endpoint->Release();
    if (device) device->Release();
    if (enumerator) enumerator->Release();
    return SUCCEEDED(hr);
}

bool TryGetPrimaryBrightness(double& value)
{
    HMONITOR monitor = MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);
    if (!monitor) return false;

    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0)
    {
        return false;
    }

    std::vector<PHYSICAL_MONITOR> monitors(count);
    if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors.data()))
    {
        return false;
    }

    bool success = false;
    for (const auto& physical : monitors)
    {
        DWORD minimum = 0;
        DWORD current = 0;
        DWORD maximum = 0;
        if (GetMonitorBrightness(physical.hPhysicalMonitor, &minimum, &current, &maximum) && maximum > minimum)
        {
            value = std::clamp(
                static_cast<double>(current - minimum) / static_cast<double>(maximum - minimum),
                0.0,
                1.0);
            success = true;
            break;
        }
    }

    DestroyPhysicalMonitors(count, monitors.data());
    return success;
}

bool TrySetPrimaryBrightness(double value)
{
    HMONITOR monitor = MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);
    if (!monitor) return false;

    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0)
    {
        return false;
    }

    std::vector<PHYSICAL_MONITOR> monitors(count);
    if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors.data()))
    {
        return false;
    }

    const double clamped = std::clamp(value, 0.0, 1.0);
    bool any_success = false;
    for (const auto& physical : monitors)
    {
        DWORD minimum = 0;
        DWORD current = 0;
        DWORD maximum = 0;
        if (!GetMonitorBrightness(physical.hPhysicalMonitor, &minimum, &current, &maximum) || maximum <= minimum)
        {
            continue;
        }

        const DWORD target = minimum + static_cast<DWORD>(
            clamped * static_cast<double>(maximum - minimum));
        if (SetMonitorBrightness(physical.hPhysicalMonitor, target))
        {
            any_success = true;
        }
    }

    DestroyPhysicalMonitors(count, monitors.data());
    return any_success;
}

bool TryGetActiveNetworkName(std::string& name)
{
    ULONG buffer_size = 0;
    ULONG result = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr,
        nullptr,
        &buffer_size);
    if (result != ERROR_BUFFER_OVERFLOW || buffer_size == 0)
    {
        return false;
    }

    std::vector<BYTE> buffer(buffer_size);
    auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    result = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr,
        adapters,
        &buffer_size);
    if (result != NO_ERROR)
    {
        return false;
    }

    for (auto* adapter = adapters; adapter != nullptr; adapter = adapter->Next)
    {
        if (adapter->OperStatus != IfOperStatusUp ||
            adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
            adapter->FirstUnicastAddress == nullptr)
        {
            continue;
        }

        std::string friendly;
        if (adapter->FriendlyName)
        {
            friendly = WideToUtf8(adapter->FriendlyName);
        }

        if (adapter->IfType == IF_TYPE_IEEE80211)
        {
            name = friendly.empty() ? "Wi-Fi" : "Wi-Fi • " + friendly;
        }
        else if (adapter->IfType == IF_TYPE_ETHERNET_CSMACD)
        {
            name = friendly.empty() ? "Ethernet" : "Ethernet • " + friendly;
        }
        else
        {
            name = friendly.empty() ? "Rede conectada" : friendly;
        }
        return true;
    }

    return false;
}

} // namespace

JsonObject SystemSnapshot::ToJsonObject() const
{
    JsonObject obj;
    obj["deviceName"] = JsonValue(device_name);
    obj["userName"] = JsonValue(user_name);
    obj["sessionId"] = JsonValue(static_cast<int64_t>(session_id));
    obj["batteryAvailable"] = JsonValue(battery_available);
    obj["batteryPercent"] = JsonValue(battery_percent);
    obj["networkAvailable"] = JsonValue(network_available);
    obj["networkName"] = JsonValue(network_name);
    obj["volumeAvailable"] = JsonValue(volume_available);
    obj["volume"] = JsonValue(volume);
    obj["brightnessAvailable"] = JsonValue(brightness_available);
    obj["brightness"] = JsonValue(brightness);
    obj["wslAvailable"] = JsonValue(wsl_available);

    JsonArray distros_arr;
    for (const auto& d : distros)
    {
        distros_arr.push_back(JsonValue(d));
    }
    obj["distros"] = JsonValue(std::move(distros_arr));
    obj["currentWorkspace"] = JsonValue(current_workspace);
    obj["timestamp"] = JsonValue(static_cast<int64_t>(timestamp_ms));
    return obj;
}

SystemServiceV21& SystemServiceV21::Instance()
{
    static SystemServiceV21 instance;
    return instance;
}

SystemSnapshot SystemServiceV21::GetSnapshot()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load())
    {
        Refresh();
    }
    return snapshot_;
}

bool SystemServiceV21::SetVolume(double value)
{
    const double clamped = std::clamp(value, 0.0, 1.0);
    if (!TrySetMasterVolume(clamped))
    {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot_.volume_available = true;
        snapshot_.volume = clamped;
        snapshot_.timestamp_ms = NowMs();
        generation_++;
    }

    JsonObject payload;
    payload["volume"] = JsonValue(clamped);
    payload["generation"] = JsonValue(static_cast<int64_t>(generation_.load()));
    EventBusV21::Instance().Publish("system.volumeChanged", payload);
    return true;
}

bool SystemServiceV21::SetBrightness(double value)
{
    const double clamped = std::clamp(value, 0.0, 1.0);
    if (!TrySetPrimaryBrightness(clamped))
    {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot_.brightness_available = true;
        snapshot_.brightness = clamped;
        snapshot_.timestamp_ms = NowMs();
        generation_++;
    }

    JsonObject payload;
    payload["brightness"] = JsonValue(clamped);
    payload["generation"] = JsonValue(static_cast<int64_t>(generation_.load()));
    EventBusV21::Instance().Publish("system.brightnessChanged", payload);
    return true;
}

std::vector<std::string> SystemServiceV21::GetCapabilities()
{
    std::vector<std::string> caps = {
        "broker.protocol.v21",
        "health.ping",
        "health.status",
        "apps.list",
        "apps.launch",
        "system.snapshot",
        "wsl.list",
        "events.subscribe",
        "events.unsubscribe",
        "jobs.submit",
        "jobs.status",
        "jobs.cancel",
        "diagnostics.snapshot",
    };

    const SystemSnapshot snapshot = GetSnapshot();
    if (snapshot.volume_available)
    {
        caps.push_back("system.volume.read");
        caps.push_back("system.volume.write");
    }
    if (snapshot.brightness_available)
    {
        caps.push_back("system.brightness.read");
        caps.push_back("system.brightness.write");
    }
    return caps;
}

void SystemServiceV21::Invalidate()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        Refresh();
        generation_++;
    }

    JsonObject payload;
    payload["generation"] = JsonValue(static_cast<int64_t>(generation_.load()));
    EventBusV21::Instance().Publish("system.snapshotChanged", payload);
}

void SystemServiceV21::Refresh()
{
    snapshot_ = {};

    WCHAR computer_name[MAX_COMPUTERNAME_LENGTH + 1]{};
    DWORD computer_name_size = ARRAYSIZE(computer_name);
    if (GetComputerNameW(computer_name, &computer_name_size))
    {
        snapshot_.device_name = WideToUtf8(computer_name);
    }
    if (snapshot_.device_name.empty())
    {
        snapshot_.device_name = "CloudOS Desktop";
    }

    WCHAR user_name[256]{};
    DWORD user_size = ARRAYSIZE(user_name);
    if (GetUserNameW(user_name, &user_size))
    {
        snapshot_.user_name = WideToUtf8(user_name);
    }
    if (snapshot_.user_name.empty())
    {
        snapshot_.user_name = "User";
    }

    snapshot_.session_id = SecurityV21::GetCurrentSessionId();

    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power) && power.BatteryLifePercent != 255)
    {
        snapshot_.battery_available = true;
        snapshot_.battery_percent = static_cast<int>(power.BatteryLifePercent);
    }
    else
    {
        snapshot_.battery_available = false;
        snapshot_.battery_percent = 100;
    }

    snapshot_.network_available = TryGetActiveNetworkName(snapshot_.network_name);
    if (!snapshot_.network_available)
    {
        snapshot_.network_name = "Offline";
    }

    snapshot_.volume_available = TryGetMasterVolume(snapshot_.volume);
    if (!snapshot_.volume_available)
    {
        snapshot_.volume = 0.0;
    }

    snapshot_.brightness_available = TryGetPrimaryBrightness(snapshot_.brightness);
    if (!snapshot_.brightness_available)
    {
        snapshot_.brightness = 0.0;
    }

    snapshot_.distros = WslServiceV21::Instance().GetDistributions();
    snapshot_.wsl_available = WslServiceV21::Instance().IsWslAvailable();
    snapshot_.current_workspace = 1;
    snapshot_.timestamp_ms = NowMs();

    initialized_.store(true);
}

} // namespace CloudOS
