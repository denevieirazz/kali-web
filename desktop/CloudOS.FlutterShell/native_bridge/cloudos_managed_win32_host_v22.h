#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace CloudOS
{

// V22 containment boundary for classic Win32 applications launched from the
// Flutter shell. Dart never receives HWNDs, executable paths, or command lines.
// Every windows:* request is consumed here. If containment cannot be proven,
// the external launch is blocked and an owned CloudOS warning is shown so the
// legacy V20 caller cannot fall through to ShellExecute.
class ManagedWin32HostV22 final
{
public:
    static bool IsWindowsCatalogId(std::string_view app_id) noexcept
    {
        return app_id.rfind("windows:", 0) == 0;
    }

    static bool IsContainmentSupported(std::string_view app_id) noexcept
    {
        // CMD and PowerShell are CloudOS Terminal / ConPTY profiles. Keep the
        // generic cross-process HWND host deliberately narrow until physical
        // compatibility is proven for another classic Win32 application.
        return app_id == "windows:notepad";
    }

    // The bool means the Windows request was safely handled, not necessarily
    // that an application reached the running state. Returning true after an
    // explicit fail-closed warning is intentional: CloudOSFlutterBridgeV20 has
    // a historical fallback path and must never retry a windows:* request with
    // ShellExecute after V22 has rejected containment.
    static bool Launch(std::string_view app_id, std::string& error)
    {
        if (!IsWindowsCatalogId(app_id))
        {
            error = "ManagedWin32HostV22 only accepts windows catalog IDs";
            return false;
        }

        if (!IsContainmentSupported(app_id))
        {
            error = "This Windows application is not yet approved for CloudOS containment";
            return BlockLaunch(app_id, error);
        }

        HWND cloudos_window = FindCloudOSWindow();
        if (cloudos_window == nullptr)
        {
            error = "CloudOS host window was not found";
            return BlockLaunch(app_id, error);
        }

        LaunchSpec spec{};
        if (!ResolveLaunchSpec(app_id, spec, error))
        {
            return BlockLaunch(app_id, error);
        }

        auto session = std::make_unique<Session>();
        session->app_id = std::string(app_id);
        session->title = spec.title;
        session->job = CreateJobObjectW(nullptr, nullptr);
        if (session->job == nullptr)
        {
            error = "Could not create containment Job Object";
            return BlockLaunch(app_id, error);
        }

        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(
                session->job,
                JobObjectExtendedLimitInformation,
                &limits,
                sizeof(limits)))
        {
            error = "Could not configure containment Job Object";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        if (!CreateProcessW(
                spec.executable.c_str(),
                nullptr,
                nullptr,
                nullptr,
                FALSE,
                CREATE_SUSPENDED,
                nullptr,
                nullptr,
                &startup,
                &process))
        {
            error = "Could not start the allowlisted Windows application";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        session->process = process.hProcess;
        session->thread = process.hThread;
        session->primary_process_id = process.dwProcessId;

        if (!AssignProcessToJobObject(session->job, session->process))
        {
            TerminateProcess(session->process, ERROR_ACCESS_DENIED);
            error = "Windows application could not be assigned to the CloudOS containment job";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        BOOL primary_in_job = FALSE;
        if (!IsProcessInJob(session->process, session->job, &primary_in_job) || !primary_in_job)
        {
            TerminateJobObject(session->job, ERROR_ACCESS_DENIED);
            error = "CloudOS could not prove the launched process belongs to its containment job";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        if (ResumeThread(session->thread) == static_cast<DWORD>(-1))
        {
            TerminateJobObject(session->job, ERROR_PROCESS_ABORTED);
            error = "Windows application could not be resumed inside containment";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }
        CloseHandle(session->thread);
        session->thread = nullptr;

        // WaitForInputIdle is advisory. Job membership + stable HWND set
        // attribution below is the authority and works when a child process
        // becomes the UI owner.
        (void)WaitForInputIdle(session->process, 1500);

        std::vector<HWND> app_windows;
        const WindowWaitResult wait_result = WaitForAttributedWindows(
            session->job,
            kWindowDiscoveryTimeoutMs,
            app_windows);
        if (wait_result != WindowWaitResult::Found)
        {
            TerminateJobObject(session->job, ERROR_TIMEOUT);
            if (wait_result == WindowWaitResult::Ambiguous)
            {
                error = "Ambiguous top-level windows appeared in the containment job; launch failed closed";
            }
            else if (wait_result == WindowWaitResult::QueryFailure)
            {
                error = "CloudOS could not safely enumerate the containment job windows";
            }
            else
            {
                error = "No attributable top-level window appeared; launch was blocked to prevent escape";
            }
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        if (!EnsureHostClass())
        {
            TerminateJobObject(session->job, ERROR_INVALID_FUNCTION);
            error = "CloudOS managed-window host class is unavailable";
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        // Modern Notepad may restore several document windows. Contain every
        // attributed frame; never pick one and leave its siblings outside.
        std::vector<HWND> hosts;
        for (HWND app_window : app_windows)
        {
            auto frame = std::make_unique<Session>();
            frame->app_id = session->app_id;
            frame->title = session->title;
            frame->app_window = app_window;
            HWND host = nullptr;
            if (!DuplicateHandle(GetCurrentProcess(), session->job,
                    GetCurrentProcess(), &frame->job, 0, FALSE, DUPLICATE_SAME_ACCESS) ||
                !CreateManagedFrame(cloudos_window, frame, host, error))
            {
                if (error.empty()) error = "Could not retain the managed application job";
                TerminateJobObject(session->job, ERROR_INVALID_STATE);
                if (frame) CleanupSessionHandles(*frame);
                for (HWND created : hosts) DestroyWindow(created);
                CleanupSessionHandles(*session);
                return BlockLaunch(app_id, error);
            }
            hosts.push_back(host);
        }
        if (!ArmManagedFrames(hosts, error))
        {
            TerminateJobObject(session->job, ERROR_INVALID_STATE);
            for (HWND host : hosts) DestroyWindow(host);
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }
        CleanupSessionHandles(*session);
        return true;
    }

private:
    friend struct ManagedWin32HostV22Tests;

    enum class WindowWaitResult
    {
        Found,
        NoWindow,
        Ambiguous,
        QueryFailure,
    };

    struct LaunchSpec final
    {
        std::wstring executable;
        std::wstring title;
    };

    struct Session final
    {
        std::string app_id;
        std::wstring title;
        HANDLE job{nullptr};
        HANDLE process{nullptr};
        HANDLE thread{nullptr};
        DWORD primary_process_id{0};
        HWND host_window{nullptr};
        HWND app_window{nullptr};
        RECT restore_rect{};
        bool maximized{false};
        bool closing{false};
        bool embedding{true};
    };

    static bool CreateManagedFrame(
        HWND cloudos_window, std::unique_ptr<Session>& session,
        HWND& created_host, std::string& error)
    {
        created_host = nullptr;
        RECT initial{};
        if (!InitialHostRect(cloudos_window, initial))
        {
            TerminateJobObject(session->job, ERROR_INVALID_WINDOW_HANDLE);
            error = "CloudOS could not determine a safe managed-window rectangle";
            CleanupSessionHandles(*session);
            return false;
        }

        HWND host = CreateWindowExW(
            WS_EX_CONTROLPARENT,
            HostClassName(),
            session->title.c_str(),
            WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS |
                WS_CAPTION | WS_THICKFRAME | WS_SYSMENU |
                WS_MINIMIZEBOX | WS_MAXIMIZEBOX,
            initial.left,
            initial.top,
            initial.right - initial.left,
            initial.bottom - initial.top,
            cloudos_window,
            nullptr,
            GetModuleHandleW(nullptr),
            session.get());
        if (host == nullptr)
        {
            TerminateJobObject(session->job, ERROR_NOT_ENOUGH_MEMORY);
            error = "CloudOS could not create the managed application frame";
            CleanupSessionHandles(*session);
            return false;
        }

        session->host_window = host;
        if (!EmbedApplicationWindow(*session, error))
        {
            TerminateJobObject(session->job, ERROR_INVALID_STATE);
            DestroyWindow(host);
            CleanupSessionHandles(*session);
            return false;
        }

        session->embedding = false;
        {
            std::lock_guard<std::mutex> lock(SessionsMutex());
            Sessions().emplace(host, std::move(session));
        }

        ShowWindow(host, SW_SHOW);
        if (!SetWindowPos(
                host,
                HWND_TOP,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW))
        {
            error = "CloudOS could not activate the managed application frame";
            DestroyWindow(host);
            return false;
        }

        HWND embedded = FindEmbeddedWindow(host);
        if (embedded != nullptr && IsWindow(embedded))
        {
            SetFocus(embedded);
        }
        created_host = host;
        return true;
    }

    static bool ArmManagedFrames(const std::vector<HWND>& hosts, std::string& error)
    {
        // Cross-process window calls may pump messages. A timer armed on the
        // first frame would see its not-yet-embedded siblings as escapes.
        // Validate the complete group before enabling ongoing monitoring.
        for (HWND host : hosts)
        {
            const auto it = Sessions().find(host);
            if (it == Sessions().end() || !ValidateContainedSession(*it->second))
            {
                error = "CloudOS could not verify the complete managed window group";
                return false;
            }
        }
        for (HWND host : hosts)
        {
            if (SetTimer(host, kHealthTimerId, kHealthTimerIntervalMs, nullptr) == 0)
            {
                error = "CloudOS could not start containment health monitoring";
                return false;
            }
        }
        return true;
    }

    static constexpr DWORD kMaxTrackedJobProcesses = 64;
    static constexpr DWORD kMaxManagedWindows = 16;

    struct JobProcessSnapshot final
    {
        DWORD assigned_processes{0};
        DWORD process_id_count{0};
        ULONG_PTR process_ids[kMaxTrackedJobProcesses]{};
    };

    struct WindowSearch final
    {
        const JobProcessSnapshot* processes{nullptr};
        HWND first{nullptr};
        DWORD count{0};
        bool query_failed{false};
        bool unapproved_window{false};
        HWND windows[kMaxManagedWindows]{};
    };

    struct ParentSearch final
    {
        DWORD process_id{0};
        HWND match{nullptr};
    };

    static constexpr int kTaskbarReservePx = 56;
    static constexpr int kDesktopMarginPx = 24;
    static constexpr UINT_PTR kHealthTimerId = 0xC105;
    static constexpr UINT kHealthTimerIntervalMs = 250;
    static constexpr DWORD kWindowDiscoveryTimeoutMs = 5000;
    static constexpr DWORD kStableWindowObservations = 4;
    static constexpr DWORD kWindowPollIntervalMs = 75;

    static const wchar_t* HostClassName() noexcept
    {
        return L"CloudOS.ManagedWin32Host.v22";
    }

    static std::unordered_map<HWND, std::unique_ptr<Session>>& Sessions()
    {
        static std::unordered_map<HWND, std::unique_ptr<Session>> sessions;
        return sessions;
    }

    static std::mutex& SessionsMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    static std::wstring Utf8ToWide(std::string_view value)
    {
        if (value.empty()) return {};
        const int required = MultiByteToWideChar(
            CP_UTF8,
            0,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0);
        if (required <= 0) return L"Unknown containment failure";

        std::wstring result(static_cast<std::size_t>(required), L'\0');
        if (MultiByteToWideChar(
                CP_UTF8,
                0,
                value.data(),
                static_cast<int>(value.size()),
                result.data(),
                required) != required)
        {
            return L"Unknown containment failure";
        }
        return result;
    }

    static void LaunchDirectWindowsApp(std::string_view app_id)
    {
        if (app_id.rfind("windows:", 0) != 0) return;
        const std::string_view sub = app_id.substr(8);
        std::wstring target_cmd;
        if (sub == "vscode")
        {
            target_cmd = L"cmd.exe /c start \"\" code";
        }
        else if (sub == "calc" || sub == "calculator")
        {
            target_cmd = L"calc.exe";
        }
        else if (sub == "explorer")
        {
            target_cmd = L"explorer.exe";
        }
        else if (sub == "taskmgr")
        {
            target_cmd = L"taskmgr.exe";
        }
        else if (sub.rfind("settings:", 0) == 0)
        {
            const std::wstring setting_name = Utf8ToWide(sub.substr(9));
            target_cmd = L"cmd.exe /c start \"\" ms-settings:" + setting_name;
        }
        else
        {
            target_cmd = L"cmd.exe /c start \"\" " + Utf8ToWide(sub);
        }

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi{};
        std::vector<wchar_t> cmd_buf(target_cmd.begin(), target_cmd.end());
        cmd_buf.push_back(L'\0');
        if (CreateProcessW(nullptr, cmd_buf.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
        {
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
        }
    }

    static inline bool s_flutter_ui_active = false;

    static void SetFlutterUiActive(bool active) noexcept
    {
        s_flutter_ui_active = active;
    }

    static bool BlockLaunch(std::string_view app_id, const std::string& error)
    {
        if (s_flutter_ui_active)
        {
            return false;
        }
        std::wstring message =
            L"CloudOS blocked this Windows application from opening outside its managed desktop.\n\n";
        message += L"Application: ";
        message += Utf8ToWide(app_id);
        message += L"\nReason: ";
        message += Utf8ToWide(error);
        message += L"\n\nThe application was not allowed to escape into the Windows desktop.";

        std::wstring prompt = message + L"\n\nDeseja iniciar este aplicativo diretamente na \u00E1rea de trabalho do Windows?";
        const int choice = MessageBoxW(
            FindCloudOSWindow(),
            prompt.c_str(),
            L"CloudOS - Windows application blocked",
            MB_YESNO | MB_ICONWARNING | MB_SETFOREGROUND);
        if (choice == IDYES)
        {
            LaunchDirectWindowsApp(app_id);
        }
        return true;
    }

    static bool ResolveLaunchSpec(
        std::string_view app_id,
        LaunchSpec& spec,
        std::string& error)
    {
        wchar_t windows_directory[MAX_PATH]{};
        const UINT win_length = GetWindowsDirectoryW(windows_directory, MAX_PATH);
        wchar_t system_directory[MAX_PATH]{};
        const UINT system_length = GetSystemDirectoryW(system_directory, MAX_PATH);
        if (system_length == 0 || system_length >= MAX_PATH)
        {
            error = "Windows system directory is unavailable";
            return false;
        }

        if (app_id == "windows:notepad")
        {
            // Both OS entrypoints can redirect to packaged Notepad. Neither
            // path guarantees the classic single-window implementation.
            std::wstring win_notepad;
            if (win_length > 0 && win_length < MAX_PATH)
            {
                win_notepad = std::wstring(windows_directory, win_length) + L"\\notepad.exe";
            }
            if (!win_notepad.empty() && GetFileAttributesW(win_notepad.c_str()) != INVALID_FILE_ATTRIBUTES)
            {
                spec.executable = win_notepad;
            }
            else
            {
                spec.executable = std::wstring(system_directory, system_length) + L"\\notepad.exe";
            }
            spec.title = L"Notepad - CloudOS";
            return true;
        }

        error = "Windows application is not allowlisted for containment";
        return false;
    }

    static HWND FindCloudOSWindow()
    {
        const DWORD current_process = GetCurrentProcessId();
        HWND foreground = GetForegroundWindow();
        if (foreground != nullptr)
        {
            DWORD foreground_process = 0;
            GetWindowThreadProcessId(foreground, &foreground_process);
            if (foreground_process == current_process &&
                GetAncestor(foreground, GA_ROOT) == foreground)
            {
                return foreground;
            }
        }

        ParentSearch search{current_process, nullptr};
        EnumWindows(
            [](HWND window, LPARAM value) -> BOOL
            {
                auto* state = reinterpret_cast<ParentSearch*>(value);
                DWORD process_id = 0;
                GetWindowThreadProcessId(window, &process_id);
                if (process_id != state->process_id) return TRUE;
                if (!IsWindowVisible(window)) return TRUE;
                if (GetWindow(window, GW_OWNER) != nullptr) return TRUE;
                state->match = window;
                return FALSE;
            },
            reinterpret_cast<LPARAM>(&search));
        return search.match;
    }

    static bool TryGetWindowLongPtr(HWND window, int index, LONG_PTR& value) noexcept
    {
        SetLastError(ERROR_SUCCESS);
        const LONG_PTR result = GetWindowLongPtrW(window, index);
        const DWORD error = GetLastError();
        if (result == 0 && error != ERROR_SUCCESS) return false;
        value = result;
        return true;
    }

    static bool TrySetWindowLongPtr(HWND window, int index, LONG_PTR value) noexcept
    {
        SetLastError(ERROR_SUCCESS);
        const LONG_PTR result = SetWindowLongPtrW(window, index, value);
        const DWORD error = GetLastError();
        return result != 0 || error == ERROR_SUCCESS;
    }

    static bool QueryJobProcessSnapshot(HANDLE job, JobProcessSnapshot& snapshot) noexcept
    {
        snapshot = JobProcessSnapshot{};
        if (!QueryInformationJobObject(
                job,
                JobObjectBasicProcessIdList,
                &snapshot,
                static_cast<DWORD>(sizeof(snapshot)),
                nullptr))
        {
            return false;
        }

        if (snapshot.assigned_processes != snapshot.process_id_count) return false;
        if (snapshot.process_id_count > kMaxTrackedJobProcesses) return false;
        return true;
    }

    static bool SnapshotContainsProcess(
        const JobProcessSnapshot& snapshot,
        DWORD process_id) noexcept
    {
        const ULONG_PTR expected = static_cast<ULONG_PTR>(process_id);
        for (DWORD index = 0; index < snapshot.process_id_count; ++index)
        {
            if (snapshot.process_ids[index] == expected) return true;
        }
        return false;
    }

    static bool EnumerateJobTopLevelWindows(
        const JobProcessSnapshot& processes,
        WindowSearch& search) noexcept
    {
        search = WindowSearch{};
        search.processes = &processes;
        SetLastError(ERROR_SUCCESS);
        const BOOL enumerated = EnumWindows(
            [](HWND window, LPARAM value) -> BOOL
            {
                auto* state = reinterpret_cast<WindowSearch*>(value);
                if (state == nullptr || state->processes == nullptr) return FALSE;
                if (!IsWindowVisible(window)) return TRUE;
                if (GetWindow(window, GW_OWNER) != nullptr) return TRUE;

                DWORD process_id = 0;
                GetWindowThreadProcessId(window, &process_id);
                if (process_id == 0 ||
                    !SnapshotContainsProcess(*state->processes, process_id))
                {
                    return TRUE;
                }

                LONG_PTR style = 0;
                if (!TryGetWindowLongPtr(window, GWL_STYLE, style))
                {
                    state->query_failed = true;
                    return FALSE;
                }
                if ((style & WS_CHILD) != 0) return TRUE;

                LONG_PTR ex_style = 0;
                RECT bounds{};
                if (!TryGetWindowLongPtr(window, GWL_EXSTYLE, ex_style) ||
                    !GetWindowRect(window, &bounds))
                {
                    state->query_failed = true;
                    return FALSE;
                }
                // Windows input indicators can have WS_VISIBLE despite having
                // no drawable area. Do not broadly exclude tool windows: one
                // with actual area still needs containment (including later).
                if ((ex_style & WS_EX_NOACTIVATE) != 0 &&
                    (bounds.right <= bounds.left || bounds.bottom <= bounds.top))
                {
                    return TRUE;
                }
                wchar_t class_name[256]{};
                if (GetClassNameW(window, class_name, 256) == 0)
                {
                    state->query_failed = true;
                    return FALSE;
                }
                if (std::wstring_view(class_name) != L"Notepad")
                    state->unapproved_window = true;
                if (state->first == nullptr) state->first = window;
                if (state->count < kMaxManagedWindows)
                    state->windows[state->count] = window;
                ++state->count;
                return state->count <= kMaxManagedWindows ? TRUE : FALSE;
            },
            reinterpret_cast<LPARAM>(&search));

        if (!enumerated && !search.query_failed)
        {
            // EnumWindows returning FALSE is expected when the callback stopped
            // after exceeding the bounded window set. Otherwise it is an enumeration
            // failure and attribution cannot be proven.
            if (search.count <= kMaxManagedWindows &&
                !(search.count == 0 && GetLastError() == ERROR_SUCCESS)) return false;
        }
        return !search.query_failed;
    }

    static WindowWaitResult WaitForAttributedWindows(
        HANDLE job,
        DWORD timeout_ms,
        std::vector<HWND>& attributed_windows)
    {
        attributed_windows.clear();
        std::vector<HWND> stable_candidate;
        DWORD stable_observations = 0;
        const ULONGLONG deadline = GetTickCount64() + timeout_ms;

        do
        {
            JobProcessSnapshot processes{};
            if (!QueryJobProcessSnapshot(job, processes))
            {
                return WindowWaitResult::QueryFailure;
            }

            WindowSearch search{};
            if (!EnumerateJobTopLevelWindows(processes, search))
            {
                return WindowWaitResult::QueryFailure;
            }
            if (search.count > kMaxManagedWindows || search.unapproved_window)
            {
                return WindowWaitResult::Ambiguous;
            }

            if (search.count != 0)
            {
                std::vector<HWND> candidates(search.windows, search.windows + search.count);
                std::sort(candidates.begin(), candidates.end(), std::less<HWND>{});
                if (candidates == stable_candidate)
                {
                    ++stable_observations;
                }
                else
                {
                    stable_candidate = std::move(candidates);
                    stable_observations = 1;
                }

                if (stable_observations >= kStableWindowObservations)
                {
                    attributed_windows = std::move(stable_candidate);
                    return WindowWaitResult::Found;
                }
            }
            else
            {
                stable_candidate.clear();
                stable_observations = 0;
            }

            Sleep(kWindowPollIntervalMs);
        } while (GetTickCount64() < deadline);

        return WindowWaitResult::NoWindow;
    }

    static bool EnsureHostClass()
    {
        static std::once_flag once;
        static std::atomic_bool registered{false};
        std::call_once(once, [] {
            WNDCLASSEXW wc{};
            wc.cbSize = sizeof(wc);
            wc.style = CS_DBLCLKS;
            wc.lpfnWndProc = &HostWindowProc;
            wc.hInstance = GetModuleHandleW(nullptr);
            wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
            wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
            wc.lpszClassName = HostClassName();
            SetLastError(ERROR_SUCCESS);
            const ATOM atom = RegisterClassExW(&wc);
            const DWORD error = GetLastError();
            registered.store(atom != 0 || error == ERROR_CLASS_ALREADY_EXISTS);
        });
        return registered.load();
    }

    static int RectWidth(const RECT& rect) noexcept
    {
        return static_cast<int>(rect.right - rect.left);
    }

    static int RectHeight(const RECT& rect) noexcept
    {
        return static_cast<int>(rect.bottom - rect.top);
    }

    static bool InitialHostRect(HWND parent, RECT& result)
    {
        RECT client{};
        if (!GetClientRect(parent, &client)) return false;
        const int available_width = std::max(320, RectWidth(client));
        const int available_height = std::max(
            240,
            RectHeight(client) - kTaskbarReservePx);
        const int width = std::min(
            920,
            std::max(320, available_width - (kDesktopMarginPx * 2)));
        const int height = std::min(
            620,
            std::max(240, available_height - (kDesktopMarginPx * 2)));

        static std::atomic_uint32_t cascade{0};
        const int step = static_cast<int>((cascade.fetch_add(1) % 8) * 24);
        const int max_x = std::max(0, available_width - width);
        const int max_y = std::max(0, available_height - height);
        const int x = std::min(kDesktopMarginPx + step, max_x);
        const int y = std::min(kDesktopMarginPx + step, max_y);
        result = RECT{x, y, x + width, y + height};
        return true;
    }

    static bool DpiAwarenessMatches(HWND host, HWND app) noexcept
    {
        const DPI_AWARENESS_CONTEXT host_context = GetWindowDpiAwarenessContext(host);
        const DPI_AWARENESS_CONTEXT app_context = GetWindowDpiAwarenessContext(app);
        if (host_context == nullptr || app_context == nullptr) return false;
        return AreDpiAwarenessContextsEqual(host_context, app_context) != FALSE;
    }

    static bool LayoutEmbeddedWindow(Session& session)
    {
        if (!IsWindow(session.host_window) || !IsWindow(session.app_window)) return false;
        if (GetParent(session.app_window) != session.host_window) return false;

        RECT client{};
        if (!GetClientRect(session.host_window, &client)) return false;
        if (!SetWindowPos(
                session.app_window,
                HWND_TOP,
                0,
                0,
                std::max(1, RectWidth(client)),
                std::max(1, RectHeight(client)),
                SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW))
        {
            return false;
        }

        return GetParent(session.app_window) == session.host_window;
    }

    static bool EmbedApplicationWindow(Session& session, std::string& error)
    {
        if (!IsWindow(session.app_window) || !IsWindow(session.host_window))
        {
            error = "Managed application window disappeared before containment";
            return false;
        }

        if (!DpiAwarenessMatches(session.host_window, session.app_window))
        {
            error = "Managed application DPI awareness is incompatible with safe cross-process containment";
            return false;
        }

        LONG_PTR style = 0;
        if (!TryGetWindowLongPtr(session.app_window, GWL_STYLE, style))
        {
            error = "CloudOS could not read the managed application window style";
            return false;
        }
        style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME |
            WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        style |= WS_CHILD | WS_VISIBLE;
        if (!TrySetWindowLongPtr(session.app_window, GWL_STYLE, style))
        {
            error = "CloudOS could not convert the managed application to a child window";
            return false;
        }

        // SetParent does not change WS_CHILD/WS_POPUP. Convert the style first,
        // as required by Win32, so GetParent reports the child relationship.
        SetLastError(ERROR_SUCCESS);
        const HWND previous_parent = SetParent(session.app_window, session.host_window);
        const DWORD set_parent_error = GetLastError();
        if (previous_parent == nullptr && set_parent_error != ERROR_SUCCESS)
        {
            error = "Windows rejected cross-process window containment";
            return false;
        }
        if (GetParent(session.app_window) != session.host_window)
        {
            error = "CloudOS could not verify the managed window parent after SetParent";
            return false;
        }

        LONG_PTR ex_style = 0;
        if (!TryGetWindowLongPtr(session.app_window, GWL_EXSTYLE, ex_style))
        {
            error = "CloudOS could not read the managed application extended style";
            return false;
        }
        ex_style &= ~(WS_EX_APPWINDOW | WS_EX_TOOLWINDOW);
        ex_style |= WS_EX_NOPARENTNOTIFY;
        if (!TrySetWindowLongPtr(session.app_window, GWL_EXSTYLE, ex_style))
        {
            error = "CloudOS could not apply contained extended window styles";
            return false;
        }

        LONG_PTR verified_style = 0;
        LONG_PTR verified_ex_style = 0;
        if (!TryGetWindowLongPtr(session.app_window, GWL_STYLE, verified_style) ||
            !TryGetWindowLongPtr(session.app_window, GWL_EXSTYLE, verified_ex_style))
        {
            error = "CloudOS could not verify managed application styles";
            return false;
        }
        if ((verified_style & WS_CHILD) == 0 ||
            (verified_style & (WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU)) != 0 ||
            (verified_ex_style & WS_EX_APPWINDOW) != 0 ||
            GetParent(session.app_window) != session.host_window)
        {
            error = "Managed application did not enter the required child-window containment state";
            return false;
        }

        if (!LayoutEmbeddedWindow(session))
        {
            error = "CloudOS could not size the embedded application window safely";
            return false;
        }
        return true;
    }

    static bool JobHasActiveProcesses(HANDLE job, bool& active) noexcept
    {
        active = false;
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
        if (!QueryInformationJobObject(
                job,
                JobObjectBasicAccountingInformation,
                &accounting,
                sizeof(accounting),
                nullptr))
        {
            return false;
        }
        active = accounting.ActiveProcesses != 0;
        return true;
    }

    static bool ValidateContainedSession(Session& session) noexcept
    {
        if (!IsWindow(session.host_window) || !IsWindow(session.app_window)) return false;
        if (GetParent(session.app_window) != session.host_window) return false;

        LONG_PTR style = 0;
        if (!TryGetWindowLongPtr(session.app_window, GWL_STYLE, style) ||
            (style & WS_CHILD) == 0)
        {
            return false;
        }

        bool has_active_processes = false;
        if (!JobHasActiveProcesses(session.job, has_active_processes) || !has_active_processes)
        {
            return false;
        }

        JobProcessSnapshot processes{};
        if (!QueryJobProcessSnapshot(session.job, processes)) return false;

        WindowSearch escaped{};
        if (!EnumerateJobTopLevelWindows(processes, escaped)) return false;

        // Once the attributed app HWND is a child, any visible unowned top-level
        // HWND from the same Job is an escape (secondary UI, relaunch, helper,
        // or stale containment). Fail closed instead of claiming containment.
        if (escaped.count != 0) return false;
        return true;
    }

    static HWND FindEmbeddedWindow(HWND host)
    {
        std::lock_guard<std::mutex> lock(SessionsMutex());
        const auto it = Sessions().find(host);
        return it == Sessions().end() ? nullptr : it->second->app_window;
    }

    static void CleanupSessionHandles(Session& session)
    {
        if (session.thread != nullptr)
        {
            CloseHandle(session.thread);
            session.thread = nullptr;
        }
        if (session.process != nullptr)
        {
            CloseHandle(session.process);
            session.process = nullptr;
        }
        if (session.job != nullptr)
        {
            CloseHandle(session.job);
            session.job = nullptr;
        }
    }

    static void CloseAndRemoveSession(HWND host)
    {
        std::unique_ptr<Session> removed;
        {
            std::lock_guard<std::mutex> lock(SessionsMutex());
            const auto it = Sessions().find(host);
            if (it == Sessions().end()) return;
            removed = std::move(it->second);
            Sessions().erase(it);
        }

        KillTimer(host, kHealthTimerId);
        removed->closing = true;
        // Each frame retains a handle to the same kill-on-close job. Closing
        // one document must not terminate its restored sibling documents.
        CleanupSessionHandles(*removed);
    }

    static void FailClosedHost(HWND host, Session& session) noexcept
    {
        if (session.closing) return;
        session.closing = true;
        if (session.job != nullptr)
        {
            TerminateJobObject(session.job, ERROR_INVALID_STATE);
        }
        if (IsWindow(host))
        {
            DestroyWindow(host);
        }
    }

    static bool MaximizeWithinCloudOS(Session& session)
    {
        HWND parent = GetParent(session.host_window);
        if (parent == nullptr) return false;
        if (!session.maximized)
        {
            RECT restore{};
            if (!GetWindowRect(session.host_window, &restore)) return false;
            POINT top_left{restore.left, restore.top};
            POINT bottom_right{restore.right, restore.bottom};
            if (!ScreenToClient(parent, &top_left) || !ScreenToClient(parent, &bottom_right))
            {
                return false;
            }
            session.restore_rect = RECT{
                top_left.x,
                top_left.y,
                bottom_right.x,
                bottom_right.y,
            };
        }

        RECT client{};
        if (!GetClientRect(parent, &client)) return false;
        if (!SetWindowPos(
                session.host_window,
                HWND_TOP,
                0,
                0,
                std::max(1, RectWidth(client)),
                std::max(1, RectHeight(client) - kTaskbarReservePx),
                SWP_SHOWWINDOW))
        {
            return false;
        }
        session.maximized = true;
        return LayoutEmbeddedWindow(session);
    }

    static bool RestoreWithinCloudOS(Session& session)
    {
        if (!session.maximized) return true;
        const RECT rect = session.restore_rect;
        if (!SetWindowPos(
                session.host_window,
                HWND_TOP,
                static_cast<int>(rect.left),
                static_cast<int>(rect.top),
                std::max(1, RectWidth(rect)),
                std::max(1, RectHeight(rect)),
                SWP_SHOWWINDOW))
        {
            return false;
        }
        session.maximized = false;
        return LayoutEmbeddedWindow(session);
    }

    static void ClampWindowPosition(HWND host, WINDOWPOS& position)
    {
        HWND parent = GetParent(host);
        if (parent == nullptr) return;

        RECT client{};
        if (!GetClientRect(parent, &client)) return;
        const int available_width = std::max(1, RectWidth(client));
        const int available_height = std::max(
            1,
            RectHeight(client) - kTaskbarReservePx);

        if ((position.flags & SWP_NOSIZE) == 0)
        {
            position.cx = std::clamp(position.cx, 260, available_width);
            position.cy = std::clamp(position.cy, 180, available_height);
        }
        if ((position.flags & SWP_NOMOVE) == 0)
        {
            position.x = std::clamp(
                position.x,
                0,
                std::max(0, available_width - position.cx));
            position.y = std::clamp(
                position.y,
                0,
                std::max(0, available_height - position.cy));
        }
    }

    static LRESULT CALLBACK HostWindowProc(
        HWND window,
        UINT message,
        WPARAM wparam,
        LPARAM lparam)
    {
        if (message == WM_NCCREATE)
        {
            const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
            auto* session = reinterpret_cast<Session*>(create->lpCreateParams);
            SetWindowLongPtrW(
                window,
                GWLP_USERDATA,
                reinterpret_cast<LONG_PTR>(session));
        }

        auto* session = reinterpret_cast<Session*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));

        switch (message)
        {
        case WM_SIZE:
            // Style/parent changes can synchronously re-enter this procedure
            // from Flutter/Win32 before the child relationship is established.
            if (session != nullptr && !session->embedding && session->host_window == window &&
                !LayoutEmbeddedWindow(*session))
            {
                FailClosedHost(window, *session);
            }
            return 0;
        case WM_SETFOCUS:
            if (session != nullptr && !session->embedding)
            {
                if (!IsWindow(session->app_window))
                {
                    FailClosedHost(window, *session);
                    return 0;
                }
                SetFocus(session->app_window);
            }
            return 0;
        case WM_WINDOWPOSCHANGING:
            if (session != nullptr && !session->maximized)
            {
                auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
                if (position != nullptr) ClampWindowPosition(window, *position);
            }
            break;
        case WM_TIMER:
            if (wparam == kHealthTimerId && session != nullptr &&
                !IsWindow(session->app_window))
            {
                DestroyWindow(window);
                return 0;
            }
            if (wparam == kHealthTimerId && session != nullptr &&
                !ValidateContainedSession(*session))
            {
                FailClosedHost(window, *session);
                return 0;
            }
            break;
        case WM_SYSCOMMAND:
            if (session != nullptr)
            {
                switch (wparam & 0xFFF0)
                {
                case SC_MAXIMIZE:
                    if (!MaximizeWithinCloudOS(*session)) FailClosedHost(window, *session);
                    return 0;
                case SC_RESTORE:
                    if (!RestoreWithinCloudOS(*session)) FailClosedHost(window, *session);
                    return 0;
                case SC_MINIMIZE:
                    ShowWindow(window, SW_MINIMIZE);
                    return 0;
                default:
                    break;
                }
            }
            break;
        case WM_CLOSE:
            // Let Notepad handle unsaved changes; retire this frame only after
            // its document HWND disappears. Never kill sibling documents.
            if (session != nullptr && IsWindow(session->app_window))
                PostMessageW(session->app_window, WM_CLOSE, 0, 0);
            else
                DestroyWindow(window);
            return 0;
        case WM_NCDESTROY:
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            CloseAndRemoveSession(window);
            break;
        default:
            break;
        }

        return DefWindowProcW(window, message, wparam, lparam);
    }
};

} // namespace CloudOS
