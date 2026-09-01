#include "cloudos_broker_client_v21.h"

#if __has_include("../../CloudOS.SystemBroker/src/protocol_v21.h")
#include "../../CloudOS.SystemBroker/src/protocol_v21.h"
#else
#include "protocol_v21.h"
#endif

#include <sddl.h>
#include <shellapi.h>
#include <shlwapi.h>

namespace CloudOS
{

namespace
{
std::wstring GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    {
        return L"CURRENT_USER";
    }

    DWORD len = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &len);
    if (len == 0)
    {
        CloseHandle(token);
        return L"CURRENT_USER";
    }

    std::vector<BYTE> buffer(len);
    if (!GetTokenInformation(token, TokenUser, buffer.data(), len, &len))
    {
        CloseHandle(token);
        return L"CURRENT_USER";
    }

    CloseHandle(token);

    auto* token_user = reinterpret_cast<TOKEN_USER*>(buffer.data());
    LPWSTR string_sid = nullptr;
    if (ConvertSidToStringSidW(token_user->User.Sid, &string_sid) && string_sid != nullptr)
    {
        std::wstring result(string_sid);
        LocalFree(string_sid);
        return result;
    }

    return L"CURRENT_USER";
}

DWORD GetCurrentSessionId()
{
    DWORD session_id = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id))
    {
        return 1;
    }
    return session_id;
}

std::wstring GetCommandPipeName()
{
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." +
        GetCurrentUserSidString() + L"." + std::to_wstring(GetCurrentSessionId());
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
    WCHAR exe_path[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return;

    WCHAR dir[MAX_PATH];
    wcscpy_s(dir, exe_path);
    PathRemoveFileSpecW(dir);

    const std::wstring candidate1 = std::wstring(dir) + L"\\CloudOS.SystemBroker.exe";
    const std::wstring candidate2 = std::wstring(dir) + L"\\..\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";
    const std::wstring candidate3 = L"C:\\CloudOS\\desktop\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";

    std::wstring target;
    if (PathFileExistsW(candidate1.c_str())) target = candidate1;
    else if (PathFileExistsW(candidate2.c_str())) target = candidate2;
    else if (PathFileExistsW(candidate3.c_str())) target = candidate3;

    if (target.empty()) return;

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};

    CreateProcessW(
        target.c_str(),
        nullptr,
        nullptr,
        nullptr,
        FALSE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &si,
        &pi);

    if (pi.hProcess) CloseHandle(pi.hProcess);
    if (pi.hThread) CloseHandle(pi.hThread);
}

bool CloudOSBrokerClientV21::SendFrame(const std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes) return false;

    const uint32_t len = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    if (!WriteFile(pipe_, &len, sizeof(len), &written, nullptr) || written != sizeof(len))
    {
        return false;
    }
    if (len > 0 &&
        (!WriteFile(pipe_, payload.data(), len, &written, nullptr) || written != len))
    {
        return false;
    }
    return true;
}

bool CloudOSBrokerClientV21::ReadFrame(std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE) return false;

    uint32_t len = 0;
    DWORD read_bytes = 0;
    if (!ReadFile(pipe_, &len, sizeof(len), &read_bytes, nullptr) || read_bytes != sizeof(len))
    {
        return false;
    }
    if (len > kMaxPayloadBytes) return false;

    payload.resize(len);
    DWORD total_read = 0;
    while (total_read < len)
    {
        if (!ReadFile(pipe_, &payload[total_read], len - total_read, &read_bytes, nullptr) || read_bytes == 0)
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

bool CloudOSBrokerClientV21::LaunchApp(const std::string& app_id, std::string& err)
{
    if (!EnsureConnected())
    {
        err = "System broker is not connected";
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
            return false;
        }
    }

    BrokerResponse response;
    std::string parse_error;
    if (!ParseResponse(raw_response, response, parse_error))
    {
        err = parse_error.empty() ? "Invalid broker launch response" : parse_error;
        return false;
    }
    if (!response.ok)
    {
        err = response.error_message.empty() ? response.error_code : response.error_message;
        return false;
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

    BrokerClientSnapshot snapshot;
    snapshot.device_name = device_name;
    snapshot.user_name = StringField(response.payload, "userName", "User");
    snapshot.session_id = static_cast<uint32_t>(
        IntField(response.payload, "sessionId", GetCurrentSessionId()));
    snapshot.battery_available = BoolField(response.payload, "batteryAvailable");
    snapshot.battery_percent = static_cast<int>(IntField(response.payload, "batteryPercent", 0));
    snapshot.network_available = BoolField(response.payload, "networkAvailable");
    snapshot.network_name = StringField(response.payload, "networkName");
    snapshot.volume_available = BoolField(response.payload, "volumeAvailable");
    snapshot.volume = DoubleField(response.payload, "volume", 0.0);
    snapshot.brightness_available = BoolField(response.payload, "brightnessAvailable");
    snapshot.brightness = DoubleField(response.payload, "brightness", 0.0);
    snapshot.wsl_available = BoolField(response.payload, "wslAvailable");
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

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    if (EnsureConnected() && !capabilities_.empty())
    {
        out_caps = capabilities_;
        return true;
    }
    return false;
}

} // namespace CloudOS
