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

    std::string hello_raw;
    if (!CloudOS::ReadFrame(pipe, hello_raw))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"read_failed\",\"message\":\"Failed to read hello response\"}}" << std::endl;
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
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"bad_handshake\",\"message\":\"Broker handshake response was invalid\"}}" << std::endl;
        return 3;
    }

    const auto protocol_it = hello.payload.find("protocolVersion");
    if (protocol_it == hello.payload.end() ||
        !protocol_it->second.IsInt() ||
        protocol_it->second.AsInt() != CloudOS::kProtocolVersion)
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"protocol_mismatch\",\"message\":\"Broker protocolVersion mismatch\"}}" << std::endl;
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
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"unknown_command\",\"message\":\"Unknown BrokerProbe command\"}}" << std::endl;
        return 5;
    }

    CloudOS::BrokerRequest req;
    req.protocol = CloudOS::kProtocolVersion;
    req.id = "probe-cmd";
    req.method = method;

    if (!CloudOS::SendFrame(pipe, CloudOS::SerializeRequest(req)))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"send_failed\",\"message\":\"Failed to send request\"}}" << std::endl;
        return 4;
    }

    std::string response_raw;
    if (!CloudOS::ReadFrame(pipe, response_raw))
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"read_failed\",\"message\":\"Failed to read response\"}}" << std::endl;
        return 4;
    }

    CloudOS::BrokerResponse response;
    parse_error.clear();
    if (!CloudOS::ParseResponse(response_raw, response, parse_error) || response.id != req.id)
    {
        CloseHandle(pipe);
        std::cerr << "{\"ok\":false,\"error\":{\"code\":\"bad_response\",\"message\":\"Malformed or mismatched broker response\"}}" << std::endl;
        return 4;
    }

    CloseHandle(pipe);
    std::cout << response_raw << std::endl;
    return response.ok ? 0 : 6;
}
