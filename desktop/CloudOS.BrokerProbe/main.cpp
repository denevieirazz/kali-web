#include "../CloudOS.SystemBroker/src/protocol_v21.h"
#include "../CloudOS.SystemBroker/src/security_v21.h"

#include <iostream>

namespace CloudOS
{

bool SendFrame(HANDLE pipe, const std::string& payload)
{
    uint32_t len = static_cast<uint32_t>(payload.size());
    DWORD written = 0;
    if (!WriteFile(pipe, &len, sizeof(len), &written, nullptr) || written != sizeof(len))
    {
        return false;
    }
    if (len > 0)
    {
        if (!WriteFile(pipe, payload.data(), len, &written, nullptr) || written != len)
        {
            return false;
        }
    }
    return true;
}

bool ReadFrame(HANDLE pipe, std::string& payload)
{
    uint32_t len = 0;
    DWORD read_bytes = 0;
    if (!ReadFile(pipe, &len, sizeof(len), &read_bytes, nullptr) || read_bytes != sizeof(len))
    {
        return false;
    }
    if (len > kMaxPayloadBytes) return false;
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

} // namespace CloudOS

#include <chrono>
#include <thread>

int main(int argc, char* argv[])
{
    std::string cmd = "ping";
    if (argc > 1)
    {
        cmd = argv[1];
    }

    if (cmd == "--help" || cmd == "-h")
    {
        std::cout << "CloudOS Broker Probe CLI V21\n"
                  << "Usage: CloudOS.BrokerProbe.exe [COMMAND] [ARGS...]\n"
                  << "Commands:\n"
                  << "  ping                               Ping broker health\n"
                  << "  status                             Check broker status\n"
                  << "  capabilities                       Query supported capabilities\n"
                  << "  apps                               Query unified application catalog\n"
                  << "  files LOCATION                     List an allowlisted Files location\n"
                  << "  list-entry ENTRY_ID                List contents of folder capability\n"
                  << "  list-drives                        List available drives including WSL\n"
                  << "  copy SRC DEST [CONFLICT]           Copy file(s) asynchronously\n"
                  << "  move SRC DEST                      Move file(s) asynchronously\n"
                  << "  delete ENTRY_ID [true|false]       Delete entry to recycle bin or permanent\n"
                  << "  wsl-list                           List WSL distributions\n"
                  << "  jobs-get JOB_ID                    Get status of a background job\n"
                  << "  jobs-cancel JOB_ID                 Cancel a running job\n"
                  << "  invoke METHOD [JSON_PAYLOAD]       Invoke arbitrary broker method\n"
                  << "  watch-events [DURATION_MS]         Subscribe to events and stream to stdout\n"
                  << "  snapshot                           Query system snapshot\n"
                  << "  set-volume VALUE                   Set Windows master volume\n"
                  << "  set-brightness VALUE               Set display brightness\n"
                  << "  diagnostics                        Query diagnostics snapshot\n";
        return 0;
    }

    std::wstring pipe_name = CloudOS::SecurityV21::GetCommandPipeName();
    HANDLE pipe = CreateFileW(
        pipe_name.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);

    if (pipe == INVALID_HANDLE_VALUE)
    {
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"broker_unavailable\",\"message\":\"Failed to connect to broker named pipe\"}}" << std::endl;
        return 2;
    }

    CloudOS::BrokerRequest hello_req;
    hello_req.protocol = CloudOS::kProtocolVersion;
    hello_req.id = "probe-hello";
    hello_req.method = "hello";
    hello_req.payload["clientName"] = CloudOS::JsonValue("CloudOS.BrokerProbe");
    hello_req.payload["clientVersion"] = CloudOS::JsonValue("21.0.0");

    if (!CloudOS::SendFrame(pipe, CloudOS::SerializeRequest(hello_req)))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"send_failed\",\"message\":\"Failed to send hello handshake\"}}" << std::endl;
        return 3;
    }

    std::string hello_resp_str;
    if (!CloudOS::ReadFrame(pipe, hello_resp_str))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"read_failed\",\"message\":\"Failed to read hello response\"}}" << std::endl;
        return 3;
    }

    if (cmd == "watch-events")
    {
        int duration_ms = 5000;
        if (argc > 2)
        {
            try { duration_ms = std::stoi(argv[2]); } catch (...) {}
        }

        CloudOS::BrokerRequest sub_req;
        sub_req.protocol = CloudOS::kProtocolVersion;
        sub_req.id = "probe-sub";
        sub_req.method = "events.subscribe";
        sub_req.payload["pattern"] = CloudOS::JsonValue("*");

        if (!CloudOS::SendFrame(pipe, CloudOS::SerializeRequest(sub_req)))
        {
            CloseHandle(pipe);
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"subscribe_failed\"}}" << std::endl;
            return 4;
        }

        std::string sub_resp;
        if (CloudOS::ReadFrame(pipe, sub_resp))
        {
            std::cout << sub_resp << std::endl;
        }

        auto start = std::chrono::steady_clock::now();
        while (true)
        {
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - start).count();
            if (elapsed >= duration_ms) break;

            DWORD bytes_avail = 0;
            if (PeekNamedPipe(pipe, nullptr, 0, nullptr, &bytes_avail, nullptr) && bytes_avail >= 4)
            {
                std::string frame;
                if (CloudOS::ReadFrame(pipe, frame))
                {
                    std::cout << frame << std::endl;
                }
            }
            else
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
        }

        CloseHandle(pipe);
        return 0;
    }

    CloudOS::BrokerRequest req;
    req.protocol = CloudOS::kProtocolVersion;
    req.id = "probe-cmd";

    if (cmd == "ping") req.method = "health.ping";
    else if (cmd == "status") req.method = "health.status";
    else if (cmd == "capabilities") req.method = "system.capabilities";
    else if (cmd == "apps") req.method = "apps.list";
    else if (cmd == "launch")
    {
        req.method = "apps.launch";
        req.payload["id"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "");
    }
    else if (cmd == "snapshot") req.method = "system.snapshot";
    else if (cmd == "diagnostics") req.method = "diagnostics.snapshot";
    else if (cmd == "list-drives") req.method = "files.listDrives";
    else if (cmd == "wsl-list") req.method = "wsl.list";
    else if (cmd == "files")
    {
        req.method = "files.list";
        req.payload["location"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "home");
    }
    else if (cmd == "list-entry")
    {
        req.method = "files.listEntry";
        req.payload["entryId"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "");
    }
    else if (cmd == "resolve")
    {
        req.method = "files.resolvePath";
        req.payload["path"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "");
    }
    else if (cmd == "copy" || cmd == "move")
    {
        req.method = (cmd == "move") ? "files.move" : "files.copy";
        std::vector<CloudOS::JsonValue> srcs;
        if (argc > 2) srcs.push_back(CloudOS::JsonValue(argv[2]));
        req.payload["sourceEntryIds"] = CloudOS::JsonValue(std::move(srcs));
        req.payload["destinationEntryId"] = CloudOS::JsonValue(argc > 3 ? argv[3] : "");
        if (argc > 4) req.payload["conflictStrategy"] = CloudOS::JsonValue(argv[4]);
    }
    else if (cmd == "delete")
    {
        req.method = "files.delete";
        std::vector<CloudOS::JsonValue> entries;
        if (argc > 2) entries.push_back(CloudOS::JsonValue(argv[2]));
        req.payload["entryIds"] = CloudOS::JsonValue(std::move(entries));
        bool perm = false;
        if (argc > 3 && std::string(argv[3]) == "true") perm = true;
        req.payload["permanent"] = CloudOS::JsonValue(perm);
    }
    else if (cmd == "jobs-get")
    {
        req.method = "jobs.status";
        req.payload["jobId"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "");
    }
    else if (cmd == "jobs-cancel")
    {
        req.method = "jobs.cancel";
        req.payload["jobId"] = CloudOS::JsonValue(argc > 2 ? argv[2] : "");
    }
    else if (cmd == "set-volume")
    {
        req.method = "system.volume.set";
        double v = (argc > 2) ? std::stod(argv[2]) : 0.5;
        req.payload["value"] = CloudOS::JsonValue(v);
    }
    else if (cmd == "set-brightness")
    {
        req.method = "system.brightness.set";
        double v = (argc > 2) ? std::stod(argv[2]) : 0.5;
        req.payload["value"] = CloudOS::JsonValue(v);
    }
    else if (cmd == "invoke")
    {
        if (argc < 3)
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"Method required for invoke\"}}" << std::endl;
            CloseHandle(pipe);
            return 1;
        }
        req.method = argv[2];
        if (argc > 3)
        {
            CloudOS::JsonValue parsed;
            if (CloudOS::ParseJson(argv[3], parsed) && parsed.IsObject())
            {
                req.payload = parsed.AsObject();
            }
        }
    }
    else
    {
        req.method = cmd;
        if (argc > 2 && cmd.rfind("window.", 0) == 0)
        {
            try
            {
                uint64_t hwnd = std::stoull(argv[2]);
                req.payload["hwnd"] = CloudOS::JsonValue(static_cast<int64_t>(hwnd));
            }
            catch (...) {}
            if (argc > 6 && cmd == "window.setBounds")
            {
                try
                {
                    req.payload["x"] = CloudOS::JsonValue(std::stoll(argv[3]));
                    req.payload["y"] = CloudOS::JsonValue(std::stoll(argv[4]));
                    req.payload["width"] = CloudOS::JsonValue(std::stoll(argv[5]));
                    req.payload["height"] = CloudOS::JsonValue(std::stoll(argv[6]));
                }
                catch (...) {}
            }
            if (argc > 3 && cmd == "window.snap")
            {
                req.payload["snap"] = CloudOS::JsonValue(argv[3]);
            }
        }
    }

    if (!CloudOS::SendFrame(pipe, CloudOS::SerializeRequest(req)))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"send_failed\",\"message\":\"Failed to send request\"}}" << std::endl;
        return 4;
    }

    std::string resp_str;
    if (!CloudOS::ReadFrame(pipe, resp_str))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"read_failed\",\"message\":\"Failed to read response\"}}" << std::endl;
        return 4;
    }

    CloseHandle(pipe);
    std::cout << resp_str << std::endl;
    return 0;
}
