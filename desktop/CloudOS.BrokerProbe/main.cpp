#include "../CloudOS.SystemBroker/src/protocol_v21.h"
#include "../CloudOS.SystemBroker/src/security_v21.h"

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

HANDLE ConnectPipe(const std::wstring& pipe_name)
{
    auto open_pipe = [&]() {
        return CreateFileW(
            pipe_name.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr);
    };

    HANDLE pipe = open_pipe();
    if (pipe != INVALID_HANDLE_VALUE)
    {
        return pipe;
    }

    if (GetLastError() == ERROR_PIPE_BUSY && WaitNamedPipeW(pipe_name.c_str(), 500))
    {
        pipe = open_pipe();
    }
    return pipe;
}

void WriteError(const char* code, const char* message)
{
    JsonObject error;
    error["code"] = JsonValue(code);
    error["message"] = JsonValue(message);

    JsonObject root;
    root["ok"] = JsonValue(false);
    root["error"] = JsonValue(std::move(error));
    std::cerr << SerializeJson(JsonValue(std::move(root))) << std::endl;
}
} // namespace

bool SendFrame(HANDLE pipe, const std::string& payload)
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

bool ReadFrame(HANDLE pipe, std::string& payload)
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

} // namespace CloudOS

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
                  << "Usage: CloudOS.BrokerProbe.exe [COMMAND]\n"
                  << "Commands:\n"
                  << "  ping          Ping broker health (health.ping)\n"
                  << "  status        Check broker status (health.status)\n"
                  << "  capabilities  Query supported capabilities (system.capabilities)\n"
                  << "  apps          Query unified application catalog (apps.list)\n"
                  << "  snapshot      Query system snapshot (system.snapshot)\n"
                  << "  wsl           Query installed WSL distributions (wsl.list)\n"
                  << "  diagnostics   Query diagnostics snapshot (diagnostics.snapshot)\n";
        return 0;
    }

    const std::wstring pipe_name = CloudOS::SecurityV21::GetCommandPipeName();
    HANDLE pipe = CloudOS::ConnectPipe(pipe_name);
    if (pipe == INVALID_HANDLE_VALUE)
    {
        CloudOS::WriteError("broker_unavailable", "Failed to connect to broker named pipe");
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
        CloudOS::WriteError("send_failed", "Failed to send hello handshake");
        return 3;
    }

    std::string hello_raw;
    if (!CloudOS::ReadFrame(pipe, hello_raw))
    {
        CloseHandle(pipe);
        CloudOS::WriteError("read_failed", "Failed to read hello response");
        return 3;
    }

    CloudOS::BrokerResponse hello;
    std::string parse_error;
    if (!CloudOS::ParseResponse(hello_raw, hello, parse_error) ||
        !hello.ok ||
        hello.id != hello_req.id ||
        hello.protocol != CloudOS::kProtocolVersion)
    {
        CloseHandle(pipe);
        CloudOS::WriteError("bad_handshake", "Broker handshake response was invalid");
        return 3;
    }

    const auto protocol_it = hello.payload.find("protocolVersion");
    const auto client_it = hello.payload.find("clientId");
    const auto server_it = hello.payload.find("serverInstanceId");
    if (protocol_it == hello.payload.end() ||
        !protocol_it->second.IsInt() ||
        protocol_it->second.AsInt() != CloudOS::kProtocolVersion ||
        client_it == hello.payload.end() ||
        !client_it->second.IsString() ||
        client_it->second.AsString().empty() ||
        server_it == hello.payload.end() ||
        !server_it->second.IsString() ||
        server_it->second.AsString().empty())
    {
        CloseHandle(pipe);
        CloudOS::WriteError("protocol_mismatch", "Broker handshake metadata is incomplete or incompatible");
        return 3;
    }

    std::string method;
    if (cmd == "ping") method = "health.ping";
    else if (cmd == "status") method = "health.status";
    else if (cmd == "capabilities") method = "system.capabilities";
    else if (cmd == "apps") method = "apps.list";
    else if (cmd == "snapshot") method = "system.snapshot";
    else if (cmd == "wsl") method = "wsl.list";
    else if (cmd == "diagnostics") method = "diagnostics.snapshot";
    else
    {
        CloseHandle(pipe);
        CloudOS::WriteError("unknown_command", "Unknown BrokerProbe command");
        return 5;
    }

    CloudOS::BrokerRequest req;
    req.protocol = CloudOS::kProtocolVersion;
    req.id = "probe-cmd";
    req.method = method;

    if (!CloudOS::SendFrame(pipe, CloudOS::SerializeRequest(req)))
    {
        CloseHandle(pipe);
        CloudOS::WriteError("send_failed", "Failed to send request");
        return 4;
    }

    std::string response_raw;
    if (!CloudOS::ReadFrame(pipe, response_raw))
    {
        CloseHandle(pipe);
        CloudOS::WriteError("read_failed", "Failed to read response");
        return 4;
    }

    CloudOS::BrokerResponse response;
    parse_error.clear();
    if (!CloudOS::ParseResponse(response_raw, response, parse_error) ||
        response.id != req.id ||
        response.protocol != CloudOS::kProtocolVersion)
    {
        CloseHandle(pipe);
        CloudOS::WriteError("bad_response", "Malformed or mismatched broker response");
        return 4;
    }

    CloseHandle(pipe);
    std::cout << response_raw << std::endl;
    return response.ok ? 0 : 6;
}
