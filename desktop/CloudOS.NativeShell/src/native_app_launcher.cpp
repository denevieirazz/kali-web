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

#include <array>
#include <string>
#include <string_view>

namespace CloudOS
{
namespace
{
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
    message += L".";
    MessageBoxW(owner, message.c_str(), L"CloudOS", MB_OK | MB_ICONERROR);
}

bool LaunchExternal(
    HWND owner,
    const std::wstring& file,
    const std::wstring& parameters = {},
    const std::wstring& working_directory = {},
    bool report_error = true)
{
    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask =
        SEE_MASK_NOCLOSEPROCESS |
        SEE_MASK_FLAG_NO_UI |
        SEE_MASK_ASYNCOK;

    // External Windows programs stay independent top-level HWNDs. CloudOS tracks
    // them through NativeWindowManager; it does not reparent/embed/capture them.
    execution.hwnd = nullptr;
    execution.lpVerb = L"open";
    execution.lpFile = file.c_str();
    execution.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
    execution.lpDirectory =
        working_directory.empty() ? nullptr : working_directory.c_str();
    execution.nShow = SW_SHOWNORMAL;

    if (!ShellExecuteExW(&execution))
    {
        if (report_error)
        {
            ShowLaunchError(owner, file);
        }
        return false;
    }

    if (execution.hProcess != nullptr)
    {
        (void)WaitForInputIdle(execution.hProcess, 750);
        CloseHandle(execution.hProcess);
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
        launched = !system_volume.empty() &&
            LaunchExternal(parent_hwnd, L"explorer.exe", system_volume);
        if (!launched && system_volume.empty())
        {
            ShowLaunchError(parent_hwnd, L"o volume do sistema");
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
