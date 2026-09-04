#include "app_service_v21.h"
#include "broker_server_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "job_manager_v21.h"
#include "protocol_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <cmath>
#include <csignal>
#include <iostream>

namespace CloudOS
{

namespace
{
std::atomic_bool g_shutdown_requested{false};

BOOL WINAPI ConsoleCtrlHandler(DWORD ctrl_type)
{
    switch (ctrl_type)
    {
    case CTRL_C_EVENT:
    case CTRL_BREAK_EVENT:
    case CTRL_CLOSE_EVENT:
    case CTRL_SHUTDOWN_EVENT:
        g_shutdown_requested.store(true);
        BrokerServerV21::Instance().Stop();
        return TRUE;
    default:
        return FALSE;
    }
}
} // namespace

int RunSelfTest()
{
    std::cout << "[SystemBroker] Running V21 Self-Test Suite..." << std::endl;
    int assertions = 0;

    auto Assert = [&assertions](bool cond, const std::string& name) {
        if (!cond)
        {
            std::cerr << "[FAIL] Assertion failed: " << name << std::endl;
            exit(1);
        }
        assertions++;
    };

    // 1. Test Protocol Serialization, strict parsing and malformed-input fail-closed behavior.
    {
        BrokerRequest req;
        req.protocol = kProtocolVersion;
        req.id = "req-test-1";
        req.method = "apps.list";
        req.payload["limit"] = JsonValue(10);
        std::string serialized = SerializeRequest(req);

        BrokerRequest parsed_req;
        std::string err;
        Assert(ParseRequest(serialized, parsed_req, err), "ParseRequest valid");
        Assert(parsed_req.protocol == 21, "ParseRequest protocol 21");
        Assert(parsed_req.id == "req-test-1", "ParseRequest id");
        Assert(parsed_req.method == "apps.list", "ParseRequest method");
        Assert(parsed_req.payload["limit"].AsInt() == 10, "ParseRequest payload int");

        std::string huge_str(kMaxPayloadBytes + 10, 'A');
        JsonValue val;
        Assert(!ParseJson(huge_str, val), "Reject oversized JSON string");
        Assert(!ParseJson("{\"x\":\"\\q\"}", val), "Reject invalid JSON escape");
        Assert(!ParseJson("{\"x\":\"\\u12xz\"}", val), "Reject invalid Unicode hex escape");
        Assert(!ParseJson("{\"x\":\"\\uD800\"}", val), "Reject lone high surrogate");
        Assert(!ParseJson("{\"x\":\"\\uDC00\"}", val), "Reject lone low surrogate");
        Assert(!ParseJson("{\"x\":01}", val), "Reject leading-zero number");
        Assert(!ParseJson("{\"x\":1.}", val), "Reject fraction without digits");
        Assert(!ParseJson("{\"x\":1e}", val), "Reject exponent without digits");
        Assert(!ParseJson("{\"x\":9223372036854775808}", val), "Reject int64 overflow");
        Assert(!ParseJson("{\"x\":1e9999}", val), "Reject non-finite float overflow");
        Assert(!ParseJson("{\"x\":1,\"x\":2}", val), "Reject duplicate object keys");

        std::string deep = "0";
        for (int i = 0; i < 70; ++i) deep = "[" + deep + "]";
        Assert(!ParseJson(deep, val), "Reject excessive JSON nesting");

        const std::string bad_payload =
            "{\"protocol\":21,\"type\":\"request\",\"id\":\"x\",\"method\":\"apps.list\",\"payload\":[]}";
        BrokerRequest bad_req;
        err.clear();
        Assert(!ParseRequest(bad_payload, bad_req, err), "Reject non-object request payload");

        BrokerResponse res;
        res.protocol = kProtocolVersion;
        res.id = "res-test-1";
        res.ok = true;
        res.payload["result"] = JsonValue("ok");
        std::string ser_res = SerializeResponse(res);
        BrokerResponse parsed_res;
        Assert(ParseResponse(ser_res, parsed_res, err), "ParseResponse valid");
        Assert(parsed_res.ok, "ParseResponse ok");
        Assert(parsed_res.payload["result"].AsString() == "ok", "ParseResponse payload");

        BrokerResponse bad_res;
        err.clear();
        Assert(
            !ParseResponse("{\"protocol\":21,\"type\":\"response\",\"id\":\"x\",\"ok\":false,\"payload\":{}}", bad_res, err),
            "Reject failed response without typed error object");

        BrokerEvent bad_event;
        err.clear();
        Assert(
            !ParseEvent("{\"protocol\":21,\"type\":\"event\",\"event\":\"x\",\"payload\":{},\"timestamp\":-1}", bad_event, err),
            "Reject negative event timestamp");
    }

    // 2. Test Security & Named Pipe ACLs
    {
        std::wstring sid = SecurityV21::GetCurrentUserSidString();
        Assert(!sid.empty(), "User SID string not empty");
        DWORD session = SecurityV21::GetCurrentSessionId();
        Assert(session >= 0, "Session ID valid");

        std::wstring cmd_pipe = SecurityV21::GetCommandPipeName();
        Assert(cmd_pipe.find(L"\\\\.\\pipe\\CloudOS.SystemBroker.v21.") == 0, "Command pipe prefix valid");

        SECURITY_ATTRIBUTES sa{};
        PSECURITY_DESCRIPTOR sd = nullptr;
        Assert(SecurityV21::CreatePerUserSecurityAttributes(&sa, &sd), "CreatePerUserSecurityAttributes succeeds");
        Assert(sa.lpSecurityDescriptor != nullptr, "SecurityDescriptor not null");
        SecurityV21::FreeSecurityDescriptor(sd);
    }

    // 3. Test Event Bus & Subscriptions
    {
        EventBusV21::Instance().Reset();
        bool received_volume = false;
        bool received_wildcard = false;

        EventBusV21::Instance().RegisterClient("client-a", [&](const BrokerEvent& ev) {
            if (ev.event == "system.volumeChanged") received_volume = true;
            if (ev.event.find("system.") == 0) received_wildcard = true;
        });

        Assert(EventBusV21::Instance().Subscribe("client-a", "system.*"), "Subscribe client-a to system.*");
        Assert(EventBusV21::Instance().GetSubscriberCount("system.volumeChanged") == 1, "Subscriber count 1");

        JsonObject payload;
        payload["volume"] = JsonValue(0.5);
        EventBusV21::Instance().Publish("system.volumeChanged", payload);

        Assert(received_volume, "Event dispatched to subscriber");
        Assert(received_wildcard, "Wildcard subscription matched");

        EventBusV21::Instance().UnregisterClient("client-a");
        Assert(EventBusV21::Instance().GetActiveClientCount() == 0, "Client count 0 after unregister");
    }

    // 4. Test Job Manager
    {
        JobManagerV21::Instance().Initialize(1);
        std::string job_id = JobManagerV21::Instance().SubmitJob("test.job", [](std::atomic_bool&, std::function<void(double)> progress_cb, std::string&) {
            progress_cb(0.5);
            return true;
        });

        Assert(!job_id.empty(), "Job submitted with valid ID");
        JobInfo info;
        Assert(JobManagerV21::Instance().GetJobInfo(job_id, info), "GetJobInfo succeeds");
        Assert(info.type == "test.job", "Job type matches");
        JobManagerV21::Instance().Shutdown();
    }

    // 5. Test App Service & Safe ID Validation
    {
        const auto apps = AppServiceV21::Instance().GetApps();
        Assert(!apps.empty(), "App catalog contains items");
        Assert(AppServiceV21::Instance().GetGeneration() >= 1, "App generation >= 1");

        std::string err;
        Assert(!AppServiceV21::Instance().LaunchApp("calc.exe && malicious_command", err), "Arbitrary command injection rejected");
        Assert(!AppServiceV21::Instance().LaunchApp("powershell.exe -enc AAAAA", err), "Arbitrary PowerShell rejected");
        Assert(!err.empty(), "Error message populated on invalid app ID");
    }

    // 6. Test System Service with capability-aware physical controls
    {
        const auto snap = SystemServiceV21::Instance().GetSnapshot();
        Assert(!snap.device_name.empty(), "Device name not empty");
        Assert(snap.volume >= 0.0 && snap.volume <= 1.0, "Volume in range [0, 1]");
        Assert(snap.brightness >= 0.0 && snap.brightness <= 1.0, "Brightness in range [0, 1]");

        const bool volume_result = SystemServiceV21::Instance().SetVolume(0.88);
        if (snap.volume_available)
        {
            Assert(volume_result, "SetVolume succeeds when audio endpoint is available");
            Assert(
                std::abs(SystemServiceV21::Instance().GetSnapshot().volume - 0.88) <= 0.02,
                "Volume update reflected in snapshot");
        }
        else
        {
            Assert(!volume_result, "SetVolume fails cleanly when audio endpoint is unavailable");
        }

        const bool brightness_result = SystemServiceV21::Instance().SetBrightness(0.64);
        if (snap.brightness_available)
        {
            Assert(brightness_result, "SetBrightness succeeds when monitor control is available");
            Assert(
                std::abs(SystemServiceV21::Instance().GetSnapshot().brightness - 0.64) <= 0.02,
                "Brightness update reflected in snapshot");
        }
        else
        {
            Assert(!brightness_result, "SetBrightness fails cleanly when monitor control is unavailable");
        }

        const auto caps = SystemServiceV21::Instance().GetCapabilities();
        Assert(caps.size() >= 10, "Capabilities list populated");
    }

    // 7. Test WSL Service
    {
        bool wsl = WslServiceV21::Instance().IsWslAvailable();
        const auto distros = WslServiceV21::Instance().GetDistributions();
        if (wsl)
        {
            Assert(!distros.empty(), "WSL distros list populated if WSL is available");
        }
    }

    // 8. Test Diagnostics Snapshot
    {
        DiagnosticsV21::Initialize();
        JsonObject diag = DiagnosticsV21::GetDiagnosticsSnapshot();
        Assert(diag["brokerVersion"].AsString() == "21.0.0", "Diagnostics brokerVersion");
        Assert(diag["protocolVersion"].AsInt() == 21, "Diagnostics protocolVersion 21");
    }

    std::cout << "[PASS] CloudOS System Broker V21 Self-Test Passed (" << assertions << " assertions verified)." << std::endl;
    return 0;
}

} // namespace CloudOS

int main(int argc, char* argv[])
{
    SetConsoleCtrlHandler(CloudOS::ConsoleCtrlHandler, TRUE);

    for (int i = 1; i < argc; ++i)
    {
        std::string arg = argv[i];
        if (arg == "--self-test")
        {
            return CloudOS::RunSelfTest();
        }
        if (arg == "--diagnostics")
        {
            CloudOS::DiagnosticsV21::Initialize();
            std::cout << CloudOS::SerializeJson(CloudOS::JsonValue(CloudOS::DiagnosticsV21::GetDiagnosticsSnapshot())) << std::endl;
            return 0;
        }
        if (arg == "--help" || arg == "-h")
        {
            std::cout << "CloudOS System Broker V21\n"
                      << "Usage: CloudOS.SystemBroker.exe [OPTIONS]\n"
                      << "Options:\n"
                      << "  --self-test    Run in-process self-test verification suite\n"
                      << "  --diagnostics  Output technical diagnostics JSON snapshot\n"
                      << "  --help         Show this help information\n";
            return 0;
        }
    }

    std::cout << "[SystemBroker] Starting CloudOS System Broker V21 (Protocol " << CloudOS::kProtocolVersion << ")..." << std::endl;

    if (!CloudOS::BrokerServerV21::Instance().Start())
    {
        std::cerr << "[SystemBroker] Failed to start broker server." << std::endl;
        return 1;
    }

    std::cout << "[SystemBroker] Broker ready and listening on user named pipe." << std::endl;

    while (!CloudOS::g_shutdown_requested.load())
    {
        Sleep(500);
    }

    std::cout << "[SystemBroker] Shutting down cleanly..." << std::endl;
    CloudOS::BrokerServerV21::Instance().Stop();
    std::cout << "[SystemBroker] Shutdown complete." << std::endl;
    return 0;
}
