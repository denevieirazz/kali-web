#include "broker_server_v21.h"
#include "app_service_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "job_manager_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <iostream>

namespace CloudOS
{

namespace
{
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
} // namespace

BrokerServerV21& BrokerServerV21::Instance()
{
    static BrokerServerV21 instance;
    return instance;
}

BrokerServerV21::~BrokerServerV21()
{
    Stop();
}

bool BrokerServerV21::Start()
{
    if (running_.load()) return true;

    const std::wstring mutex_name = SecurityV21::GetBrokerMutexName();
    mutex_handle_ = CreateMutexW(nullptr, TRUE, mutex_name.c_str());
    if (!mutex_handle_ || GetLastError() == ERROR_ALREADY_EXISTS)
    {
        if (mutex_handle_)
        {
            CloseHandle(mutex_handle_);
            mutex_handle_ = nullptr;
        }
        std::cerr << "[SystemBroker] Another instance is already running for this user session." << std::endl;
        return false;
    }

    DiagnosticsV21::Initialize();
    JobManagerV21::Instance().Initialize(2);

    running_.store(true);
    listener_thread_ = std::thread(&BrokerServerV21::ListenerLoop, this);

    JsonObject ready_payload;
    ready_payload["version"] = JsonValue("21.0.0");
    ready_payload["protocol"] = JsonValue(kProtocolVersion);
    EventBusV21::Instance().Publish("broker.ready", ready_payload);

    return true;
}

void BrokerServerV21::Stop()
{
    if (!running_.exchange(false)) return;

    // Unblock ConnectNamedPipe in the listener thread.
    const std::wstring pipe_name = SecurityV21::GetCommandPipeName();
    HANDLE dummy = CreateFileW(
        pipe_name.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);
    if (dummy != INVALID_HANDLE_VALUE)
    {
        CloseHandle(dummy);
    }

    if (listener_thread_.joinable())
    {
        listener_thread_.join();
    }

    // Client sessions may be blocked in synchronous ReadFile. Cancel their
    // pending I/O before joining so broker shutdown cannot hang indefinitely.
    {
        std::lock_guard<std::mutex> lock(client_threads_mutex_);
        for (auto& thread : client_threads_)
        {
            if (thread.joinable())
            {
                CancelSynchronousIo(thread.native_handle());
            }
        }
        for (auto& thread : client_threads_)
        {
            if (thread.joinable())
            {
                thread.join();
            }
        }
        client_threads_.clear();
    }

    JobManagerV21::Instance().Shutdown();

    if (mutex_handle_)
    {
        ReleaseMutex(mutex_handle_);
        CloseHandle(mutex_handle_);
        mutex_handle_ = nullptr;
    }
}

bool BrokerServerV21::SendFrame(HANDLE pipe, const std::string& payload)
{
    if (pipe == INVALID_HANDLE_VALUE || payload.size() > kMaxPayloadBytes)
    {
        return false;
    }

    const uint32_t len = static_cast<uint32_t>(payload.size());
    if (!WriteExact(pipe, &len, static_cast<DWORD>(sizeof(len))))
    {
        return false;
    }
    return len == 0 || WriteExact(pipe, payload.data(), len);
}

bool BrokerServerV21::ReadFrame(HANDLE pipe, std::string& payload)
{
    if (pipe == INVALID_HANDLE_VALUE)
    {
        return false;
    }

    uint32_t len = 0;
    if (!ReadExact(pipe, &len, static_cast<DWORD>(sizeof(len))) || len > kMaxPayloadBytes)
    {
        return false;
    }

    payload.assign(len, '\0');
    return len == 0 || ReadExact(pipe, payload.data(), len);
}

void BrokerServerV21::ListenerLoop()
{
    const std::wstring pipe_name = SecurityV21::GetCommandPipeName();

    while (running_.load())
    {
        SECURITY_ATTRIBUTES sa{};
        PSECURITY_DESCRIPTOR sd = nullptr;
        const bool sa_ok = SecurityV21::CreatePerUserSecurityAttributes(&sa, &sd);

        HANDLE pipe = CreateNamedPipeW(
            pipe_name.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            PIPE_UNLIMITED_INSTANCES,
            65536,
            65536,
            0,
            sa_ok ? &sa : nullptr);

        if (sa_ok)
        {
            SecurityV21::FreeSecurityDescriptor(sd);
        }

        if (pipe == INVALID_HANDLE_VALUE)
        {
            Sleep(100);
            continue;
        }

        const BOOL connected = ConnectNamedPipe(pipe, nullptr)
            ? TRUE
            : (GetLastError() == ERROR_PIPE_CONNECTED);

        if (!running_.load())
        {
            CloseHandle(pipe);
            break;
        }

        if (connected)
        {
            const std::string client_id = "client-" + std::to_string(next_client_id_++);
            std::lock_guard<std::mutex> lock(client_threads_mutex_);
            client_threads_.emplace_back(&BrokerServerV21::ClientSessionLoop, this, pipe, client_id);
        }
        else
        {
            CloseHandle(pipe);
        }
    }
}

void BrokerServerV21::ClientSessionLoop(HANDLE pipe, std::string client_id)
{
    std::mutex send_mutex;
    EventBusV21::Instance().RegisterClient(
        client_id,
        [this, pipe, &send_mutex](const BrokerEvent& ev) {
            const std::string serialized = SerializeEvent(ev);
            std::lock_guard<std::mutex> lock(send_mutex);
            SendFrame(pipe, serialized);
        });

    while (running_.load())
    {
        std::string frame;
        if (!ReadFrame(pipe, frame))
        {
            break;
        }

        BrokerRequest req;
        std::string parse_err;
        BrokerResponse res;

        if (!ParseRequest(frame, req, parse_err))
        {
            res.protocol = kProtocolVersion;
            res.id = "unknown";
            res.ok = false;
            res.error_code = "invalid_request";
            res.error_message = parse_err;
        }
        else
        {
            res = HandleRequest(client_id, req);
        }

        const std::string response = SerializeResponse(res);
        std::lock_guard<std::mutex> lock(send_mutex);
        if (!SendFrame(pipe, response))
        {
            break;
        }
    }

    EventBusV21::Instance().UnregisterClient(client_id);
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
}

BrokerResponse BrokerServerV21::HandleRequest(const std::string& client_id, const BrokerRequest& req)
{
    BrokerResponse res;
    res.protocol = kProtocolVersion;
    res.id = req.id;
    res.ok = true;

    const std::string& method = req.method;

    if (method == "hello")
    {
        res.payload["brokerVersion"] = JsonValue("21.0.0");
        res.payload["protocolVersion"] = JsonValue(kProtocolVersion);
        res.payload["clientId"] = JsonValue(client_id);
        res.payload["serverInstanceId"] = JsonValue("broker-session-" + std::to_string(SecurityV21::GetCurrentSessionId()));

        JsonArray caps;
        for (const auto& cap : SystemServiceV21::Instance().GetCapabilities())
        {
            caps.push_back(JsonValue(cap));
        }
        res.payload["capabilities"] = JsonValue(std::move(caps));
        return res;
    }

    if (method == "health.ping")
    {
        res.payload["pong"] = JsonValue(true);
        res.payload["protocol"] = JsonValue(kProtocolVersion);
        return res;
    }

    if (method == "health.status")
    {
        res.payload["status"] = JsonValue("healthy");
        res.payload["protocol"] = JsonValue(kProtocolVersion);
        res.payload["activeClients"] = JsonValue(static_cast<int64_t>(EventBusV21::Instance().GetActiveClientCount()));
        res.payload["activeJobs"] = JsonValue(static_cast<int64_t>(JobManagerV21::Instance().GetActiveJobCount()));
        return res;
    }

    if (method == "system.capabilities")
    {
        JsonArray caps;
        for (const auto& cap : SystemServiceV21::Instance().GetCapabilities())
        {
            caps.push_back(JsonValue(cap));
        }
        res.payload["capabilities"] = JsonValue(std::move(caps));
        return res;
    }

    if (method == "apps.list")
    {
        const auto apps = AppServiceV21::Instance().GetApps();
        JsonArray arr;
        for (const auto& app : apps)
        {
            arr.push_back(JsonValue(app.ToJsonObject()));
        }
        res.payload["apps"] = JsonValue(std::move(arr));
        res.payload["generation"] = JsonValue(static_cast<int64_t>(AppServiceV21::Instance().GetGeneration()));
        return res;
    }

    if (method == "apps.launch")
    {
        const auto it = req.payload.find("id");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'id' parameter in payload";
            return res;
        }

        const std::string app_id = it->second.AsString();
        std::string err;
        if (!AppServiceV21::Instance().LaunchApp(app_id, err))
        {
            res.ok = false;
            res.error_code = "launch_failed";
            res.error_message = err;
            return res;
        }
        res.payload["launched"] = JsonValue(true);
        res.payload["id"] = JsonValue(app_id);
        return res;
    }

    if (method == "system.snapshot")
    {
        res.payload = SystemServiceV21::Instance().GetSnapshot().ToJsonObject();
        return res;
    }

    if (method == "system.volume.set")
    {
        const auto it = req.payload.find("value");
        if (it == req.payload.end() || !it->second.IsDouble())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid double 'value'";
            return res;
        }
        if (!SystemServiceV21::Instance().SetVolume(it->second.AsDouble()))
        {
            res.ok = false;
            res.error_code = "not_supported";
            res.error_message = "No writable default audio endpoint is available";
            return res;
        }
        res.payload["updated"] = JsonValue(true);
        return res;
    }

    if (method == "system.brightness.set")
    {
        const auto it = req.payload.find("value");
        if (it == req.payload.end() || !it->second.IsDouble())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid double 'value'";
            return res;
        }
        if (!SystemServiceV21::Instance().SetBrightness(it->second.AsDouble()))
        {
            res.ok = false;
            res.error_code = "not_supported";
            res.error_message = "Primary monitor does not expose writable brightness control";
            return res;
        }
        res.payload["updated"] = JsonValue(true);
        return res;
    }

    if (method == "wsl.list")
    {
        res.payload["wslAvailable"] = JsonValue(WslServiceV21::Instance().IsWslAvailable());
        JsonArray distros;
        for (const auto& d : WslServiceV21::Instance().GetDistributions())
        {
            distros.push_back(JsonValue(d));
        }
        res.payload["distros"] = JsonValue(std::move(distros));
        res.payload["generation"] = JsonValue(static_cast<int64_t>(WslServiceV21::Instance().GetGeneration()));
        return res;
    }

    if (method == "events.subscribe")
    {
        const auto it = req.payload.find("pattern");
        const std::string pattern = (it != req.payload.end() && it->second.IsString())
            ? it->second.AsString()
            : "*";
        const bool ok = EventBusV21::Instance().Subscribe(client_id, pattern);
        res.payload["subscribed"] = JsonValue(ok);
        res.payload["pattern"] = JsonValue(pattern);
        return res;
    }

    if (method == "events.unsubscribe")
    {
        const auto it = req.payload.find("pattern");
        const std::string pattern = (it != req.payload.end() && it->second.IsString())
            ? it->second.AsString()
            : "*";
        const bool ok = EventBusV21::Instance().Unsubscribe(client_id, pattern);
        res.payload["unsubscribed"] = JsonValue(ok);
        res.payload["pattern"] = JsonValue(pattern);
        return res;
    }

    if (method == "jobs.status")
    {
        const auto it = req.payload.find("jobId");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'jobId'";
            return res;
        }
        JobInfo info;
        if (!JobManagerV21::Instance().GetJobInfo(it->second.AsString(), info))
        {
            res.ok = false;
            res.error_code = "not_found";
            res.error_message = "Job not found";
            return res;
        }
        res.payload["jobId"] = JsonValue(info.id);
        res.payload["type"] = JsonValue(info.type);
        res.payload["state"] = JsonValue(JobStateToString(info.state));
        res.payload["progress"] = JsonValue(info.progress);
        res.payload["error"] = JsonValue(info.error_message);
        return res;
    }

    if (method == "jobs.cancel")
    {
        const auto it = req.payload.find("jobId");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'jobId'";
            return res;
        }
        const bool cancelled = JobManagerV21::Instance().CancelJob(it->second.AsString());
        res.payload["cancelled"] = JsonValue(cancelled);
        return res;
    }

    if (method == "diagnostics.snapshot")
    {
        res.payload = DiagnosticsV21::GetDiagnosticsSnapshot();
        return res;
    }

    res.ok = false;
    res.error_code = "unsupported_method";
    res.error_message = "Method '" + method + "' is not supported by protocol " + std::to_string(kProtocolVersion);
    return res;
}

} // namespace CloudOS
