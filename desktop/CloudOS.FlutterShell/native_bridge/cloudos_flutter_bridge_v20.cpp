#include "cloudos_flutter_bridge_v20.h"
#include "cloudos_broker_client_v21.h"
#include "../../CloudOS.NativeCommon/native_shell_activation_client_v21.h"
#include "../../CloudOS.NativeCommon/native_shell_notification_client_v21.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <charconv>
#include <cstdio>
#include <cwchar>
#include <iostream>
#include <memory>
#include <system_error>

namespace CloudOS
{
namespace
{
constexpr const char* kChannelName = "cloudos/native/v19";

bool ResolveSurfaceApp(
    const std::string& id,
    ShellActivationV21::App* app)
{
    if (app == nullptr) return false;
    if (id == "browser" || id == "cloudos:browser")
    {
        *app = ShellActivationV21::App::Browser;
        return true;
    }
    if (id == "terminal" || id == "cloudos:terminal")
    {
        *app = ShellActivationV21::App::Terminal;
        return true;
    }
    return false;
}

bool ReadStringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    const char* key,
    std::string* value)
{
    if (value == nullptr) return false;
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) return false;
    const auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end() || !std::holds_alternative<std::string>(it->second)) return false;
    *value = std::get<std::string>(it->second);
    return !value->empty();
}

bool ReadSurfaceArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    ShellActivationV21::App* app,
    std::string* id)
{
    std::string surface_id;
    if (!ReadStringArgument(method_call, "id", &surface_id)) return false;
    if (!ResolveSurfaceApp(surface_id, app)) return false;
    if (id != nullptr) *id = surface_id;
    return true;
}

bool ReadWorkspaceArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    int* workspace)
{
    if (workspace == nullptr) return false;
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) return false;

    const auto it = args->find(flutter::EncodableValue("workspace"));
    if (it == args->end()) return false;

    if (const auto* value = std::get_if<int32_t>(&it->second))
    {
        *workspace = static_cast<int>(*value);
        return true;
    }
    if (const auto* value = std::get_if<int64_t>(&it->second))
    {
        if (*value < 1 || *value > ShellActivationV21::kWorkspaceCount) return false;
        *workspace = static_cast<int>(*value);
        return true;
    }
    return false;
}

std::string WideToUtf8(const wchar_t* value, std::size_t max_chars)
{
    if (value == nullptr || max_chars == 0) return {};
    const std::size_t length = wcsnlen_s(value, max_chars);
    if (length == 0 || length >= max_chars) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        static_cast<int>(length),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            0,
            value,
            static_cast<int>(length),
            result.data(),
            required,
            nullptr,
            nullptr) != required)
    {
        return {};
    }
    return result;
}

std::string FormatNotificationTime(const ShellNotificationV21::Item& item)
{
    char buffer[16]{};
    sprintf_s(
        buffer,
        "%02u:%02u",
        static_cast<unsigned int>(item.hour),
        static_cast<unsigned int>(item.minute));
    return buffer;
}

bool ParseNotificationId(const std::string& value, std::uint64_t* id)
{
    if (id == nullptr || value.empty()) return false;
    std::uint64_t parsed = 0;
    const auto result = std::from_chars(
        value.data(),
        value.data() + value.size(),
        parsed);
    if (result.ec != std::errc{} || result.ptr != value.data() + value.size() || parsed == 0)
    {
        return false;
    }
    *id = parsed;
    return true;
}

flutter::EncodableValue EncodeFileItems(const std::vector<NativeFileItem>& files)
{
    flutter::EncodableList list;
    list.reserve(files.size());
    for (const NativeFileItem& file : files)
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(file.name);
        map[flutter::EncodableValue("path")] = flutter::EncodableValue(file.path);
        map[flutter::EncodableValue("isFolder")] = flutter::EncodableValue(file.is_folder);
        map[flutter::EncodableValue("sizeFormatted")] = flutter::EncodableValue(file.size_formatted);
        map[flutter::EncodableValue("modifiedFormatted")] = flutter::EncodableValue(file.modified_formatted);
        map[flutter::EncodableValue("source")] = flutter::EncodableValue(file.source);
        map[flutter::EncodableValue("extension")] = flutter::EncodableValue(file.extension);
        map[flutter::EncodableValue("entryId")] = flutter::EncodableValue(file.entry_id);
        list.push_back(flutter::EncodableValue(std::move(map)));
    }
    return flutter::EncodableValue(std::move(list));
}

flutter::EncodableValue EncodeNotificationState(
    const ShellNotificationV21::Snapshot& snapshot)
{
    flutter::EncodableMap state;
    state[flutter::EncodableValue("revision")] =
        flutter::EncodableValue(static_cast<int64_t>(snapshot.revision));
    state[flutter::EncodableValue("unreadCount")] =
        flutter::EncodableValue(static_cast<int32_t>(snapshot.unread_count));

    flutter::EncodableList items;
    items.reserve(snapshot.count);
    for (std::uint32_t index = 0; index < snapshot.count; ++index)
    {
        const auto& item = snapshot.items[index];
        flutter::EncodableMap map;
        map[flutter::EncodableValue("id")] =
            flutter::EncodableValue(std::to_string(item.id));
        map[flutter::EncodableValue("title")] = flutter::EncodableValue(
            WideToUtf8(item.title, ShellNotificationV21::kTitleChars));
        map[flutter::EncodableValue("message")] = flutter::EncodableValue(
            WideToUtf8(item.message, ShellNotificationV21::kMessageChars));
        map[flutter::EncodableValue("time")] =
            flutter::EncodableValue(FormatNotificationTime(item));
        map[flutter::EncodableValue("severity")] =
            flutter::EncodableValue(static_cast<int32_t>(item.severity));
        map[flutter::EncodableValue("read")] =
            flutter::EncodableValue(item.read != 0);
        items.push_back(flutter::EncodableValue(std::move(map)));
    }
    state[flutter::EncodableValue("items")] = flutter::EncodableValue(std::move(items));
    return flutter::EncodableValue(std::move(state));
}

void ConvertBrokerFiles(
    const std::vector<BrokerClientFileItem>& broker_files,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<NativeFileItem> files;
    files.reserve(broker_files.size());
    for (const BrokerClientFileItem& item : broker_files)
    {
        files.push_back({
            item.name,
            item.path,
            item.is_folder,
            item.size_formatted,
            item.modified_formatted,
            item.source,
            item.extension,
            item.entry_id,
        });
    }
    out_files = std::move(files);
}
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

    if (method == "getFiles")
    {
        std::string location;
        if (!ReadStringArgument(method_call, "location", &location))
        {
            result->Error("INVALID_ARGUMENT", "getFiles requires an allowlisted location id");
            return;
        }
        std::vector<NativeFileItem> files;
        if (!GetFiles(location, files))
        {
            result->Error("FILES_UNAVAILABLE", "System broker rejected or failed the allowlisted Files location");
            return;
        }
        result->Success(EncodeFileItems(files));
        return;
    }

    if (method == "getFilesEntry")
    {
        std::string entry_id;
        if (!ReadStringArgument(method_call, "entryId", &entry_id))
        {
            result->Error("INVALID_ARGUMENT", "getFilesEntry requires an opaque entryId capability");
            return;
        }
        std::vector<NativeFileItem> files;
        if (!GetFilesEntry(entry_id, files))
        {
            result->Error("FILES_ENTRY_UNAVAILABLE", "System broker rejected or expired the Files entry capability");
            return;
        }
        result->Success(EncodeFileItems(files));
        return;
    }

    if (method == "openFileEntry")
    {
        std::string entry_id;
        if (!ReadStringArgument(method_call, "entryId", &entry_id))
        {
            result->Error("INVALID_ARGUMENT", "openFileEntry requires an opaque entryId capability");
            return;
        }
        if (!OpenFileEntry(entry_id))
        {
            result->Error("FILES_OPEN_FAILED", "System broker rejected or failed the Files entry capability");
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "getSystemSnapshot")
    {
        const auto snapshot = GetSystemSnapshot();
        flutter::EncodableMap map;
        map[flutter::EncodableValue("deviceName")] = flutter::EncodableValue(snapshot.device_name);
        map[flutter::EncodableValue("networkAvailable")] = flutter::EncodableValue(snapshot.network_available);
        map[flutter::EncodableValue("networkName")] = flutter::EncodableValue(snapshot.network_name);
        map[flutter::EncodableValue("volumeAvailable")] = flutter::EncodableValue(snapshot.volume_available);
        map[flutter::EncodableValue("volume")] = flutter::EncodableValue(snapshot.volume);
        map[flutter::EncodableValue("brightnessAvailable")] = flutter::EncodableValue(snapshot.brightness_available);
        map[flutter::EncodableValue("brightness")] = flutter::EncodableValue(snapshot.brightness);
        map[flutter::EncodableValue("batteryAvailable")] = flutter::EncodableValue(snapshot.battery_available);
        map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(snapshot.battery_percent);
        map[flutter::EncodableValue("wslAvailable")] = flutter::EncodableValue(snapshot.wsl_available);
        map[flutter::EncodableValue("currentWorkspace")] = flutter::EncodableValue(snapshot.current_workspace);
        flutter::EncodableList distros_list;
        for (const auto& d : snapshot.distros) distros_list.push_back(flutter::EncodableValue(d));
        map[flutter::EncodableValue("distros")] = flutter::EncodableValue(std::move(distros_list));
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "getNotificationState")
    {
        auto snapshot = std::make_unique<ShellNotificationV21::Snapshot>();
        std::string error;
        if (!NativeShellNotificationClientV21::Query(snapshot.get(), &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(EncodeNotificationState(*snapshot));
        return;
    }

    if (method == "markNotificationsRead")
    {
        std::string error;
        if (!NativeShellNotificationClientV21::MarkAllRead(&error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "dismissNotification")
    {
        std::string notification_id_text;
        std::uint64_t notification_id = 0;
        if (!ReadStringArgument(method_call, "id", &notification_id_text) ||
            !ParseNotificationId(notification_id_text, &notification_id))
        {
            result->Error("INVALID_ARGUMENT", "dismissNotification requires a numeric notification id");
            return;
        }
        std::string error;
        if (!NativeShellNotificationClientV21::Dismiss(notification_id, &error))
        {
            result->Error("NOTIFICATION_MUTATION_FAILED", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "clearNotifications")
    {
        std::string error;
        if (!NativeShellNotificationClientV21::Clear(&error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "getShellSurfaceStates")
    {
        bool browser_running = false;
        bool terminal_running = false;
        std::string error;
        if (!NativeShellActivationClientV21::QueryRunning(
                ShellActivationV21::App::Browser,
                &browser_running,
                &error) ||
            !NativeShellActivationClientV21::QueryRunning(
                ShellActivationV21::App::Terminal,
                &terminal_running,
                &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        flutter::EncodableMap map;
        map[flutter::EncodableValue("browser")] = flutter::EncodableValue(browser_running);
        map[flutter::EncodableValue("terminal")] = flutter::EncodableValue(terminal_running);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "focusShellSurface" || method == "closeShellSurface")
    {
        ShellActivationV21::App app{};
        std::string surface_id;
        if (!ReadSurfaceArgument(method_call, &app, &surface_id))
        {
            result->Error("INVALID_ARGUMENT", "A supported Browser or Terminal surface id is required");
            return;
        }
        bool surface_was_running = false;
        std::string error;
        const bool ok = method == "focusShellSurface"
            ? NativeShellActivationClientV21::Focus(app, &surface_was_running, &error)
            : NativeShellActivationClientV21::Close(app, &surface_was_running, &error);
        if (!ok)
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(surface_was_running));
        return;
    }

    if (method == "getCurrentWorkspace")
    {
        int workspace = 0;
        std::string error;
        if (!NativeShellActivationClientV21::QueryWorkspace(&workspace, &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(workspace + 1));
        return;
    }

    if (method == "switchWorkspace")
    {
        int workspace = 0;
        if (!ReadWorkspaceArgument(method_call, &workspace) || workspace < 1 ||
            workspace > ShellActivationV21::kWorkspaceCount)
        {
            result->Error("INVALID_ARGUMENT", "workspace must be in the presentation range 1..4");
            return;
        }
        int actual_workspace = 0;
        std::string error;
        if (!NativeShellActivationClientV21::SwitchWorkspace(
                workspace - 1,
                &actual_workspace,
                &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(actual_workspace + 1));
        return;
    }

    if (method == "launchApp")
    {
        std::string app_id;
        if (!ReadStringArgument(method_call, "id", &app_id))
        {
            result->Error("INVALID_ARGUMENT", "launchApp requires a map with an 'id' property");
            return;
        }
        const bool ok = LaunchApp(app_id);
        if (ok) result->Success(flutter::EncodableValue(true));
        else result->Error("LAUNCH_FAILED", "Failed to launch application with ID: " + app_id);
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
                const bool ok = SetVolume(std::get<double>(it->second));
                if (ok) result->Success(flutter::EncodableValue(true));
                else result->Error("BROKER_WRITE_FAILED", "System broker rejected or failed the volume update");
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
                const bool ok = SetBrightness(std::get<double>(it->second));
                if (ok) result->Success(flutter::EncodableValue(true));
                else result->Error("BROKER_WRITE_FAILED", "System broker rejected or failed the brightness update");
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
        map[flutter::EncodableValue("bridge_type")] = flutter::EncodableValue("CloudOSFlutterBridgeV20");
        map[flutter::EncodableValue("channel")] = flutter::EncodableValue(kChannelName);
        map[flutter::EncodableValue("brokerConnected")] = flutter::EncodableValue(CloudOSBrokerClientV21::Instance().IsConnected());
        map[flutter::EncodableValue("brokerState")] = flutter::EncodableValue(ConnectionStateToString(CloudOSBrokerClientV21::Instance().GetConnectionState()));
        map[flutter::EncodableValue("arbitrary_command_api")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("winlogon_modified")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("shell_activation_executed")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("shell_surface_lifecycle")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("shell_workspace_control")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("shell_notification_authority")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("files_capability_actions")] = flutter::EncodableValue(true);
        result->Success(flutter::EncodableValue(std::move(map)));
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

bool CloudOSFlutterBridgeV20::GetFiles(
    const std::string& location,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<BrokerClientFileItem> broker_files;
    if (!CloudOSBrokerClientV21::Instance().GetFiles(location, broker_files)) return false;
    ConvertBrokerFiles(broker_files, out_files);
    return true;
}

bool CloudOSFlutterBridgeV20::GetFilesEntry(
    const std::string& entry_id,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<BrokerClientFileItem> broker_files;
    if (!CloudOSBrokerClientV21::Instance().GetFilesEntry(entry_id, broker_files)) return false;
    ConvertBrokerFiles(broker_files, out_files);
    return true;
}

bool CloudOSFlutterBridgeV20::OpenFileEntry(const std::string& entry_id)
{
    return CloudOSBrokerClientV21::Instance().OpenFileEntry(entry_id);
}

NativeSystemSnapshot CloudOSFlutterBridgeV20::GetSystemSnapshot()
{
    NativeSystemSnapshot snapshot;
    BrokerClientSnapshot broker_snap;
    if (CloudOSBrokerClientV21::Instance().GetSystemSnapshot(broker_snap))
    {
        snapshot.device_name = broker_snap.device_name;
        snapshot.network_available = broker_snap.network_available;
        snapshot.network_name = broker_snap.network_name;
        snapshot.volume_available = broker_snap.volume_available;
        snapshot.volume = broker_snap.volume;
        snapshot.brightness_available = broker_snap.brightness_available;
        snapshot.brightness = broker_snap.brightness;
        snapshot.battery_available = broker_snap.battery_available;
        snapshot.battery_percent = broker_snap.battery_percent;
        snapshot.wsl_available = broker_snap.wsl_available;
        snapshot.distros = broker_snap.distros;
        snapshot.current_workspace = broker_snap.current_workspace;
    }
    else
    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot = cached_snapshot_;
    }

    int native_workspace = 0;
    if (NativeShellActivationClientV21::QueryWorkspace(&native_workspace))
    {
        snapshot.current_workspace = native_workspace + 1;
    }
    return snapshot;
}

bool CloudOSFlutterBridgeV20::LaunchApp(const std::string& app_id)
{
    std::string err;
    if (CloudOSBrokerClientV21::Instance().LaunchApp(app_id, err)) return true;

    ShellActivationV21::App surface_app{};
    if (ResolveSurfaceApp(app_id, &surface_app))
    {
        return NativeShellActivationClientV21::Activate(surface_app, &err);
    }

    if (app_id == "files" || app_id == "cloudos:files")
    {
        return reinterpret_cast<intptr_t>(
            ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL)) > 32;
    }
    if (app_id == "windows:notepad")
    {
        return reinterpret_cast<intptr_t>(
            ShellExecuteW(nullptr, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL)) > 32;
    }
    return false;
}

bool CloudOSFlutterBridgeV20::SetVolume(double volume)
{
    const double clamped = std::clamp(volume, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetVolume(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.volume_available = true;
    cached_snapshot_.volume = clamped;
    return true;
}

bool CloudOSFlutterBridgeV20::SetBrightness(double brightness)
{
    const double clamped = std::clamp(brightness, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetBrightness(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.brightness_available = true;
    cached_snapshot_.brightness = clamped;
    return true;
}

void CloudOSFlutterBridgeV20::RefreshAppCatalog()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_apps_.clear();
    cached_apps_.push_back({"cloudos:files", "Arquivos", "cloudos", "Windows + Linux (WSL2)", "", "Sistema", "CloudOS", true, true, false});
    cached_apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "WebView2 nativo do CloudOS", "", "Produtividade", "CloudOS", true, true, true});
    cached_apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Terminal nativo / ConPTY", "", "Utilitários", "CloudOS", true, true, true});
    cached_apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, true, false});
}

void CloudOSFlutterBridgeV20::RefreshSystemSnapshot()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.device_name = "CloudOS Desktop";
    cached_snapshot_.network_available = false;
    cached_snapshot_.network_name = "Indisponível";
    cached_snapshot_.volume_available = false;
    cached_snapshot_.volume = 0.0;
    cached_snapshot_.brightness_available = false;
    cached_snapshot_.brightness = 0.0;
    cached_snapshot_.battery_available = false;
    cached_snapshot_.battery_percent = 0;
    cached_snapshot_.wsl_available = false;
    cached_snapshot_.distros = {};
    cached_snapshot_.current_workspace = 1;
}

} // namespace CloudOS
