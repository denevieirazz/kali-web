#include "../CloudOS.SystemBroker/src/protocol_v21.h"
#include "../CloudOS.SystemBroker/src/security_v21.h"

#include <cstdint>
#include <iostream>
#include <limits>
#include <string>

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

int main(int argc, char* argv[])
{
    std::string cmd = "ping";
    if (argc > 1)
    {
        cmd = argv[1];
    }

    if (cmd == "--help" || cmd == "-h")
    {
        std::cout << "CloudOS Broker Probe CLI V22\n"
                  << "Usage: CloudOS.BrokerProbe.exe [COMMAND] [VALUE]\n"
                  << "Commands:\n"
                  << "  ping                         Ping broker health (health.ping)\n"
                  << "  status                       Check broker status (health.status)\n"
                  << "  capabilities                 Query supported capabilities (system.capabilities)\n"
                  << "  apps                         Query unified application catalog (apps.list)\n"
                  << "  files LOCATION               List an allowlisted Files location (files.list)\n"
                  << "  snapshot                     Query system snapshot (system.snapshot)\n"
                  << "  wsl-health DISTRO [TIMEOUT]  Run fixed bounded WSL health probe (1000-15000 ms)\n"
                  << "  set-volume VALUE             Set Windows master volume (system.volume.set)\n"
                  << "  set-brightness VALUE         Set display brightness (system.brightness.set)\n"
                  << "  diagnostics                  Query diagnostics snapshot (diagnostics.snapshot)\n";
        return 0;
    }

    bool has_value = false;
    double numeric_value = 0.0;
    if (cmd == "set-volume" || cmd == "set-brightness")
    {
        if (argc < 3)
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"A numeric VALUE is required\"}}" << std::endl;
            return 1;
        }
        try
        {
            numeric_value = std::stod(argv[2]);
            has_value = true;
        }
        catch (...)
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"VALUE must be numeric\"}}" << std::endl;
            return 1;
        }
    }

    std::string location;
    if (cmd == "files")
    {
        if (argc < 3)
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"An allowlisted LOCATION id is required\"}}" << std::endl;
            return 1;
        }
        location = argv[2];
    }

    std::string wsl_distro;
    int64_t wsl_timeout_ms = 8000;
    if (cmd == "wsl-health")
    {
        if (argc < 3 || argv[2] == nullptr || argv[2][0] == '\0')
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"A WSL DISTRO name is required\"}}" << std::endl;
            return 1;
        }
        wsl_distro = argv[2];
        if (wsl_distro.size() > 128)
        {
            std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"DISTRO exceeds 128 bytes\"}}" << std::endl;
            return 1;
        }
        if (argc >= 4)
        {
            try
            {
                const long long parsed = std::stoll(argv[3]);
                if (parsed < 1000 || parsed > 15000)
                {
                    throw std::out_of_range("timeout");
                }
                wsl_timeout_ms = static_cast<int64_t>(parsed);
            }
            catch (...)
            {
                std::cerr << "{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"TIMEOUT must be an integer between 1000 and 15000 ms\"}}" << std::endl;
                return 1;
            }
        }
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

    std::string method = "health.ping";
    if (cmd == "ping") method = "health.ping";
    else if (cmd == "status") method = "health.status";
    else if (cmd == "capabilities") method = "system.capabilities";
    else if (cmd == "apps") method = "apps.list";
    else if (cmd == "files") method = "files.list";
    else if (cmd == "snapshot") method = "system.snapshot";
    else if (cmd == "wsl-health") method = "wsl.health.probe";
    else if (cmd == "set-volume") method = "system.volume.set";
    else if (cmd == "set-brightness") method = "system.brightness.set";
    else if (cmd == "diagnostics") method = "diagnostics.snapshot";
    else method = cmd;

    CloudOS::BrokerRequest req;
    req.protocol = CloudOS::kProtocolVersion;
    req.id = "probe-cmd";
    req.method = method;
    if (has_value)
    {
        req.payload["value"] = CloudOS::JsonValue(numeric_value);
    }
    if (cmd == "files")
    {
        req.payload["location"] = CloudOS::JsonValue(location);
    }
    if (cmd == "wsl-health")
    {
        req.payload["distro"] = CloudOS::JsonValue(wsl_distro);
        req.payload["timeoutMs"] = CloudOS::JsonValue(wsl_timeout_ms);
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
