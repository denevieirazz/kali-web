#include "../../desktop/CloudOS.FlutterShell/native_bridge/cloudos_managed_win32_host_v22.h"
#include <cstdio>
#include <stdexcept>

namespace CloudOS {
struct ManagedWin32HostV22Tests {
    using Host = ManagedWin32HostV22;
    static void Require(bool value, const char* message) {
        if (!value) throw std::runtime_error(message);
    }
    static void Pump(DWORD duration) {
        const auto deadline = GetTickCount64() + duration;
        do {
            MSG message{};
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            Sleep(10);
        } while (GetTickCount64() < deadline);
    }
    static void Run(const wchar_t* executable, const wchar_t* desktop,
                    const wchar_t* arguments, bool expect_ambiguous, bool real_notepad) {
        Host::Session launch{};
        std::vector<HWND> hosts;
        HWND parent = nullptr;
        try {
            launch.job = CreateJobObjectW(nullptr, nullptr);
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            Require(launch.job && SetInformationJobObject(launch.job,
                JobObjectExtendedLimitInformation, &limits, sizeof(limits)), "job setup");
            STARTUPINFOW startup{};
            startup.cb = sizeof(startup);
            startup.lpDesktop = const_cast<wchar_t*>(desktop);
            PROCESS_INFORMATION process{};
            std::wstring command = L"\"" + std::wstring(executable) + L"\" " + arguments;
            Require(CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE,
                CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process) != FALSE, "create fixture");
            launch.process = process.hProcess;
            launch.thread = process.hThread;
            if (!AssignProcessToJobObject(launch.job, launch.process)) {
                TerminateProcess(launch.process, 1);
                Require(false, "assign fixture job");
            }
            Require(ResumeThread(launch.thread) != static_cast<DWORD>(-1), "resume fixture");
            WaitForInputIdle(launch.process, 1500);
            std::vector<HWND> windows;
            const auto result = Host::WaitForAttributedWindows(launch.job, 5000, windows);
            if (result != Host::WindowWaitResult::Found && !expect_ambiguous) {
                Host::JobProcessSnapshot snapshot{};
                Host::WindowSearch search{};
                const bool queried = Host::QueryJobProcessSnapshot(launch.job, snapshot);
                const bool enumerated = Host::EnumerateJobTopLevelWindows(snapshot, search);
                std::printf("snapshot=%d assigned=%lu processes=%lu enum=%d error=%lu\n", queried,
                    snapshot.assigned_processes, snapshot.process_id_count, enumerated, GetLastError());
                std::printf("discovery=%d count=%lu unknown=%d\n", static_cast<int>(result), search.count, search.unapproved_window);
                for (DWORD i = 0; i < search.count && i < Host::kMaxManagedWindows; ++i) {
                    wchar_t class_name[256]{};
                    GetClassNameW(search.windows[i], class_name, 256);
                    std::wprintf(L"class=%ls\n", class_name);
                }
            }
            if (expect_ambiguous) {
                Require(result == Host::WindowWaitResult::Ambiguous, "unknown drawable window must fail closed");
                std::puts("PASS unknown/visible helper rejected");
            } else {
                Require(result == Host::WindowWaitResult::Found, "discover approved window set");
                Require(real_notepad ? !windows.empty() : windows.size() == 4, "all document windows discovered");
                Require(Host::EnsureHostClass(), "register frame class");
                parent = CreateWindowExW(0, L"STATIC", L"CloudOS containment test",
                    WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, 1200, 900,
                    nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
                Require(parent != nullptr, "test desktop parent");
                Host::Session initializing{};
                initializing.app_window = windows.front();
                initializing.job = launch.job;
                initializing.host_window = CreateWindowExW(0, Host::HostClassName(), L"Initializing frame",
                    WS_CHILD, 0, 0, 500, 400, parent, nullptr, GetModuleHandleW(nullptr), &initializing);
                Require(initializing.host_window != nullptr, "initializing host exists");
                SendMessageW(initializing.host_window, WM_SIZE, 0, 0);
                Require(IsWindow(initializing.host_window) && IsWindow(windows.front()),
                    "reentrant layout during embedding must not kill the session");
                DestroyWindow(initializing.host_window);
                std::puts("PASS reentrant layout deferred until embedding completes");
                for (HWND window : windows) {
                    auto session = std::make_unique<Host::Session>();
                    session->app_window = window;
                    session->title = L"Containment test";
                    Require(DuplicateHandle(GetCurrentProcess(), launch.job, GetCurrentProcess(),
                        &session->job, 0, FALSE, DUPLICATE_SAME_ACCESS) != FALSE, "share job handle");
                    HWND frame = nullptr;
                    std::string error;
                    const bool embedded = Host::CreateManagedFrame(parent, session, frame, error);
                    if (!embedded && session) Host::CleanupSessionHandles(*session);
                    if (!embedded) throw std::runtime_error(error);
                    hosts.push_back(frame);
                }
                std::string monitor_error;
                Require(Host::ArmManagedFrames(hosts, monitor_error), "arm completed group monitoring");
                for (HWND frame : hosts) {
                    auto& session = *Host::Sessions().at(frame);
                    Require(Host::ValidateContainedSession(session), "all windows contained with helpers excluded");
                    Require(GetParent(session.app_window) == frame, "document belongs to its CloudOS frame");
                }
                std::printf("PASS embedded documents=%zu; health and parent/style checks\n", windows.size());
                if (!real_notepad) {
                    // Closing one host is delivered to just that document. The
                    // other handles keep its shared job and sibling UI alive.
                    SendMessageW(hosts.front(), WM_CLOSE, 0, 0);
                    Pump(600);
                    Require(!IsWindow(hosts.front()), "closed document frame retired");
                    Require(IsWindow(windows.back()), "sibling document survived close");
                    Require(WaitForSingleObject(launch.process, 0) == WAIT_TIMEOUT, "shared process survived close");
                    std::puts("PASS close-one preserves sibling documents");
                    HWND helper = FindWindowExW(nullptr, nullptr,
                        L"CloudOS.ContainmentFixture.Helper", nullptr);
                    Require(helper != nullptr, "fixture helper exists");
                    Require(SetWindowPos(helper, nullptr, 0, 0, 40, 40,
                        SWP_NOACTIVATE | SWP_NOZORDER) != FALSE, "helper becomes drawable");
                    auto& remaining = *Host::Sessions().at(hosts.back());
                    Require(!Host::ValidateContainedSession(remaining), "new drawable helper is an escape");
                    Host::FailClosedHost(hosts.back(), remaining);
                    Require(WaitForSingleObject(launch.process, 3000) == WAIT_OBJECT_0,
                        "escape terminates only the fixture containment job");
                    std::puts("PASS newly drawable helper detected and job stopped");
                }
            }
        } catch (...) {
            if (launch.job) TerminateJobObject(launch.job, 1);
            for (HWND frame : hosts) if (IsWindow(frame)) DestroyWindow(frame);
            if (parent) DestroyWindow(parent);
            Host::CleanupSessionHandles(launch);
            throw;
        }
        TerminateJobObject(launch.job, 0);
        WaitForSingleObject(launch.process, 3000);
        for (HWND frame : hosts) if (IsWindow(frame)) DestroyWindow(frame);
        if (parent) DestroyWindow(parent);
        Host::CleanupSessionHandles(launch);
    }
};
}

int wmain(int argc, wchar_t** argv) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    if (argc > 1 && std::wstring_view(argv[1]) == L"--fixture") {
        WNDCLASSW wc{};
        wc.lpfnWndProc = DefWindowProcW;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = L"Notepad";
        RegisterClassW(&wc);
        for (int i = 0; i < 4; ++i)
            CreateWindowExW(0, L"Notepad", L"Synthetic document", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                20, 20, 640, 480, nullptr, nullptr, wc.hInstance, nullptr);
        const bool visible_helper = argc > 2;
        wc.lpszClassName = L"CloudOS.ContainmentFixture.Helper";
        RegisterClassW(&wc);
        CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, wc.lpszClassName, L"Synthetic input helper",
            WS_POPUP | WS_VISIBLE, 0, 0, visible_helper ? 40 : 0, visible_helper ? 40 : 0,
            nullptr, nullptr, wc.hInstance, nullptr);
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0) DispatchMessageW(&message);
        return 0;
    }
    // Runtime regression owns an isolated non-input desktop. It neither switches
    // the user's desktop nor enumerates/operates unrelated application windows.
    const std::wstring name = L"CloudOSContainmentTest_" + std::to_wstring(GetCurrentProcessId());
    HDESK original = GetThreadDesktop(GetCurrentThreadId());
    HDESK desktop = CreateDesktopW(name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
    if (!desktop || !SetThreadDesktop(desktop)) return 2;
    int result = 0;
    try {
        wchar_t executable[MAX_PATH]{};
        GetModuleFileNameW(nullptr, executable, MAX_PATH);
        CloudOS::ManagedWin32HostV22Tests::Run(executable, name.c_str(), L"--fixture", false, false);
        CloudOS::ManagedWin32HostV22Tests::Run(executable, name.c_str(), L"--fixture --visible-helper", true, false);
        if (argc > 1 && std::wstring_view(argv[1]) == L"--real-notepad") {
            wchar_t directory[MAX_PATH]{};
            GetWindowsDirectoryW(directory, MAX_PATH);
            const auto notepad = std::wstring(directory) + L"\\notepad.exe";
            CloudOS::ManagedWin32HostV22Tests::Run(notepad.c_str(), name.c_str(), L"", false, true);
        }
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL %s\n", error.what());
        result = 1;
    }
    SetThreadDesktop(original);
    CloseDesktop(desktop);
    return result;
}
