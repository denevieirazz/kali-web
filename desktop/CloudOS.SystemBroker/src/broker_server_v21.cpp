#include "broker_server_v21.h"
#include "app_service_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "file_service_v21.h"
#include "job_manager_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <iostream>

namespace CloudOS
{
namespace
{
constexpr size_t kMaxQueuedEventFrames = 128;
constexpr size_t kMaxQueuedEventBytes = 2 * kMaxPayloadBytes;
constexpr auto kClientIdleWait = std::chrono::milliseconds(5);

struct ClientSendState final
{
    std::mutex mutex;
    std::condition_variable event_ready;
    std::deque<std::string> event_queue;
    size_t queued_event_bytes{0};
    HANDLE pipe{INVALID_HANDLE_VALUE};
    bool active{true};
};

enum class InboundFrameProbe
{
    None,
    HeaderReady,
    Disconnected,
};

void WriteFilesPayload(
    BrokerResponse& response,
    const std::vector<FileItemV21>& items)
{
    JsonArray files;
    files.reserve(items.size());
    for (const FileItemV21& item : items)
    {
        files.push_back(JsonValue(item.ToJsonObject()));
    }
    response.payload["files"] = JsonValue(std::move(files));
}

void DeactivateClientSendState(const std::shared_ptr<ClientSendState>& state)
{
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->active = false;
        state->event_queue.clear();
        state->queued_event_bytes = 0;
    }
    state->event_ready.notify_all();
}

bool IsClientSendStateActive(const std::shared_ptr<ClientSendState>& state)
{
    std::lock_guard<std::mutex> lock(state->mutex);
    return state->active;
}

bool TryPopQueuedEvent(
    const std::shared_ptr<ClientSendState>& state,
    std::string& serialized)
{
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->active || state->event_queue.empty()) return false;
    serialized = std::move(state->event_queue.front());
    state->event_queue.pop_front();
    state->queued_event_bytes -= serialized.size();
    return true;
}

InboundFrameProbe ProbeInboundFrame(HANDLE pipe)
{
    uint32_t frame_length = 0;
    DWORD peeked = 0;
    DWORD available = 0;
    if (!PeekNamedPipe(
            pipe,
            &frame_length,
            static_cast<DWORD>(sizeof(frame_length)),
            &peeked,
            &available,
            nullptr))
    {
        return InboundFrameProbe::Disconnected;
    }

    if (available < sizeof(frame_length) || peeked < sizeof(frame_length))
    {
        return InboundFrameProbe::None;
    }

    return InboundFrameProbe::HeaderReady;
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

    std::wstring mutex_name = SecurityV21::GetBrokerMutexName();
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
    if (!running_.load()) return;
    running_.store(false);

    // Wake ConnectNamedPipe without requiring an external client.
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

    if (listener_thread_.joinable()) listener_thread_.join();

    // Client sessions may be blocked in synchronous ReadFile. Cancel both the
    // pipe I/O and the owning thread's synchronous I/O before joining so broker
    // shutdown is bounded even when a connected client is idle or wedged.
    std::vector<ClientThreadEntry> client_threads;
    {
        std::lock_guard<std::mutex> lock(client_threads_mutex_);
        for (HANDLE pipe : client_pipes_)
        {
            CancelIoEx(pipe, nullptr);
            DisconnectNamedPipe(pipe);
        }
        for (auto& entry : client_threads_)
        {
            if (entry.thread.joinable())
            {
                CancelSynchronousIo(entry.thread.native_handle());
            }
        }
        client_threads.swap(client_threads_);
    }

    for (auto& entry : client_threads)
    {
        if (entry.thread.joinable()) entry.thread.join();
    }

    {
        std::lock_guard<std::mutex> lock(client_threads_mutex_);
        client_pipes_.clear();
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
    if (payload.size() > kMaxPayloadBytes) return false;

    const uint32_t len = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    DWORD header_written = 0;
    const auto* header = reinterpret_cast<const unsigned char*>(&len);
    while (header_written < sizeof(len))
    {
        if (!WriteFile(
                pipe,
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
                pipe,
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

bool BrokerServerV21::ReadFrame(HANDLE pipe, std::string& payload)
{
    uint32_t len = 0;
    DWORD read_bytes = 0;
    DWORD header_bytes = 0;
    auto* header = reinterpret_cast<unsigned char*>(&len);
    while (header_bytes < sizeof(len))
    {
        if (!ReadFile(
                pipe,
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
                pipe,
                &payload[total_read],
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

void BrokerServerV21::ListenerLoop()
{
    const std::wstring pipe_name = SecurityV21::GetCommandPipeName();
    while (running_.load())
    {
        SECURITY_ATTRIBUTES sa{};
        PSECURITY_DESCRIPTOR sd = nullptr;
        const bool sa_ok = SecurityV21::CreatePerUserSecurityAttributes(&sa, &sd);
        if (!sa_ok)
        {
            // Never fall back to a default/null DACL. Broker availability is
            // allowed to degrade rather than becoming cross-user reachable.
            std::cerr << "[SystemBroker] Failed to construct fail-closed pipe security." << std::endl;
            Sleep(100);
            continue;
        }

        HANDLE pipe = CreateNamedPipeW(
            pipe_name.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            PIPE_UNLIMITED_INSTANCES,
            65536,
            65536,
            0,
            &sa);

        SecurityV21::FreeSecurityDescriptor(sd);
        if (pipe == INVALID_HANDLE_VALUE)
        {
            Sleep(100);
            continue;
        }

        const BOOL connected = ConnectNamedPipe(pipe, nullptr) ?
            TRUE :
            (GetLastError() == ERROR_PIPE_CONNECTED);
        if (!running_.load())
        {
            CloseHandle(pipe);
            break;
        }

        if (connected)
        {
            DWORD client_process_id = 0;
            if (!SecurityV21::ValidateNamedPipeClient(pipe, &client_process_id))
            {
                std::cerr << "[SystemBroker] Rejected unvalidated named-pipe client." << std::endl;
                DisconnectNamedPipe(pipe);
                CloseHandle(pipe);
                continue;
            }

            const std::string client_id = "client-" + std::to_string(next_client_id_++) +
                "-pid-" + std::to_string(client_process_id);
            std::lock_guard<std::mutex> lock(client_threads_mutex_);

            for (auto it = client_threads_.begin(); it != client_threads_.end();)
            {
                if (it->finished && it->finished->load())
                {
                    if (it->thread.joinable()) it->thread.join();
                    it = client_threads_.erase(it);
                }
                else
                {
                    ++it;
                }
            }

            auto finished = std::make_shared<std::atomic_bool>(false);
            client_pipes_.push_back(pipe);
            ClientThreadEntry entry;
            entry.finished = finished;
            entry.thread = std::thread(
                &BrokerServerV21::ClientSessionLoop,
                this,
                pipe,
                client_id,
                finished);
            client_threads_.push_back(std::move(entry));
        }
        else
        {
            CloseHandle(pipe);
        }
    }
}

void BrokerServerV21::ClientSessionLoop(
    HANDLE pipe,
    std::string client_id,
    std::shared_ptr<std::atomic_bool> finished)
{
    // Publishers enqueue bounded frames only. This session thread remains the
    // sole synchronous I/O owner for the pipe, preventing response/event write
    // races and eliminating callbacks that capture stack-owned mutexes.
    auto send_state = std::make_shared<ClientSendState>();
    send_state->pipe = pipe;

    EventBusV21::Instance().RegisterClient(
        client_id,
        [send_state](const BrokerEvent& event) {
            std::string serialized = SerializeEvent(event);
            bool overflow = false;
            {
                std::lock_guard<std::mutex> lock(send_state->mutex);
                if (!send_state->active) return;

                const bool frame_limit =
                    send_state->event_queue.size() >= kMaxQueuedEventFrames;
                const bool oversized = serialized.size() > kMaxPayloadBytes;
                const bool byte_limit =
                    serialized.size() > kMaxQueuedEventBytes ||
                    send_state->queued_event_bytes >
                        kMaxQueuedEventBytes - std::min(serialized.size(), kMaxQueuedEventBytes);

                if (frame_limit || oversized || byte_limit)
                {
                    send_state->active = false;
                    send_state->event_queue.clear();
                    send_state->queued_event_bytes = 0;
                    overflow = true;
                }
                else
                {
                    send_state->queued_event_bytes += serialized.size();
                    send_state->event_queue.push_back(std::move(serialized));
                }
            }

            send_state->event_ready.notify_all();
            if (overflow)
            {
                // Disconnect a stalled subscriber rather than blocking a
                // publisher or growing memory without bound.
                CancelIoEx(send_state->pipe, nullptr);
            }
        });

    while (running_.load())
    {
        if (!IsClientSendStateActive(send_state)) break;

        std::string outbound_event;
        if (TryPopQueuedEvent(send_state, outbound_event))
        {
            if (!SendFrame(pipe, outbound_event))
            {
                DeactivateClientSendState(send_state);
                break;
            }
            continue;
        }

        const InboundFrameProbe probe = ProbeInboundFrame(pipe);
        if (probe == InboundFrameProbe::Disconnected) break;
        if (probe == InboundFrameProbe::None)
        {
            std::unique_lock<std::mutex> lock(send_state->mutex);
            if (send_state->active && send_state->event_queue.empty())
            {
                send_state->event_ready.wait_for(lock, kClientIdleWait);
            }
            continue;
        }

        std::string frame;
        if (!ReadFrame(pipe, frame)) break;

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

        // Response first, then queued events. A request may publish an event
        // while HandleRequest runs; that event remains queued until this reply
        // has been written, preserving deterministic request/response ordering.
        if (!SendFrame(pipe, SerializeResponse(res)))
        {
            DeactivateClientSendState(send_state);
            break;
        }
    }

    EventBusV21::Instance().UnregisterClient(client_id);
    DeactivateClientSendState(send_state);
    CancelIoEx(pipe, nullptr);
    DisconnectNamedPipe(pipe);

    {
        std::lock_guard<std::mutex> lock(client_threads_mutex_);
        const auto it = std::find(client_pipes_.begin(), client_pipes_.end(), pipe);
        if (it != client_pipes_.end()) client_pipes_.erase(it);
    }

    CloseHandle(pipe);
    finished->store(true);
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
        res.payload["serverInstanceId"] = JsonValue(
            "broker-session-" + std::to_string(SecurityV21::GetCurrentSessionId()));
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
        res.payload["activeClients"] = JsonValue(
            static_cast<int64_t>(EventBusV21::Instance().GetActiveClientCount()));
        res.payload["activeJobs"] = JsonValue(
            static_cast<int64_t>(JobManagerV21::Instance().GetActiveJobCount()));
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
        res.payload["generation"] = JsonValue(
            static_cast<int64_t>(AppServiceV21::Instance().GetGeneration()));
        return res;
    }

    if (method == "apps.launch")
    {
        auto it = req.payload.find("id");
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

    if (method == "files.list")
    {
        auto it = req.payload.find("location");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid allowlisted 'location' id";
            return res;
        }

        const std::string location = it->second.AsString();
        if (!FileServiceV21::IsAllowedLocation(location))
        {
            res.ok = false;
            res.error_code = "location_not_allowed";
            res.error_message = "The requested Files location is not allowlisted";
            return res;
        }

        std::vector<FileItemV21> items;
        std::string error;
        if (!FileServiceV21::Instance().ListLocation(location, items, error))
        {
            res.ok = false;
            res.error_code = "files_unavailable";
            res.error_message = error.empty() ?
                "The requested Files location is unavailable" :
                error;
            return res;
        }
        res.payload["location"] = JsonValue(location);
        WriteFilesPayload(res, items);
        return res;
    }

    if (method == "files.listEntry")
    {
        auto it = req.payload.find("entryId");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid Files entry capability";
            return res;
        }

        std::vector<FileItemV21> items;
        std::string error;
        if (!FileServiceV21::Instance().ListEntry(it->second.AsString(), items, error))
        {
            res.ok = false;
            res.error_code = "entry_unavailable";
            res.error_message = error;
            return res;
        }
        res.payload["entryId"] = JsonValue(it->second.AsString());
        WriteFilesPayload(res, items);
        return res;
    }

    if (method == "files.openEntry")
    {
        auto it = req.payload.find("entryId");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid Files entry capability";
            return res;
        }

        std::string error;
        if (!FileServiceV21::Instance().OpenEntry(it->second.AsString(), error))
        {
            res.ok = false;
            res.error_code = "entry_open_failed";
            res.error_message = error;
            return res;
        }
        res.payload["opened"] = JsonValue(true);
        return res;
    }

    if (method == "system.snapshot")
    {
        res.payload = SystemServiceV21::Instance().GetSnapshot().ToJsonObject();
        return res;
    }

    if (method == "system.volume.set")
    {
        auto it = req.payload.find("value");
        if (it == req.payload.end() || !it->second.IsDouble())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid double 'value'";
            return res;
        }

        const double value = it->second.AsDouble();
        if (!std::isfinite(value) || value < 0.0 || value > 1.0)
        {
            res.ok = false;
            res.error_code = "out_of_range";
            res.error_message = "Volume must be a finite value in [0, 1]";
            return res;
        }
        if (!SystemServiceV21::Instance().SetVolume(value))
        {
            res.ok = false;
            res.error_code = "system_control_unavailable";
            res.error_message =
                "The active Windows audio endpoint rejected or does not support volume control";
            res.payload["updated"] = JsonValue(false);
            return res;
        }
        res.payload["updated"] = JsonValue(true);
        return res;
    }

    if (method == "system.brightness.set")
    {
        auto it = req.payload.find("value");
        if (it == req.payload.end() || !it->second.IsDouble())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid double 'value'";
            return res;
        }

        const double value = it->second.AsDouble();
        if (!std::isfinite(value) || value < 0.0 || value > 1.0)
        {
            res.ok = false;
            res.error_code = "out_of_range";
            res.error_message = "Brightness must be a finite value in [0, 1]";
            return res;
        }
        if (!SystemServiceV21::Instance().SetBrightness(value))
        {
            res.ok = false;
            res.error_code = "system_control_unavailable";
            res.error_message = "No monitor accepted brightness control through DDC/CI or WMI";
            res.payload["updated"] = JsonValue(false);
            return res;
        }
        res.payload["updated"] = JsonValue(true);
        return res;
    }

    if (method == "wsl.list")
    {
        res.payload["wslAvailable"] = JsonValue(WslServiceV21::Instance().IsWslAvailable());
        JsonArray distros;
        for (const auto& distro : WslServiceV21::Instance().GetDistributions())
        {
            distros.push_back(JsonValue(distro));
        }
        res.payload["distros"] = JsonValue(std::move(distros));
        res.payload["generation"] = JsonValue(
            static_cast<int64_t>(WslServiceV21::Instance().GetGeneration()));
        return res;
    }

    if (method == "events.subscribe")
    {
        auto it = req.payload.find("pattern");
        const std::string pattern =
            (it != req.payload.end() && it->second.IsString()) ?
                it->second.AsString() :
                "*";
        const bool ok = EventBusV21::Instance().Subscribe(client_id, pattern);
        res.payload["subscribed"] = JsonValue(ok);
        res.payload["pattern"] = JsonValue(pattern);
        return res;
    }

    if (method == "events.unsubscribe")
    {
        auto it = req.payload.find("pattern");
        const std::string pattern =
            (it != req.payload.end() && it->second.IsString()) ?
                it->second.AsString() :
                "*";
        const bool ok = EventBusV21::Instance().Unsubscribe(client_id, pattern);
        res.payload["unsubscribed"] = JsonValue(ok);
        res.payload["pattern"] = JsonValue(pattern);
        return res;
    }

    if (method == "jobs.status")
    {
        auto it = req.payload.find("jobId");
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
        auto it = req.payload.find("jobId");
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
    res.error_message =
        "Method '" + method + "' is not supported by protocol " +
        std::to_string(kProtocolVersion);
    return res;
}

} // namespace CloudOS
