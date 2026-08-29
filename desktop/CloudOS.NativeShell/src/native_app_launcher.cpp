#include "native_app_launcher.h"

#include "cloudos_native_runtime.h"
#include "native_apps_window.h"
#include "native_calculator_window.h"
#include "native_cloudos_drive.h"
#include "native_env_doctor_window.h"
#include "native_files_window.h"
#include "native_notepad_window.h"
#include "native_projects_window.h"
#include "native_run_window.h"
#include "native_settings_window.h"
#include "native_shell_platform.h"
#include "native_start_menu_mru.h"
#include "native_system_monitor_window.h"
#include "native_terminal_window.h"
#include "native_theme.h"

#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr wchar_t kExternalHostClass[] = L"CloudOS.NativeShell.ExternalHost.v1";
constexpr UINT_PTR kExternalHostTimer = 1;
constexpr DWORD kExternalHostTimeoutMs = 5000;

struct ExternalHostState final
{
    HWND host{};
    HWND embedded{};
    HANDLE process{};
    DWORD root_process_id{};
    ULONGLONG started_at{};
    std::wstring target;
};

std::wstring QuoteArgument(const std::wstring& value)
{
    std::wstring result = L"\"";
    for (const wchar_t character : value)
    {
        if (character == L'\"')
        {
            result += L"\\\"";
        }
        else
        {
            result += character;
        }
    }
    result += L"\"";
    return result;
}

void ShowLaunchError(HWND owner, const std::wstring& target)
{
    std::wstring message = L"Nao foi possivel abrir ";
    message += target.empty() ? L"o aplicativo solicitado" : target;
    message += L" dentro do CloudOS.";
    MessageBoxW(owner, message.c_str(), L"CloudOS", MB_OK | MB_ICONERROR);
}

bool ContainsProcessId(const std::vector<DWORD>& ids, DWORD process_id)
{
    return std::find(ids.cbegin(), ids.cend(), process_id) != ids.cend();
}

std::vector<DWORD> CollectProcessFamily(DWORD root_process_id)
{
    std::vector<DWORD> result;
    if (root_process_id == 0)
    {
        return result;
    }
    result.push_back(root_process_id);

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return result;
    }

    struct ProcessLink final
    {
        DWORD process_id{};
        DWORD parent_process_id{};
    };
    std::vector<ProcessLink> links;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            links.push_back({entry.th32ProcessID, entry.th32ParentProcessID});
        }
        while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    bool changed = true;
    while (changed)
    {
        changed = false;
        for (const ProcessLink& link : links)
        {
            if (!ContainsProcessId(result, link.process_id) &&
                ContainsProcessId(result, link.parent_process_id))
            {
                result.push_back(link.process_id);
                changed = true;
            }
        }
    }
    return result;
}

struct FindHostedWindowContext final
{
    const std::vector<DWORD>* process_ids{};
    HWND found{};
};

BOOL CALLBACK FindHostedWindow(HWND window, LPARAM parameter)
{
    auto* context = reinterpret_cast<FindHostedWindowContext*>(parameter);
    if (context == nullptr || context->process_ids == nullptr)
    {
        return FALSE;
    }

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (!ContainsProcessId(*context->process_ids, process_id))
    {
        return TRUE;
    }

    const LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if (GetWindow(window, GW_OWNER) != nullptr &&
        (extended_style & WS_EX_APPWINDOW) == 0)
    {
        return TRUE;
    }

    RECT bounds{};
    if (!GetWindowRect(window, &bounds) ||
        bounds.right - bounds.left < 32 ||
        bounds.bottom - bounds.top < 32)
    {
        return TRUE;
    }

    context->found = window;
    return FALSE;
}

HWND FindProcessFamilyWindow(DWORD root_process_id)
{
    const std::vector<DWORD> process_ids = CollectProcessFamily(root_process_id);
    FindHostedWindowContext context{};
    context.process_ids = &process_ids;
    EnumWindows(&FindHostedWindow, reinterpret_cast<LPARAM>(&context));
    return context.found;
}

void LayoutEmbeddedWindow(ExternalHostState* state)
{
    if (state == nullptr ||
        state->host == nullptr ||
        state->embedded == nullptr ||
        !IsWindow(state->embedded))
    {
        return;
    }

    RECT client{};
    GetClientRect(state->host, &client);
    SetWindowPos(
        state->embedded,
        nullptr,
        0,
        0,
        std::max(1L, client.right - client.left),
        std::max(1L, client.bottom - client.top),
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

bool EmbedExternalWindow(ExternalHostState* state, HWND application_window)
{
    if (state == nullptr ||
        state->host == nullptr ||
        application_window == nullptr ||
        !IsWindow(application_window))
    {
        return false;
    }

    LONG_PTR style = GetWindowLongPtrW(application_window, GWL_STYLE);
    LONG_PTR extended_style = GetWindowLongPtrW(application_window, GWL_EXSTYLE);

    style &= ~static_cast<LONG_PTR>(
        WS_POPUP |
        WS_CAPTION |
        WS_THICKFRAME |
        WS_SYSMENU |
        WS_MINIMIZEBOX |
        WS_MAXIMIZEBOX);
    style |= WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;

    extended_style &= ~static_cast<LONG_PTR>(
        WS_EX_APPWINDOW |
        WS_EX_TOPMOST |
        WS_EX_TOOLWINDOW);
    extended_style |= WS_EX_CONTROLPARENT;

    SetLastError(ERROR_SUCCESS);
    const HWND previous_parent = SetParent(application_window, state->host);
    if (previous_parent == nullptr && GetLastError() != ERROR_SUCCESS)
    {
        return false;
    }

    SetWindowLongPtrW(application_window, GWL_STYLE, style);
    SetWindowLongPtrW(application_window, GWL_EXSTYLE, extended_style);
    SetWindowPos(
        application_window,
        nullptr,
        0,
        0,
        1,
        1,
        SWP_NOZORDER |
            SWP_NOACTIVATE |
            SWP_FRAMECHANGED |
            SWP_SHOWWINDOW);

    state->embedded = application_window;
    KillTimer(state->host, kExternalHostTimer);
    LayoutEmbeddedWindow(state);
    SetFocus(application_window);
    return true;
}

LRESULT CALLBACK ExternalHostWindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* state = reinterpret_cast<ExternalHostState*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));

    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        state = static_cast<ExternalHostState*>(create->lpCreateParams);
        state->host = window;
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(state));
    }

    if (state == nullptr)
    {
        return DefWindowProcW(window, message, w_param, l_param);
    }

    switch (message)
    {
    case WM_TIMER:
        if (w_param == kExternalHostTimer && state->embedded == nullptr)
        {
            const HWND candidate = FindProcessFamilyWindow(state->root_process_id);
            if (candidate != nullptr)
            {
                if (!EmbedExternalWindow(state, candidate))
                {
                    ShowLaunchError(GetParent(window), state->target);
                    PostMessageW(candidate, WM_CLOSE, 0, 0);
                    DestroyWindow(window);
                }
                return 0;
            }

            if (GetTickCount64() - state->started_at >= kExternalHostTimeoutMs)
            {
                ShowLaunchError(GetParent(window), state->target);
                if (state->process != nullptr)
                {
                    (void)TerminateProcess(state->process, ERROR_TIMEOUT);
                }
                DestroyWindow(window);
                return 0;
            }
        }
        return 0;

    case WM_SIZE:
        LayoutEmbeddedWindow(state);
        return 0;

    case WM_SETFOCUS:
        if (state->embedded != nullptr && IsWindow(state->embedded))
        {
            SetFocus(state->embedded);
        }
        return 0;

    case WM_CLOSE:
        if (state->embedded != nullptr && IsWindow(state->embedded))
        {
            PostMessageW(state->embedded, WM_CLOSE, 0, 0);
        }
        DestroyWindow(window);
        return 0;

    case WM_NCDESTROY:
        KillTimer(window, kExternalHostTimer);
        if (state->process != nullptr)
        {
            CloseHandle(state->process);
            state->process = nullptr;
        }
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        state->host = nullptr;
        delete state;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window, message, w_param, l_param);
}

bool EnsureExternalHostClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &ExternalHostWindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = CreateSolidBrush(RGB(14, 18, 28));
    window_class.lpszClassName = kExternalHostClass;

    if (RegisterClassExW(&window_class) != 0)
    {
        return true;
    }
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

HWND CreateExternalHost(HWND owner, const std::wstring& target, ExternalHostState* state)
{
    if (owner == nullptr || !IsWindow(owner) || state == nullptr)
    {
        return nullptr;
    }

    HINSTANCE instance = GetModuleHandleW(nullptr);
    if (!EnsureExternalHostClass(instance))
    {
        return nullptr;
    }

    RECT client{};
    GetClientRect(owner, &client);
    const UINT dpi = GetDpiForWindow(owner);
    const int margin = Scale(42, dpi);
    const int top_offset = Scale(28, dpi);
    const int reserved_bottom = Scale(kBottomBarHeight + 18, dpi);
    const int width = std::max(420, static_cast<int>(client.right) - margin * 2);
    const int height = std::max(
        300,
        static_cast<int>(client.bottom) - top_offset - margin - reserved_bottom);

    std::wstring title = L"CloudOS  |  ";
    title += target.empty() ? L"Aplicativo Windows" : target;

    HWND host = CreateWindowExW(
        0,
        kExternalHostClass,
        title.c_str(),
        WS_CHILD |
            WS_VISIBLE |
            WS_CLIPCHILDREN |
            WS_CLIPSIBLINGS |
            WS_CAPTION |
            WS_THICKFRAME |
            WS_SYSMENU |
            WS_MINIMIZEBOX |
            WS_MAXIMIZEBOX,
        margin,
        top_offset,
        width,
        height,
        owner,
        nullptr,
        instance,
        state);

    if (host != nullptr)
    {
        DarkWindow(host);
        ShowWindow(host, SW_SHOW);
        BringWindowToTop(host);
    }
    return host;
}

bool LaunchExternal(
    HWND owner,
    const std::wstring& file,
    const std::wstring& parameters = {},
    const std::wstring& working_directory = {},
    bool report_error = true)
{
    auto* state = new (std::nothrow) ExternalHostState();
    if (state == nullptr)
    {
        if (report_error)
        {
            ShowLaunchError(owner, file);
        }
        return false;
    }
    state->target = file;

    HWND host = CreateExternalHost(owner, file, state);
    if (host == nullptr)
    {
        delete state;
        if (report_error)
        {
            ShowLaunchError(owner, file);
        }
        return false;
    }

    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask =
        SEE_MASK_NOCLOSEPROCESS |
        SEE_MASK_FLAG_NO_UI |
        SEE_MASK_ASYNCOK;
    execution.hwnd = host;
    execution.lpVerb = L"open";
    execution.lpFile = file.c_str();
    execution.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
    execution.lpDirectory =
        working_directory.empty() ? nullptr : working_directory.c_str();
    execution.nShow = SW_SHOWNOACTIVATE;

    if (!ShellExecuteExW(&execution) || execution.hProcess == nullptr)
    {
        DestroyWindow(host);
        if (report_error)
        {
            ShowLaunchError(owner, file);
        }
        return false;
    }

    state->process = execution.hProcess;
    state->root_process_id = GetProcessId(execution.hProcess);
    state->started_at = GetTickCount64();

    (void)WaitForInputIdle(execution.hProcess, 750);

    const HWND immediate = FindProcessFamilyWindow(state->root_process_id);
    if (immediate != nullptr && EmbedExternalWindow(state, immediate))
    {
        return true;
    }

    if (SetTimer(host, kExternalHostTimer, 50, nullptr) == 0)
    {
        if (report_error)
        {
            ShowLaunchError(owner, file);
        }
        (void)TerminateProcess(execution.hProcess, ERROR_TIMEOUT);
        DestroyWindow(host);
        return false;
    }

    return true;
}

bool IsRegisteredDistribution(const std::wstring& distribution)
{
    if (distribution.empty())
    {
        return false;
    }

    BOOL registered = FALSE;
    return cloudos_native_wsl_is_registered(distribution.c_str(), &registered) != FALSE &&
        registered != FALSE;
}

std::wstring ResolveWslDistribution()
{
    const CloudOSNativeSettings settings = CloudOSNativeSettingsWindow::Load();
    if (IsRegisteredDistribution(settings.default_wsl_distribution))
    {
        return settings.default_wsl_distribution;
    }

    if (_wcsicmp(settings.default_wsl_distribution.c_str(), L"kali-linux") != 0 &&
        IsRegisteredDistribution(L"kali-linux"))
    {
        return L"kali-linux";
    }

    return {};
}

void OpenWslTerminal(HINSTANCE instance)
{
    std::wstring command = L"wsl.exe";
    std::wstring title = L"WSL - CloudOS";
    const std::wstring distribution = ResolveWslDistribution();
    if (!distribution.empty())
    {
        command += L" -d ";
        command += QuoteArgument(distribution);
        title = L"WSL / ";
        title += distribution;
        title += L" - CloudOS";
    }

    CloudOSNativeTerminalWindow::Open(instance, command, title);
}

std::wstring CanonicalAppId(std::wstring_view id)
{
    if (id == L"comms")
    {
        return L"terminal";
    }
    if (id == L"mail")
    {
        return L"notepad";
    }
    if (id == L"more")
    {
        return L"apps";
    }
    if (id == L"disk" || id == L"local-drive")
    {
        return L"systemdrive";
    }
    return std::wstring(id);
}

bool IsCatalogAppId(std::wstring_view id)
{
    for (const AppItem& app : kAllApps)
    {
        if (id == app.id)
        {
            return true;
        }
    }
    return false;
}

bool RestartCloudOSShell(HWND owner)
{
    std::array<wchar_t, 32768> executable{};
    const DWORD length = GetModuleFileNameW(
        nullptr,
        executable.data(),
        static_cast<DWORD>(executable.size()));
    if (length == 0 || length >= executable.size())
    {
        ShowLaunchError(owner, L"o executavel do CloudOS");
        return false;
    }

    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
    execution.hwnd = nullptr;
    execution.lpVerb = L"open";
    execution.lpFile = executable.data();
    execution.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&execution))
    {
        ShowLaunchError(owner, L"uma nova sessao do CloudOS");
        return false;
    }

    if (execution.hProcess != nullptr)
    {
        CloseHandle(execution.hProcess);
    }
    PostQuitMessage(0);
    return true;
}
}

void NativeAppLauncher::Launch(
    HINSTANCE instance,
    HWND parent_hwnd,
    const AppItem& app)
{
    LaunchById(instance, parent_hwnd, app.id);
}

void NativeAppLauncher::LaunchById(
    HINSTANCE instance,
    HWND parent_hwnd,
    const std::wstring& requested_id)
{
    const std::wstring id = CanonicalAppId(requested_id);
    bool launched = true;

    if (id == L"terminal")
    {
        CloudOSNativeTerminalWindow::Open(
            instance,
            L"cmd.exe",
            L"Terminal - CloudOS");
    }
    else if (id == L"projects")
    {
        CloudOSNativeProjectsWindow::Open(instance);
    }
    else if (id == L"wsl")
    {
        OpenWslTerminal(instance);
    }
    else if (id == L"powershell")
    {
        CloudOSNativeTerminalWindow::Open(
            instance,
            L"powershell.exe -NoLogo -NoProfile",
            L"PowerShell - CloudOS");
    }
    else if (id == L"files")
    {
        CloudOSNativeFilesWindow::Open(instance);
    }
    else if (id == L"drive")
    {
        std::wstring error;
        if (!NativeCloudOSDrive::EnsureReady(&error))
        {
            std::wstring message = L"CloudOS Drive indisponivel.";
            if (!error.empty())
            {
                message += L"\n\n";
                message += error;
            }
            MessageBoxW(parent_hwnd, message.c_str(), L"CloudOS Drive", MB_OK | MB_ICONERROR);
            launched = false;
        }
        else
        {
            const std::wstring root = NativeCloudOSDrive::Root();
            if (root.empty())
            {
                ShowLaunchError(parent_hwnd, L"o CloudOS Drive");
                launched = false;
            }
            else
            {
                CloudOSNativeFilesWindow::Open(instance, root);
            }
        }
    }
    else if (id == L"systemdrive")
    {
        const std::wstring system_volume = NativeShellPlatform::WindowsVolumeRoot();
        if (system_volume.empty())
        {
            ShowLaunchError(parent_hwnd, L"o volume do sistema");
            launched = false;
        }
        else
        {
            CloudOSNativeFilesWindow::Open(instance, system_volume);
        }
    }
    else if (id == L"notepad")
    {
        CloudOSNativeNotepadWindow::Open(instance);
    }
    else if (id == L"code")
    {
        launched = LaunchExternal(
            parent_hwnd,
            L"code.cmd",
            L".",
            {},
            false);
        if (!launched)
        {
            CloudOSNativeNotepadWindow::Open(instance);
            launched = true;
        }
    }
    else if (id == L"calc")
    {
        CloudOSNativeCalculatorWindow::Open(instance);
    }
    else if (id == L"sysmon")
    {
        CloudOSNativeSystemMonitorWindow::Open(instance);
    }
    else if (id == L"settings")
    {
        CloudOSNativeSettingsWindow::Open(instance);
    }
    else if (id == L"apps")
    {
        CloudOSNativeAppsWindow::Open(instance);
    }
    else if (id == L"run")
    {
        CloudOSNativeRunWindow::Open(instance);
    }
    else if (id == L"health")
    {
        launched = CloudOSNativeEnvDoctorWindow::Open(instance) != nullptr;
        if (!launched)
        {
            ShowLaunchError(parent_hwnd, L"Saude do Sistema");
        }
    }
    else if (id == L"browser")
    {
        launched = LaunchExternal(parent_hwnd, L"https://www.google.com/");
    }
    else if (id == L"paint")
    {
        launched = LaunchExternal(parent_hwnd, L"mspaint.exe");
    }
    else if (id == L"media")
    {
        launched = LaunchExternal(
            parent_hwnd,
            L"mswindowsmusic:",
            {},
            {},
            false);
        if (!launched)
        {
            launched = LaunchExternal(parent_hwnd, L"wmplayer.exe");
        }
    }
    else if (id == L"regedit")
    {
        launched = LaunchExternal(parent_hwnd, L"regedit.exe");
    }
    else if (id == L"snip")
    {
        launched = LaunchExternal(parent_hwnd, L"SnippingTool.exe");
    }
    else if (id == L"weather")
    {
        launched = LaunchExternal(parent_hwnd, L"https://www.msn.com/weather");
    }
    else if (id == L"datetime")
    {
        launched = LaunchExternal(parent_hwnd, L"ms-settings:dateandtime");
    }
    else
    {
        launched = false;
    }

    if (launched && IsCatalogAppId(id))
    {
        StartMenuMRUTracker::Instance().RecordLaunch(id.c_str());
    }
}

void NativeAppLauncher::ShowQuickPowerMenu(HWND parent_hwnd, POINT screen_pt)
{
    HMENU menu = CreatePopupMenu();
    if (menu == nullptr)
    {
        return;
    }

    InsertMenuW(menu, 0, MF_BYPOSITION | MF_STRING, 1001, L"Bloquear Windows");
    InsertMenuW(menu, 1, MF_BYPOSITION | MF_STRING, 1002, L"Configuracoes do CloudOS");
    InsertMenuW(menu, 2, MF_BYPOSITION | MF_STRING, 1005, L"Saude do Sistema");
    InsertMenuW(menu, 3, MF_BYPOSITION | MF_SEPARATOR, 0, nullptr);
    InsertMenuW(menu, 4, MF_BYPOSITION | MF_STRING, 1003, L"Reiniciar CloudOS");
    InsertMenuW(menu, 5, MF_BYPOSITION | MF_STRING, 1004, L"Sair do CloudOS");

    if (parent_hwnd != nullptr)
    {
        SetForegroundWindow(parent_hwnd);
    }
    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_BOTTOMALIGN,
        screen_pt.x,
        screen_pt.y,
        0,
        parent_hwnd,
        nullptr);
    DestroyMenu(menu);

    switch (command)
    {
    case 1001:
        if (!LockWorkStation())
        {
            ShowLaunchError(parent_hwnd, L"o bloqueio do Windows");
        }
        break;
    case 1002:
        CloudOSNativeSettingsWindow::Open(GetModuleHandleW(nullptr));
        break;
    case 1003:
        (void)RestartCloudOSShell(parent_hwnd);
        break;
    case 1004:
        PostQuitMessage(0);
        break;
    case 1005:
        (void)CloudOSNativeEnvDoctorWindow::Open(GetModuleHandleW(nullptr));
        break;
    default:
        break;
    }
}

} // namespace CloudOS
