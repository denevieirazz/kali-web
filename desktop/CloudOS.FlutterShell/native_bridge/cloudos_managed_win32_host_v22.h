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
        return app_id == "windows:notepad" ||
            app_id == "windows:cmd" ||
            app_id == "windows:powershell";
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

        if (!AssignProcessToJobObject(session->job, session->process))
        {
            TerminateProcess(session->process, ERROR_ACCESS_DENIED);
            error = "Windows application could not be assigned to the CloudOS containment job";
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

        // Console-hosted apps may reject WaitForInputIdle. The Job-based HWND
        // attribution loop is the authority and never accepts an unrelated HWND.
        WaitForInputIdle(session->process, 1500);

        session->app_window = WaitForAttributedWindow(session->job, 5000);
        if (session->app_window == nullptr)
        {
            TerminateJobObject(session->job, ERROR_TIMEOUT);
            error = "No attributable top-level window appeared; launch was blocked to prevent escape";
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

        const RECT initial = InitialHostRect(cloudos_window);
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
            return BlockLaunch(app_id, error);
        }

        session->host_window = host;
        if (!EmbedApplicationWindow(*session, error))
        {
            TerminateJobObject(session->job, ERROR_INVALID_STATE);
            DestroyWindow(host);
            CleanupSessionHandles(*session);
            return BlockLaunch(app_id, error);
        }

        {
            std::lock_guard<std::mutex> lock(SessionsMutex());
            Sessions().emplace(host, std::move(session));
        }

        SetTimer(host, kHealthTimerId, 500, nullptr);
        ShowWindow(host, SW_SHOW);
        SetWindowPos(
            host,
            HWND_TOP,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetFocus(FindEmbeddedWindow(host));
        return true;
    }

private:
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
        HWND host_window{nullptr};
        HWND app_window{nullptr};
        RECT restore_rect{};
        bool maximized{false};
    };

    struct WindowSearch final
    {
        HANDLE job{nullptr};
        HWND match{nullptr};
    };

    struct ParentSearch final
    {
        DWORD process_id{0};
        HWND match{nullptr};
    };

    static constexpr int kTaskbarReservePx = 56;
    static constexpr int kDesktopMarginPx = 24;
    static constexpr UINT_PTR kHealthTimerId = 0xC105;

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

    static bool BlockLaunch(std::string_view app_id, const std::string& error)
    {
        std::wstring message =
            L"CloudOS blocked this Windows application from opening outside its managed desktop.\n\n";
        message += L"Application: ";
        message += Utf8ToWide(app_id);
        message += L"\nReason: ";
        message += Utf8ToWide(error);
        message += L"\n\nThe application was not allowed to escape into the Windows desktop.";

        MessageBoxW(
            FindCloudOSWindow(),
            message.c_str(),
            L"CloudOS - Windows application blocked",
            MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
        return true;
    }

    static bool ResolveLaunchSpec(
        std::string_view app_id,
        LaunchSpec& spec,
        std::string& error)
    {
        wchar_t system_directory[MAX_PATH]{};
        const UINT system_length = GetSystemDirectoryW(system_directory, MAX_PATH);
        if (system_length == 0 || system_length >= MAX_PATH)
        {
            error = "Windows system directory is unavailable";
            return false;
        }

        const std::wstring system32(system_directory, system_length);
        if (app_id == "windows:notepad")
        {
            spec.executable = system32 + L"\\notepad.exe";
            spec.title = L"Notepad - CloudOS";
            return true;
        }
        if (app_id == "windows:cmd")
        {
            spec.executable = system32 + L"\\cmd.exe";
            spec.title = L"Command Prompt - CloudOS";
            return true;
        }
        if (app_id == "windows:powershell")
        {
            wchar_t windows_directory[MAX_PATH]{};
            const UINT windows_length = GetWindowsDirectoryW(windows_directory, MAX_PATH);
            if (windows_length == 0 || windows_length >= MAX_PATH)
            {
                error = "Windows directory is unavailable";
                return false;
            }
            spec.executable = std::wstring(windows_directory, windows_length) +
                L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
            spec.title = L"PowerShell - CloudOS";
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

    static HWND WaitForAttributedWindow(HANDLE job, DWORD timeout_ms)
    {
        const ULONGLONG deadline = GetTickCount64() + timeout_ms;
        do
        {
            WindowSearch search{job, nullptr};
            EnumWindows(
                [](HWND window, LPARAM value) -> BOOL
                {
                    auto* state = reinterpret_cast<WindowSearch*>(value);
                    if (!IsWindowVisible(window)) return TRUE;
                    if (GetWindow(window, GW_OWNER) != nullptr) return TRUE;

                    DWORD process_id = 0;
                    GetWindowThreadProcessId(window, &process_id);
                    if (process_id == 0) return TRUE;

                    HANDLE process = OpenProcess(
                        PROCESS_QUERY_LIMITED_INFORMATION,
                        FALSE,
                        process_id);
                    if (process == nullptr) return TRUE;

                    BOOL in_job = FALSE;
                    const BOOL queried = IsProcessInJob(process, state->job, &in_job);
                    CloseHandle(process);
                    if (!queried || !in_job) return TRUE;

                    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
                    if ((style & WS_CHILD) != 0) return TRUE;
                    state->match = window;
                    return FALSE;
                },
                reinterpret_cast<LPARAM>(&search));
            if (search.match != nullptr) return search.match;
            Sleep(50);
        } while (GetTickCount64() < deadline);
        return nullptr;
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
            const ATOM atom = RegisterClassExW(&wc);
            registered.store(atom != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS);
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

    static RECT InitialHostRect(HWND parent)
    {
        RECT client{};
        GetClientRect(parent, &client);
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
        return RECT{x, y, x + width, y + height};
    }

    static bool EmbedApplicationWindow(Session& session, std::string& error)
    {
        if (!IsWindow(session.app_window) || !IsWindow(session.host_window))
        {
            error = "Managed application window disappeared before containment";
            return false;
        }

        SetLastError(0);
        HWND previous_parent = SetParent(session.app_window, session.host_window);
        if (previous_parent == nullptr && GetLastError() != 0)
        {
            error = "Windows rejected cross-process window containment";
            return false;
        }

        LONG_PTR style = GetWindowLongPtrW(session.app_window, GWL_STYLE);
        style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME |
            WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        style |= WS_CHILD | WS_VISIBLE;
        SetWindowLongPtrW(session.app_window, GWL_STYLE, style);

        LONG_PTR ex_style = GetWindowLongPtrW(session.app_window, GWL_EXSTYLE);
        ex_style &= ~(WS_EX_APPWINDOW | WS_EX_TOOLWINDOW);
        ex_style |= WS_EX_NOPARENTNOTIFY;
        SetWindowLongPtrW(session.app_window, GWL_EXSTYLE, ex_style);

        LayoutEmbeddedWindow(session);
        return true;
    }

    static void LayoutEmbeddedWindow(Session& session)
    {
        if (!IsWindow(session.host_window) || !IsWindow(session.app_window)) return;
        RECT client{};
        GetClientRect(session.host_window, &client);
        SetWindowPos(
            session.app_window,
            HWND_TOP,
            0,
            0,
            std::max(1, RectWidth(client)),
            std::max(1, RectHeight(client)),
            SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
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
        if (removed->app_window != nullptr && IsWindow(removed->app_window))
        {
            PostMessageW(removed->app_window, WM_CLOSE, 0, 0);
        }
        if (removed->job != nullptr)
        {
            TerminateJobObject(removed->job, ERROR_PROCESS_ABORTED);
        }
        CleanupSessionHandles(*removed);
    }

    static void MaximizeWithinCloudOS(Session& session)
    {
        HWND parent = GetParent(session.host_window);
        if (parent == nullptr) return;
        if (!session.maximized)
        {
            GetWindowRect(session.host_window, &session.restore_rect);
            POINT top_left{session.restore_rect.left, session.restore_rect.top};
            POINT bottom_right{session.restore_rect.right, session.restore_rect.bottom};
            ScreenToClient(parent, &top_left);
            ScreenToClient(parent, &bottom_right);
            session.restore_rect = RECT{
                top_left.x,
                top_left.y,
                bottom_right.x,
                bottom_right.y,
            };
        }

        RECT client{};
        GetClientRect(parent, &client);
        SetWindowPos(
            session.host_window,
            HWND_TOP,
            0,
            0,
            std::max(1, RectWidth(client)),
            std::max(1, RectHeight(client) - kTaskbarReservePx),
            SWP_SHOWWINDOW);
        session.maximized = true;
    }

    static void RestoreWithinCloudOS(Session& session)
    {
        if (!session.maximized) return;
        const RECT rect = session.restore_rect;
        SetWindowPos(
            session.host_window,
            HWND_TOP,
            static_cast<int>(rect.left),
            static_cast<int>(rect.top),
            std::max(1, RectWidth(rect)),
            std::max(1, RectHeight(rect)),
            SWP_SHOWWINDOW);
        session.maximized = false;
    }

    static void ClampWindowPosition(HWND host, WINDOWPOS& position)
    {
        HWND parent = GetParent(host);
        if (parent == nullptr) return;

        RECT client{};
        GetClientRect(parent, &client);
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
            if (session != nullptr) LayoutEmbeddedWindow(*session);
            return 0;
        case WM_SETFOCUS:
            if (session != nullptr && IsWindow(session->app_window))
                SetFocus(session->app_window);
            return 0;
        case WM_WINDOWPOSCHANGING:
            if (session != nullptr && !session->maximized)
            {
                auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
                if (position != nullptr) ClampWindowPosition(window, *position);
            }
            break;
        case WM_TIMER:
            if (wparam == kHealthTimerId &&
                (session == nullptr || !IsWindow(session->app_window)))
            {
                DestroyWindow(window);
                return 0;
            }
            break;
        case WM_SYSCOMMAND:
            if (session != nullptr)
            {
                switch (wparam & 0xFFF0)
                {
                case SC_MAXIMIZE:
                    MaximizeWithinCloudOS(*session);
                    return 0;
                case SC_RESTORE:
                    RestoreWithinCloudOS(*session);
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
