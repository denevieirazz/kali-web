#include "cloudos_broker_client_v21.h"
#include "cloudos_managed_win32_host_v22.h"

#if __has_include("../../CloudOS.SystemBroker/src/protocol_v21.h")
#include "../../CloudOS.SystemBroker/src/protocol_v21.h"
#else
#include "protocol_v21.h"
#endif

#include <sddl.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <cmath>

namespace CloudOS
{

namespace
{
std::wstring GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    {
        return {};
    }

    DWORD len = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &len);
    if (len == 0)
    {
        CloseHandle(token);
        return {};
    }

    std::vector<BYTE> buffer(len);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), len, &len))
    {
        CloseHandle(token);
        return {};
    }

    CloseHandle(token);

    const auto* token_user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
    if (token_user->User.Sid == nullptr || !IsValidSid(token_user->User.Sid))
    {
        return {};
    }

    LPWSTR string_sid = nullptr;
    if (!ConvertSidToStringSidW(token_user->User.Sid, &string_sid) || string_sid == nullptr)
    {
        return {};
    }

    std::wstring result(string_sid);
    LocalFree(string_sid);
    return result;
}

bool TryGetCurrentSessionId(DWORD& session_id)
{
    session_id = 0;
    return ProcessIdToSessionId(GetCurrentProcessId(), &session_id) != FALSE;
}

std::wstring GetCommandPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = 0;
    if (sid.empty() || !TryGetCurrentSessionId(session_id)) return {};

    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." +
        sid + L"." + std::to_wstring(session_id);
}

const JsonValue* FindValue(const JsonObject& object, const char* key)
{
    const auto it = object.find(key);
    return it == object.end() ? nullptr : &it->second;
}

std::string StringField(
    const JsonObject& object,
    const char* key,
    const std::string& fallback = {})
{
    const JsonValue* value = FindValue(object, key);
    return value != nullptr && value->IsString() ? value->AsString() : fallback;
}

bool BoolField(const JsonObject& object, const char* key, bool fallback = false)
{
    const JsonValue* value = FindValue(object, key);
    return value != nullptr && value->IsBool() ? value->AsBool() : fallback;
}

int64_t IntField(const JsonObject& object, const char* key, int64_t fallback = 0)
{
    const JsonValue* value = FindValue(object, key);
    return value != nullptr && value->IsInt() ? value->AsInt() : fallback;
}

double DoubleField(const JsonObject& object, const char* key, double fallback = 0.0)
{
    const JsonValue* value = FindValue(object, key);
    return value != nullptr && value->IsDouble() ? value->AsDouble() : fallback;
}

bool ParseSuccessfulResponse(const std::string& json, BrokerResponse& response)
{
    std::string parse_error;
    return ParseResponse(json, response, parse_error) && response.ok;
}

BrokerRequest MakeRequest(
    const std::string& id,
    const std::string& method,
    JsonObject payload = {})
{
    BrokerRequest request;
    request.protocol = kProtocolVersion;
    request.id = id;
    request.method = method;
    request.payload = std::move(payload);
    return request;
}
} // namespace

std::string ConnectionStateToString(BrokerConnectionState s)
{
    switch (s)
    {
    case BrokerConnectionState::Connected: return "connected";
    case BrokerConnectionState::Connecting: return "connecting";
    case BrokerConnectionState::Degraded: return "degraded";
    case BrokerConnectionState::Disconnected: return "disconnected";
    default: return "unknown";
    }
}

CloudOSBrokerClientV21& CloudOSBrokerClientV21::Instance()
{
    static CloudOSBrokerClientV21 instance;
    return instance;
}

CloudOSBrokerClientV21::~CloudOSBrokerClientV21()
{
    Disconnect();
}

bool CloudOSBrokerClientV21::EnsureConnected()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (pipe_ != INVALID_HANDLE_VALUE && state_.load() == BrokerConnectionState::Connected)
    {
        return true;
    }

    state_.store(BrokerConnectionState::Connecting);

    // SID + session are part of the pipe security boundary. Never invent a
    // fallback identity such as CURRENT_USER/session 1 when Windows identity
    // APIs fail; an unresolved identity must fail closed.
    if (GetCommandPipeName().empty())
    {
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }

    if (TryConnectPipe() && PerformHandshake())
    {
        state_.store(BrokerConnectionState::Connected);
        return true;
    }

    SpawnBrokerIfNeeded();

    for (int attempt = 0; attempt < 10; ++attempt)
    {
        Sleep(100);
        if (TryConnectPipe() && PerformHandshake())
        {
            state_.store(BrokerConnectionState::Connected);
            return true;
        }
    }

    if (pipe_ != INVALID_HANDLE_VALUE)
    {
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
    }
    state_.store(BrokerConnectionState::Degraded);
    return false;
}

void CloudOSBrokerClientV21::Disconnect()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (pipe_ != INVALID_HANDLE_VALUE)
    {
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
    }
    client_id_.clear();
    server_instance_id_.clear();
    capabilities_.clear();
    state_.store(BrokerConnectionState::Disconnected);
}

bool CloudOSBrokerClientV21::TryConnectPipe()
{
    if (pipe_ != INVALID_HANDLE_VALUE)
    {
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
    }

    const std::wstring pipe_name = GetCommandPipeName();
    if (pipe_name.empty()) return false;

    pipe_ = CreateFileW(
        pipe_name.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);

    return pipe_ != INVALID_HANDLE_VALUE;
}

void CloudOSBrokerClientV21::SpawnBrokerIfNeeded()
{
    if (GetCommandPipeName().empty()) return;

    const uint64_t now = GetTickCount64();
    const uint64_t previous = last_spawn_attempt_ms_.load();
    if (previous != 0 && now - previous < 5000) return;
    last_spawn_attempt_ms_.store(now);

    WCHAR exe_path[MAX_PATH]{};
    const DWORD exe_length = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
    if (exe_length == 0 || exe_length >= MAX_PATH) return;

    WCHAR dir[MAX_PATH]{};
    wcscpy_s(dir, exe_path);
    if (!PathRemoveFileSpecW(dir)) return;

    const std::wstring packaged = std::wstring(dir) + L"\\CloudOS.SystemBroker.exe";
    const std::wstring development =
        std::wstring(dir) + L"\\..\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";

    std::wstring target;
    if (PathFileExistsW(packaged.c_str())) target = packaged;
    else if (PathFileExistsW(development.c_str())) target = development;
    if (target.empty()) return;

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};

    if (!CreateProcessW(
            target.c_str(),
            nullptr,
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            &startup,
            &process))
    {
        return;
    }

    if (process.hProcess) CloseHandle(process.hProcess);
    if (process.hThread) CloseHandle(process.hThread);
}

bool CloudOSBrokerClientV21::SendFrame(const std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes) return false;

    const uint32_t len = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    DWORD header_written = 0;
    const auto* header = reinterpret_cast<const unsigned char*>(&len);
    while (header_written < sizeof(len))
    {
        if (!WriteFile(
                pipe_,
                header + header_written,
                static_cast<DWORD>(sizeof(len)) - header_written,
                &written,
                nullptr) || written == 0)
        {
            return false;
        }
        header_written += written;
    }

    DWORD total_written = 0;
    while (total_written < len)
    {
        if (!WriteFile(
                pipe_,
                payload.data() + total_written,
                len - total_written,
                &written,
                nullptr) || written == 0)
        {
            return false;
        }
        total_written += written;
    }
    return true;
}

bool CloudOSBrokerClientV21::ReadFrame(std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE) return false;

    uint32_t len = 0;
    DWORD read_bytes = 0;
    DWORD header_bytes = 0;
    auto* header = reinterpret_cast<unsigned char*>(&len);
    while (header_bytes < sizeof(len))
    {
        if (!ReadFile(
                pipe_,
                header + header_bytes,
                static_cast<DWORD>(sizeof(len)) - header_bytes,
                &read_bytes,
                nullptr) || read_bytes == 0)
        {
            return false;
        }
        header_bytes += read_bytes;
    }
    if (len > kMaxPayloadBytes) return false;

    payload.resize(len);
    DWORD total_read = 0;
    while (total_read < len)
    {
        if (!ReadFile(
                pipe_,
                payload.data() + total_read,
                len - total_read,
                &read_bytes,
                nullptr) || read_bytes == 0)
        {
            return false;
        }
        total_read += read_bytes;
    }
    return true;
}

bool CloudOSBrokerClientV21::PerformHandshake()
{
    JsonObject hello_payload;
    hello_payload["clientName"] = JsonValue("CloudOS.FlutterShell");
    hello_payload["clientVersion"] = JsonValue("21.0.0");
    const BrokerRequest request = MakeRequest("init-hello", "hello", std::move(hello_payload));

    if (!SendFrame(SerializeRequest(request))) return false;

    std::string raw_response;
    if (!ReadFrame(raw_response)) return false;

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    client_id_ = StringField(response.payload, "clientId");
    server_instance_id_ = StringField(response.payload, "serverInstanceId");
    if (client_id_.empty() || server_instance_id_.empty()) return false;

    capabilities_.clear();
    const JsonValue* capabilities = FindValue(response.payload, "capabilities");
    if (capabilities != nullptr && capabilities->IsArray())
    {
        for (const JsonValue& item : capabilities->AsArray())
        {
            if (item.IsString()) capabilities_.push_back(item.AsString());
        }
    }
    return true;
}

bool CloudOSBrokerClientV21::GetApps(std::vector<BrokerClientAppItem>& out_apps)
{
    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "get-apps-" + std::to_string(next_req_id_.fetch_add(1)),
        "apps.list");
    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    const JsonValue* apps_value = FindValue(response.payload, "apps");
    if (apps_value == nullptr || !apps_value->IsArray()) return false;

    std::vector<BrokerClientAppItem> parsed_apps;
    for (const JsonValue& item_value : apps_value->AsArray())
    {
        if (!item_value.IsObject()) continue;
        const JsonObject& item = item_value.AsObject();
        const std::string id = StringField(item, "id");
        const std::string name = StringField(item, "name");
        const std::string platform = StringField(item, "platform");
        if (id.empty() || name.empty() || platform.empty()) continue;

        BrokerClientAppItem app;
        app.id = id;
        app.name = name;
        app.platform = platform;
        app.subtitle = StringField(item, "subtitle");
        app.distro = StringField(item, "distro");
        app.category = StringField(item, "category");
        app.source = StringField(item, "source");
        app.display_name = StringField(item, "displayName", name);
        app.launch_target = StringField(item, "launchTarget", id);
        app.availability = StringField(item, "availability", BoolField(item, "canLaunch", true) ? "ready" : "unavailable");
        const JsonValue* caps_val = FindValue(item, "capabilities");
        if (caps_val != nullptr && caps_val->IsArray())
        {
            for (const JsonValue& c : caps_val->AsArray())
            {
                if (c.IsString()) app.capabilities.push_back(c.AsString());
            }
        }
        app.can_launch = BoolField(item, "canLaunch", true);
        app.can_uninstall = BoolField(item, "canUninstall");
        app.can_update = BoolField(item, "canUpdate");
        app.icon_key = StringField(item, "iconKey", id);
        app.pinned = BoolField(item, "pinned");
        app.recent = BoolField(item, "recent");
        parsed_apps.push_back(std::move(app));
    }

    if (parsed_apps.empty()) return false;
    out_apps = std::move(parsed_apps);
    return true;
}

bool CloudOSBrokerClientV21::LaunchAppStructured(
    const std::string& app_id,
    BrokerClientLaunchResult& out_result,
    std::string& err)
{
    out_result.id = app_id;
    out_result.status = "failed";
    out_result.launched = false;
    out_result.platform = "windows";
    out_result.target = app_id;

    if (app_id == "windows:cmd" || app_id == "windows:powershell")
    {
        err = "Windows console profiles must be routed to CloudOS Terminal / ConPTY";
        out_result.message = err;
        return false;
    }

    if (ManagedWin32HostV22::IsWindowsCatalogId(app_id))
    {
        const bool ok = ManagedWin32HostV22::Launch(app_id, err);
        if (ok)
        {
            out_result.launched = true;
            out_result.status = "running";
            out_result.platform = "windows";
            out_result.message = "Launched successfully via ManagedWin32Host";
        }
        else
        {
            out_result.message = err;
        }
        return ok;
    }

    if (!EnsureConnected())
    {
        err = "System broker is not connected";
        out_result.message = err;
        return false;
    }

    JsonObject payload;
    payload["id"] = JsonValue(app_id);
    const BrokerRequest request = MakeRequest(
        "launch-app-" + std::to_string(next_req_id_.fetch_add(1)),
        "apps.launch",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC communication failed during launch";
            out_result.message = err;
            return false;
        }
    }

    BrokerResponse response;
    std::string parse_error;
    if (!ParseResponse(raw_response, response, parse_error))
    {
        err = parse_error.empty() ? "Invalid broker launch response" : parse_error;
        out_result.message = err;
        return false;
    }
    if (!response.ok)
    {
        err = response.error_message.empty() ? response.error_code : response.error_message;
        out_result.message = err;
        return false;
    }

    out_result.launched = BoolField(response.payload, "launched", true);
    out_result.status = StringField(response.payload, "status", "running");
    out_result.platform = StringField(response.payload, "platform", "linux");
    out_result.target = StringField(response.payload, "target", app_id);
    out_result.message = StringField(response.payload, "message", "Application launched successfully");
    return true;
}

bool CloudOSBrokerClientV21::LaunchApp(const std::string& app_id, std::string& err)
{
    if (app_id == "windows:cmd" || app_id == "windows:powershell")
    {
        err = "Windows console profiles must be routed to CloudOS Terminal / ConPTY";
        return false;
    }

    if (ManagedWin32HostV22::IsWindowsCatalogId(app_id))
    {
        return ManagedWin32HostV22::Launch(app_id, err);
    }

    if (!EnsureConnected())
    {
        err = "System broker is not connected";
        return false;
    }

    BrokerClientLaunchResult res;
    return LaunchAppStructured(app_id, res, err);
}

bool CloudOSBrokerClientV21::ListWslDistros(
    std::vector<BrokerClientDistroInfo>& out_distros,
    std::string& out_default_distro,
    bool& out_available)
{
    out_distros.clear();
    out_default_distro.clear();
    out_available = false;

    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "wsl-list-" + std::to_string(next_req_id_.fetch_add(1)),
        "wsl.list");
    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    out_available = BoolField(response.payload, "wslAvailable");
    out_default_distro = StringField(response.payload, "defaultDistro");

    const JsonValue* details = FindValue(response.payload, "distroDetails");
    if (details != nullptr && details->IsArray())
    {
        for (const JsonValue& val : details->AsArray())
        {
            if (!val.IsObject()) continue;
            const JsonObject& obj = val.AsObject();
            BrokerClientDistroInfo info;
            info.id = StringField(obj, "id");
            info.name = StringField(obj, "name");
            info.guid = StringField(obj, "guid");
            info.version = static_cast<uint32_t>(IntField(obj, "version", 2));
            info.state = StringField(obj, "state", "Stopped");
            info.base_path = StringField(obj, "basePath");
            info.default_uid = static_cast<uint32_t>(IntField(obj, "defaultUid", 0));
            info.flags = static_cast<uint32_t>(IntField(obj, "flags", 15));
            info.is_default = BoolField(obj, "isDefault");
            out_distros.push_back(std::move(info));
        }
    }
    else
    {
        const JsonValue* distros = FindValue(response.payload, "distros");
        if (distros != nullptr && distros->IsArray())
        {
            for (const JsonValue& val : distros->AsArray())
            {
                if (val.IsString())
                {
                    BrokerClientDistroInfo info;
                    info.id = val.AsString();
                    info.name = val.AsString();
                    info.version = 2;
                    info.state = "Stopped";
                    info.is_default = (info.name == out_default_distro);
                    out_distros.push_back(std::move(info));
                }
            }
        }
    }
    return true;
}

bool CloudOSBrokerClientV21::TranslatePath(
    const std::string& path,
    const std::string& target,
    const std::string& distro,
    BrokerClientPathTranslation& out_result)
{
    out_result.original_path = path;
    out_result.target = target;
    out_result.distro = distro;
    out_result.translated_path = path;
    out_result.exists = false;

    if (!EnsureConnected() || path.empty()) return false;

    JsonObject payload;
    payload["path"] = JsonValue(path);
    payload["target"] = JsonValue(target);
    if (!distro.empty())
    {
        payload["distro"] = JsonValue(distro);
    }

    const BrokerRequest request = MakeRequest(
        "path-trans-" + std::to_string(next_req_id_.fetch_add(1)),
        "path.translate",
        std::move(payload));
    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    out_result.translated_path = StringField(response.payload, "translatedPath", path);
    out_result.exists = BoolField(response.payload, "exists");
    return true;
}

bool CloudOSBrokerClientV21::GetMountPoints(std::vector<BrokerClientMountPoint>& out_mounts)
{
    out_mounts.clear();
    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "mounts-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.mounts.list");
    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    const JsonValue* mounts = FindValue(response.payload, "mounts");
    if (mounts != nullptr && mounts->IsArray())
    {
        for (const JsonValue& val : mounts->AsArray())
        {
            if (!val.IsObject()) continue;
            const JsonObject& obj = val.AsObject();
            BrokerClientMountPoint mp;
            mp.id = StringField(obj, "id");
            mp.label = StringField(obj, "label");
            mp.path = StringField(obj, "path");
            mp.platform = StringField(obj, "platform");
            mp.is_online = BoolField(obj, "isOnline", true);
            out_mounts.push_back(std::move(mp));
        }
    }
    return true;
}

bool CloudOSBrokerClientV21::GetSystemSnapshot(BrokerClientSnapshot& out_snapshot)
{
    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "get-snapshot-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.snapshot");
    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    const std::string device_name = StringField(response.payload, "deviceName");
    if (device_name.empty()) return false;

    const int64_t session_id = IntField(response.payload, "sessionId", 0);
    if (session_id < 0 || session_id > UINT32_MAX) return false;

    BrokerClientSnapshot snapshot;
    snapshot.device_name = device_name;
    snapshot.user_name = StringField(response.payload, "userName");
    snapshot.session_id = static_cast<uint32_t>(session_id);
    snapshot.battery_available = BoolField(response.payload, "batteryAvailable");
    snapshot.battery_percent = static_cast<int>(IntField(response.payload, "batteryPercent", 0));
    snapshot.network_available = BoolField(response.payload, "networkAvailable");
    snapshot.network_name = StringField(response.payload, "networkName");
    snapshot.volume_available = BoolField(response.payload, "volumeAvailable");
    snapshot.volume = DoubleField(response.payload, "volume", 0.0);
    snapshot.brightness_available = BoolField(response.payload, "brightnessAvailable");
    snapshot.brightness = DoubleField(response.payload, "brightness", 0.0);
    snapshot.wsl_available = BoolField(response.payload, "wslAvailable");
    snapshot.default_distro = StringField(response.payload, "defaultDistro");
    snapshot.current_workspace = static_cast<int>(IntField(response.payload, "currentWorkspace", 1));
    snapshot.timestamp_ms = static_cast<uint64_t>(IntField(response.payload, "timestamp", 0));

    const JsonValue* distros = FindValue(response.payload, "distros");
    if (distros != nullptr && distros->IsArray())
    {
        for (const JsonValue& distro : distros->AsArray())
        {
            if (distro.IsString()) snapshot.distros.push_back(distro.AsString());
        }
    }

    out_snapshot = std::move(snapshot);
    return true;
}

bool CloudOSBrokerClientV21::SetVolume(double value)
{
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    if (!EnsureConnected()) return false;

    JsonObject payload;
    payload["value"] = JsonValue(value);
    const BrokerRequest request = MakeRequest(
        "set-volume-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.volume.set",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    return ParseSuccessfulResponse(raw_response, response) &&
        BoolField(response.payload, "updated");
}

bool CloudOSBrokerClientV21::SetBrightness(double value)
{
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    if (!EnsureConnected()) return false;

    JsonObject payload;
    payload["value"] = JsonValue(value);
    const BrokerRequest request = MakeRequest(
        "set-brightness-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.brightness.set",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    return ParseSuccessfulResponse(raw_response, response) &&
        BoolField(response.payload, "updated");
}

bool CloudOSBrokerClientV21::GetPerformanceProfile(BrokerClientPerformanceProfile& out_profile)
{
    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "get-perf-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.performance.get",
        JsonObject{});

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;

    BrokerClientPerformanceProfile profile;
    profile.profile = StringField(response.payload, "profile", "balanced");
    profile.total_ram_mb = IntField(response.payload, "totalRamMb", 0);
    profile.free_ram_mb = IntField(response.payload, "freeRamMb", 0);
    profile.memory_load_percent = IntField(response.payload, "memoryLoadPercent", 0);
    profile.cpu_cores = IntField(response.payload, "cpuCores", 0);
    profile.on_battery = BoolField(response.payload, "onBattery", false);
    profile.battery_percent = IntField(response.payload, "batteryPercent", -1);
    profile.is_low_end_hardware = BoolField(response.payload, "isLowEndHardware", false);

    out_profile = std::move(profile);
    return true;
}

bool CloudOSBrokerClientV21::SetPerformanceProfile(const std::string& profile)
{
    if (!EnsureConnected() || profile.empty()) return false;

    JsonObject payload;
    payload["profile"] = JsonValue(profile);
    const BrokerRequest request = MakeRequest(
        "set-perf-" + std::to_string(next_req_id_.fetch_add(1)),
        "system.performance.set",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    return ParseSuccessfulResponse(raw_response, response) &&
        BoolField(response.payload, "updated");
}

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    if (EnsureConnected() && !capabilities_.empty())
    {
        out_caps = capabilities_;
        return true;
    }
    return false;
}

bool CloudOSBrokerClientV21::GetWindowSnapshot(std::string& out_snapshot_json)
{
    if (!EnsureConnected()) return false;

    const BrokerRequest request = MakeRequest(
        "get-window-snapshot-" + std::to_string(next_req_id_.fetch_add(1)),
        "window.snapshot");

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response)) return false;
    out_snapshot_json = StringField(response.payload, "snapshot");
    return !out_snapshot_json.empty();
}

bool CloudOSBrokerClientV21::ExecuteWindowCommand(
    const std::string& action,
    uint64_t hwnd,
    int x,
    int y,
    int width,
    int height,
    int workspace,
    const std::string& snap,
    bool fullscreen)
{
    if (!EnsureConnected()) return false;

    JsonObject payload;
    payload["hwnd"] = JsonValue(static_cast<int64_t>(hwnd));
    if (action == "setBounds")
    {
        payload["x"] = JsonValue(static_cast<int64_t>(x));
        payload["y"] = JsonValue(static_cast<int64_t>(y));
        payload["width"] = JsonValue(static_cast<int64_t>(width));
        payload["height"] = JsonValue(static_cast<int64_t>(height));
    }
    else if (action == "snap")
    {
        payload["snap"] = JsonValue(snap);
    }
    else if (action == "moveToWorkspace")
    {
        payload["workspace"] = JsonValue(static_cast<int64_t>(workspace));
    }
    else if (action == "setFullscreen")
    {
        payload["fullscreen"] = JsonValue(fullscreen);
    }

    const BrokerRequest request = MakeRequest(
        "window-cmd-" + std::to_string(next_req_id_.fetch_add(1)),
        "window." + action,
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    return ParseSuccessfulResponse(raw_response, response);
}

bool CloudOSBrokerClientV21::CreateFolder(
    const std::string& parent_entry_id,
    const std::string& name,
    BrokerClientFileItem& out_item,
    std::string& err)
{
    if (!EnsureConnected())
    {
        err = "SystemBroker unavailable";
        return false;
    }

    JsonObject payload;
    payload["parentEntryId"] = JsonValue(parent_entry_id);
    payload["name"] = JsonValue(name);

    const BrokerRequest request = MakeRequest(
        "create-folder-" + std::to_string(next_req_id_.fetch_add(1)),
        "files.createFolder",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC connection lost";
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response))
    {
        err = response.error_message.empty() ? "Falha ao criar pasta" : response.error_message;
        return false;
    }

    out_item.name = StringField(response.payload, "name");
    out_item.path = StringField(response.payload, "path");
    out_item.is_folder = true;
    out_item.size_formatted = StringField(response.payload, "sizeFormatted");
    out_item.modified_formatted = StringField(response.payload, "modifiedFormatted");
    out_item.source = StringField(response.payload, "source");
    out_item.extension = "";
    out_item.entry_id = StringField(response.payload, "entryId");
    return true;
}

bool CloudOSBrokerClientV21::RenameFile(
    const std::string& entry_id,
    const std::string& new_name,
    BrokerClientFileItem& out_item,
    std::string& err)
{
    if (!EnsureConnected())
    {
        err = "SystemBroker unavailable";
        return false;
    }

    JsonObject payload;
    payload["entryId"] = JsonValue(entry_id);
    payload["newName"] = JsonValue(new_name);

    const BrokerRequest request = MakeRequest(
        "rename-file-" + std::to_string(next_req_id_.fetch_add(1)),
        "files.rename",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC connection lost";
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response))
    {
        err = response.error_message.empty() ? "Falha ao renomear" : response.error_message;
        return false;
    }

    out_item.name = StringField(response.payload, "name");
    out_item.path = StringField(response.payload, "path");
    const auto it_folder = response.payload.find("isFolder");
    out_item.is_folder = it_folder != response.payload.end() && it_folder->second.IsBool() && it_folder->second.AsBool();
    out_item.size_formatted = StringField(response.payload, "sizeFormatted");
    out_item.modified_formatted = StringField(response.payload, "modifiedFormatted");
    out_item.source = StringField(response.payload, "source");
    out_item.extension = StringField(response.payload, "extension");
    out_item.entry_id = StringField(response.payload, "entryId");
    return true;
}

bool CloudOSBrokerClientV21::DeleteFiles(
    const std::vector<std::string>& entry_ids,
    bool permanent,
    std::vector<std::string>& out_deleted_ids,
    std::string& err)
{
    if (!EnsureConnected())
    {
        err = "SystemBroker unavailable";
        return false;
    }

    std::vector<JsonValue> arr;
    arr.reserve(entry_ids.size());
    for (const auto& id : entry_ids) arr.push_back(JsonValue(id));

    JsonObject payload;
    payload["entryIds"] = JsonValue(std::move(arr));
    payload["permanent"] = JsonValue(permanent);

    const BrokerRequest request = MakeRequest(
        "delete-files-" + std::to_string(next_req_id_.fetch_add(1)),
        "files.delete",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC connection lost";
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response))
    {
        err = response.error_message.empty() ? "Falha ao excluir itens" : response.error_message;
        return false;
    }

    const JsonValue* deleted_val = FindValue(response.payload, "deletedEntryIds");
    if (deleted_val != nullptr && deleted_val->IsArray())
    {
        for (const auto& item : deleted_val->AsArray())
        {
            if (item.IsString()) out_deleted_ids.push_back(item.AsString());
        }
    }
    return true;
}

bool CloudOSBrokerClientV21::CopyOrMoveFiles(
    const std::string& type,
    const std::vector<std::string>& source_ids,
    const std::string& destination_id,
    std::string& out_job_id,
    std::string& err)
{
    if (!EnsureConnected())
    {
        err = "SystemBroker unavailable";
        return false;
    }

    std::vector<JsonValue> arr;
    arr.reserve(source_ids.size());
    for (const auto& id : source_ids) arr.push_back(JsonValue(id));

    JsonObject payload;
    payload["sourceEntryIds"] = JsonValue(std::move(arr));
    payload["destinationEntryId"] = JsonValue(destination_id);

    const std::string method = (type == "move") ? "files.move" : "files.copy";
    const BrokerRequest request = MakeRequest(
        "file-op-" + std::to_string(next_req_id_.fetch_add(1)),
        method,
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC connection lost";
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response))
    {
        err = response.error_message.empty() ? "Falha na operação de arquivos" : response.error_message;
        return false;
    }

    out_job_id = StringField(response.payload, "jobId");
    return true;
}

bool CloudOSBrokerClientV21::CancelFileOperation(const std::string& job_id)
{
    if (!EnsureConnected() || job_id.empty()) return false;

    JsonObject payload;
    payload["jobId"] = JsonValue(job_id);

    const BrokerRequest request = MakeRequest(
        "cancel-job-" + std::to_string(next_req_id_.fetch_add(1)),
        "jobs.cancel",
        std::move(payload));

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    BrokerResponse response;
    return ParseSuccessfulResponse(raw_response, response);
}

bool CloudOSBrokerClientV21::ListDrives(
    std::vector<BrokerClientDriveItem>& out_drives,
    std::string& err)
{
    if (!EnsureConnected())
    {
        err = "SystemBroker unavailable";
        return false;
    }

    const BrokerRequest request = MakeRequest(
        "list-drives-" + std::to_string(next_req_id_.fetch_add(1)),
        "files.listDrives");

    std::string raw_response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(SerializeRequest(request)) || !ReadFrame(raw_response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC connection lost";
            return false;
        }
    }

    BrokerResponse response;
    if (!ParseSuccessfulResponse(raw_response, response))
    {
        err = response.error_message.empty() ? "Falha ao listar unidades" : response.error_message;
        return false;
    }

    const JsonValue* drives_val = FindValue(response.payload, "drives");
    if (drives_val == nullptr || !drives_val->IsArray()) return false;

    for (const auto& item_val : drives_val->AsArray())
    {
        if (!item_val.IsObject()) continue;
        const auto& obj = item_val.AsObject();

        BrokerClientDriveItem d;
        d.mount_path = StringField(obj, "mountPath");
        d.label = StringField(obj, "label");
        d.drive_type = StringField(obj, "driveType");
        const auto it_total = obj.find("totalBytes");
        if (it_total != obj.end() && it_total->second.IsInt()) d.total_bytes = static_cast<uint64_t>(it_total->second.AsInt());
        const auto it_free = obj.find("freeBytes");
        if (it_free != obj.end() && it_free->second.IsInt()) d.free_bytes = static_cast<uint64_t>(it_free->second.AsInt());
        d.total_formatted = StringField(obj, "totalFormatted");
        d.free_formatted = StringField(obj, "freeFormatted");
        d.entry_id = StringField(obj, "entryId");
        out_drives.push_back(std::move(d));
    }
    return true;
}

} // namespace CloudOS
