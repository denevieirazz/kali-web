#include "system_service_v21.h"
#include "event_bus_v21.h"
#include "network_status_v21.h"
#include "security_v21.h"
#include "system_control_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>

#include <algorithm>
#include <chrono>

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

    // Preserve the V21 scalar/list fields for older clients.
    obj["wslAvailable"] = JsonValue(wsl_available);
    obj["defaultDistro"] = JsonValue(default_distro);
    JsonArray distros_arr;
    for (const auto& d : distros)
    {
        distros_arr.push_back(JsonValue(d));
    }
    obj["distros"] = JsonValue(std::move(distros_arr));

    // Additive evidence for clients that need to distinguish an installed WSL
    // engine from a usable registered distribution. No distro is launched to
    // produce this snapshot.
    obj["wslEngineAvailable"] = JsonValue(wsl_engine_available);
    obj["wslPassiveReady"] = JsonValue(wsl_passive_ready);
    obj["wslRegisteredCount"] = JsonValue(static_cast<int64_t>(wsl_registered_count));
    obj["wslLaunchCandidateCount"] = JsonValue(static_cast<int64_t>(wsl_launch_candidate_count));
    obj["wsl1Count"] = JsonValue(static_cast<int64_t>(wsl1_count));
    obj["wsl2Count"] = JsonValue(static_cast<int64_t>(wsl2_count));
    obj["preferredSecurityDistro"] = JsonValue(preferred_security_distro);

    JsonArray typed_distros;
    for (const auto& distro : wsl_distros)
    {
        JsonObject item;
        item["name"] = JsonValue(distro.name);
        item["isDefault"] = JsonValue(distro.is_default);
        item["basePathPresent"] = JsonValue(distro.base_path_present);
        item["securityCandidate"] = JsonValue(distro.is_security_candidate);
        item["versionKnown"] = JsonValue(distro.version == 1 || distro.version == 2);
        if (distro.version == 1 || distro.version == 2)
        {
            item["version"] = JsonValue(distro.version);
        }
        typed_distros.push_back(JsonValue(std::move(item)));
    }
    obj["wslDistros"] = JsonValue(std::move(typed_distros));

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
    if (!SystemControlV21::SetVolume(clamped))
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
    if (!SystemControlV21::SetBrightness(clamped))
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
    return {
        "broker.protocol.v21",
        "health.ping",
        "health.status",
        "apps.list",
        "apps.launch",
        "files.list",
        "system.snapshot",
        "system.network.read",
        "system.volume.read",
        "system.volume.write",
        "system.brightness.read",
        "system.brightness.write",
        "wsl.list",
        "wsl.inventory.typed",
        "wsl.inventory.health",
        "wsl.health.probe",
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

    const NetworkStatusV21 network = NetworkStatusServiceV21::Query();
    snapshot_.network_available = network.available;
    snapshot_.network_name = network.available && !network.name.empty()
        ? network.name
        : "Desconectado";

    const AudioControlStateV21 audio = SystemControlV21::QueryAudio();
    snapshot_.volume_available = audio.available;
    snapshot_.volume = audio.available ? audio.volume : 0.0;

    const BrightnessControlStateV21 brightness = SystemControlV21::QueryBrightness();
    snapshot_.brightness_available = brightness.available;
    snapshot_.brightness = brightness.available ? brightness.brightness : 0.0;

    const WslRuntimeSnapshotV21 wsl = WslServiceV21::Instance().GetRuntimeSnapshot();
    snapshot_.wsl_engine_available = wsl.engine_available;
    snapshot_.wsl_available = wsl.usable;
    snapshot_.wsl_passive_ready = wsl.passive_ready;
    snapshot_.default_distro = wsl.default_distribution;
    snapshot_.preferred_security_distro = wsl.preferred_security_distribution;
    snapshot_.wsl_registered_count = wsl.registered_count;
    snapshot_.wsl_launch_candidate_count = wsl.launch_candidate_count;
    snapshot_.wsl1_count = wsl.wsl1_count;
    snapshot_.wsl2_count = wsl.wsl2_count;
    snapshot_.distros.reserve(wsl.distributions.size());
    snapshot_.wsl_distros.reserve(wsl.distributions.size());
    for (const auto& distro : wsl.distributions)
    {
        snapshot_.distros.push_back(distro.name);
        snapshot_.wsl_distros.push_back(SystemWslDistributionSnapshot{
            distro.name,
            distro.version,
            distro.is_default,
            distro.base_path_present,
            distro.is_security_candidate});
    }

    snapshot_.current_workspace = 1;
    snapshot_.timestamp_ms = NowMs();

    initialized_.store(true);
}

} // namespace CloudOS
