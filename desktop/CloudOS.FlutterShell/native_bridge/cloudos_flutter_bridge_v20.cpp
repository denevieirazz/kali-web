#include "cloudos_flutter_bridge_v20.h"
#include "cloudos_broker_client_v21.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <iostream>

namespace CloudOS
{

namespace
{
constexpr const char* kChannelName = "cloudos/native/v19";
} // namespace

void CloudOSFlutterBridgeV20::RegisterWithMessenger(
    flutter::BinaryMessenger* messenger,
    HWND window_handle)
{
    auto& bridge = Instance();
    bridge.Initialize(window_handle);

    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            CloudOSFlutterBridgeV20::Instance().HandleMethodCall(call, std::move(result));
        });

    bridge.is_registered_.store(true);
}

CloudOSFlutterBridgeV20& CloudOSFlutterBridgeV20::Instance()
{
    static CloudOSFlutterBridgeV20 instance;
    return instance;
}

void CloudOSFlutterBridgeV20::Initialize(HWND window_handle)
{
    window_handle_ = window_handle;
    // Attempt connection to SystemBroker
    CloudOSBrokerClientV21::Instance().EnsureConnected();
    RefreshAppCatalog();
    RefreshSystemSnapshot();
}

void CloudOSFlutterBridgeV20::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    const std::string& method = method_call.method_name();

    if (method == "getApps")
    {
        const auto apps = GetApps();
        flutter::EncodableList list;
        list.reserve(apps.size());

        for (const auto& app : apps)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("id")] = flutter::EncodableValue(app.id);
            map[flutter::EncodableValue("name")] = flutter::EncodableValue(app.name);
            map[flutter::EncodableValue("platform")] = flutter::EncodableValue(app.platform);
            map[flutter::EncodableValue("subtitle")] = flutter::EncodableValue(app.subtitle);
            map[flutter::EncodableValue("distro")] = flutter::EncodableValue(app.distro);
            map[flutter::EncodableValue("category")] = flutter::EncodableValue(app.category);
            map[flutter::EncodableValue("source")] = flutter::EncodableValue(app.source);
            map[flutter::EncodableValue("canLaunch")] = flutter::EncodableValue(app.can_launch);
            map[flutter::EncodableValue("pinned")] = flutter::EncodableValue(app.pinned);
            map[flutter::EncodableValue("recent")] = flutter::EncodableValue(app.recent);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }

        result->Success(flutter::EncodableValue(std::move(list)));
        return;
    }

    if (method == "getSystemSnapshot")
    {
        const auto snapshot = GetSystemSnapshot();
        flutter::EncodableMap map;
        map[flutter::EncodableValue("deviceName")] = flutter::EncodableValue(snapshot.device_name);
        map[flutter::EncodableValue("networkName")] = flutter::EncodableValue(snapshot.network_name);
        map[flutter::EncodableValue("volume")] = flutter::EncodableValue(snapshot.volume);
        map[flutter::EncodableValue("brightness")] = flutter::EncodableValue(snapshot.brightness);
        map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(snapshot.battery_percent);
        map[flutter::EncodableValue("wslAvailable")] = flutter::EncodableValue(snapshot.wsl_available);
        map[flutter::EncodableValue("currentWorkspace")] = flutter::EncodableValue(snapshot.current_workspace);

        flutter::EncodableList distros_list;
        for (const auto& d : snapshot.distros)
        {
            distros_list.push_back(flutter::EncodableValue(d));
        }
        map[flutter::EncodableValue("distros")] = flutter::EncodableValue(std::move(distros_list));

        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "launchApp")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (!args)
        {
            result->Error("INVALID_ARGUMENT", "launchApp requires a map with an 'id' property");
            return;
        }

        auto it = args->find(flutter::EncodableValue("id"));
        if (it == args->end() || !std::holds_alternative<std::string>(it->second))
        {
            result->Error("INVALID_ARGUMENT", "Missing or invalid 'id' parameter");
            return;
        }

        const std::string app_id = std::get<std::string>(it->second);
        bool ok = LaunchApp(app_id);
        if (ok)
        {
            result->Success(flutter::EncodableValue(true));
        }
        else
        {
            result->Error("LAUNCH_FAILED", "Failed to launch application with ID: " + app_id);
        }
        return;
    }

    if (method == "setVolume")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                const bool updated = SetVolume(std::get<double>(it->second));
                result->Success(flutter::EncodableValue(updated));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setVolume requires a double 'value'");
        return;
    }

    if (method == "setBrightness")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                const bool updated = SetBrightness(std::get<double>(it->second));
                result->Success(flutter::EncodableValue(updated));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setBrightness requires a double 'value'");
        return;
    }

    if (method == "getBridgeInfo")
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("schema")] = flutter::EncodableValue(21);
        map[flutter::EncodableValue("verdict")] = flutter::EncodableValue("pass");
        map[flutter::EncodableValue("brokerConnected")] = flutter::EncodableValue(CloudOSBrokerClientV21::Instance().IsConnected());
        map[flutter::EncodableValue("brokerState")] = flutter::EncodableValue(ConnectionStateToString(CloudOSBrokerClientV21::Instance().GetConnectionState()));
        map[flutter::EncodableValue("arbitrary_command_api")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("winlogon_modified")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("shell_activation_executed")] = flutter::EncodableValue(false);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "invokeBrokerRpc")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (!args)
        {
            result->Error("INVALID_ARGUMENT", "invokeBrokerRpc requires a map with 'method' and 'payload'");
            return;
        }

        auto it_m = args->find(flutter::EncodableValue("method"));
        auto it_p = args->find(flutter::EncodableValue("payload"));
        if (it_m == args->end() || !std::holds_alternative<std::string>(it_m->second))
        {
            result->Error("INVALID_ARGUMENT", "Missing 'method' string in arguments");
            return;
        }

        std::string rpc_method = std::get<std::string>(it_m->second);
        std::string rpc_payload = (it_p != args->end() && std::holds_alternative<std::string>(it_p->second)) ? std::get<std::string>(it_p->second) : "{}";

        std::string out_resp;
        if (CloudOSBrokerClientV21::Instance().InvokeBrokerRpc(rpc_method, rpc_payload, out_resp))
        {
            result->Success(flutter::EncodableValue(out_resp));
        }
        else
        {
            result->Error("BROKER_RPC_FAILED", "Failed to communicate with System Broker for method: " + rpc_method);
        }
        return;
    }

    result->NotImplemented();
}

std::vector<NativeAppItem> CloudOSFlutterBridgeV20::GetApps()
{
    std::vector<BrokerClientAppItem> broker_apps;
    if (CloudOSBrokerClientV21::Instance().GetApps(broker_apps) && !broker_apps.empty())
    {
        std::vector<NativeAppItem> result;
        result.reserve(broker_apps.size());
        for (const auto& a : broker_apps)
        {
            result.push_back({a.id, a.name, a.platform, a.subtitle, a.distro, a.category, a.source, a.can_launch, a.pinned, a.recent});
        }
        return result;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    return cached_apps_;
}

NativeSystemSnapshot CloudOSFlutterBridgeV20::GetSystemSnapshot()
{
    BrokerClientSnapshot broker_snap;
    if (CloudOSBrokerClientV21::Instance().GetSystemSnapshot(broker_snap))
    {
        NativeSystemSnapshot snap;
        snap.device_name = broker_snap.device_name;
        snap.network_name = broker_snap.network_name;
        snap.volume = broker_snap.volume;
        snap.brightness = broker_snap.brightness;
        snap.battery_percent = broker_snap.battery_percent;
        snap.wsl_available = broker_snap.wsl_available;
        snap.distros = broker_snap.distros;
        snap.current_workspace = broker_snap.current_workspace;
        return snap;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    return cached_snapshot_;
}

bool CloudOSFlutterBridgeV20::LaunchApp(const std::string& app_id)
{
    std::string err;
    if (CloudOSBrokerClientV21::Instance().LaunchApp(app_id, err))
    {
        return true;
    }

    // Flutter is a presentation client. It has no local execution fallback.
    return false;
}

bool CloudOSFlutterBridgeV20::SetVolume(double volume)
{
    double clamped = std::clamp(volume, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetVolume(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.volume = clamped;
    return true;
}

bool CloudOSFlutterBridgeV20::SetBrightness(double brightness)
{
    double clamped = std::clamp(brightness, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetBrightness(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.brightness = clamped;
    return true;
}

void CloudOSFlutterBridgeV20::RefreshAppCatalog()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_apps_.clear();
}

void CloudOSFlutterBridgeV20::RefreshSystemSnapshot()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_ = {};
}

} // namespace CloudOS
