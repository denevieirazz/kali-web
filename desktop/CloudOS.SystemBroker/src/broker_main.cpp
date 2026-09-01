#include "app_service_v21.h"
#include "broker_server_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "job_manager_v21.h"
#include "protocol_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <atomic>
#include <csignal>
#include <iostream>
#include <string>

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
        ++assertions;
    };

    // 1. Protocol serialization, strict parsing and malformed-input handling.
    {
        BrokerRequest req;
        req.protocol = kProtocolVersion;
        req.id = "req-test-1";
        req.method = "apps.list";
        req.payload["limit"] = JsonValue(10);
        const std::string serialized = SerializeRequest(req);

        BrokerRequest parsed_req;
        std::string err;
        Assert(ParseRequest(serialized, parsed_req, err), "ParseRequest valid");
        Assert(parsed_req.protocol == 21, "ParseRequest protocol 21");
        Assert(parsed_req.id == "req-test-1", "ParseRequest id");
        Assert(parsed_req.method == "apps.list", "ParseRequest method");
        Assert(parsed_req.payload["limit"].AsInt() == 10, "ParseRequest payload int");

        std::string huge_str(kMaxPayloadBytes + 10, 'A');
        JsonValue value;
        Assert(!ParseJson(huge_str, value), "Reject oversized JSON string");
        Assert(!ParseJson("{\"n\":01}", value), "Reject leading-zero number");
        Assert(!ParseJson("{\"n\":1e}", value), "Reject malformed exponent");
        Assert(!ParseJson("{\"s\":\"\\q\"}", value), "Reject invalid string escape");
        Assert(!ParseJson("{\"a\":1,\"a\":2}", value), "Reject duplicate object key");
        Assert(ParseJson("{\"s\":\"CloudOS \\u2601\"}", value), "Accept valid Unicode escape");

        std::string nested;
        for (int i = 0; i < 70; ++i) nested.push_back('[');
        nested.append("0");
        for (int i = 0; i < 70; ++i) nested.push_back(']');
        Assert(!ParseJson(nested, value), "Reject excessive JSON nesting");

        BrokerResponse res;
        res.protocol = kProtocolVersion;
        res.id = "res-test-1";
        res.ok = true;
        res.payload["result"] = JsonValue("ok");
        const std::string ser_res = SerializeResponse(res);
        BrokerResponse parsed_res;
        Assert(ParseResponse(ser_res, parsed_res, err), "ParseResponse valid");
        Assert(parsed_res.ok, "ParseResponse ok");
        Assert(parsed_res.payload["result"].AsString() == "ok", "ParseResponse payload");

        Assert(
            !ParseRequest(
                "{\"protocol\":21,\"type\":\"request\",\"id\":\"x\",\"method\":\"health.ping\",\"payload\":[]}",
                parsed_req,
                err),
            "Reject non-object request payload");
    }

    // 2. Security & named-pipe ACLs.
    {
        const std::wstring sid = SecurityV21::GetCurrentUserSidString();
        Assert(!sid.empty(), "User SID string not empty");

        const std::wstring cmd_pipe = SecurityV21::GetCommandPipeName();
        Assert(cmd_pipe.find(L"\\\\.\\pipe\\CloudOS.SystemBroker.v21.") == 0, "Command pipe prefix valid");

        SECURITY_ATTRIBUTES sa{};
        PSECURITY_DESCRIPTOR sd = nullptr;
        Assert(SecurityV21::CreatePerUserSecurityAttributes(&sa, &sd), "CreatePerUserSecurityAttributes succeeds");
        Assert(sa.lpSecurityDescriptor != nullptr, "SecurityDescriptor not null");
        Assert(sa.bInheritHandle == FALSE, "Pipe security handle is non-inheritable");

        BOOL dacl_present = FALSE;
        BOOL dacl_defaulted = FALSE;
        PACL dacl = nullptr;
        Assert(
            GetSecurityDescriptorDacl(sd, &dacl_present, &dacl, &dacl_defaulted) != FALSE,
            "Security descriptor exposes DACL");
        Assert(dacl_present != FALSE && dacl != nullptr, "Security descriptor DACL is present");
        SecurityV21::FreeSecurityDescriptor(sd);
    }

    // 3. Event bus, bounded subscriptions and pattern validation.
    {
        EventBusV21::Instance().Reset();
        bool received_volume = false;
        bool received_wildcard = false;

        EventBusV21::Instance().RegisterClient("client-a", [&](const BrokerEvent& ev) {
            if (ev.event == "system.volumeChanged") received_volume = true;
            if (ev.event.find("system.") == 0) received_wildcard = true;
        });

        Assert(EventBusV21::Instance().Subscribe("client-a", "system.*"), "Subscribe client-a to system.*");
        Assert(!EventBusV21::Instance().Subscribe("client-a", "system.*.bad"), "Reject mid-pattern wildcard");
        Assert(!EventBusV21::Instance().Subscribe("client-a", "bad pattern"), "Reject unsafe subscription characters");
        Assert(EventBusV21::Instance().GetSubscriberCount("system.volumeChanged") == 1, "Subscriber count 1");

        JsonObject payload;
        payload["volume"] = JsonValue(0.5);
        EventBusV21::Instance().Publish("system.volumeChanged", payload);

        Assert(received_volume, "Event dispatched to subscriber");
        Assert(received_wildcard, "Wildcard subscription matched");
        Assert(EventBusV21::Instance().Unsubscribe("client-a", "system.*"), "Unsubscribe existing pattern");
        Assert(!EventBusV21::Instance().Unsubscribe("client-a", "system.*"), "Unsubscribe missing pattern returns false");

        for (int i = 0; i < 64; ++i)
        {
            Assert(
                EventBusV21::Instance().Subscribe("client-a", "test." + std::to_string(i)),
                "Bounded event subscription accepted");
        }
        Assert(!EventBusV21::Instance().Subscribe("client-a", "test.overflow"), "Reject subscription beyond per-client limit");

        EventBusV21::Instance().UnregisterClient("client-a");
        Assert(EventBusV21::Instance().GetActiveClientCount() == 0, "Client count 0 after unregister");
    }

    // 4. Job manager state is observable and converges without races.
    {
        JobManagerV21::Instance().Initialize(1);
        const std::string job_id = JobManagerV21::Instance().SubmitJob(
            "test.job",
            [](std::atomic_bool&, std::function<void(double)> progress_cb, std::string&) {
                progress_cb(0.5);
                progress_cb(2.0); // Must be clamped to 1.0.
                return true;
            });

        Assert(!job_id.empty(), "Job submitted with valid ID");

        JobInfo info;
        bool terminal = false;
        for (int attempt = 0; attempt < 200; ++attempt)
        {
            Assert(JobManagerV21::Instance().GetJobInfo(job_id, info), "GetJobInfo succeeds");
            if (info.state == JobState::Completed || info.state == JobState::Failed || info.state == JobState::Cancelled)
            {
                terminal = true;
                break;
            }
            Sleep(5);
        }

        Assert(terminal, "Job reaches terminal state");
        Assert(info.type == "test.job", "Job type matches");
        Assert(info.state == JobState::Completed, "Job completed successfully");
        Assert(info.progress == 1.0, "Completed job progress is exactly 1.0");
        Assert(JobManagerV21::Instance().GetActiveJobCount() == 0, "No active jobs after completion");
        JobManagerV21::Instance().Shutdown();
    }

    // 5. App service & safe ID validation.
    {
        const auto apps = AppServiceV21::Instance().GetApps();
        Assert(!apps.empty(), "App catalog contains items");
        Assert(AppServiceV21::Instance().GetGeneration() >= 1, "App generation >= 1");

        std::string err;
        Assert(!AppServiceV21::Instance().LaunchApp("calc.exe && malicious_command", err), "Arbitrary command injection rejected");
        Assert(!AppServiceV21::Instance().LaunchApp("powershell.exe -enc AAAAA", err), "Arbitrary PowerShell rejected");
        Assert(!err.empty(), "Error message populated on invalid app ID");
    }

    // 6. System service. Physical capabilities are conditional on the runner.
    {
        const auto snap = SystemServiceV21::Instance().GetSnapshot();
        Assert(!snap.device_name.empty(), "Device name not empty");
        Assert(!snap.user_name.empty(), "User name not empty");
        Assert(snap.volume >= 0.0 && snap.volume <= 1.0, "Volume in range [0, 1]");
        Assert(snap.brightness >= 0.0 && snap.brightness <= 1.0, "Brightness in range [0, 1]");

        if (snap.volume_available)
        {
            Assert(SystemServiceV21::Instance().SetVolume(snap.volume), "SetVolume round-trip when endpoint exists");
        }
        else
        {
            Assert(!SystemServiceV21::Instance().SetVolume(0.5), "SetVolume reports unavailable without audio endpoint");
        }

        if (snap.brightness_available)
        {
            Assert(SystemServiceV21::Instance().SetBrightness(snap.brightness), "SetBrightness round-trip when monitor supports it");
        }
        else
        {
            Assert(!SystemServiceV21::Instance().SetBrightness(0.5), "SetBrightness reports unavailable when unsupported");
        }

        const auto caps = SystemServiceV21::Instance().GetCapabilities();
        Assert(caps.size() >= 10, "Capabilities list populated");
    }

    // 7. WSL service. WSL may be installed with zero registered distros.
    {
        const bool wsl = WslServiceV21::Instance().IsWslAvailable();
        const auto distros = WslServiceV21::Instance().GetDistributions();
        Assert(distros.empty() || wsl, "Registered WSL distros imply WSL availability");
    }

    // 8. Diagnostics snapshot.
    {
        DiagnosticsV21::Initialize();
        const JsonObject diag = DiagnosticsV21::GetDiagnosticsSnapshot();
        Assert(diag.at("brokerVersion").AsString() == "21.0.0", "Diagnostics brokerVersion");
        Assert(diag.at("protocolVersion").AsInt() == 21, "Diagnostics protocolVersion 21");
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
        const std::string arg = argv[i];
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

    std::cout << "[SystemBroker] Broker ready and listening on secure per-user named pipe." << std::endl;

    while (!CloudOS::g_shutdown_requested.load())
    {
        Sleep(500);
    }

    std::cout << "[SystemBroker] Shutting down cleanly..." << std::endl;
    CloudOS::BrokerServerV21::Instance().Stop();
    std::cout << "[SystemBroker] Shutdown complete." << std::endl;
    return 0;
}
