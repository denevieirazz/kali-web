#include "cloudos_broker_client_v21.h"

#include <sddl.h>
#include <shlwapi.h>

#include <algorithm>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

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

bool WriteExact(HANDLE handle, const void* buffer, DWORD bytes)
{
    const auto* src = static_cast<const BYTE*>(buffer);
    DWORD total = 0;
    while (total < bytes)
    {
        DWORD written = 0;
        if (!WriteFile(handle, src + total, bytes - total, &written, nullptr) || written == 0)
        {
            return false;
        }
        total += written;
    }
    return true;
}

bool ReadExact(HANDLE handle, void* buffer, DWORD bytes)
{
    auto* dst = static_cast<BYTE*>(buffer);
    DWORD total = 0;
    while (total < bytes)
    {
        DWORD read_bytes = 0;
        if (!ReadFile(handle, dst + total, bytes - total, &read_bytes, nullptr) || read_bytes == 0)
        {
            return false;
        }
        total += read_bytes;
    }
    return true;
}

const JsonValue* FindField(const JsonObject& obj, const char* key)
{
    const auto it = obj.find(key);
    return it == obj.end() ? nullptr : &it->second;
}

std::string StringField(const JsonObject& obj, const char* key, const std::string& fallback = {})
{
    const JsonValue* value = FindField(obj, key);
    return value && value->IsString() ? value->AsString() : fallback;
}

bool BoolField(const JsonObject& obj, const char* key, bool fallback = false)
{
    const JsonValue* value = FindField(obj, key);
    return value && value->IsBool() ? value->AsBool() : fallback;
}

int64_t IntField(const JsonObject& obj, const char* key, int64_t fallback = 0)
{
    const JsonValue* value = FindField(obj, key);
    return value && value->IsInt() ? value->AsInt() : fallback;
}

double DoubleField(const JsonObject& obj, const char* key, double fallback = 0.0)
{
    const JsonValue* value = FindField(obj, key);
    return value && value->IsDouble() ? value->AsDouble() : fallback;
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

    for (int attempt = 0; attempt < 15; ++attempt)
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
    WCHAR exe_path[MAX_PATH]{};
    if (GetModuleFileNameW(nullptr, exe_path, ARRAYSIZE(exe_path)) == 0)
    {
        return;
    }

    WCHAR dir[MAX_PATH]{};
    wcscpy_s(dir, exe_path);
    PathRemoveFileSpecW(dir);

    const std::wstring candidate1 = std::wstring(dir) + L"\\CloudOS.SystemBroker.exe";
    const std::wstring candidate2 = std::wstring(dir) + L"\\..\\..\\..\\..\\..\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";
    const std::wstring candidate3 = L"C:\\CloudOS\\desktop\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";

    std::wstring target;
    if (PathFileExistsW(candidate1.c_str())) target = candidate1;
    else if (PathFileExistsW(candidate2.c_str())) target = candidate2;
    else if (PathFileExistsW(candidate3.c_str())) target = candidate3;

    if (target.empty())
    {
        return;
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};

    if (CreateProcessW(
            target.c_str(),
            nullptr,
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            &si,
            &pi))
    {
        if (pi.hProcess) CloseHandle(pi.hProcess);
        if (pi.hThread) CloseHandle(pi.hThread);
    }
}

bool CloudOSBrokerClientV21::SendFrame(const std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes)
    {
        return false;
    }

    const uint32_t len = static_cast<uint32_t>(payload.size());
    if (!WriteExact(pipe_, &len, static_cast<DWORD>(sizeof(len))))
    {
        return false;
    }
    return len == 0 || WriteExact(pipe_, payload.data(), len);
}

bool CloudOSBrokerClientV21::ReadFrame(std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE)
    {
        return false;
    }

    uint32_t len = 0;
    if (!ReadExact(pipe_, &len, static_cast<DWORD>(sizeof(len))) || len > kMaxPayloadBytes)
    {
        return false;
    }

    payload.assign(len, '\0');
    return len == 0 || ReadExact(pipe_, payload.data(), len);
}

bool CloudOSBrokerClientV21::SendRequestLocked(
    const std::string& method,
    JsonObject payload,
    BrokerResponse& response,
    std::string& err)
{
    if (pipe_ == INVALID_HANDLE_VALUE)
    {
        err = "Broker pipe is not connected";
        return false;
    }

    BrokerRequest req;
    req.protocol = kProtocolVersion;
    req.id = "flutter-" + std::to_string(next_req_id_.fetch_add(1));
    req.method = method;
    req.payload = std::move(payload);

    if (!SendFrame(SerializeRequest(req)))
    {
        err = "Failed to send request to System Broker";
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }

    // Future-proof against event frames sharing the same duplex pipe.
    for (int frame_index = 0; frame_index < 16; ++frame_index)
    {
        std::string raw;
        if (!ReadFrame(raw))
        {
            err = "Failed to read response from System Broker";
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }

        BrokerResponse candidate;
        std::string parse_err;
        if (ParseResponse(raw, candidate, parse_err))
        {
            if (candidate.protocol != kProtocolVersion)
            {
                err = "Broker returned incompatible protocol version";
                return false;
            }
            if (candidate.id != req.id)
            {
                continue;
            }

            response = std::move(candidate);
            if (!response.ok)
            {
                err = response.error_message.empty()
                    ? (response.error_code.empty() ? "Broker rejected request" : response.error_code)
                    : response.error_message;
                return false;
            }
            return true;
        }

        BrokerEvent event;
        if (ParseEvent(raw, event, parse_err))
        {
            continue;
        }

        err = "Broker returned malformed IPC frame";
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }

    err = "Broker response was not received after event frames";
    return false;
}

bool CloudOSBrokerClientV21::PerformHandshake()
{
    JsonObject payload;
    payload["clientName"] = JsonValue("CloudOS.FlutterShell");
    payload["clientVersion"] = JsonValue("21.0.0");

    BrokerResponse response;
    std::string err;
    if (!SendRequestLocked("hello", std::move(payload), response, err))
    {
        return false;
    }

    client_id_ = StringField(response.payload, "clientId");
    server_instance_id_ = StringField(response.payload, "serverInstanceId");
    capabilities_.clear();

    const JsonValue* caps = FindField(response.payload, "capabilities");
    if (caps && caps->IsArray())
    {
        for (const auto& value : caps->AsArray())
        {
            if (value.IsString())
            {
                capabilities_.push_back(value.AsString());
            }
        }
    }

    return IntField(response.payload, "protocolVersion", 0) == kProtocolVersion;
}

bool CloudOSBrokerClientV21::GetApps(std::vector<BrokerClientAppItem>& out_apps)
{
    if (!EnsureConnected())
    {
        return false;
    }

    BrokerResponse response;
    std::string err;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendRequestLocked("apps.list", {}, response, err))
        {
            return false;
        }
    }

    const JsonValue* apps_value = FindField(response.payload, "apps");
    if (!apps_value || !apps_value->IsArray())
    {
        return false;
    }

    std::vector<BrokerClientAppItem> parsed;
    parsed.reserve(apps_value->AsArray().size());

    for (const auto& value : apps_value->AsArray())
    {
        if (!value.IsObject())
        {
            continue;
        }

        const auto& obj = value.AsObject();
        BrokerClientAppItem item;
        item.id = StringField(obj, "id");
        item.name = StringField(obj, "name", item.id);
        item.platform = StringField(obj, "platform", "windows");
        item.subtitle = StringField(obj, "subtitle");
        item.distro = StringField(obj, "distro");
        item.category = StringField(obj, "category", "Utilitários");
        item.source = StringField(obj, "source");
        item.can_launch = BoolField(obj, "canLaunch", true);
        item.can_uninstall = BoolField(obj, "canUninstall", false);
        item.can_update = BoolField(obj, "canUpdate", false);
        item.icon_key = StringField(obj, "iconKey", item.id);
        item.pinned = BoolField(obj, "pinned", false);
        item.recent = BoolField(obj, "recent", false);

        if (!item.id.empty())
        {
            parsed.push_back(std::move(item));
        }
    }

    if (parsed.empty())
    {
        return false;
    }

    out_apps = std::move(parsed);
    return true;
}

bool CloudOSBrokerClientV21::LaunchApp(const std::string& app_id, std::string& err)
{
    if (app_id.empty())
    {
        err = "Application id is empty";
        return false;
    }
    if (!EnsureConnected())
    {
        err = "System Broker is not connected";
        return false;
    }

    JsonObject payload;
    payload["id"] = JsonValue(app_id);

    BrokerResponse response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendRequestLocked("apps.launch", std::move(payload), response, err))
        {
            return false;
        }
    }

    return BoolField(response.payload, "launched", false);
}

bool CloudOSBrokerClientV21::GetSystemSnapshot(BrokerClientSnapshot& out_snapshot)
{
    if (!EnsureConnected())
    {
        return false;
    }

    BrokerResponse response;
    std::string err;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendRequestLocked("system.snapshot", {}, response, err))
        {
            return false;
        }
    }

    BrokerClientSnapshot snapshot;
    snapshot.device_name = StringField(response.payload, "deviceName", "CloudOS Desktop");
    snapshot.user_name = StringField(response.payload, "userName", "User");
    snapshot.session_id = static_cast<uint32_t>(std::max<int64_t>(0, IntField(response.payload, "sessionId", 1)));
    snapshot.battery_available = BoolField(response.payload, "batteryAvailable", false);
    snapshot.battery_percent = static_cast<int>(std::clamp<int64_t>(IntField(response.payload, "batteryPercent", 100), 0, 100));
    snapshot.network_available = BoolField(response.payload, "networkAvailable", false);
    snapshot.network_name = StringField(response.payload, "networkName", snapshot.network_available ? "Connected" : "Offline");
    snapshot.volume = std::clamp(DoubleField(response.payload, "volume", 0.0), 0.0, 1.0);
    snapshot.brightness_available = BoolField(response.payload, "brightnessAvailable", false);
    snapshot.brightness = std::clamp(DoubleField(response.payload, "brightness", 0.0), 0.0, 1.0);
    snapshot.wsl_available = BoolField(response.payload, "wslAvailable", false);
    snapshot.current_workspace = static_cast<int>(std::max<int64_t>(1, IntField(response.payload, "currentWorkspace", 1)));
    snapshot.timestamp_ms = static_cast<uint64_t>(std::max<int64_t>(0, IntField(response.payload, "timestamp", 0)));

    if (const JsonValue* distros = FindField(response.payload, "distros"); distros && distros->IsArray())
    {
        for (const auto& value : distros->AsArray())
        {
            if (value.IsString() && !value.AsString().empty())
            {
                snapshot.distros.push_back(value.AsString());
            }
        }
    }

    out_snapshot = std::move(snapshot);
    return true;
}

bool CloudOSBrokerClientV21::SetVolume(double value)
{
    if (!EnsureConnected())
    {
        return false;
    }

    JsonObject payload;
    payload["value"] = JsonValue(std::clamp(value, 0.0, 1.0));

    BrokerResponse response;
    std::string err;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendRequestLocked("system.volume.set", std::move(payload), response, err))
    {
        return false;
    }
    return BoolField(response.payload, "updated", false);
}

bool CloudOSBrokerClientV21::SetBrightness(double value)
{
    if (!EnsureConnected())
    {
        return false;
    }

    JsonObject payload;
    payload["value"] = JsonValue(std::clamp(value, 0.0, 1.0));

    BrokerResponse response;
    std::string err;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendRequestLocked("system.brightness.set", std::move(payload), response, err))
    {
        return false;
    }
    return BoolField(response.payload, "updated", false);
}

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    if (!EnsureConnected())
    {
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!capabilities_.empty())
        {
            out_caps = capabilities_;
            return true;
        }

        BrokerResponse response;
        std::string err;
        if (!SendRequestLocked("system.capabilities", {}, response, err))
        {
            return false;
        }

        const JsonValue* caps = FindField(response.payload, "capabilities");
        if (!caps || !caps->IsArray())
        {
            return false;
        }

        capabilities_.clear();
        for (const auto& value : caps->AsArray())
        {
            if (value.IsString())
            {
                capabilities_.push_back(value.AsString());
            }
        }
        out_caps = capabilities_;
    }

    return !out_caps.empty();
}

} // namespace CloudOS
