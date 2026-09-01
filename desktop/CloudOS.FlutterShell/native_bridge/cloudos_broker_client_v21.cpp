#include "cloudos_broker_client_v21.h"

#include <sddl.h>
#include <shlwapi.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <locale>
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
constexpr size_t kMaxEventPatternBytes = 128;
constexpr size_t kMaxDesiredSubscriptions = 16;
constexpr size_t kMaxJsonDepth = 32;

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

bool IsSafeEventPattern(std::string_view pattern)
{
    if (pattern.empty() || pattern.size() > kMaxEventPatternBytes) return false;
    if (pattern == "*") return true;

    for (size_t i = 0; i < pattern.size(); ++i)
    {
        const unsigned char ch = static_cast<unsigned char>(pattern[i]);
        if (std::isalnum(ch) != 0 || ch == '.' || ch == '_' || ch == '-') continue;
        if (ch == '*' && i + 1 == pattern.size()) continue;
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

void SkipWhitespace(std::string_view json, size_t& pos)
{
    while (pos < json.size() && std::isspace(static_cast<unsigned char>(json[pos])) != 0) ++pos;
}

bool IsHexDigit(char ch)
{
    return (ch >= '0' && ch <= '9') ||
           (ch >= 'a' && ch <= 'f') ||
           (ch >= 'A' && ch <= 'F');
}

bool ParseJsonStringToken(std::string_view json, size_t& pos, std::string* out)
{
    if (pos >= json.size() || json[pos] != '"') return false;
    ++pos;
    if (out) out->clear();

    while (pos < json.size())
    {
        const unsigned char ch = static_cast<unsigned char>(json[pos++]);
        if (ch == '"') return true;
        if (ch < 0x20) return false;

        if (ch != '\\')
        {
            if (out) out->push_back(static_cast<char>(ch));
            continue;
        }

        if (pos >= json.size()) return false;
        const char escaped = json[pos++];
        switch (escaped)
        {
        case '"': if (out) out->push_back('"'); break;
        case '\\': if (out) out->push_back('\\'); break;
        case '/': if (out) out->push_back('/'); break;
        case 'b': if (out) out->push_back('\b'); break;
        case 'f': if (out) out->push_back('\f'); break;
        case 'n': if (out) out->push_back('\n'); break;
        case 'r': if (out) out->push_back('\r'); break;
        case 't': if (out) out->push_back('\t'); break;
        case 'u':
            if (pos + 4 > json.size()) return false;
            for (size_t i = 0; i < 4; ++i)
            {
                if (!IsHexDigit(json[pos + i])) return false;
            }
            pos += 4;
            // Envelope keys/type/id/event are ASCII in protocol V21. Preserve
            // structural validity without implementing a second Unicode codec.
            if (out) out->push_back('?');
            break;
        default:
            return false;
        }
    }
    return false;
}

bool SkipJsonValue(std::string_view json, size_t& pos, size_t depth);

bool SkipJsonObject(std::string_view json, size_t& pos, size_t depth)
{
    if (depth > kMaxJsonDepth || pos >= json.size() || json[pos] != '{') return false;
    ++pos;
    SkipWhitespace(json, pos);
    if (pos < json.size() && json[pos] == '}')
    {
        ++pos;
        return true;
    }

    while (pos < json.size())
    {
        if (!ParseJsonStringToken(json, pos, nullptr)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size() || json[pos] != ':') return false;
        ++pos;
        if (!SkipJsonValue(json, pos, depth + 1)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size()) return false;
        if (json[pos] == '}')
        {
            ++pos;
            return true;
        }
        if (json[pos] != ',') return false;
        ++pos;
        SkipWhitespace(json, pos);
    }
    return false;
}

bool SkipJsonArray(std::string_view json, size_t& pos, size_t depth)
{
    if (depth > kMaxJsonDepth || pos >= json.size() || json[pos] != '[') return false;
    ++pos;
    SkipWhitespace(json, pos);
    if (pos < json.size() && json[pos] == ']')
    {
        ++pos;
        return true;
    }

    while (pos < json.size())
    {
        if (!SkipJsonValue(json, pos, depth + 1)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size()) return false;
        if (json[pos] == ']')
        {
            ++pos;
            return true;
        }
        if (json[pos] != ',') return false;
        ++pos;
        SkipWhitespace(json, pos);
    }
    return false;
}

bool SkipJsonNumber(std::string_view json, size_t& pos)
{
    const size_t start = pos;
    if (pos < json.size() && json[pos] == '-') ++pos;
    if (pos >= json.size()) return false;

    if (json[pos] == '0')
    {
        ++pos;
    }
    else if (json[pos] >= '1' && json[pos] <= '9')
    {
        while (pos < json.size() && std::isdigit(static_cast<unsigned char>(json[pos])) != 0) ++pos;
    }
    else
    {
        return false;
    }

    if (pos < json.size() && json[pos] == '.')
    {
        ++pos;
        const size_t fraction_start = pos;
        while (pos < json.size() && std::isdigit(static_cast<unsigned char>(json[pos])) != 0) ++pos;
        if (pos == fraction_start) return false;
    }

    if (pos < json.size() && (json[pos] == 'e' || json[pos] == 'E'))
    {
        ++pos;
        if (pos < json.size() && (json[pos] == '+' || json[pos] == '-')) ++pos;
        const size_t exponent_start = pos;
        while (pos < json.size() && std::isdigit(static_cast<unsigned char>(json[pos])) != 0) ++pos;
        if (pos == exponent_start) return false;
    }

    return pos > start;
}

bool SkipJsonValue(std::string_view json, size_t& pos, size_t depth)
{
    if (depth > kMaxJsonDepth) return false;
    SkipWhitespace(json, pos);
    if (pos >= json.size()) return false;

    if (json[pos] == '"') return ParseJsonStringToken(json, pos, nullptr);
    if (json[pos] == '{') return SkipJsonObject(json, pos, depth + 1);
    if (json[pos] == '[') return SkipJsonArray(json, pos, depth + 1);
    if (json.substr(pos, 4) == "true") { pos += 4; return true; }
    if (json.substr(pos, 5) == "false") { pos += 5; return true; }
    if (json.substr(pos, 4) == "null") { pos += 4; return true; }
    if (json[pos] == '-' || std::isdigit(static_cast<unsigned char>(json[pos])) != 0)
    {
        return SkipJsonNumber(json, pos);
    }
    return false;
}

bool ExtractTopLevelStringField(
    std::string_view json,
    std::string_view target,
    std::string& out)
{
    size_t pos = 0;
    SkipWhitespace(json, pos);
    if (pos >= json.size() || json[pos] != '{') return false;
    ++pos;
    SkipWhitespace(json, pos);

    while (pos < json.size() && json[pos] != '}')
    {
        std::string key;
        if (!ParseJsonStringToken(json, pos, &key)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size() || json[pos] != ':') return false;
        ++pos;
        SkipWhitespace(json, pos);

        if (key == target)
        {
            return ParseJsonStringToken(json, pos, &out);
        }

        if (!SkipJsonValue(json, pos, 0)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size()) return false;
        if (json[pos] == ',')
        {
            ++pos;
            SkipWhitespace(json, pos);
            continue;
        }
        if (json[pos] == '}') break;
        return false;
    }
    return false;
}

bool ExtractTopLevelBoolField(
    std::string_view json,
    std::string_view target,
    bool& out)
{
    size_t pos = 0;
    SkipWhitespace(json, pos);
    if (pos >= json.size() || json[pos] != '{') return false;
    ++pos;
    SkipWhitespace(json, pos);

    while (pos < json.size() && json[pos] != '}')
    {
        std::string key;
        if (!ParseJsonStringToken(json, pos, &key)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size() || json[pos] != ':') return false;
        ++pos;
        SkipWhitespace(json, pos);

        if (key == target)
        {
            if (json.substr(pos, 4) == "true")
            {
                out = true;
                return true;
            }
            if (json.substr(pos, 5) == "false")
            {
                out = false;
                return true;
            }
            return false;
        }

        if (!SkipJsonValue(json, pos, 0)) return false;
        SkipWhitespace(json, pos);
        if (pos >= json.size()) return false;
        if (json[pos] == ',')
        {
            ++pos;
            SkipWhitespace(json, pos);
            continue;
        }
        if (json[pos] == '}') break;
        return false;
    }
    return false;
}

bool ResponseReportsOk(const std::string& response)
{
    if (response.size() > kMaxPayloadBytes) return false;
    std::string type;
    bool ok = false;
    return ExtractTopLevelStringField(response, "type", type) &&
           type == "response" &&
           ExtractTopLevelBoolField(response, "ok", ok) &&
           ok;
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
    bool connected = false;
    {
        std::lock_guard<std::mutex> lock(connection_mutex_);
        if (pipe_ != INVALID_HANDLE_VALUE &&
            state_.load() == BrokerConnectionState::Connected &&
            reader_thread_.joinable())
        {
            return true;
        }

        CloseConnectionLocked();
        state_.store(BrokerConnectionState::Connecting);

        if (TryConnectPipeLocked() && PerformHandshakeLocked())
        {
            StartReaderLocked();
            state_.store(BrokerConnectionState::Connected);
            connected = true;
        }
        else
        {
            if (pipe_ != INVALID_HANDLE_VALUE)
            {
                CloseHandle(pipe_);
                pipe_ = INVALID_HANDLE_VALUE;
            }

            // Identity resolution is part of the pipe security boundary. If it
            // cannot be resolved, fail closed instead of inventing a pipe name.
            if (GetCommandPipeName().empty())
            {
                state_.store(BrokerConnectionState::Degraded);
                return false;
            }

            SpawnBrokerIfNeeded();
            for (int attempt = 0; attempt < 10 && !connected; ++attempt)
            {
                Sleep(100);
                if (TryConnectPipeLocked() && PerformHandshakeLocked())
                {
                    StartReaderLocked();
                    state_.store(BrokerConnectionState::Connected);
                    connected = true;
                    break;
                }
                if (pipe_ != INVALID_HANDLE_VALUE)
                {
                    CloseHandle(pipe_);
                    pipe_ = INVALID_HANDLE_VALUE;
                }
            }
        }

        if (!connected)
        {
            state_.store(BrokerConnectionState::Degraded);
        }
    }

    if (connected)
    {
        // Subscription restoration is best-effort for the base RPC channel.
        // ConfigureEventSubscriptions reports failure to callers that require
        // the reactive stream, while ordinary RPC remains available.
        ReconcileEventSubscriptions();
    }
    return connected;
}

void CloudOSBrokerClientV21::Disconnect()
{
    std::lock_guard<std::mutex> lock(connection_mutex_);
    CloseConnectionLocked();
    state_.store(BrokerConnectionState::Disconnected);
}

bool CloudOSBrokerClientV21::TryConnectPipeLocked()
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

bool CloudOSBrokerClientV21::WriteFrame(HANDLE pipe, const std::string& payload) const
{
    if (pipe == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes) return false;

    const uint32_t len = static_cast<uint32_t>(payload.size());
    const auto* header = reinterpret_cast<const unsigned char*>(&len);
    DWORD written = 0;
    DWORD header_written = 0;
    while (header_written < sizeof(len))
    {
        if (!WriteFile(pipe, header + header_written, sizeof(len) - header_written, &written, nullptr) || written == 0)
        {
            return false;
        }
        header_written += written;
    }

    DWORD total_written = 0;
    while (total_written < len)
    {
        if (!WriteFile(pipe, payload.data() + total_written, len - total_written, &written, nullptr) || written == 0)
        {
            return false;
        }
        total_written += written;
    }
    return true;
}

bool CloudOSBrokerClientV21::ReadFrame(HANDLE pipe, std::string& payload) const
{
    if (pipe == INVALID_HANDLE_VALUE) return false;

    uint32_t len = 0;
    auto* header = reinterpret_cast<unsigned char*>(&len);
    DWORD read_bytes = 0;
    DWORD header_bytes = 0;
    while (header_bytes < sizeof(len))
    {
        if (!ReadFile(pipe, header + header_bytes, sizeof(len) - header_bytes, &read_bytes, nullptr) || read_bytes == 0)
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
        if (!ReadFile(pipe, payload.data() + total_read, len - total_read, &read_bytes, nullptr) || read_bytes == 0)
        {
            return false;
        }
        total_read += read_bytes;
    }
    return true;
}

bool CloudOSBrokerClientV21::PerformHandshakeLocked()
{
    if (pipe_ == INVALID_HANDLE_VALUE) return false;
    const std::string payload = "{\"clientName\":\"CloudOS.FlutterShell\",\"clientVersion\":\"23.0\"}";
    const std::string request = BuildRequest("init-hello", "hello", payload);
    if (!WriteFrame(pipe_, request)) return false;

    std::string response;
    if (!ReadFrame(pipe_, response) || !ResponseReportsOk(response)) return false;

    std::string response_id;
    return ExtractTopLevelStringField(response, "id", response_id) && response_id == "init-hello";
}

void CloudOSBrokerClientV21::StartReaderLocked()
{
    reader_stop_.store(false);
    const HANDLE reader_pipe = pipe_;
    reader_thread_ = std::thread(&CloudOSBrokerClientV21::ReaderLoop, this, reader_pipe);
}

void CloudOSBrokerClientV21::CloseConnectionLocked()
{
    reader_stop_.store(true);

    if (pipe_ != INVALID_HANDLE_VALUE)
    {
        CancelIoEx(pipe_, nullptr);
        if (reader_thread_.joinable())
        {
            CancelSynchronousIo(reader_thread_.native_handle());
        }
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
    }

    if (reader_thread_.joinable())
    {
        reader_thread_.join();
    }

    {
        std::lock_guard<std::mutex> lock(subscriptions_mutex_);
        active_subscriptions_.clear();
    }
    FailAllPending();
}

void CloudOSBrokerClientV21::ReaderLoop(HANDLE pipe)
{
    while (!reader_stop_.load())
    {
        std::string frame;
        if (!ReadFrame(pipe, frame))
        {
            if (!reader_stop_.load())
            {
                state_.store(BrokerConnectionState::Degraded);
                FailAllPending();
            }
            break;
        }
        HandleIncomingFrame(frame);
        if (state_.load() == BrokerConnectionState::Degraded) break;
    }
}

void CloudOSBrokerClientV21::HandleIncomingFrame(const std::string& frame)
{
    std::string type;
    if (!ExtractTopLevelStringField(frame, "type", type))
    {
        state_.store(BrokerConnectionState::Degraded);
        FailAllPending();
        return;
    }

    if (type == "response")
    {
        std::string response_id;
        if (!ExtractTopLevelStringField(frame, "id", response_id) || response_id.empty())
        {
            state_.store(BrokerConnectionState::Degraded);
            FailAllPending();
            return;
        }

        std::shared_ptr<PendingResponse> pending;
        {
            std::lock_guard<std::mutex> lock(pending_mutex_);
            const auto it = pending_responses_.find(response_id);
            if (it != pending_responses_.end())
            {
                pending = it->second;
                pending_responses_.erase(it);
            }
        }

        // A late response for a request that already timed out is safe to drop:
        // request IDs are monotonic and never reused during the process lifetime.
        if (!pending) return;

        {
            std::lock_guard<std::mutex> lock(pending->mutex);
            pending->response = frame;
            pending->completed = true;
        }
        pending->cv.notify_one();
        return;
    }

    if (type == "event")
    {
        std::string event_name;
        if (!ExtractTopLevelStringField(frame, "event", event_name) || event_name.empty())
        {
            state_.store(BrokerConnectionState::Degraded);
            FailAllPending();
            return;
        }

        BrokerEventCallback callback;
        {
            std::lock_guard<std::mutex> lock(event_callback_mutex_);
            callback = event_callback_;
        }
        if (callback) callback(event_name, frame);
        return;
    }

    state_.store(BrokerConnectionState::Degraded);
    FailAllPending();
}

void CloudOSBrokerClientV21::FailAllPending()
{
    std::vector<std::shared_ptr<PendingResponse>> pending;
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        pending.reserve(pending_responses_.size());
        for (const auto& [id, response] : pending_responses_)
        {
            (void)id;
            pending.push_back(response);
        }
        pending_responses_.clear();
    }

    for (const auto& response : pending)
    {
        {
            std::lock_guard<std::mutex> lock(response->mutex);
            response->failed = true;
            response->completed = true;
        }
        response->cv.notify_all();
    }
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

    std::string response;
    if (!InvokeBrokerRpc("apps.launch", BuildStringPayload("id", app_id), response))
    {
        err = "IPC communication failed during launch";
        return false;
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
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    std::string response;
    return InvokeBrokerRpc("system.volume.set", BuildDoublePayload("value", value), response) &&
           ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::SetBrightness(double value)
{
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    std::string response;
    return InvokeBrokerRpc("system.brightness.set", BuildDoublePayload("value", value), response) &&
           ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    out_caps = {
        "broker.protocol.v21",
        "broker.event_demux.v23",
        "health.ping",
        "health.status",
        "system.capabilities",
        "apps.list",
        "apps.launch",
        "system.snapshot",
        "wsl.list",
        "events.subscribe",
        "events.unsubscribe",
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

    const auto pending = std::make_shared<PendingResponse>();
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        if (pending_responses_.size() >= kMaxPendingResponses) return false;
        pending_responses_[request_id] = pending;
    }

    HANDLE pipe = INVALID_HANDLE_VALUE;
    {
        std::lock_guard<std::mutex> lock(connection_mutex_);
        if (state_.load() == BrokerConnectionState::Connected)
        {
            pipe = pipe_;
        }
    }

    if (pipe == INVALID_HANDLE_VALUE)
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        pending_responses_.erase(request_id);
        return false;
    }

    bool sent = false;
    {
        std::lock_guard<std::mutex> lock(write_mutex_);
        sent = WriteFrame(pipe, request);
    }
    if (!sent)
    {
        {
            std::lock_guard<std::mutex> lock(pending_mutex_);
            pending_responses_.erase(request_id);
        }
        state_.store(BrokerConnectionState::Degraded);
        FailAllPending();
        return false;
    }

    std::unique_lock<std::mutex> pending_lock(pending->mutex);
    const bool signaled = pending->cv.wait_for(
        pending_lock,
        std::chrono::milliseconds(kRpcTimeoutMs),
        [&pending]() { return pending->completed; });

    if (!signaled)
    {
        pending_lock.unlock();
        {
            std::lock_guard<std::mutex> lock(pending_mutex_);
            const auto it = pending_responses_.find(request_id);
            if (it != pending_responses_.end() && it->second == pending)
            {
                pending_responses_.erase(it);
            }
        }
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }

    if (pending->failed) return false;
    out_resp_json = pending->response;
    return !out_resp_json.empty();
}

void CloudOSBrokerClientV21::SetEventCallback(BrokerEventCallback callback)
{
    std::lock_guard<std::mutex> lock(event_callback_mutex_);
    event_callback_ = std::move(callback);
}

bool CloudOSBrokerClientV21::ConfigureEventSubscriptions(const std::vector<std::string>& patterns)
{
    if (patterns.size() > kMaxDesiredSubscriptions) return false;

    std::vector<std::string> normalized;
    normalized.reserve(patterns.size());
    std::unordered_set<std::string> seen;
    for (const auto& pattern : patterns)
    {
        if (!IsSafeEventPattern(pattern)) return false;
        if (seen.insert(pattern).second) normalized.push_back(pattern);
    }

    {
        std::lock_guard<std::mutex> lock(subscriptions_mutex_);
        desired_subscriptions_ = std::move(normalized);
    }

    if (!EnsureConnected()) return false;
    return ReconcileEventSubscriptions();
}

size_t CloudOSBrokerClientV21::DesiredEventSubscriptionCount() const
{
    std::lock_guard<std::mutex> lock(subscriptions_mutex_);
    return desired_subscriptions_.size();
}

bool CloudOSBrokerClientV21::SendSubscriptionRpc(const char* method, const std::string& pattern)
{
    std::string response;
    return InvokeBrokerRpc(method, BuildStringPayload("pattern", pattern), response) &&
           ResponseReportsOk(response);
}

bool CloudOSBrokerClientV21::ReconcileEventSubscriptions()
{
    if (!IsConnected()) return false;

    std::vector<std::string> desired;
    std::unordered_set<std::string> active;
    {
        std::lock_guard<std::mutex> lock(subscriptions_mutex_);
        desired = desired_subscriptions_;
        active = active_subscriptions_;
    }

    std::unordered_set<std::string> desired_set(desired.begin(), desired.end());

    for (const auto& pattern : active)
    {
        if (desired_set.find(pattern) != desired_set.end()) continue;
        if (!SendSubscriptionRpc("events.unsubscribe", pattern)) return false;
        std::lock_guard<std::mutex> lock(subscriptions_mutex_);
        active_subscriptions_.erase(pattern);
    }

    for (const auto& pattern : desired)
    {
        {
            std::lock_guard<std::mutex> lock(subscriptions_mutex_);
            if (active_subscriptions_.find(pattern) != active_subscriptions_.end()) continue;
        }
        if (!SendSubscriptionRpc("events.subscribe", pattern)) return false;
        std::lock_guard<std::mutex> lock(subscriptions_mutex_);
        active_subscriptions_.insert(pattern);
    }

    return true;
}

} // namespace CloudOS
