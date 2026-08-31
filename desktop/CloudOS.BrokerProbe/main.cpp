#include "../CloudOS.SystemBroker/src/protocol_v21.h"
#include "../CloudOS.SystemBroker/src/security_v21.h"

#include <iostream>
#include <string_view>

namespace CloudOS
{

std::string WideToUtf8(std::wstring_view value)
{
    if (value.empty()) return {};
    const int size = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
    return result;
}

bool SendFrame(HANDLE pipe, const std::string& payload)
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

bool ReadFrame(HANDLE pipe, std::string& payload)
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

int wmain(int argc, wchar_t* argv[])
{
    const auto argument = [argc, argv](int index, const char* fallback = "") {
        return index < argc ? CloudOS::WideToUtf8(argv[index]) : std::string(fallback);
    };
    std::string cmd = "ping";
    if (argc > 1)
    {
        cmd = argument(1);
    }

    if (cmd == "--help" || cmd == "-h")
    {
        std::cout << "CloudOS Broker Probe CLI V22\n"
                  << "Usage: CloudOS.BrokerProbe.exe [COMMAND] [ARGS...]\n"
                  << "Commands:\n"
                  << "  ping                 Ping broker health (health.ping)\n"
                  << "  status               Check broker status (health.status)\n"
                  << "  capabilities         Query supported capabilities (system.capabilities)\n"
                  << "  apps                 Query unified application catalog (apps.list)\n"
                  << "  snapshot             Query system snapshot (system.snapshot)\n"
                  << "  diagnostics          Query diagnostics snapshot (diagnostics.snapshot)\n"
                  << "  drives               List system drives (files.drives)\n"
                  << "  known-folders        List known folders (files.knownFolders)\n"
                  << "  list [path]          List directory items (files.list)\n"
                  << "  metadata <path>      Query item metadata (files.metadata)\n"
                  << "  search <path> <q>    Search items (files.search)\n"
                  << "  open-with <path>     Query Open With apps (files.openWith.list)\n"
                  << "  create-folder <parent> <name>  Create a sandbox folder\n"
                  << "  rename <path> <name>            Rename a sandbox item\n"
                  << "  delete <path>                   Permanently delete a sandbox item\n"
                  << "  copy <source> <destination> [policy]  Start a copy job\n"
                  << "  move <source> <destination> [policy]  Start a move job\n"
                  << "  job-status <id>                 Query job state\n"
                  << "  job-cancel <id>                 Cancel a job\n";
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

    // 1. Handshake
    CloudOS::BrokerRequest hello_req;
    hello_req.protocol = CloudOS::kProtocolVersion;
    hello_req.id = "probe-hello";
    hello_req.method = "hello";
    hello_req.payload["clientName"] = CloudOS::JsonValue("CloudOS.BrokerProbe");
    hello_req.payload["clientVersion"] = CloudOS::JsonValue("22.0.0");

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

    // Map command to method
    std::string method = "health.ping";
    CloudOS::JsonObject payload;

    if (cmd == "ping") method = "health.ping";
    else if (cmd == "status") method = "health.status";
    else if (cmd == "capabilities") method = "system.capabilities";
    else if (cmd == "apps") method = "apps.list";
    else if (cmd == "snapshot") method = "system.snapshot";
    else if (cmd == "diagnostics") method = "diagnostics.snapshot";
    else if (cmd == "drives") method = "files.drives";
    else if (cmd == "known-folders") method = "files.knownFolders";
    else if (cmd == "list")
    {
        method = "files.list";
        payload["path"] = CloudOS::JsonValue(argument(2, "home"));
    }
    else if (cmd == "metadata")
    {
        method = "files.metadata";
        payload["path"] = CloudOS::JsonValue(argument(2, "home"));
    }
    else if (cmd == "search")
    {
        method = "files.search";
        payload["rootPath"] = CloudOS::JsonValue(argument(2, "home"));
        payload["query"] = CloudOS::JsonValue(argument(3));
    }
    else if (cmd == "open-with")
    {
        method = "files.openWith.list";
        payload["path"] = CloudOS::JsonValue(argument(2));
    }
    else if (cmd == "create-folder")
    {
        method = "files.createFolder";
        payload["parentPath"] = CloudOS::JsonValue(argument(2));
        payload["name"] = CloudOS::JsonValue(argument(3));
    }
    else if (cmd == "rename")
    {
        method = "files.rename";
        payload["path"] = CloudOS::JsonValue(argument(2));
        payload["newName"] = CloudOS::JsonValue(argument(3));
    }
    else if (cmd == "delete")
    {
        method = "files.delete";
        CloudOS::JsonArray paths;
        if (argc > 2) paths.push_back(CloudOS::JsonValue(argument(2)));
        payload["paths"] = CloudOS::JsonValue(std::move(paths));
        payload["permanent"] = CloudOS::JsonValue(true);
    }
    else if (cmd == "copy" || cmd == "move")
    {
        method = cmd == "copy" ? "files.copy" : "files.move";
        CloudOS::JsonArray sources;
        if (argc > 2) sources.push_back(CloudOS::JsonValue(argument(2)));
        payload["sources"] = CloudOS::JsonValue(std::move(sources));
        payload["destination"] = CloudOS::JsonValue(argument(3));
        payload["overwritePolicy"] = CloudOS::JsonValue(argument(4, "ask"));
    }
    else if (cmd == "job-status" || cmd == "job-cancel")
    {
        method = cmd == "job-status" ? "jobs.status" : "jobs.cancel";
        payload["jobId"] = CloudOS::JsonValue(argument(2));
    }
    else method = cmd;

    CloudOS::BrokerRequest req;
    req.protocol = CloudOS::kProtocolVersion;
    req.id = "probe-cmd";
    req.method = method;
    req.payload = std::move(payload);

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
