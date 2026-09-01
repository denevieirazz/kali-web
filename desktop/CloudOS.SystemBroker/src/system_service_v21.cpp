#include "system_service_v21.h"
#include "event_bus_v21.h"
#include "security_v21.h"
#include "wsl_service_v21.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <Windows.h>
#include <endpointvolume.h>
#include <iphlpapi.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace CloudOS
{

namespace
{
std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size_needed <= 0) return {};
    std::string result(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size_needed, nullptr, nullptr);
    return result;
}

uint64_t NowMs()
{
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
}

bool QueryMasterVolume(double* out_volume)
{
    if (!out_volume) return false;
    const HRESULT init_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool uninitialize = SUCCEEDED(init_hr);

    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    Microsoft::WRL::ComPtr<IMMDevice> device;
    if (SUCCEEDED(hr)) hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    Microsoft::WRL::ComPtr<IAudioEndpointVolume> endpoint;
    if (SUCCEEDED(hr)) hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, &endpoint);
    float scalar = 0.0F;
    if (SUCCEEDED(hr)) hr = endpoint->GetMasterVolumeLevelScalar(&scalar);

    if (uninitialize) CoUninitialize();
    if (FAILED(hr) || !std::isfinite(scalar)) return false;
    *out_volume = std::clamp(static_cast<double>(scalar), 0.0, 1.0);
    return true;
}

bool SetMasterVolume(double value)
{
    const HRESULT init_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool uninitialize = SUCCEEDED(init_hr);

    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    Microsoft::WRL::ComPtr<IMMDevice> device;
    if (SUCCEEDED(hr)) hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    Microsoft::WRL::ComPtr<IAudioEndpointVolume> endpoint;
    if (SUCCEEDED(hr)) hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, &endpoint);
    if (SUCCEEDED(hr)) hr = endpoint->SetMasterVolumeLevelScalar(static_cast<float>(value), nullptr);

    if (uninitialize) CoUninitialize();
    return SUCCEEDED(hr);
}

bool QueryConnectedNetwork(std::string* out_name)
{
    if (out_name) out_name->clear();
    ULONG bytes = 16 * 1024;
    std::vector<unsigned char> buffer(bytes);
    auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    ULONG result = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr,
        addresses,
        &bytes);
    if (result == ERROR_BUFFER_OVERFLOW)
    {
        buffer.resize(bytes);
        addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
        result = GetAdaptersAddresses(
            AF_UNSPEC,
            GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
            nullptr,
            addresses,
            &bytes);
    }
    if (result != NO_ERROR) return false;

    for (auto* adapter = addresses; adapter; adapter = adapter->Next)
    {
        if (adapter->OperStatus != IfOperStatusUp ||
            adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
            adapter->IfType == IF_TYPE_TUNNEL)
        {
            continue;
        }
        if (out_name && adapter->FriendlyName)
        {
            *out_name = WideToUtf8(adapter->FriendlyName);
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
    obj["defaultDistro"] = JsonValue(default_distro);
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
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    double clamped = value;
    if (!SetMasterVolume(clamped)) return false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
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
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    // V21 has no verified physical-monitor write backend. Returning false is
    // safer than claiming a value changed when the hardware did not expose it.
    return false;
}

std::vector<std::string> SystemServiceV21::GetCapabilities()
{
    return {
        "broker.protocol.v21",
        "health.ping",
        "health.status",
        "apps.list",
        "apps.launch",
        "system.snapshot",
        "system.volume.read",
        "system.volume.write",
        "system.brightness.read",
        "system.brightness.write",
        "wsl.list",
        "events.subscribe",
        "events.unsubscribe",
        "jobs.submit",
        "jobs.status",
        "jobs.cancel",
        "diagnostics.snapshot",
    };
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

    // Device Name
    WCHAR computer_name[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD size = ARRAYSIZE(computer_name);
    if (GetComputerNameW(computer_name, &size))
    {
        snapshot_.device_name = WideToUtf8(computer_name);
    }
    else
    {
        snapshot_.device_name = "CloudOS Desktop";
    }

    // User Name
    WCHAR user_name[256];
    DWORD user_size = ARRAYSIZE(user_name);
    if (GetUserNameW(user_name, &user_size))
    {
        snapshot_.user_name = WideToUtf8(user_name);
    }
    else
    {
        snapshot_.user_name = "User";
    }

    // Session ID
    snapshot_.session_id = SecurityV21::GetCurrentSessionId();

    // Power / Battery
    SYSTEM_POWER_STATUS power;
    if (GetSystemPowerStatus(&power) && power.BatteryLifePercent != 255)
    {
        snapshot_.battery_available = true;
        snapshot_.battery_percent = static_cast<int>(power.BatteryLifePercent);
    }
    else
    {
        snapshot_.battery_available = false;
        snapshot_.battery_percent = -1;
    }

    // Network
    snapshot_.network_available = QueryConnectedNetwork(&snapshot_.network_name);

    // Audio is read from the current default render endpoint. Brightness is
    // reported unavailable until a supported physical monitor API succeeds;
    // no placeholder hardware value is emitted.
    snapshot_.volume_available = QueryMasterVolume(&snapshot_.volume);
    snapshot_.brightness_available = false;
    snapshot_.brightness = 0.0;

    // WSL status
    snapshot_.distros = WslServiceV21::Instance().GetDistributions();
    snapshot_.default_distro = WslServiceV21::Instance().GetDefaultDistribution();
    snapshot_.wsl_available = WslServiceV21::Instance().IsWslAvailable();
    snapshot_.current_workspace = 1;
    snapshot_.timestamp_ms = NowMs();

    initialized_.store(true);
}

} // namespace CloudOS
