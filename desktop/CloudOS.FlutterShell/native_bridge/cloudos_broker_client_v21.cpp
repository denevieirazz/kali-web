#include "cloudos_broker_client_v21.h"

#include <sddl.h>
#include <shlwapi.h>

#include <cctype>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <string_view>

namespace CloudOS
{

namespace
{
constexpr int kProtocolVersion = 21;
constexpr uint32_t kMaxPayloadBytes = 1048576;
constexpr size_t kMaxRpcMethodBytes = 128;
constexpr size_t kMaxAppIdBytes = 512;

std::wstring GetCurrentUserSidString()
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};

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
    if (!token_user->User.Sid || !IsValidSid(token_user->User.Sid)) return {};

    LPWSTR string_sid = nullptr;
    if (!ConvertSidToStringSidW(token_user->User.Sid, &string_sid) || string_sid == nullptr) return {};
    std::wstring result(string_sid);
    LocalFree(string_sid);
    return result;
}

bool TryGetCurrentSessionId(DWORD* out_session_id)
{
    if (!out_session_id) return false;
    DWORD session_id = 0;
    if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id)) return false;
    *out_session_id = session_id;
    return true;
}

std::wstring GetCommandPipeName()
{
    const std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = 0;
    if (sid.empty() || !TryGetCurrentSessionId(&session_id)) return {};
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." + std::to_wstring(session_id);
}

void AppendJsonString(std::string_view value, std::string& output)
{
    static constexpr char hex[] = "0123456789abcdef";
    output.push_back('"');
    for (const unsigned char ch : value)
    {
        switch (ch)
        {
        case '"': output.append("\\\""); break;
        case '\\': output.append("\\\\"); break;
        case '\b': output.append("\\b"); break;
        case '\f': output.append("\\f"); break;
        case '\n': output.append("\\n"); break;
        case '\r': output.append("\\r"); break;
        case '\t': output.append("\\t"); break;
        default:
            if (ch < 0x20)
            {
                output.append("\\u00");
                output.push_back(hex[(ch >> 4) & 0x0f]);
                output.push_back(hex[ch & 0x0f]);
            }
            else
            {
                output.push_back(static_cast<char>(ch));
            }
            break;
        }
    }
    output.push_back('"');
}

bool IsSafeRpcMethod(std::string_view method)
{
    if (method.empty() || method.size() > kMaxRpcMethodBytes) return false;
    for (const unsigned char ch : method)
    {
        if (std::isalnum(ch) != 0 || ch == '.' || ch == '_' || ch == '-') continue;
        return false;
    }
    return true;
}

bool LooksLikeJsonObjectPayload(std::string_view payload)
{
    if (payload.empty()) return true;
    if (payload.size() > kMaxPayloadBytes) return false;

    size_t first = 0;
    while (first < payload.size() && std::isspace(static_cast<unsigned char>(payload[first])) != 0) ++first;
    if (first == payload.size()) return false;

    size_t last = payload.size();
    while (last > first && std::isspace(static_cast<unsigned char>(payload[last - 1])) != 0) --last;
    return last > first && payload[first] == '{' && payload[last - 1] == '}';
}

std::string BuildRequest(
    std::string_view request_id,
    std::string_view method,
    std::string_view payload_json)
{
    std::string request;
    request.reserve(request_id.size() + method.size() + payload_json.size() + 96);
    request.append("{\"protocol\":21,\"type\":\"request\",\"id\":");
    AppendJsonString(request_id, request);
    request.append(",\"method\":");
    AppendJsonString(method, request);
    request.append(",\"payload\":");
    request.append(payload_json.empty() ? "{}" : payload_json);
    request.push_back('}');
    return request;
}

std::string BuildStringPayload(std::string_view key, std::string_view value)
{
    std::string payload;
    payload.reserve(key.size() + value.size() + 16);
    payload.push_back('{');
    AppendJsonString(key, payload);
    payload.push_back(':');
    AppendJsonString(value, payload);
    payload.push_back('}');
    return payload;
}

std::string BuildDoublePayload(std::string_view key, double value)
{
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream << std::setprecision(17) << value;
    std::string payload;
    payload.reserve(key.size() + 48);
    payload.push_back('{');
    AppendJsonString(key, payload);
    payload.push_back(':');
    payload.append(stream.str());
    payload.push_back('}');
    return payload;
}

bool ResponseReportsOk(const std::string& response)
{
    return response.size() <= kMaxPayloadBytes &&
           response.find("\"type\":\"response\"") != std::string::npos &&
           response.find("\"ok\":true") != std::string::npos;
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

    // Identity resolution is part of the pipe security boundary. If it cannot
    // be resolved, fail closed instead of inventing a pipe name or spawning a
    // broker that this client cannot securely address.
    if (GetCommandPipeName().empty())
    {
        state_.store(BrokerConnectionState::Degraded);
        return false;
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
    if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return;

    WCHAR dir[MAX_PATH]{};
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

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};

    if (CreateProcessW(
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
        if (process.hProcess) CloseHandle(process.hProcess);
        if (process.hThread) CloseHandle(process.hThread);
    }
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
        if (!WriteFile(pipe_, header + header_written, sizeof(len) - header_written, &written, nullptr) || written == 0)
        {
            return false;
        }
        header_written += written;
    }

    DWORD total_written = 0;
    while (total_written < len)
    {
        if (!WriteFile(pipe_, payload.data() + total_written, len - total_written, &written, nullptr) || written == 0)
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
        if (!ReadFile(pipe_, header + header_bytes, sizeof(len) - header_bytes, &read_bytes, nullptr) || read_bytes == 0)
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
        if (!ReadFile(pipe_, payload.data() + total_read, len - total_read, &read_bytes, nullptr) || read_bytes == 0)
        {
            return false;
        }
        total_read += read_bytes;
    }
    return true;
}

bool CloudOSBrokerClientV21::PerformHandshake()
{
    const std::string payload = "{\"clientName\":\"CloudOS.FlutterShell\",\"clientVersion\":\"22.1\"}";
    const std::string request = BuildRequest("init-hello", "hello", payload);
    if (!SendFrame(request)) return false;

    std::string response;
    return ReadFrame(response) && ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::GetApps(std::vector<BrokerClientAppItem>& out_apps)
{
    out_apps.clear();
    // The Dart presentation path consumes apps.list through InvokeBrokerRpc.
    // Keep this legacy typed adapter non-authoritative instead of fabricating a
    // second parser/catalog inside the Flutter runner.
    return false;
}

bool CloudOSBrokerClientV21::LaunchApp(const std::string& app_id, std::string& err)
{
    if (app_id.empty() || app_id.size() > kMaxAppIdBytes)
    {
        err = "Application id is empty or too long";
        return false;
    }
    if (!EnsureConnected())
    {
        err = "System broker is not connected";
        return false;
    }

    const std::string payload = BuildStringPayload("id", app_id);
    const std::string request = BuildRequest("launch-app", "apps.launch", payload);
    std::string response;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(request) || !ReadFrame(response))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC communication failed during launch";
            return false;
        }
    }

    if (!ResponseReportsOk(response))
    {
        err = "Broker rejected application launch";
        return false;
    }
    return true;
}

bool CloudOSBrokerClientV21::GetSystemSnapshot(BrokerClientSnapshot& out_snapshot)
{
    out_snapshot = {};
    // The Dart presentation path consumes system.snapshot through
    // InvokeBrokerRpc. This legacy adapter intentionally remains empty.
    return false;
}

bool CloudOSBrokerClientV21::SetVolume(double value)
{
    if (!std::isfinite(value) || value < 0.0 || value > 1.0 || !EnsureConnected()) return false;
    const std::string request = BuildRequest("set-vol", "system.volume.set", BuildDoublePayload("value", value));
    std::string response;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(request) || !ReadFrame(response))
    {
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }
    return ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::SetBrightness(double value)
{
    if (!std::isfinite(value) || value < 0.0 || value > 1.0 || !EnsureConnected()) return false;
    const std::string request = BuildRequest("set-bri", "system.brightness.set", BuildDoublePayload("value", value));
    std::string response;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(request) || !ReadFrame(response))
    {
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }
    return ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    // Only advertise methods the synchronous Flutter client can safely expose
    // independent of hardware. Dynamic hardware capabilities belong to the
    // broker's system.capabilities response. Event subscriptions are excluded
    // until this client owns a real event demultiplexer.
    out_caps = {
        "broker.protocol.v21",
        "health.ping",
        "health.status",
        "system.capabilities",
        "apps.list",
        "apps.launch",
        "system.snapshot",
        "wsl.list",
        "jobs.status",
        "jobs.cancel",
        "diagnostics.snapshot",
        "files.list",
        "files.metadata",
        "files.drives",
        "files.knownFolders",
        "files.resolvePath",
        "files.createFolder",
        "files.rename",
        "files.delete",
        "files.copy",
        "files.move",
        "files.search",
        "files.open",
        "files.openWith.list",
        "files.openWith.launch",
    };
    return true;
}

bool CloudOSBrokerClientV21::InvokeBrokerRpc(
    const std::string& method,
    const std::string& payload_json,
    std::string& out_resp_json)
{
    out_resp_json.clear();
    if (!IsSafeRpcMethod(method) || !LooksLikeJsonObjectPayload(payload_json)) return false;
    if (!EnsureConnected()) return false;

    const uint64_t req_id = next_req_id_++;
    const std::string request_id = "req-" + std::to_string(req_id);
    const std::string request = BuildRequest(request_id, method, payload_json);
    if (request.size() > kMaxPayloadBytes) return false;

    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(request) || !ReadFrame(out_resp_json))
    {
        state_.store(BrokerConnectionState::Degraded);
        out_resp_json.clear();
        return false;
    }
    return true;
}

} // namespace CloudOS
