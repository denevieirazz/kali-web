#include "app_service_v21.h"
#include "broker_server_v21.h"
#include "diagnostics_v21.h"
#include "event_bus_v21.h"
#include "file_service_v22.h"
#include "job_manager_v21.h"
#include "protocol_v21.h"
#include "security_v21.h"
#include "system_service_v21.h"
#include "wsl_service_v21.h"

#include <csignal>
#include <chrono>
#include <iostream>
#include <limits>
#include <string_view>

namespace CloudOS
{

namespace
{
std::atomic_bool g_shutdown_requested{false};

std::string Utf16ToUtf8Strict(std::wstring_view value)
{
    if (value.empty()) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string result(static_cast<size_t>(required), '\0');
    const int written = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        required,
        nullptr,
        nullptr);
    return written == required ? result : std::string{};
}

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
    std::cout << "[SystemBroker] Running V22.1 Self-Test Suite..." << std::endl;
    int assertions = 0;

    auto Assert = [&assertions](bool cond, const std::string& name) {
        if (!cond)
        {
            std::cerr << "[FAIL] Assertion failed: " << name << std::endl;
            exit(1);
        }
        assertions++;
    };

    // 1. Test Protocol Serialization, Parsing, and malformed-input rejection.
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
        Assert(!ParseRequest(
            R"({"protocol":21,"type":"request","id":"bad","method":"apps.list","payload":[]})",
            parsed_req,
            err),
            "Reject non-object request payload");
        Assert(!ParseJson(R"({"bad":"\q"})", val), "Reject invalid JSON escape");
        Assert(!ParseJson(R"({"n":9223372036854775808})", val), "Reject overflowing JSON integer");

        std::string deep_json;
        for (int i = 0; i < 70; ++i) deep_json.push_back('[');
        deep_json += "0";
        for (int i = 0; i < 70; ++i) deep_json.push_back(']');
        Assert(!ParseJson(deep_json, val), "Reject excessive JSON nesting");

        Assert(ParseJson(R"({"text":"\u00e3\u6f22\u5b57"})", val), "Parse escaped Unicode JSON");
        Assert(val.AsObject().at("text").AsString() == "ã漢字", "Decode escaped Unicode as UTF-8");

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
            progress_cb(50.0);
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

    // 6. Test System Service
    {
        const auto snap = SystemServiceV21::Instance().GetSnapshot();
        Assert(!snap.device_name.empty(), "Device name not empty");
        Assert(snap.volume >= 0.0 && snap.volume <= 1.0, "Volume in range [0, 1]");

        Assert(!SystemServiceV21::Instance().SetVolume(-1.0), "SetVolume rejects negative values");
        Assert(!SystemServiceV21::Instance().SetVolume(2.0), "SetVolume rejects values above one");
        Assert(!SystemServiceV21::Instance().SetVolume(std::numeric_limits<double>::quiet_NaN()), "SetVolume rejects NaN");
        if (snap.volume_available)
        {
            Assert(SystemServiceV21::Instance().SetVolume(snap.volume), "SetVolume accepts current real endpoint value");
        }
        else
        {
            Assert(!SystemServiceV21::Instance().SetVolume(0.5), "SetVolume reports unavailable endpoint");
        }

        const auto caps = SystemServiceV21::Instance().GetCapabilities();
        Assert(caps.size() >= 10, "Capabilities list populated");
    }

    // 7. Test WSL Service. WSL can be installed with zero configured distros.
    {
        const bool wsl = WslServiceV21::Instance().IsWslAvailable();
        const auto distros = WslServiceV21::Instance().GetDistributions();
        Assert(wsl || distros.empty(), "No distributions reported when WSL is unavailable");
    }

    // 8. Test Diagnostics Snapshot
    {
        DiagnosticsV21::Initialize();
        JsonObject diag = DiagnosticsV21::GetDiagnosticsSnapshot();
        Assert(diag["brokerVersion"].AsString() == "21.0.0", "Diagnostics brokerVersion");
        Assert(diag["protocolVersion"].AsInt() == 21, "Diagnostics protocolVersion 21");
    }

    // 9. Test FileService V22
    {
        JsonObject kf = FileServiceV22::Instance().GetKnownFolders();
        Assert(kf["folders"].IsArray(), "Known folders returns array");
        Assert(!kf["folders"].AsArray().empty(), "Known folders is not empty");

        JsonObject drv = FileServiceV22::Instance().GetDrives();
        Assert(drv["drives"].IsArray(), "Drives returns array");
        Assert(!drv["drives"].AsArray().empty(), "Drives is not empty");

        wchar_t temp_path[MAX_PATH] = {0};
        Assert(GetTempPathW(MAX_PATH, temp_path) > 0, "Resolve Windows temporary directory");
        std::wstring test_dir = std::wstring(temp_path) + L"cloudos_v22_selftest_" +
            std::to_wstring(GetCurrentProcessId()) + L"_" + std::to_wstring(GetTickCount64());
        Assert(CreateDirectoryW(test_dir.c_str(), nullptr) != FALSE, "Create isolated V22 self-test directory");

        const std::string test_dir_utf8 = Utf16ToUtf8Strict(test_dir);
        Assert(!test_dir_utf8.empty(), "Convert self-test directory to UTF-8 without overflow");

        JsonObject create_res = FileServiceV22::Instance().CreateFolder(test_dir_utf8, "Pasta_Teste_ãéíóú_漢字");
        Assert(create_res["ok"].AsBool(), "Create folder with Unicode");

        JsonObject list_res = FileServiceV22::Instance().ListDirectory(test_dir_utf8);
        Assert(list_res["items"].IsArray(), "List items is array");
        Assert(list_res["items"].AsArray().size() == 1, "List items has 1 entry");

        std::wstring test_file = test_dir + L"\\teste_arquivo.txt";
        HANDLE hFile = CreateFileW(test_file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        Assert(hFile != INVALID_HANDLE_VALUE, "Create isolated self-test file");
        const char* data = "CloudOS V22 Unified Files Self Test";
        DWORD written = 0;
        Assert(WriteFile(hFile, data, static_cast<DWORD>(strlen(data)), &written, nullptr) != FALSE &&
            written == static_cast<DWORD>(strlen(data)), "Write isolated self-test file");
        CloseHandle(hFile);

        const std::string test_file_utf8 = test_dir_utf8 + "\\teste_arquivo.txt";
        JsonObject meta_res = FileServiceV22::Instance().GetMetadata(test_file_utf8);
        Assert(meta_res["name"].AsString() == "teste_arquivo.txt", "GetMetadata file name");
        Assert(!meta_res["isDirectory"].AsBool(), "GetMetadata isDirectory false");
        Assert(meta_res["size"].AsDouble() > 0, "GetMetadata file size > 0");

        JsonObject ow_res = FileServiceV22::Instance().GetOpenWithList(test_file_utf8);
        Assert(ow_res["apps"].IsArray(), "Open with returns apps array");

        JsonObject ren_res = FileServiceV22::Instance().RenameItem(test_file_utf8, "teste_arquivo_renomeado.txt");
        Assert(ren_res["ok"].AsBool(), "Rename item");

        const std::string renamed_file_utf8 = test_dir_utf8 + "\\teste_arquivo_renomeado.txt";
        const std::string subfolder_utf8 = test_dir_utf8 + "\\Pasta_Teste_ãéíóú_漢字";
        JsonObject del_res = FileServiceV22::Instance().DeleteItems({renamed_file_utf8, subfolder_utf8}, true);
        Assert(del_res["ok"].AsBool(), "Delete items permanent");
        Assert(RemoveDirectoryW(test_dir.c_str()) != FALSE, "Remove isolated V22 self-test directory");
    }

    // 10. Broker shutdown must interrupt an idle connected client instead of
    // deadlocking while ClientSessionLoop is blocked in ReadFile.
    {
        Assert(BrokerServerV21::Instance().Start(), "Broker starts for shutdown regression");
        Sleep(150);
        HANDLE idle_client = CreateFileW(
            SecurityV21::GetCommandPipeName().c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr);
        Assert(idle_client != INVALID_HANDLE_VALUE, "Idle broker client connected");
        Sleep(100);
        const auto stop_started = std::chrono::steady_clock::now();
        BrokerServerV21::Instance().Stop();
        const auto stop_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - stop_started).count();
        Assert(stop_ms < 3000, "Broker shutdown with idle client is bounded");
        if (idle_client != INVALID_HANDLE_VALUE) CloseHandle(idle_client);
    }

    std::cout << "[PASS] CloudOS System Broker V22.1 Self-Test Passed (" << assertions << " assertions verified)." << std::endl;
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
            std::cout << "CloudOS System Broker V22.1\n"
                      << "Usage: CloudOS.SystemBroker.exe [OPTIONS]\n"
                      << "Options:\n"
                      << "  --self-test    Run in-process self-test verification suite\n"
                      << "  --diagnostics  Output technical diagnostics JSON snapshot\n"
                      << "  --help         Show this help information\n";
            return 0;
        }
    }

    std::cout << "[SystemBroker] Starting CloudOS System Broker V22.1 (Protocol " << CloudOS::kProtocolVersion << ")..." << std::endl;

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
