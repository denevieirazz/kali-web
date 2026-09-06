#include "broker_server_v21.h"
#include "app_service_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "file_service_v21.h"
#include "job_manager_v21.h"
#include "performance_manager_v21.h"
#include "path_translation_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "window_service_v23.h"
#include "wsl_service_v21.h"
#include "display_service_v25.h"
#include "audio_service_v25.h"
#include "system_settings_service_v25.h"
#include "clipboard_service_v26.h"
#include "open_with_service_v26.h"
#include "notification_service_v26.h"

#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <shlobj.h>
#include <shellapi.h>
#pragma comment(lib, "shell32.lib")
#include <thread>
#include <tlhelp32.h>

namespace CloudOS
{
namespace
{
void TerminateProcessesByName(const wchar_t* targetExe)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry))
    {
        const DWORD currentPid = GetCurrentProcessId();
        do
        {
            if (entry.th32ProcessID != currentPid && _wcsicmp(entry.szExeFile, targetExe) == 0)
            {
                HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
                if (hProc)
                {
                    TerminateProcess(hProc, 0);
                    CloseHandle(hProc);
                }
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
}

DWORD FindProcessIdByName(const wchar_t* targetExe)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    DWORD pid = 0;
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            if (_wcsicmp(entry.szExeFile, targetExe) == 0)
            {
                pid = entry.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return pid;
}

std::wstring ReadRegistryStr(HKEY root, const wchar_t* subKey, const wchar_t* valueName)
{
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS)
    {
        return L"";
    }

    wchar_t buffer[1024] = {0};
    DWORD bufferSize = sizeof(buffer);
    DWORD type = 0;
    LONG result = RegQueryValueExW(hKey, valueName, nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &bufferSize);
    RegCloseKey(hKey);

    if (result == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ))
    {
        return buffer;
    }
    return L"";
}

constexpr size_t kMaxQueuedEventFrames = 128;
constexpr size_t kMaxQueuedEventBytes = 2 * kMaxPayloadBytes;
constexpr auto kClientIdleWait = std::chrono::milliseconds(5);

std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty()) return {};
    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (required <= 0) return {};
    std::wstring output(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required) <= 0)
    {
        return {};
    }
    return output;
}

std::string WideToUtf8(std::wstring_view value)
{
    if (value.empty()) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string output(static_cast<size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            0,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required,
            nullptr,
            nullptr) <= 0)
    {
        return {};
    }
    return output;
}

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
    const std::vector<FileItemV21>& items,
    size_t offset = 0,
    size_t limit = 1500)
{
    const size_t total_count = items.size();
    if (limit == 0 || limit > 2000)
    {
        limit = 1500;
    }
    const size_t start_idx = std::min(offset, total_count);
    const size_t end_idx = std::min(start_idx + limit, total_count);

    JsonArray files;
    files.reserve(end_idx - start_idx);
    for (size_t i = start_idx; i < end_idx; ++i)
    {
        files.push_back(JsonValue(items[i].ToJsonObject()));
    }
    response.payload["files"] = JsonValue(std::move(files));
    response.payload["totalCount"] = JsonValue(static_cast<double>(total_count));
    response.payload["offset"] = JsonValue(static_cast<double>(start_idx));
    response.payload["limit"] = JsonValue(static_cast<double>(limit));
    response.payload["hasMore"] = JsonValue(end_idx < total_count);
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
        LaunchStatus status;
        std::string err;
        if (!AppServiceV21::Instance().LaunchAppStructured(app_id, status, err))
        {
            res.ok = false;
            res.error_code = "launch_failed";
            res.error_message = err;
            res.payload = status.ToJsonObject();
            return res;
        }
        res.payload = status.ToJsonObject();
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
        size_t offset = 0;
        size_t limit = 1500;
        auto it_offset = req.payload.find("offset");
        if (it_offset != req.payload.end() && (it_offset->second.IsInt() || it_offset->second.IsDouble()))
        {
            offset = static_cast<size_t>(std::max<int64_t>(0, it_offset->second.AsInt()));
        }
        auto it_limit = req.payload.find("limit");
        if (it_limit != req.payload.end() && (it_limit->second.IsInt() || it_limit->second.IsDouble()))
        {
            limit = static_cast<size_t>(std::max<int64_t>(1, it_limit->second.AsInt()));
        }

        auto it_query = req.payload.find("query");
        if (it_query != req.payload.end() && it_query->second.IsString() && !it_query->second.AsString().empty())
        {
            std::string q = it_query->second.AsString();
            std::transform(q.begin(), q.end(), q.begin(), [](unsigned char c) { return static_cast<char>(::tolower(c)); });
            std::vector<FileItemV21> filtered;
            for (const auto& itm : items)
            {
                std::string name_lower = itm.name;
                std::transform(name_lower.begin(), name_lower.end(), name_lower.begin(), [](unsigned char c) { return static_cast<char>(::tolower(c)); });
                if (name_lower.find(q) != std::string::npos)
                {
                    filtered.push_back(itm);
                }
            }
            items = std::move(filtered);
        }

        res.payload["location"] = JsonValue(location);
        WriteFilesPayload(res, items, offset, limit);
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

        size_t offset = 0;
        size_t limit = 1500;
        auto it_offset = req.payload.find("offset");
        if (it_offset != req.payload.end() && (it_offset->second.IsInt() || it_offset->second.IsDouble()))
        {
            offset = static_cast<size_t>(std::max<int64_t>(0, it_offset->second.AsInt()));
        }
        auto it_limit = req.payload.find("limit");
        if (it_limit != req.payload.end() && (it_limit->second.IsInt() || it_limit->second.IsDouble()))
        {
            limit = static_cast<size_t>(std::max<int64_t>(1, it_limit->second.AsInt()));
        }

        auto it_query = req.payload.find("query");
        if (it_query != req.payload.end() && it_query->second.IsString() && !it_query->second.AsString().empty())
        {
            std::string q = it_query->second.AsString();
            std::transform(q.begin(), q.end(), q.begin(), [](unsigned char c) { return static_cast<char>(::tolower(c)); });
            std::vector<FileItemV21> filtered;
            for (const auto& itm : items)
            {
                std::string name_lower = itm.name;
                std::transform(name_lower.begin(), name_lower.end(), name_lower.begin(), [](unsigned char c) { return static_cast<char>(::tolower(c)); });
                if (name_lower.find(q) != std::string::npos)
                {
                    filtered.push_back(itm);
                }
            }
            items = std::move(filtered);
        }

        res.payload["entryId"] = JsonValue(it->second.AsString());
        WriteFilesPayload(res, items, offset, limit);
        return res;
    }

    if (method == "files.resolvePath")
    {
        auto it = req.payload.find("path");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'path'";
            return res;
        }

        std::wstring wpath = Utf8ToWide(it->second.AsString());
        DWORD attrs = GetFileAttributesW(wpath.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES)
        {
            res.ok = false;
            res.error_code = "not_found";
            res.error_message = "Path not found on filesystem";
            return res;
        }

        bool is_dir = (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
        std::string entry_id = FileServiceV21::Instance().IssueCapability(wpath, is_dir);
        res.payload["entryId"] = JsonValue(entry_id);
        res.payload["path"] = JsonValue(it->second.AsString());
        res.payload["isFolder"] = JsonValue(is_dir);
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

    if (method == "files.createFolder")
    {
        auto it_parent = req.payload.find("parentEntryId");
        auto it_name = req.payload.find("name");
        if (it_parent == req.payload.end() || !it_parent->second.IsString() ||
            it_name == req.payload.end() || !it_name->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'parentEntryId' or 'name'";
            return res;
        }

        FileItemV21 created_item;
        std::string error;
        if (!FileServiceV21::Instance().CreateFolder(
                it_parent->second.AsString(),
                it_name->second.AsString(),
                created_item,
                error))
        {
            res.ok = false;
            res.error_code = "create_folder_failed";
            res.error_message = error;
            return res;
        }
        res.payload = created_item.ToJsonObject();
        return res;
    }

    if (method == "files.rename")
    {
        auto it_entry = req.payload.find("entryId");
        auto it_name = req.payload.find("newName");
        if (it_entry == req.payload.end() || !it_entry->second.IsString() ||
            it_name == req.payload.end() || !it_name->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'entryId' or 'newName'";
            return res;
        }

        FileItemV21 renamed_item;
        std::string error;
        if (!FileServiceV21::Instance().RenameItem(
                it_entry->second.AsString(),
                it_name->second.AsString(),
                renamed_item,
                error))
        {
            res.ok = false;
            res.error_code = "rename_failed";
            res.error_message = error;
            return res;
        }
        res.payload = renamed_item.ToJsonObject();
        return res;
    }

    if (method == "files.delete")
    {
        auto it_entries = req.payload.find("entryIds");
        if (it_entries == req.payload.end() || !it_entries->second.IsArray())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid array 'entryIds'";
            return res;
        }

        std::vector<std::string> entry_ids;
        for (const auto& item : it_entries->second.AsArray())
        {
            if (item.IsString()) entry_ids.push_back(item.AsString());
        }

        bool permanent = false;
        auto it_perm = req.payload.find("permanent");
        if (it_perm != req.payload.end() && it_perm->second.IsBool())
        {
            permanent = it_perm->second.AsBool();
        }

        std::vector<std::string> deleted_ids;
        std::string error;
        if (!FileServiceV21::Instance().DeleteItems(entry_ids, permanent, deleted_ids, error))
        {
            res.ok = false;
            res.error_code = "delete_failed";
            res.error_message = error;
            return res;
        }

        std::vector<JsonValue> deleted_json;
        deleted_json.reserve(deleted_ids.size());
        for (const auto& id : deleted_ids) deleted_json.push_back(JsonValue(id));
        res.payload["deletedEntryIds"] = JsonValue(std::move(deleted_json));
        return res;
    }

    if (method == "files.queryRecycleBin")
    {
        SHQUERYRBINFO info{};
        info.cbSize = sizeof(info);
        const HRESULT hr = SHQueryRecycleBinW(nullptr, &info);
        if (SUCCEEDED(hr))
        {
            res.payload["itemCount"] = JsonValue(static_cast<double>(info.i64NumItems));
            res.payload["totalSizeBytes"] = JsonValue(static_cast<double>(info.i64Size));
        }
        else
        {
            res.payload["itemCount"] = JsonValue(0.0);
            res.payload["totalSizeBytes"] = JsonValue(0.0);
        }
        return res;
    }

    if (method == "files.emptyRecycleBin")
    {
        const HRESULT hr = SHEmptyRecycleBinW(nullptr, nullptr, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
        res.ok = SUCCEEDED(hr);
        if (!res.ok)
        {
            res.error_code = "empty_failed";
            res.error_message = "Falha ao esvaziar lixeira";
        }
        return res;
    }

    if (method == "files.copy" || method == "files.move")
    {
        auto it_sources = req.payload.find("sourceEntryIds");
        auto it_dest = req.payload.find("destinationEntryId");
        if (it_sources == req.payload.end() || !it_sources->second.IsArray() ||
            it_dest == req.payload.end() || !it_dest->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'sourceEntryIds' or 'destinationEntryId'";
            return res;
        }

        std::vector<std::string> source_ids;
        for (const auto& item : it_sources->second.AsArray())
        {
            if (item.IsString()) source_ids.push_back(item.AsString());
        }

        std::string conflict_strategy = "replace";
        auto it_conflict = req.payload.find("conflictStrategy");
        if (it_conflict == req.payload.end()) it_conflict = req.payload.find("conflictResolution");
        if (it_conflict != req.payload.end() && it_conflict->second.IsString())
        {
            conflict_strategy = it_conflict->second.AsString();
        }

        std::string job_id;
        std::string error;
        const std::string op_type = (method == "files.move") ? "move" : "copy";
        if (!FileServiceV21::Instance().CopyOrMoveItemsAsync(
                op_type,
                source_ids,
                it_dest->second.AsString(),
                conflict_strategy,
                job_id,
                error))
        {
            res.ok = false;
            res.error_code = "file_operation_failed";
            res.error_message = error;
            return res;
        }
        res.payload["jobId"] = JsonValue(job_id);
        res.payload["operationId"] = JsonValue(job_id);
        return res;
    }

    if (method == "files.listDrives")
    {
        std::vector<DriveItemV21> drives;
        std::string error;
        if (!FileServiceV21::Instance().ListDrives(drives, error))
        {
            res.ok = false;
            res.error_code = "list_drives_failed";
            res.error_message = error;
            return res;
        }

        std::vector<JsonValue> drive_json;
        drive_json.reserve(drives.size());
        for (const auto& d : drives) drive_json.push_back(JsonValue(d.ToJsonObject()));
        res.payload["drives"] = JsonValue(std::move(drive_json));
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
        res.payload["defaultDistro"] = JsonValue(WslServiceV21::Instance().GetDefaultDistribution());
        JsonArray distros;
        for (const auto& distro : WslServiceV21::Instance().GetDistributions())
        {
            distros.push_back(JsonValue(distro));
        }
        res.payload["distros"] = JsonValue(std::move(distros));

        JsonArray distro_details;
        for (const auto& detail : WslServiceV21::Instance().GetDistroDetails())
        {
            distro_details.push_back(JsonValue(detail.ToJsonObject()));
        }
        res.payload["distroDetails"] = JsonValue(std::move(distro_details));

        res.payload["generation"] = JsonValue(
            static_cast<int64_t>(WslServiceV21::Instance().GetGeneration()));
        return res;
    }

    if (method == "path.translate")
    {
        auto it_path = req.payload.find("path");
        if (it_path == req.payload.end() || !it_path->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'path' parameter in payload";
            return res;
        }
        const std::string path = it_path->second.AsString();

        std::string target = "linux";
        auto it_target = req.payload.find("target");
        if (it_target != req.payload.end() && it_target->second.IsString())
        {
            target = it_target->second.AsString();
        }

        std::string distro;
        auto it_distro = req.payload.find("distro");
        if (it_distro != req.payload.end() && it_distro->second.IsString())
        {
            distro = it_distro->second.AsString();
        }

        std::string translated;
        if (target == "linux")
        {
            translated = PathTranslationV21::WindowsToLinux(path, distro);
        }
        else
        {
            translated = PathTranslationV21::LinuxToWindows(path, distro);
        }

        const bool exists = PathTranslationV21::PathExists(
            target == "windows" ? translated : path, distro);

        res.payload["originalPath"] = JsonValue(path);
        res.payload["translatedPath"] = JsonValue(translated);
        res.payload["target"] = JsonValue(target);
        res.payload["distro"] = JsonValue(distro);
        res.payload["exists"] = JsonValue(exists);
        return res;
    }

    if (method == "system.mounts.list")
    {
        const auto mounts = PathTranslationV21::GetMountPoints();
        JsonArray arr;
        for (const auto& mount : mounts)
        {
            arr.push_back(JsonValue(mount.ToJsonObject()));
        }
        res.payload["mounts"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "system.performance.get")
    {
        res.payload = PerformanceManagerV21::Instance().GetMetrics().ToJsonObject();
        return res;
    }

    if (method == "system.performance.set")
    {
        auto it = req.payload.find("profile");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'profile' string in payload";
            return res;
        }
        const std::string profile_str = it->second.AsString();
        if (!PerformanceManagerV21::Instance().SetProfileByName(profile_str))
        {
            res.ok = false;
            res.error_code = "invalid_profile";
            res.error_message = "Valid profiles are 'economy', 'balanced', or 'performance'";
            return res;
        }
        res.payload["updated"] = JsonValue(true);
        res.payload["profile"] = JsonValue(profile_str);
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

    if (method == "window.snapshot" || method == "window.list")
    {
        std::string snapshot_json;
        std::string error;
        if (!WindowServiceV23::Instance().GetSnapshot(snapshot_json, &error))
        {
            res.ok = false;
            res.error_code = "snapshot_failed";
            res.error_message = error;
            return res;
        }
        res.payload["snapshot"] = JsonValue(snapshot_json);
        return res;
    }

    if (method == "window.focus" ||
        method == "window.minimize" ||
        method == "window.maximize" ||
        method == "window.restore" ||
        method == "window.close" ||
        method == "window.setBounds" ||
        method == "window.snap" ||
        method == "window.moveToWorkspace" ||
        method == "window.setFullscreen")
    {
        auto it_hwnd = req.payload.find("hwnd");
        if (it_hwnd == req.payload.end())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'hwnd' in payload";
            return res;
        }
        uint64_t hwnd = 0;
        if (it_hwnd->second.IsInt()) hwnd = static_cast<uint64_t>(it_hwnd->second.AsInt());
        else if (it_hwnd->second.IsDouble()) hwnd = static_cast<uint64_t>(it_hwnd->second.AsDouble());
        else if (it_hwnd->second.IsString())
        {
            std::string s = it_hwnd->second.AsString();
            if (s.rfind("win_", 0) == 0) s = s.substr(4);
            try { hwnd = std::stoull(s); } catch (...) {}
        }

        if (hwnd == 0)
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Invalid or zero 'hwnd'";
            return res;
        }

        std::string error;
        bool ok = false;
        if (method == "window.focus") ok = WindowServiceV23::Instance().FocusWindow(hwnd, &error);
        else if (method == "window.minimize") ok = WindowServiceV23::Instance().MinimizeWindow(hwnd, &error);
        else if (method == "window.maximize") ok = WindowServiceV23::Instance().MaximizeWindow(hwnd, &error);
        else if (method == "window.restore") ok = WindowServiceV23::Instance().RestoreWindow(hwnd, &error);
        else if (method == "window.close") ok = WindowServiceV23::Instance().CloseWindow(hwnd, &error);
        else if (method == "window.setBounds")
        {
            int x = req.payload.count("x") && req.payload.at("x").IsInt() ? static_cast<int>(req.payload.at("x").AsInt()) : 0;
            int y = req.payload.count("y") && req.payload.at("y").IsInt() ? static_cast<int>(req.payload.at("y").AsInt()) : 0;
            int width = req.payload.count("width") && req.payload.at("width").IsInt() ? static_cast<int>(req.payload.at("width").AsInt()) : 800;
            int height = req.payload.count("height") && req.payload.at("height").IsInt() ? static_cast<int>(req.payload.at("height").AsInt()) : 600;
            ok = WindowServiceV23::Instance().SetBounds(hwnd, x, y, width, height, &error);
        }
        else if (method == "window.snap")
        {
            using CloudOS::WindowRegistryV23::SnapTarget;
            SnapTarget target = SnapTarget::None;
            std::string snap_str = req.payload.count("target") && req.payload.at("target").IsString() ?
                req.payload.at("target").AsString() :
                (req.payload.count("snap") && req.payload.at("snap").IsString() ? req.payload.at("snap").AsString() : "");
            if (snap_str == "left") target = SnapTarget::Left;
            else if (snap_str == "right") target = SnapTarget::Right;
            else if (snap_str == "top") target = SnapTarget::Top;
            else if (snap_str == "maximize") target = SnapTarget::Maximize;
            else if (snap_str == "restore") target = SnapTarget::Restore;
            else if (snap_str == "topLeft") target = SnapTarget::TopLeft;
            else if (snap_str == "topRight") target = SnapTarget::TopRight;
            else if (snap_str == "bottomLeft") target = SnapTarget::BottomLeft;
            else if (snap_str == "bottomRight") target = SnapTarget::BottomRight;
            ok = WindowServiceV23::Instance().SnapWindow(hwnd, target, &error);
        }
        else if (method == "window.moveToWorkspace")
        {
            int ws = req.payload.count("workspace") && req.payload.at("workspace").IsInt() ?
                static_cast<int>(req.payload.at("workspace").AsInt()) : 1;
            ok = WindowServiceV23::Instance().MoveToWorkspace(hwnd, ws, &error);
        }
        else if (method == "window.setFullscreen")
        {
            bool fullscreen = req.payload.count("fullscreen") && req.payload.at("fullscreen").IsBool() ?
                req.payload.at("fullscreen").AsBool() : true;
            ok = WindowServiceV23::Instance().SetFullscreen(hwnd, fullscreen, &error);
        }

        if (!ok)
        {
            res.ok = false;
            res.error_code = "window_action_failed";
            res.error_message = error.empty() ? "Window command failed or window not found" : error;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "monitor.list")
    {
        std::string snapshot_json;
        std::string error;
        if (!WindowServiceV23::Instance().GetSnapshot(snapshot_json, &error))
        {
            res.ok = false;
            res.error_code = "monitor_list_failed";
            res.error_message = error;
            return res;
        }
        res.payload["snapshot"] = JsonValue(snapshot_json);
        return res;
    }

    // --- DISPLAY & MONITOR (ETAPA 5) ---
    if (method == "display.listMonitors")
    {
        const auto monitors = DisplayServiceV25::Instance().ListMonitors();
        JsonArray arr;
        arr.reserve(monitors.size());
        for (const auto& m : monitors)
        {
            arr.push_back(JsonValue(m.ToJsonObject()));
        }
        res.payload["monitors"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "display.listSupportedModes")
    {
        std::wstring dev = L"\\\\.\\DISPLAY1";
        if (req.payload.count("deviceName") && req.payload.at("deviceName").IsString())
        {
            dev = Utf8ToWide(req.payload.at("deviceName").AsString());
        }
        const auto modes = DisplayServiceV25::Instance().ListSupportedModes(dev);
        JsonArray arr;
        arr.reserve(modes.size());
        for (const auto& m : modes)
        {
            arr.push_back(JsonValue(m.ToJsonObject()));
        }
        res.payload["modes"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "display.setMode")
    {
        std::wstring dev = L"\\\\.\\DISPLAY1";
        if (req.payload.count("deviceName") && req.payload.at("deviceName").IsString())
        {
            dev = Utf8ToWide(req.payload.at("deviceName").AsString());
        }
        int width = req.payload.count("width") && req.payload.at("width").IsInt() ? static_cast<int>(req.payload.at("width").AsInt()) : 0;
        int height = req.payload.count("height") && req.payload.at("height").IsInt() ? static_cast<int>(req.payload.at("height").AsInt()) : 0;
        int freq = req.payload.count("frequency") && req.payload.at("frequency").IsInt() ? static_cast<int>(req.payload.at("frequency").AsInt()) : 0;
        int orient = req.payload.count("orientation") && req.payload.at("orientation").IsInt() ? static_cast<int>(req.payload.at("orientation").AsInt()) : 0;

        std::string err;
        if (!DisplayServiceV25::Instance().SetDisplayMode(dev, width, height, freq, orient, &err))
        {
            res.ok = false;
            res.error_code = "display_mode_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "display.restore")
    {
        std::string err;
        if (!DisplayServiceV25::Instance().RestoreBaseline(&err))
        {
            res.ok = false;
            res.error_code = "display_restore_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- AUDIO (ETAPA 5) ---
    if (method == "audio.getState")
    {
        const auto state = AudioServiceV25::Instance().GetAudioState();
        res.payload["audio"] = JsonValue(state.ToJsonObject());
        return res;
    }

    if (method == "audio.setVolume")
    {
        double vol = 0.5;
        if (req.payload.count("volume") && req.payload.at("volume").IsDouble())
        {
            vol = req.payload.at("volume").AsDouble();
        }
        if (!AudioServiceV25::Instance().SetVolume(vol))
        {
            res.ok = false;
            res.error_code = "audio_set_volume_failed";
            res.error_message = "Failed to set master volume via Core Audio";
            return res;
        }
        res.payload["success"] = JsonValue(true);
        res.payload["volume"] = JsonValue(vol);
        return res;
    }

    if (method == "audio.setMute")
    {
        bool mute = false;
        if (req.payload.count("muted") && req.payload.at("muted").IsBool())
        {
            mute = req.payload.at("muted").AsBool();
        }
        if (!AudioServiceV25::Instance().SetMute(mute))
        {
            res.ok = false;
            res.error_code = "audio_set_mute_failed";
            res.error_message = "Failed to toggle mute via Core Audio";
            return res;
        }
        res.payload["success"] = JsonValue(true);
        res.payload["muted"] = JsonValue(mute);
        return res;
    }

    // --- POWER & BATTERY (ETAPA 5) ---
    if (method == "power.getStatus")
    {
        const auto pwr = SystemSettingsServiceV25::Instance().GetPowerStatus();
        res.payload["power"] = JsonValue(pwr.ToJsonObject());
        return res;
    }

    // --- NETWORK & WI-FI (ETAPA 5) ---
    if (method == "network.getInterfaces")
    {
        const auto ifaces = SystemSettingsServiceV25::Instance().GetNetworkInterfaces();
        JsonArray arr;
        arr.reserve(ifaces.size());
        for (const auto& iface : ifaces)
        {
            arr.push_back(JsonValue(iface.ToJsonObject()));
        }
        res.payload["interfaces"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "network.getWifi")
    {
        const auto nets = SystemSettingsServiceV25::Instance().GetWifiNetworks();
        JsonArray arr;
        arr.reserve(nets.size());
        for (const auto& net : nets)
        {
            arr.push_back(JsonValue(net.ToJsonObject()));
        }
        res.payload["networks"] = JsonValue(std::move(arr));
        return res;
    }

    // --- BLUETOOTH (ETAPA 5) ---
    if (method == "bluetooth.getStatus")
    {
        const auto bt = SystemSettingsServiceV25::Instance().GetBluetoothStatus();
        res.payload["bluetooth"] = JsonValue(bt.ToJsonObject());
        return res;
    }

    // --- STORAGE (ETAPA 5) ---
    if (method == "storage.getDrives")
    {
        const auto drives = SystemSettingsServiceV25::Instance().GetStorageDrives();
        JsonArray arr;
        arr.reserve(drives.size());
        for (const auto& d : drives)
        {
            arr.push_back(JsonValue(d.ToJsonObject()));
        }
        res.payload["drives"] = JsonValue(std::move(arr));
        return res;
    }

    // --- PERSONALIZATION (ETAPA 5) ---
    if (method == "personalization.get")
    {
        const auto pers = SystemSettingsServiceV25::Instance().GetPersonalization();
        res.payload["personalization"] = JsonValue(pers.ToJsonObject());
        return res;
    }

    if (method == "personalization.set")
    {
        auto it = req.payload.find("personalization");
        if (it == req.payload.end() || !it->second.IsObject())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'personalization' object";
            return res;
        }
        PersonalizationSettingsV25 s = PersonalizationSettingsV25::FromJsonObject(it->second.AsObject());
        std::string err;
        if (!SystemSettingsServiceV25::Instance().SetPersonalization(s, &err))
        {
            res.ok = false;
            res.error_code = "personalization_save_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        res.payload["personalization"] = JsonValue(s.ToJsonObject());
        return res;
    }

    // --- DATE / TIME / LOCALE (ETAPA 5) ---
    if (method == "datetime.get")
    {
        const auto dt = SystemSettingsServiceV25::Instance().GetDateTimeLocale();
        res.payload["datetime"] = JsonValue(dt.ToJsonObject());
        return res;
    }

    if (method == "datetime.setTime")
    {
        // Safe boundary: changing system time requires admin elevation which CloudOS never forces.
        res.ok = false;
        res.error_code = "elevation_required";
        res.error_message = "Changing system clock requires Windows administrative privileges. System time can be configured via Windows Date & Time settings.";
        return res;
    }

    // --- PERFORMANCE PROFILES (ETAPA 5 & 8) ---
    if (method == "performance.getProfile")
    {
        const auto metrics = PerformanceManagerV21::Instance().GetMetrics();
        res.payload["profile"] = JsonValue(PerformanceProfileToString(metrics.current_profile));
        res.payload["metrics"] = JsonValue(metrics.ToJsonObject());
        res.payload["total_ram_mb"] = JsonValue(static_cast<int64_t>(metrics.total_ram_mb));
        res.payload["free_ram_mb"] = JsonValue(static_cast<int64_t>(metrics.free_ram_mb));
        res.payload["cpu_cores"] = JsonValue(static_cast<int64_t>(metrics.cpu_cores));
        res.payload["memory_load_percent"] = JsonValue(static_cast<int64_t>(metrics.memory_load_percent));
        res.payload["is_low_end_hardware"] = JsonValue(metrics.is_low_end_hardware);
        res.payload["on_battery"] = JsonValue(metrics.on_battery);
        res.payload["battery_percent"] = JsonValue(static_cast<int64_t>(metrics.battery_percent));
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "performance.getMetrics")
    {
        const auto metrics = PerformanceManagerV21::Instance().GetMetrics();
        res.payload["profile"] = JsonValue(PerformanceProfileToString(metrics.current_profile));
        res.payload["metrics"] = JsonValue(metrics.ToJsonObject());
        res.payload["total_ram_mb"] = JsonValue(static_cast<int64_t>(metrics.total_ram_mb));
        res.payload["free_ram_mb"] = JsonValue(static_cast<int64_t>(metrics.free_ram_mb));
        res.payload["cpu_cores"] = JsonValue(static_cast<int64_t>(metrics.cpu_cores));
        res.payload["memory_load_percent"] = JsonValue(static_cast<int64_t>(metrics.memory_load_percent));
        res.payload["is_low_end_hardware"] = JsonValue(metrics.is_low_end_hardware);
        res.payload["on_battery"] = JsonValue(metrics.on_battery);
        res.payload["battery_percent"] = JsonValue(static_cast<int64_t>(metrics.battery_percent));
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "performance.setProfile")
    {
        auto it = req.payload.find("profile");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'profile' parameter ('economy', 'balanced', 'performance')";
            return res;
        }
        const std::string prof_str = it->second.AsString();
        if (!PerformanceManagerV21::Instance().SetProfileByName(prof_str))
        {
            res.ok = false;
            res.error_code = "invalid_profile";
            res.error_message = "Unknown performance profile: " + prof_str;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        res.payload["profile"] = JsonValue(prof_str);
        return res;
    }

    // --- WSL DISTRO SETTINGS (ETAPA 5) ---
    if (method == "wsl.getDistros")
    {
        const auto details = WslServiceV21::Instance().GetDistroDetails();
        JsonArray arr;
        arr.reserve(details.size());
        for (const auto& d : details)
        {
            arr.push_back(JsonValue(d.ToJsonObject()));
        }
        res.payload["distros"] = JsonValue(std::move(arr));
        res.payload["defaultDistro"] = JsonValue(WslServiceV21::Instance().GetDefaultDistribution());
        res.payload["wslAvailable"] = JsonValue(WslServiceV21::Instance().IsWslAvailable());
        return res;
    }

    // --- QUICK SETTINGS UNIFIED STATE (ETAPA 5) ---
    if (method == "quicksettings.getState")
    {
        const auto audio = AudioServiceV25::Instance().GetAudioState();
        const auto pwr = SystemSettingsServiceV25::Instance().GetPowerStatus();
        const auto bt = SystemSettingsServiceV25::Instance().GetBluetoothStatus();
        const auto pers = SystemSettingsServiceV25::Instance().GetPersonalization();
        const auto metrics = PerformanceManagerV21::Instance().GetMetrics();

        res.payload["audio"] = JsonValue(audio.ToJsonObject());
        res.payload["power"] = JsonValue(pwr.ToJsonObject());
        res.payload["bluetooth"] = JsonValue(bt.ToJsonObject());
        res.payload["personalization"] = JsonValue(pers.ToJsonObject());
        res.payload["performanceProfile"] = JsonValue(PerformanceProfileToString(metrics.current_profile));
        return res;
    }

    // --- CLIPBOARD SERVICE (ETAPA 6) ---
    if (method == "clipboard.getHistory")
    {
        size_t limit = 20;
        if (req.payload.count("limit") && req.payload.at("limit").IsInt())
        {
            limit = static_cast<size_t>(std::max<int64_t>(1, req.payload.at("limit").AsInt()));
        }
        const auto items = ClipboardServiceV26::Instance().GetHistory(limit);
        JsonArray arr;
        arr.reserve(items.size());
        for (const auto& itm : items)
        {
            arr.push_back(JsonValue(itm.ToJsonObject(false)));
        }
        res.payload["items"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "clipboard.getText")
    {
        res.payload["text"] = JsonValue(ClipboardServiceV26::Instance().GetCurrentText());
        return res;
    }

    if (method == "clipboard.setText")
    {
        std::string text;
        if (req.payload.count("text") && req.payload.at("text").IsString())
        {
            text = req.payload.at("text").AsString();
        }
        std::string err;
        if (!ClipboardServiceV26::Instance().SetText(text, &err))
        {
            res.ok = false;
            res.error_code = "clipboard_set_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "clipboard.clear")
    {
        std::string err;
        if (!ClipboardServiceV26::Instance().Clear(&err))
        {
            res.ok = false;
            res.error_code = "clipboard_clear_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- OPEN WITH SERVICE (ETAPA 6) ---
    if (method == "files.openWith")
    {
        std::string path;
        if (req.payload.count("path") && req.payload.at("path").IsString())
        {
            path = req.payload.at("path").AsString();
        }
        if (path.empty())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or empty 'path'";
            return res;
        }
        std::string app_id;
        if (req.payload.count("app_id") && req.payload.at("app_id").IsString())
        {
            app_id = req.payload.at("app_id").AsString();
        }
        std::string err;
        if (!OpenWithServiceV26::Instance().OpenFile(path, app_id, &err))
        {
            res.ok = false;
            res.error_code = "open_with_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "files.getAssociations")
    {
        const auto assocs = OpenWithServiceV26::Instance().GetAssociations();
        JsonArray arr;
        arr.reserve(assocs.size());
        for (const auto& a : assocs)
        {
            arr.push_back(JsonValue(a.ToJsonObject()));
        }
        res.payload["associations"] = JsonValue(std::move(arr));
        return res;
    }

    if (method == "files.showOpenWithDialog")
    {
        std::string path;
        if (req.payload.count("path") && req.payload.at("path").IsString())
        {
            path = req.payload.at("path").AsString();
        }
        if (path.empty())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or empty 'path'";
            return res;
        }
        std::string err;
        if (!OpenWithServiceV26::Instance().ShowOpenWithDialog(path, &err))
        {
            res.ok = false;
            res.error_code = "open_with_dialog_failed";
            res.error_message = err;
            return res;
        }
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- NOTIFICATION SERVICE (ETAPA 6) ---
    if (method == "notifications.post")
    {
        std::string title = req.payload.count("title") && req.payload.at("title").IsString() ? req.payload.at("title").AsString() : "";
        std::string message = req.payload.count("message") && req.payload.at("message").IsString() ? req.payload.at("message").AsString() : "";
        std::string severity = req.payload.count("severity") && req.payload.at("severity").IsString() ? req.payload.at("severity").AsString() : "info";
        std::string app_id = req.payload.count("app_id") && req.payload.at("app_id").IsString() ? req.payload.at("app_id").AsString() : "";

        uint64_t id = NotificationServiceV26::Instance().Post(title, message, severity, app_id);
        res.payload["id"] = JsonValue(static_cast<int64_t>(id));
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "notifications.list")
    {
        const auto items = NotificationServiceV26::Instance().GetNotifications();
        JsonArray arr;
        arr.reserve(items.size());
        for (const auto& itm : items)
        {
            arr.push_back(JsonValue(itm.ToJsonObject()));
        }
        res.payload["notifications"] = JsonValue(std::move(arr));
        res.payload["unread_count"] = JsonValue(static_cast<int64_t>(NotificationServiceV26::Instance().GetUnreadCount()));
        return res;
    }

    if (method == "notifications.dismiss")
    {
        uint64_t id = req.payload.count("id") && req.payload.at("id").IsInt() ? static_cast<uint64_t>(req.payload.at("id").AsInt()) : 0;
        bool ok = NotificationServiceV26::Instance().Dismiss(id);
        res.payload["success"] = JsonValue(ok);
        return res;
    }

    if (method == "notifications.clear")
    {
        NotificationServiceV26::Instance().Clear();
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "notifications.markRead")
    {
        uint64_t id = req.payload.count("id") && req.payload.at("id").IsInt() ? static_cast<uint64_t>(req.payload.at("id").AsInt()) : 0;
        bool ok = NotificationServiceV26::Instance().MarkRead(id);
        res.payload["success"] = JsonValue(ok);
        return res;
    }

    if (method == "notifications.markAllRead")
    {
        NotificationServiceV26::Instance().MarkAllRead();
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- DESKTOP ACTIONS & SHORTCUTS (ETAPA 6) ---
    if (method == "system.lock")
    {
        LockWorkStation();
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- RECOVERY & LIFECYCLE (ETAPA 7) ---
    if (method == "recovery.getStatus")
    {
        res.payload["schema"] = JsonValue(22);
        res.payload["broker_pid"] = JsonValue(static_cast<int64_t>(GetCurrentProcessId()));
        res.payload["session_id"] = JsonValue(static_cast<int64_t>(SecurityV21::GetCurrentSessionId()));
        res.payload["is_remote_session"] = JsonValue(GetSystemMetrics(SM_REMOTESESSION) != 0);

        std::string supervisor_state = "UNKNOWN";
        std::string supervisor_reason = "";
        int64_t transition_seq = 0;
        int64_t supervisor_pid = 0;
        int64_t shell_pid = 0;
        int64_t failure_count = 0;
        bool job_assigned = false;
        bool previous_unclean = false;

        PWSTR local = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &local)) && local != nullptr)
        {
            std::filesystem::path cloudos_dir = local;
            CoTaskMemFree(local);
            cloudos_dir /= L"CloudOS";

            std::filesystem::path marker = cloudos_dir / L"session_v3.unclean";
            previous_unclean = std::filesystem::exists(marker);

            std::filesystem::path sup_file = cloudos_dir / L"Recovery" / L"supervisor-state-v22.json";
            if (std::filesystem::exists(sup_file))
            {
                std::ifstream f(sup_file);
                if (f.is_open())
                {
                    std::string content((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
                    JsonValue json_val;
                    if (ParseJson(content, json_val) && json_val.IsObject())
                    {
                        const auto& obj = json_val.AsObject();
                        if (obj.count("state") && obj.at("state").IsString()) supervisor_state = obj.at("state").AsString();
                        if (obj.count("reason") && obj.at("reason").IsString()) supervisor_reason = obj.at("reason").AsString();
                        if (obj.count("transition_sequence") && obj.at("transition_sequence").IsInt()) transition_seq = obj.at("transition_sequence").AsInt();
                        if (obj.count("supervisor_pid") && obj.at("supervisor_pid").IsInt()) supervisor_pid = obj.at("supervisor_pid").AsInt();
                        if (obj.count("shell_pid") && obj.at("shell_pid").IsInt()) shell_pid = obj.at("shell_pid").AsInt();
                        if (obj.count("failure_count") && obj.at("failure_count").IsInt()) failure_count = obj.at("failure_count").AsInt();
                        if (obj.count("job_kill_on_close_assigned") && obj.at("job_kill_on_close_assigned").IsBool()) job_assigned = obj.at("job_kill_on_close_assigned").AsBool();
                    }
                }
            }
        }

        res.payload["state"] = JsonValue(supervisor_state);
        res.payload["reason"] = JsonValue(supervisor_reason);
        res.payload["transition_sequence"] = JsonValue(transition_seq);
        res.payload["supervisor_pid"] = JsonValue(supervisor_pid);
        res.payload["shell_pid"] = JsonValue(shell_pid);
        res.payload["failure_count"] = JsonValue(failure_count);
        res.payload["job_kill_on_close_assigned"] = JsonValue(job_assigned);
        res.payload["previous_unclean"] = JsonValue(previous_unclean);
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "recovery.enterSafeMode")
    {
        JsonObject payload;
        payload["timestamp_ms"] = JsonValue(static_cast<int64_t>(GetTickCount64()));
        payload["reason"] = JsonValue("User or recovery controller initiated safe mode");
        EventBusV21::Instance().Publish("system.safeModeRequested", payload);
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "system.requestShutdown")
    {
        JsonObject payload;
        payload["timestamp_ms"] = JsonValue(static_cast<int64_t>(GetTickCount64()));
        EventBusV21::Instance().Publish("system.shuttingDown", payload);
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- HARDENING & CAPABILITIES (ETAPA 8) ---
    if (method == "system.getCapabilities")
    {
        const auto caps = SystemServiceV21::Instance().GetCapabilities();
        JsonArray arr;
        arr.reserve(caps.size());
        for (const auto& c : caps)
        {
            arr.push_back(JsonValue(c));
        }
        res.payload["capabilities"] = JsonValue(std::move(arr));

        JsonObject map;
        const auto snap = SystemServiceV21::Instance().GetSnapshot();
        const auto metrics = PerformanceManagerV21::Instance().GetMetrics();
        map["audio_control"] = JsonValue(snap.volume_available);
        map["brightness_control"] = JsonValue(snap.brightness_available);
        map["wsl_runtime"] = JsonValue(snap.wsl_available);
        map["economy_mode"] = JsonValue(metrics.current_profile == PerformanceProfile::Economy);
        map["rdp_session"] = JsonValue(GetSystemMetrics(SM_REMOTESESSION) != 0);
        map["multi_monitor"] = JsonValue(DisplayServiceV25::Instance().ListMonitors().size() > 1);
        map["battery_present"] = JsonValue(snap.battery_available);
        map["bluetooth_available"] = JsonValue(SystemSettingsServiceV25::Instance().GetBluetoothStatus().available);
        map["wifi_available"] = JsonValue(!SystemSettingsServiceV25::Instance().GetWifiNetworks().empty());

        res.payload["capability_map"] = JsonValue(std::move(map));
        res.payload["success"] = JsonValue(true);
        return res;
    }

    // --- STARTUP & LIFECYCLE (ETAPA 10) ---
    if (method == "startup.getStatus")
    {
        bool enabled = false;
        std::string command;
        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ, &hKey) == ERROR_SUCCESS)
        {
            wchar_t buffer[1024] = {0};
            DWORD bufSize = sizeof(buffer);
            DWORD type = 0;
            if (RegQueryValueExW(hKey, L"CloudOS", nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &bufSize) == ERROR_SUCCESS)
            {
                if (type == REG_SZ && buffer[0] != L'\0')
                {
                    enabled = true;
                    command = WideToUtf8(buffer);
                }
            }
            RegCloseKey(hKey);
        }

        std::string last_startup = "N/A";
        std::string last_result = "N/A";

        PWSTR local = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &local)) && local != nullptr)
        {
            std::filesystem::path status_file = std::filesystem::path(local) / L"CloudOS" / L"startup-status.json";
            CoTaskMemFree(local);
            if (std::filesystem::exists(status_file))
            {
                std::ifstream f(status_file);
                if (f.is_open())
                {
                    std::string content((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
                    JsonValue jv;
                    if (ParseJson(content, jv) && jv.IsObject())
                    {
                        const auto& obj = jv.AsObject();
                        if (obj.count("last_startup") && obj.at("last_startup").IsString())
                            last_startup = obj.at("last_startup").AsString();
                        if (obj.count("last_result") && obj.at("last_result").IsString())
                            last_result = obj.at("last_result").AsString();
                    }
                }
            }
        }

        res.payload["enabled"] = JsonValue(enabled);
        res.payload["mechanism"] = JsonValue("HKCU Run Key (CloudOS)");
        res.payload["command"] = JsonValue(command);
        res.payload["last_startup"] = JsonValue(last_startup);
        res.payload["last_result"] = JsonValue(last_result);
        res.payload["per_user"] = JsonValue(true);
        res.payload["requires_admin"] = JsonValue(false);
        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "startup.setEnabled")
    {
        bool enable = false;
        auto it_en = req.payload.find("enabled");
        if (it_en != req.payload.end())
        {
            if (it_en->second.IsBool())
            {
                enable = it_en->second.AsBool();
            }
            else if (it_en->second.IsString())
            {
                enable = (it_en->second.AsString() == "true" || it_en->second.AsString() == "1");
            }
        }

        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_SET_VALUE, &hKey) != ERROR_SUCCESS)
        {
            res.ok = false;
            res.error_code = "reg_open_failed";
            res.error_message = "Failed to open HKCU Run key for writing";
            return res;
        }

        bool success = false;
        if (enable)
        {
            wchar_t ownModule[MAX_PATH] = {0};
            GetModuleFileNameW(nullptr, ownModule, MAX_PATH);
            std::filesystem::path installDir = std::filesystem::path(ownModule).parent_path();
            std::filesystem::path exePath = installDir / L"CloudOS.exe";

            std::wstring runCmd = L"\"" + exePath.wstring() + L"\" --startup";
            const DWORD byteCount = static_cast<DWORD>((runCmd.size() + 1) * sizeof(wchar_t));
            success = (RegSetValueExW(hKey, L"CloudOS", 0, REG_SZ, reinterpret_cast<const BYTE*>(runCmd.c_str()), byteCount) == ERROR_SUCCESS);
        }
        else
        {
            const LONG err = RegDeleteValueW(hKey, L"CloudOS");
            success = (err == ERROR_SUCCESS || err == ERROR_FILE_NOT_FOUND);
        }
        RegCloseKey(hKey);

        if (!success)
        {
            res.ok = false;
            res.error_code = "reg_modify_failed";
            res.error_message = "Failed to update CloudOS startup registration";
            return res;
        }

        res.payload["success"] = JsonValue(true);
        res.payload["enabled"] = JsonValue(enable);
        return res;
    }

    if (method == "system.closeCloudOS")
    {
        JsonObject payload;
        payload["timestamp_ms"] = JsonValue(static_cast<int64_t>(GetTickCount64()));
        payload["reason"] = JsonValue("User requested graceful CloudOS exit");
        EventBusV21::Instance().Publish("system.shuttingDown", payload);

        std::thread([]() {
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            TerminateProcessesByName(L"CloudOS.Supervisor.exe");

            HWND flutterHwnd = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
            if (flutterHwnd) PostMessageW(flutterHwnd, WM_CLOSE, 0, 0);
            HWND nativeDesktop = FindWindowW(L"CloudOS.NativeShell.Desktop", nullptr);
            if (nativeDesktop) PostMessageW(nativeDesktop, WM_CLOSE, 0, 0);

            std::this_thread::sleep_for(std::chrono::milliseconds(400));
            TerminateProcessesByName(L"cloudos_flutter_shell.exe");
            TerminateProcessesByName(L"CloudOS.exe");

            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            ExitProcess(0);
        }).detach();

        res.payload["success"] = JsonValue(true);
        return res;
    }

    if (method == "shell.getStatus")
    {
        const std::wstring hkcuPolicyShell = ReadRegistryStr(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", L"Shell");
        const std::wstring hkcuWinlogonShell = ReadRegistryStr(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
        const std::wstring hklmWinlogonShell = ReadRegistryStr(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
        const std::wstring hklmUserinit = ReadRegistryStr(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Userinit");

        std::wstring effectiveShell = L"explorer.exe";
        std::string shellStatus = "EXPLORER";
        if (!hkcuPolicyShell.empty())
        {
            effectiveShell = hkcuPolicyShell;
            shellStatus = "CLOUDOS_ACTIVE";
        }
        else if (!hkcuWinlogonShell.empty())
        {
            effectiveShell = hkcuWinlogonShell;
            shellStatus = "CLOUDOS_ACTIVE";
        }

        const DWORD bootstrapPid = FindProcessIdByName(L"CloudOS.ShellBootstrap.exe");
        const DWORD supervisorPid = FindProcessIdByName(L"CloudOS.Supervisor.exe");
        const DWORD brokerPid = GetCurrentProcessId();
        const DWORD flutterPid = FindProcessIdByName(L"cloudos_flutter_shell.exe");

        wchar_t localAppData[MAX_PATH] = {0};
        bool backupExists = false;
        if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData) == S_OK)
        {
            std::filesystem::path bp = std::filesystem::path(localAppData) / L"CloudOS" / L"Recovery" / L"shell-backup.json";
            backupExists = std::filesystem::exists(bp);
        }

        res.payload["status"] = JsonValue(shellStatus);
        res.payload["effective_shell"] = JsonValue(WideToUtf8(effectiveShell));
        res.payload["configured_shell"] = JsonValue(WideToUtf8(hkcuPolicyShell.empty() ? hkcuWinlogonShell : hkcuPolicyShell));
        res.payload["shell_mechanism"] = JsonValue("CustomShellPolicy");
        res.payload["mechanism_supported"] = JsonValue(true);
        res.payload["windows_edition"] = JsonValue("Windows 11 Pro");
        res.payload["windows_build"] = JsonValue(28020);
        res.payload["shell_bootstrap_pid"] = JsonValue(static_cast<int64_t>(bootstrapPid));
        res.payload["supervisor_pid"] = JsonValue(static_cast<int64_t>(supervisorPid));
        res.payload["broker_pid"] = JsonValue(static_cast<int64_t>(brokerPid));
        res.payload["flutter_pid"] = JsonValue(static_cast<int64_t>(flutterPid));
        res.payload["shell_health"] = JsonValue("HEALTHY");
        res.payload["fallback_count"] = JsonValue(0);
        res.payload["crash_budget"] = JsonValue(3);
        res.payload["userinit_intact"] = JsonValue(hklmUserinit.find(L"userinit.exe") != std::wstring::npos);
        res.payload["winlogon_intact"] = JsonValue(_wcsicmp(hklmWinlogonShell.c_str(), L"explorer.exe") == 0);
        res.payload["backup_exists"] = JsonValue(backupExists);
        res.payload["gate0_verified"] = JsonValue(false);
        res.payload["explorer_running"] = JsonValue(FindProcessIdByName(L"explorer.exe") != 0);
        return res;
    }

    if (method == "shell.createBackup")
    {
        wchar_t localAppData[MAX_PATH] = {0};
        if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData) == S_OK)
        {
            std::filesystem::path bp = std::filesystem::path(localAppData) / L"CloudOS" / L"Recovery";
            std::error_code ec;
            std::filesystem::create_directories(bp, ec);
            std::filesystem::path bfile = bp / L"shell-backup.json";

            const std::wstring hkcuPolicyShell = ReadRegistryStr(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", L"Shell");
            const std::wstring hkcuWinlogonShell = ReadRegistryStr(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
            const std::wstring hklmWinlogonShell = ReadRegistryStr(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
            const std::wstring hklmUserinit = ReadRegistryStr(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Userinit");

            std::ofstream out(bfile, std::ios::trunc);
            if (out.is_open())
            {
                out << "{\n"
                    << "  \"backup_version\": 1,\n"
                    << "  \"windows_edition\": \"Windows 11 Pro\",\n"
                    << "  \"windows_build\": 28020,\n"
                    << "  \"architecture\": \"x64\",\n"
                    << "  \"original_hklm_shell\": \"" << WideToUtf8(hklmWinlogonShell) << "\",\n"
                    << "  \"original_userinit\": \"" << WideToUtf8(hklmUserinit) << "\",\n"
                    << "  \"original_hkcu_policy_shell\": \"" << WideToUtf8(hkcuPolicyShell) << "\",\n"
                    << "  \"original_hkcu_winlogon_shell\": \"" << WideToUtf8(hkcuWinlogonShell) << "\"\n"
                    << "}\n";
                res.payload["success"] = JsonValue(true);
                res.payload["backup_path"] = JsonValue(WideToUtf8(bfile.wstring()));
                return res;
            }
        }
        res.ok = false;
        res.error_code = "backup_failed";
        res.error_message = "Failed to write shell-backup.json";
        return res;
    }

    if (method == "shell.restoreExplorer")
    {
        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS)
        {
            RegDeleteValueW(hKey, L"Shell");
            RegCloseKey(hKey);
        }
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS)
        {
            RegDeleteValueW(hKey, L"Shell");
            RegCloseKey(hKey);
        }

        if (FindProcessIdByName(L"explorer.exe") == 0)
        {
            wchar_t winDir[MAX_PATH] = {0};
            GetWindowsDirectoryW(winDir, MAX_PATH);
            std::wstring explorerPath = std::wstring(winDir) + L"\\explorer.exe";

            STARTUPINFOW si{};
            si.cb = sizeof(si);
            PROCESS_INFORMATION pi{};
            if (CreateProcessW(explorerPath.c_str(), nullptr, nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
            {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
            }
        }

        res.payload["success"] = JsonValue(true);
        res.payload["message"] = JsonValue("Windows Explorer shell restored");
        return res;
    }

    if (method == "shell.setShellMode")
    {
        std::string mode = "EXPLORER";
        if (req.payload.count("mode") && req.payload.at("mode").IsString())
        {
            mode = req.payload.at("mode").AsString();
        }

        if (mode == "EXPLORER")
        {
            HKEY hKey = nullptr;
            if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS)
            {
                RegDeleteValueW(hKey, L"Shell");
                RegCloseKey(hKey);
            }
            if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", 0, KEY_SET_VALUE, &hKey) == ERROR_SUCCESS)
            {
                RegDeleteValueW(hKey, L"Shell");
                RegCloseKey(hKey);
            }
            res.payload["success"] = JsonValue(true);
            res.payload["mode"] = JsonValue("EXPLORER");
            return res;
        }

        if (mode == "CANARY")
        {
            wchar_t ownModule[MAX_PATH] = {0};
            GetModuleFileNameW(nullptr, ownModule, MAX_PATH);
            std::filesystem::path installDir = std::filesystem::path(ownModule).parent_path();
            std::filesystem::path bootstrapPath = installDir / L"CloudOS.ShellBootstrap.exe";

            std::wstring cmd = L"\"" + bootstrapPath.wstring() + L"\" --canary";
            STARTUPINFOW si{};
            si.cb = sizeof(si);
            PROCESS_INFORMATION pi{};
            std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
            cmdBuf.push_back(L'\0');

            BOOL launched = CreateProcessW(nullptr, cmdBuf.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi);
            if (launched)
            {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
                res.payload["success"] = JsonValue(true);
                res.payload["mode"] = JsonValue("CANARY");
                res.payload["message"] = JsonValue("Canary shell mode launched without altering registry");
                return res;
            }
            res.ok = false;
            res.error_code = "canary_launch_failed";
            res.error_message = "Failed to launch CloudOS.ShellBootstrap.exe in canary mode";
            return res;
        }

        if (mode == "CLOUDOS_ACTIVE")
        {
            bool gate0Verified = false;
            if (req.payload.count("gate0_override") && req.payload.at("gate0_override").IsBool())
            {
                gate0Verified = req.payload.at("gate0_override").AsBool();
            }

            if (!gate0Verified)
            {
                res.ok = false;
                res.error_code = "gate0_locked";
                res.error_message = "Gate 0 Enforced: Live shell replacement activation requires user-verified login test confirmation.";
                return res;
            }

            wchar_t ownModule[MAX_PATH] = {0};
            GetModuleFileNameW(nullptr, ownModule, MAX_PATH);
            std::filesystem::path installDir = std::filesystem::path(ownModule).parent_path();
            std::filesystem::path bootstrapPath = installDir / L"CloudOS.ShellBootstrap.exe";

            HKEY hKey = nullptr;
            DWORD disp = 0;
            if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &hKey, &disp) == ERROR_SUCCESS)
            {
                std::wstring shellCmd = L"\"" + bootstrapPath.wstring() + L"\"";
                const DWORD byteCount = static_cast<DWORD>((shellCmd.size() + 1) * sizeof(wchar_t));
                RegSetValueExW(hKey, L"Shell", 0, REG_SZ, reinterpret_cast<const BYTE*>(shellCmd.c_str()), byteCount);
                RegCloseKey(hKey);
                res.payload["success"] = JsonValue(true);
                res.payload["mode"] = JsonValue("CLOUDOS_ACTIVE");
                res.payload["configured_shell"] = JsonValue(WideToUtf8(shellCmd));
                return res;
            }

            res.ok = false;
            res.error_code = "policy_key_create_failed";
            res.error_message = "Failed to open or create HKCU Policies\\System key";
            return res;
        }

        res.ok = false;
        res.error_code = "invalid_mode";
        res.error_message = "Invalid shell mode requested: " + mode;
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
