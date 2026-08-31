#include "broker_server_v21.h"
#include "app_service_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "file_service_v22.h"
#include "job_manager_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <iostream>
#include <cmath>
#include <algorithm>

namespace CloudOS
{

namespace
{
struct ClientSendState final
{
    std::mutex mutex;
    HANDLE pipe{INVALID_HANDLE_VALUE};
    bool active{true};
};
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

    // 1. Acquire single-instance per-user mutex
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

    // 2. Initialize subsystems
    DiagnosticsV21::Initialize();
    JobManagerV21::Instance().Initialize(2);

    running_.store(true);
    listener_thread_ = std::thread(&BrokerServerV21::ListenerLoop, this);

    // Publish broker.ready
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

    // Unblock listener by connecting a dummy client
    std::wstring pipe_name = SecurityV21::GetCommandPipeName();
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
            if (entry.thread.joinable()) CancelSynchronousIo(entry.thread.native_handle());
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
    uint32_t len = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    DWORD header_written = 0;
    const auto* header = reinterpret_cast<const unsigned char*>(&len);
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

bool BrokerServerV21::ReadFrame(HANDLE pipe, std::string& payload)
{
    uint32_t len = 0;
    DWORD read_bytes = 0;
    DWORD header_bytes = 0;
    auto* header = reinterpret_cast<unsigned char*>(&len);
    while (header_bytes < sizeof(len))
    {
        if (!ReadFile(pipe, header + header_bytes, sizeof(len) - header_bytes, &read_bytes, nullptr) || read_bytes == 0)
        {
            return false;
        }
        header_bytes += read_bytes;
    }
    if (len > kMaxPayloadBytes)
    {
        return false; // Reject oversized frame
    }
    payload.resize(len);
    if (len > 0)
    {
        DWORD total_read = 0;
        while (total_read < len)
        {
            if (!ReadFile(pipe, &payload[total_read], len - total_read, &read_bytes, nullptr) || read_bytes == 0)
            {
                return false;
            }
            total_read += read_bytes;
        }
    }
    return true;
}

void BrokerServerV21::ListenerLoop()
{
    std::wstring pipe_name = SecurityV21::GetCommandPipeName();

    while (running_.load())
    {
        SECURITY_ATTRIBUTES sa{};
        PSECURITY_DESCRIPTOR sd = nullptr;
        bool sa_ok = SecurityV21::CreatePerUserSecurityAttributes(&sa, &sd);

        // The command pipe is privileged. Never fall back to the process
        // default DACL when the per-user descriptor cannot be constructed.
        if (!sa_ok)
        {
            Sleep(100);
            continue;
        }

        HANDLE pipe = CreateNamedPipeW(
            pipe_name.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
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

        BOOL connected = ConnectNamedPipe(pipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
        if (!running_.load())
        {
            CloseHandle(pipe);
            break;
        }

        if (connected)
        {
            std::string client_id = "client-" + std::to_string(next_client_id_++);
            std::lock_guard<std::mutex> lock(client_threads_mutex_);
            for (auto it = client_threads_.begin(); it != client_threads_.end();)
            {
                if (it->finished->load())
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
            entry.thread = std::thread(&BrokerServerV21::ClientSessionLoop, this, pipe, client_id, finished);
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
    // Register client for events through this pipe
    auto send_state = std::make_shared<ClientSendState>();
    send_state->pipe = pipe;
    EventBusV21::Instance().RegisterClient(
        client_id,
        [this, send_state](const BrokerEvent& ev) {
            std::string serialized = SerializeEvent(ev);
            std::lock_guard<std::mutex> lock(send_state->mutex);
            if (send_state->active)
            {
                SendFrame(send_state->pipe, serialized);
            }
        });

    while (running_.load())
    {
        std::string frame;
        if (!ReadFrame(pipe, frame))
        {
            break; // Client disconnected or error
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

        std::string resp_str = SerializeResponse(res);
        {
            std::lock_guard<std::mutex> lock(send_state->mutex);
            if (!SendFrame(pipe, resp_str))
            {
                break;
            }
        }
    }

    {
        std::lock_guard<std::mutex> lock(send_state->mutex);
        send_state->active = false;
    }
    EventBusV21::Instance().UnregisterClient(client_id);
    FlushFileBuffers(pipe);
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
        auto it = req.payload.find("id");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing or invalid 'id' parameter in payload";
            return res;
        }

        std::string app_id = it->second.AsString();
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
        const bool updated = SystemServiceV21::Instance().SetVolume(value);
        if (!updated)
        {
            res.ok = false;
            res.error_code = "volume_unavailable";
            res.error_message = "The default audio endpoint is unavailable";
            return res;
        }
        res.payload["updated"] = JsonValue(updated);
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
        const bool updated = SystemServiceV21::Instance().SetBrightness(value);
        if (!updated)
        {
            res.ok = false;
            res.error_code = "brightness_unavailable";
            res.error_message = "Brightness control is unavailable on this display";
            return res;
        }
        res.payload["updated"] = JsonValue(updated);
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
        auto it = req.payload.find("pattern");
        std::string pattern = (it != req.payload.end() && it->second.IsString()) ? it->second.AsString() : "*";
        bool ok = EventBusV21::Instance().Subscribe(client_id, pattern);
        res.payload["subscribed"] = JsonValue(ok);
        res.payload["pattern"] = JsonValue(pattern);
        return res;
    }

    if (method == "events.unsubscribe")
    {
        auto it = req.payload.find("pattern");
        std::string pattern = (it != req.payload.end() && it->second.IsString()) ? it->second.AsString() : "*";
        bool ok = EventBusV21::Instance().Unsubscribe(client_id, pattern);
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
        bool cancelled = JobManagerV21::Instance().CancelJob(it->second.AsString());
        res.payload["cancelled"] = JsonValue(cancelled);
        return res;
    }

    if (method == "files.list")
    {
        auto it_path = req.payload.find("path");
        std::string path = (it_path != req.payload.end() && it_path->second.IsString()) ? it_path->second.AsString() : "home";

        size_t page_size = 200;
        auto it_size = req.payload.find("pageSize");
        if (it_size != req.payload.end() && it_size->second.IsInt()) page_size = static_cast<size_t>(it_size->second.AsInt());

        std::string continuation;
        auto it_cont = req.payload.find("continuationToken");
        if (it_cont != req.payload.end() && it_cont->second.IsString()) continuation = it_cont->second.AsString();

        FileSortOptions sort;
        auto it_sort_field = req.payload.find("sortField");
        if (it_sort_field != req.payload.end() && it_sort_field->second.IsString())
        {
            std::string sf = it_sort_field->second.AsString();
            if (sf == "size") sort.field = FileSortField::Size;
            else if (sf == "modified") sort.field = FileSortField::Modified;
            else if (sf == "type") sort.field = FileSortField::Type;
            else sort.field = FileSortField::Name;
        }

        auto it_sort_asc = req.payload.find("ascending");
        if (it_sort_asc != req.payload.end() && it_sort_asc->second.IsBool()) sort.ascending = it_sort_asc->second.AsBool();

        auto it_sort_dirs = req.payload.find("directoriesFirst");
        if (it_sort_dirs != req.payload.end() && it_sort_dirs->second.IsBool()) sort.directories_first = it_sort_dirs->second.AsBool();

        FileFilterOptions filter;
        auto it_hidden = req.payload.find("showHidden");
        if (it_hidden != req.payload.end() && it_hidden->second.IsBool()) filter.show_hidden = it_hidden->second.AsBool();

        auto it_filter_search = req.payload.find("searchText");
        if (it_filter_search != req.payload.end() && it_filter_search->second.IsString()) filter.search_text = it_filter_search->second.AsString();

        res.payload = FileServiceV22::Instance().ListDirectory(path, page_size, continuation, sort, filter);
        return res;
    }

    if (method == "files.metadata")
    {
        auto it = req.payload.find("path");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path'";
            return res;
        }
        res.payload = FileServiceV22::Instance().GetMetadata(it->second.AsString());
        return res;
    }

    if (method == "files.drives")
    {
        res.payload = FileServiceV22::Instance().GetDrives();
        return res;
    }

    if (method == "files.knownFolders")
    {
        res.payload = FileServiceV22::Instance().GetKnownFolders();
        return res;
    }

    if (method == "files.resolvePath")
    {
        auto it = req.payload.find("path");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path'";
            return res;
        }
        res.payload = FileServiceV22::Instance().ResolvePath(it->second.AsString());
        return res;
    }

    if (method == "files.createFolder")
    {
        auto it_parent = req.payload.find("parentPath");
        auto it_name = req.payload.find("name");
        if (it_parent == req.payload.end() || !it_parent->second.IsString() ||
            it_name == req.payload.end() || !it_name->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'parentPath' or 'name'";
            return res;
        }
        res.payload = FileServiceV22::Instance().CreateFolder(it_parent->second.AsString(), it_name->second.AsString());
        return res;
    }

    if (method == "files.rename")
    {
        auto it_path = req.payload.find("path");
        auto it_name = req.payload.find("newName");
        if (it_path == req.payload.end() || !it_path->second.IsString() ||
            it_name == req.payload.end() || !it_name->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path' or 'newName'";
            return res;
        }
        res.payload = FileServiceV22::Instance().RenameItem(it_path->second.AsString(), it_name->second.AsString());
        return res;
    }

    if (method == "files.delete")
    {
        auto it_paths = req.payload.find("paths");
        if (it_paths == req.payload.end() || !it_paths->second.IsArray())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing array 'paths'";
            return res;
        }
        std::vector<std::string> paths;
        for (const auto& p : it_paths->second.AsArray())
        {
            if (p.IsString()) paths.push_back(p.AsString());
        }
        bool permanent = false;
        auto it_perm = req.payload.find("permanent");
        if (it_perm != req.payload.end() && it_perm->second.IsBool()) permanent = it_perm->second.AsBool();

        res.payload = FileServiceV22::Instance().DeleteItems(paths, permanent);
        return res;
    }

    if (method == "files.copy")
    {
        auto it_sources = req.payload.find("sources");
        auto it_dest = req.payload.find("destination");
        if (it_sources == req.payload.end() || !it_sources->second.IsArray() ||
            it_dest == req.payload.end() || !it_dest->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'sources' or 'destination'";
            return res;
        }
        std::vector<std::string> sources;
        for (const auto& s : it_sources->second.AsArray())
        {
            if (s.IsString()) sources.push_back(s.AsString());
        }
        std::string overwrite = "ask";
        auto it_ov = req.payload.find("overwritePolicy");
        if (it_ov != req.payload.end() && it_ov->second.IsString()) overwrite = it_ov->second.AsString();

        std::string job_id = FileServiceV22::Instance().StartCopyJob(sources, it_dest->second.AsString(), overwrite);
        res.payload["jobId"] = JsonValue(job_id);
        res.payload["status"] = JsonValue("started");
        return res;
    }

    if (method == "files.move")
    {
        auto it_sources = req.payload.find("sources");
        auto it_dest = req.payload.find("destination");
        if (it_sources == req.payload.end() || !it_sources->second.IsArray() ||
            it_dest == req.payload.end() || !it_dest->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'sources' or 'destination'";
            return res;
        }
        std::vector<std::string> sources;
        for (const auto& s : it_sources->second.AsArray())
        {
            if (s.IsString()) sources.push_back(s.AsString());
        }
        std::string overwrite = "ask";
        auto it_ov = req.payload.find("overwritePolicy");
        if (it_ov != req.payload.end() && it_ov->second.IsString()) overwrite = it_ov->second.AsString();

        std::string job_id = FileServiceV22::Instance().StartMoveJob(sources, it_dest->second.AsString(), overwrite);
        res.payload["jobId"] = JsonValue(job_id);
        res.payload["status"] = JsonValue("started");
        return res;
    }

    if (method == "files.search")
    {
        auto it_root = req.payload.find("rootPath");
        auto it_query = req.payload.find("query");
        if (it_root == req.payload.end() || !it_root->second.IsString() ||
            it_query == req.payload.end() || !it_query->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'rootPath' or 'query'";
            return res;
        }
        bool recursive = true;
        auto it_rec = req.payload.find("recursive");
        if (it_rec != req.payload.end() && it_rec->second.IsBool()) recursive = it_rec->second.AsBool();

        std::string job_id = FileServiceV22::Instance().StartSearchJob(it_root->second.AsString(), it_query->second.AsString(), recursive);
        res.payload["jobId"] = JsonValue(job_id);
        res.payload["status"] = JsonValue("started");
        return res;
    }

    if (method == "files.open")
    {
        auto it = req.payload.find("path");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path'";
            return res;
        }
        res.payload = FileServiceV22::Instance().OpenDefault(it->second.AsString());
        return res;
    }

    if (method == "files.openWith.list")
    {
        auto it = req.payload.find("path");
        if (it == req.payload.end() || !it->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path'";
            return res;
        }
        res.payload = FileServiceV22::Instance().GetOpenWithList(it->second.AsString());
        return res;
    }

    if (method == "files.openWith.launch")
    {
        auto it_path = req.payload.find("path");
        auto it_app = req.payload.find("appId");
        auto it_plat = req.payload.find("platform");
        if (it_path == req.payload.end() || !it_path->second.IsString() ||
            it_app == req.payload.end() || !it_app->second.IsString() ||
            it_plat == req.payload.end() || !it_plat->second.IsString())
        {
            res.ok = false;
            res.error_code = "invalid_argument";
            res.error_message = "Missing 'path', 'appId', or 'platform'";
            return res;
        }
        std::string distro;
        auto it_distro = req.payload.find("distro");
        if (it_distro != req.payload.end() && it_distro->second.IsString()) distro = it_distro->second.AsString();

        res.payload = FileServiceV22::Instance().LaunchOpenWith(it_path->second.AsString(), it_app->second.AsString(), it_plat->second.AsString(), distro);
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
