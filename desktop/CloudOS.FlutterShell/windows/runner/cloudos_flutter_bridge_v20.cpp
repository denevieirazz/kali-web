#include "cloudos_flutter_bridge_v20.h"
#include "cloudos_broker_client_v21.h"
#include "cloudos_conpty_manager.h"
#include "cloudos_system_metrics_native.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <iostream>

namespace CloudOS
{

namespace
{
constexpr const char* kChannelName = "cloudos/native/v19";

std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size, nullptr, nullptr);
    return result;
}

void QueryWslFromRegistry(std::vector<std::string>& out_distros, std::string& out_default_distro, bool& out_wsl_available)
{
    out_distros.clear();
    out_default_distro.clear();
    out_wsl_available = false;

    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss", 0, KEY_READ, &key) == ERROR_SUCCESS)
    {
        WCHAR default_guid[128] = {0};
        DWORD default_guid_size = sizeof(default_guid);
        DWORD type = 0;
        bool has_default = (RegQueryValueExW(key, L"DefaultDistribution", nullptr, &type, reinterpret_cast<LPBYTE>(default_guid), &default_guid_size) == ERROR_SUCCESS);

        DWORD index = 0;
        WCHAR subkey_name[256];
        DWORD name_len = ARRAYSIZE(subkey_name);

        while (RegEnumKeyExW(key, index++, subkey_name, &name_len, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
        {
            HKEY distro_key = nullptr;
            if (RegOpenKeyExW(key, subkey_name, 0, KEY_READ, &distro_key) == ERROR_SUCCESS)
            {
                WCHAR distro_name[256];
                DWORD distro_name_size = sizeof(distro_name);
                if (RegQueryValueExW(distro_key, L"DistributionName", nullptr, &type, reinterpret_cast<LPBYTE>(distro_name), &distro_name_size) == ERROR_SUCCESS)
                {
                    std::string d_name = WideToUtf8(distro_name);
                    out_distros.push_back(d_name);

                    if (has_default && _wcsicmp(subkey_name, default_guid) == 0)
                    {
                        out_default_distro = d_name;
                    }
                }
                RegCloseKey(distro_key);
            }
            name_len = ARRAYSIZE(subkey_name);
        }
        RegCloseKey(key);
    }

    if (out_default_distro.empty() && !out_distros.empty())
    {
        out_default_distro = out_distros.front();
    }

    WCHAR sys_dir[MAX_PATH];
    if (GetSystemDirectoryW(sys_dir, MAX_PATH) > 0)
    {
        std::wstring wsl_exe = std::wstring(sys_dir) + L"\\wsl.exe";
        DWORD attr = GetFileAttributesW(wsl_exe.c_str());
        if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY))
        {
            out_wsl_available = true;
        }
    }

    if (!out_distros.empty())
    {
        out_wsl_available = true;
    }
}

} // namespace

void CloudOSFlutterBridgeV20::RegisterWithMessenger(
    flutter::BinaryMessenger* messenger,
    HWND window_handle)
{
    auto& bridge = Instance();
    bridge.Initialize(window_handle);

    bridge.channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    CloudOSConPTYManager::Instance().SetMethodChannel(bridge.channel_.get());
    CloudOSConPTYManager::Instance().SetPlatformWindow(window_handle);

    bridge.channel_->SetMethodCallHandler(
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
        map[flutter::EncodableValue("defaultDistro")] = flutter::EncodableValue(snapshot.default_distro);
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

    if (method == "getSystemMetrics")
    {
        const auto metrics = CloudOSSystemMetricsNative::Instance().CollectMetrics();
        result->Success(flutter::EncodableValue(CloudOSSystemMetricsNative::Instance().ToEncodableMap(metrics)));
        return;
    }

    if (method == "lockSession")
    {
        BOOL ok = LockWorkStation();
        result->Success(flutter::EncodableValue(ok == TRUE));
        return;
    }

    // ==========================================
    // ConPTY Terminal Methods
    // ==========================================
    if (method == "terminal.createSession")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        std::string shell_kind = "powershell";
        std::string distro = "";
        int cols = 80;
        int rows = 24;

        if (args)
        {
            auto it_k = args->find(flutter::EncodableValue("shellKind"));
            if (it_k != args->end() && std::holds_alternative<std::string>(it_k->second))
            {
                shell_kind = std::get<std::string>(it_k->second);
            }
            auto it_d = args->find(flutter::EncodableValue("distro"));
            if (it_d != args->end() && std::holds_alternative<std::string>(it_d->second))
            {
                distro = std::get<std::string>(it_d->second);
            }
            auto it_c = args->find(flutter::EncodableValue("cols"));
            if (it_c != args->end() && std::holds_alternative<int>(it_c->second))
            {
                cols = std::get<int>(it_c->second);
            }
            auto it_r = args->find(flutter::EncodableValue("rows"));
            if (it_r != args->end() && std::holds_alternative<int>(it_r->second))
            {
                rows = std::get<int>(it_r->second);
            }
        }

        std::string err;
        std::string session_id = CloudOSConPTYManager::Instance().CreateSession(shell_kind, distro, cols, rows, err);
        if (!session_id.empty())
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(session_id);
            result->Success(flutter::EncodableValue(std::move(map)));
        }
        else
        {
            result->Error("CONPTY_CREATE_FAILED", err.empty() ? "Failed to create PseudoConsole session" : err);
        }
        return;
    }

    if (method == "terminal.write")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it_s = args->find(flutter::EncodableValue("sessionId"));
            auto it_d = args->find(flutter::EncodableValue("data"));
            if (it_s != args->end() && std::holds_alternative<std::string>(it_s->second) &&
                it_d != args->end() && std::holds_alternative<std::string>(it_d->second))
            {
                bool ok = CloudOSConPTYManager::Instance().WriteSession(
                    std::get<std::string>(it_s->second),
                    std::get<std::string>(it_d->second));
                result->Success(flutter::EncodableValue(ok));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "terminal.write requires 'sessionId' and 'data'");
        return;
    }

    if (method == "terminal.resize")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it_s = args->find(flutter::EncodableValue("sessionId"));
            auto it_c = args->find(flutter::EncodableValue("cols"));
            auto it_r = args->find(flutter::EncodableValue("rows"));
            if (it_s != args->end() && std::holds_alternative<std::string>(it_s->second) &&
                it_c != args->end() && std::holds_alternative<int>(it_c->second) &&
                it_r != args->end() && std::holds_alternative<int>(it_r->second))
            {
                bool ok = CloudOSConPTYManager::Instance().ResizeSession(
                    std::get<std::string>(it_s->second),
                    std::get<int>(it_c->second),
                    std::get<int>(it_r->second));
                result->Success(flutter::EncodableValue(ok));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "terminal.resize requires 'sessionId', 'cols', and 'rows'");
        return;
    }

    if (method == "terminal.signal")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it_s = args->find(flutter::EncodableValue("sessionId"));
            auto it_sig = args->find(flutter::EncodableValue("signal"));
            if (it_s != args->end() && std::holds_alternative<std::string>(it_s->second) &&
                it_sig != args->end() && std::holds_alternative<std::string>(it_sig->second))
            {
                bool ok = CloudOSConPTYManager::Instance().SignalSession(
                    std::get<std::string>(it_s->second),
                    std::get<std::string>(it_sig->second));
                result->Success(flutter::EncodableValue(ok));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "terminal.signal requires 'sessionId' and 'signal'");
        return;
    }

    if (method == "terminal.close")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it_s = args->find(flutter::EncodableValue("sessionId"));
            if (it_s != args->end() && std::holds_alternative<std::string>(it_s->second))
            {
                bool ok = CloudOSConPTYManager::Instance().CloseSession(std::get<std::string>(it_s->second));
                result->Success(flutter::EncodableValue(ok));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "terminal.close requires 'sessionId'");
        return;
    }

    if (method == "terminal.listSessions")
    {
        const auto sessions = CloudOSConPTYManager::Instance().ListSessions();
        flutter::EncodableList list;
        for (const auto& s : sessions)
        {
            flutter::EncodableMap s_map;
            s_map[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(s.session_id);
            s_map[flutter::EncodableValue("shellKind")] = flutter::EncodableValue(s.shell_kind);
            s_map[flutter::EncodableValue("distro")] = flutter::EncodableValue(s.distro);
            s_map[flutter::EncodableValue("cols")] = flutter::EncodableValue(s.cols);
            s_map[flutter::EncodableValue("rows")] = flutter::EncodableValue(s.rows);
            s_map[flutter::EncodableValue("isAlive")] = flutter::EncodableValue(s.is_alive);
            s_map[flutter::EncodableValue("processId")] = flutter::EncodableValue(static_cast<int64_t>(s.process_id));
            list.push_back(flutter::EncodableValue(std::move(s_map)));
        }
        result->Success(flutter::EncodableValue(std::move(list)));
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
        map[flutter::EncodableValue("conptyAvailable")] = flutter::EncodableValue(true);
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

        bool reg_wsl_avail = false;
        std::vector<std::string> reg_distros;
        std::string reg_default_distro;
        QueryWslFromRegistry(reg_distros, reg_default_distro, reg_wsl_avail);
        snap.default_distro = reg_default_distro;
        if (snap.distros.empty())
        {
            snap.distros = reg_distros;
            snap.wsl_available = reg_wsl_avail;
        }

        return snap;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (cached_snapshot_.distros.empty())
    {
        QueryWslFromRegistry(cached_snapshot_.distros, cached_snapshot_.default_distro, cached_snapshot_.wsl_available);
    }
    return cached_snapshot_;
}

bool CloudOSFlutterBridgeV20::LaunchApp(const std::string& app_id)
{
    std::string err;
    if (CloudOSBrokerClientV21::Instance().LaunchApp(app_id, err))
    {
        return true;
    }

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
