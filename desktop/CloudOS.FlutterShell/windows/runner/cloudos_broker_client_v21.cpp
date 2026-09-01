#include "cloudos_broker_client_v21.h"

#include <sddl.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <chrono>
#include <iostream>
#include <sstream>

namespace CloudOS
{

namespace
{
constexpr int kProtocolVersion = 21;
constexpr uint32_t kMaxPayloadBytes = 1048576;

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
    std::wstring sid = GetCurrentUserSidString();
    DWORD session_id = GetCurrentSessionId();
    return L"\\\\.\\pipe\\CloudOS.SystemBroker.v21." + sid + L"." + std::to_wstring(session_id);
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

    if (TryConnectPipe())
    {
        if (PerformHandshake())
        {
            state_.store(BrokerConnectionState::Connected);
            return true;
        }
    }

    // Try to spawn broker and retry connection
    SpawnBrokerIfNeeded();

    for (int attempt = 0; attempt < 10; ++attempt)
    {
        Sleep(100);
        if (TryConnectPipe())
        {
            if (PerformHandshake())
            {
                state_.store(BrokerConnectionState::Connected);
                return true;
            }
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

    std::wstring pipe_name = GetCommandPipeName();
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
    const uint64_t now = GetTickCount64();
    const uint64_t previous = last_spawn_attempt_ms_.load();
    if (previous != 0 && now - previous < 5000) return;
    last_spawn_attempt_ms_.store(now);

    WCHAR exe_path[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return;

    WCHAR dir[MAX_PATH];
    wcscpy_s(dir, exe_path);
    PathRemoveFileSpecW(dir);

    // Look for CloudOS.SystemBroker.exe in same dir, or adjacent Release build
    std::wstring candidate1 = std::wstring(dir) + L"\\CloudOS.SystemBroker.exe";
    std::wstring candidate2 = std::wstring(dir) + L"\\..\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";
    std::wstring candidate3 = L"C:\\CloudOS\\desktop\\CloudOS.NativeShell\\bin\\Release\\CloudOS.SystemBroker.exe";

    std::wstring target;
    if (PathFileExistsW(candidate1.c_str())) target = candidate1;
    else if (PathFileExistsW(candidate2.c_str())) target = candidate2;
    else if (PathFileExistsW(candidate3.c_str())) target = candidate3;

    if (!target.empty())
    {
        STARTUPINFOW si{};
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE; // Run background
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
}

bool CloudOSBrokerClientV21::SendFrame(const std::string& payload)
{
    if (pipe_ == INVALID_HANDLE_VALUE) return false;
    if (payload.size() > kMaxPayloadBytes) return false;
    uint32_t len = static_cast<uint32_t>(payload.size());
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
    if (len > 0)
    {
        DWORD total_read = 0;
        while (total_read < len)
        {
            if (!ReadFile(pipe_, &payload[total_read], len - total_read, &read_bytes, nullptr) || read_bytes == 0)
            {
                return false;
            }
            total_read += read_bytes;
        }
    }
    return true;
}

bool CloudOSBrokerClientV21::PerformHandshake()
{
    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"init-hello\",\"method\":\"hello\",\"payload\":{\"clientName\":\"CloudOS.FlutterShell\",\"clientVersion\":\"21.0.0\"}}";
    if (!SendFrame(req)) return false;

    std::string resp;
    if (!ReadFrame(resp)) return false;

    // Verify response contains ok:true
    if (resp.find("\"ok\":true") == std::string::npos) return false;
    return true;
}

bool CloudOSBrokerClientV21::GetApps(std::vector<BrokerClientAppItem>& out_apps)
{
    if (!EnsureConnected()) return false;

    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"get-apps\",\"method\":\"apps.list\",\"payload\":{}}";
    std::string resp;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(req) || !ReadFrame(resp))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    if (resp.find("\"ok\":true") == std::string::npos) return false;

    out_apps.clear();
    // The typed UI path consumes apps.list through InvokeBrokerRpc so the JSON
    // remains broker-authoritative. This legacy adapter never fabricates apps.
    return false;
}

bool CloudOSBrokerClientV21::LaunchApp(const std::string& app_id, std::string& err)
{
    if (!EnsureConnected())
    {
        err = "System broker is not connected";
        return false;
    }

    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"launch-app\",\"method\":\"apps.launch\",\"payload\":{\"id\":\"" + app_id + "\"}}";
    std::string resp;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(req) || !ReadFrame(resp))
        {
            state_.store(BrokerConnectionState::Degraded);
            err = "IPC communication failed during launch";
            return false;
        }
    }

    if (resp.find("\"ok\":true") == std::string::npos)
    {
        err = "Broker rejected application launch";
        return false;
    }
    return true;
}

bool CloudOSBrokerClientV21::GetSystemSnapshot(BrokerClientSnapshot& out_snapshot)
{
    if (!EnsureConnected()) return false;

    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"get-snap\",\"method\":\"system.snapshot\",\"payload\":{}}";
    std::string resp;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!SendFrame(req) || !ReadFrame(resp))
        {
            state_.store(BrokerConnectionState::Degraded);
            return false;
        }
    }

    if (resp.find("\"ok\":true") == std::string::npos) return false;

    out_snapshot = {};
    return false;
}

bool CloudOSBrokerClientV21::SetVolume(double value)
{
    if (!EnsureConnected()) return false;
    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"set-vol\",\"method\":\"system.volume.set\",\"payload\":{\"value\":" + std::to_string(value) + "}}";
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(req)) return false;
    std::string resp;
    return ReadFrame(resp) && resp.find("\"ok\":true") != std::string::npos;
}

bool CloudOSBrokerClientV21::SetBrightness(double value)
{
    if (!EnsureConnected()) return false;
    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"set-bri\",\"method\":\"system.brightness.set\",\"payload\":{\"value\":" + std::to_string(value) + "}}";
    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(req)) return false;
    std::string resp;
    return ReadFrame(resp) && resp.find("\"ok\":true") != std::string::npos;
}

bool CloudOSBrokerClientV21::GetCapabilities(std::vector<std::string>& out_caps)
{
    out_caps = {
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

bool CloudOSBrokerClientV21::InvokeBrokerRpc(const std::string& method, const std::string& payload_json, std::string& out_resp_json)
{
    if (!EnsureConnected()) return false;

    uint64_t req_id = next_req_id_++;
    std::string req = "{\"protocol\":21,\"type\":\"request\",\"id\":\"req-" + std::to_string(req_id) + "\",\"method\":\"" + method + "\",\"payload\":" + (payload_json.empty() ? "{}" : payload_json) + "}";

    std::lock_guard<std::mutex> lock(mutex_);
    if (!SendFrame(req) || !ReadFrame(out_resp_json))
    {
        state_.store(BrokerConnectionState::Degraded);
        return false;
    }
    return true;
}

} // namespace CloudOS
