#include "native_app_launcher.h"

#include "cloudos_native_runtime.h"
#include "native_apps_window.h"
#include "native_browser_window.h"
#include "native_calculator_window.h"
#include "native_cloudos_drive.h"
#include "native_command_center_window.h"
#include "native_env_doctor_window.h"
#include "native_notepad_window.h"
#include "native_projects_window.h"
#include "native_run_window.h"
#include "native_settings_window.h"
#include "native_shell_actions.h"
#include "native_shell_platform.h"
#include "native_start_menu_mru.h"
#include "native_system_monitor_window.h"
#include "native_terminal_window.h"

#include <shellapi.h>

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
    message += target.empty()
        ? L"o aplicativo solicitado"
        : target;
    message += L".";
    MessageBoxW(
        owner,
        message.c_str(),
        L"CloudOS",
        MB_OK | MB_ICONERROR);
}

bool LaunchWindowsTarget(
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
    execution.hwnd = owner;
    execution.lpVerb = L"open";
    execution.lpFile = file.c_str();
    execution.lpParameters =
        parameters.empty() ? nullptr : parameters.c_str();
    execution.lpDirectory =
        working_directory.empty()
            ? nullptr
            : working_directory.c_str();
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
    return cloudos_native_wsl_is_registered(
               distribution.c_str(),
               &registered) != FALSE &&
        registered != FALSE;
}

std::wstring ResolveWslDistribution()
{
    const CloudOSNativeSettings settings =
        CloudOSNativeSettingsWindow::Load();
    if (IsRegisteredDistribution(
            settings.default_wsl_distribution))
    {
        return settings.default_wsl_distribution;
    }

    if (_wcsicmp(
            settings.default_wsl_distribution.c_str(),
            L"kali-linux") != 0 &&
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
    const std::wstring distribution =
        ResolveWslDistribution();

    if (!distribution.empty())
    {
        command += L" -d ";
        command += QuoteArgument(distribution);
        title = L"WSL / ";
        title += distribution;
        title += L" - CloudOS";
    }

    CloudOSNativeTerminalWindow::Open(
        instance,
        command,
        title);
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
    if (id == L"commands" ||
        id == L"command-center" ||
        id == L"action-center")
    {
        return L"control";
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

bool ExecuteNamedShellAction(
    HINSTANCE instance,
    HWND owner,
    std::wstring_view id)
{
    const ShellAction* action =
        NativeShellActions::Find(id);
    return action != nullptr &&
        NativeShellActions::Execute(
            instance,
            owner,
            *action);
}
} // namespace

void NativeAppLauncher::Launch(
    HINSTANCE instance,
    HWND parent_hwnd,
    const AppItem& app)
{
    LaunchById(
        instance,
        parent_hwnd,
        app.id);
}

void NativeAppLauncher::LaunchById(
    HINSTANCE instance,
    HWND parent_hwnd,
    const std::wstring& requested_id)
{
    const std::wstring id =
        CanonicalAppId(requested_id);
    bool launched = true;

    if (id == L"control")
    {
        CloudOSNativeCommandCenterWindow::Open(
            instance,
            parent_hwnd);
    }
    else if (id == L"terminal")
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
        // Use the real Windows Explorer for the main Files entry. It is much
        // faster than hosting IExplorerBrowser inside a custom CloudOS frame,
        // and it gives the user the complete Windows 11 file-management UX.
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"explorer.exe");
    }
    else if (id == L"drive")
    {
        std::wstring error;
        if (!NativeCloudOSDrive::EnsureReady(&error))
        {
            std::wstring message =
                L"CloudOS Drive indisponivel.";
            if (!error.empty())
            {
                message += L"\n\n";
                message += error;
            }
            MessageBoxW(
                parent_hwnd,
                message.c_str(),
                L"CloudOS Drive",
                MB_OK | MB_ICONERROR);
            launched = false;
        }
        else
        {
            const std::wstring root =
                NativeCloudOSDrive::Root();
            if (root.empty())
            {
                ShowLaunchError(
                    parent_hwnd,
                    L"o CloudOS Drive");
                launched = false;
            }
            else
            {
                // ShellExecute on a directory delegates directly to Explorer.
                launched = LaunchWindowsTarget(
                    parent_hwnd,
                    root);
            }
        }
    }
    else if (id == L"systemdrive")
    {
        const std::wstring system_volume =
            NativeShellPlatform::WindowsVolumeRoot();
        if (system_volume.empty())
        {
            ShowLaunchError(
                parent_hwnd,
                L"o volume do sistema");
            launched = false;
        }
        else
        {
            launched = LaunchWindowsTarget(
                parent_hwnd,
                system_volume);
        }
    }
    else if (id == L"notepad")
    {
        CloudOSNativeNotepadWindow::Open(instance);
    }
    else if (id == L"code")
    {
        launched = LaunchWindowsTarget(
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
        launched =
            CloudOSNativeEnvDoctorWindow::Open(instance) != nullptr;
        if (!launched)
        {
            ShowLaunchError(
                parent_hwnd,
                L"Saude do Sistema");
        }
    }
    else if (id == L"browser")
    {
        CloudOSNativeBrowserWindow::Open(
            instance,
            L"https://www.google.com/");
    }
    else if (id == L"paint")
    {
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"mspaint.exe");
    }
    else if (id == L"media")
    {
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"mswindowsmusic:",
            {},
            {},
            false);
        if (!launched)
        {
            launched = LaunchWindowsTarget(
                parent_hwnd,
                L"wmplayer.exe");
        }
    }
    else if (id == L"regedit")
    {
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"regedit.exe");
    }
    else if (id == L"snip")
    {
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"SnippingTool.exe");
    }
    else if (id == L"weather")
    {
        CloudOSNativeBrowserWindow::Open(
            instance,
            L"https://www.msn.com/weather");
    }
    else if (id == L"datetime")
    {
        launched = LaunchWindowsTarget(
            parent_hwnd,
            L"ms-settings:dateandtime");
    }
    else
    {
        launched = false;
    }

    if (launched && IsCatalogAppId(id))
    {
        StartMenuMRUTracker::Instance().RecordLaunch(
            id.c_str());
    }
}

void NativeAppLauncher::ShowQuickPowerMenu(
    HWND parent_hwnd,
    POINT screen_pt)
{
    constexpr UINT kCommandCenter = 1100;
    constexpr UINT kBrowser = 1101;
    constexpr UINT kFiles = 1102;
    constexpr UINT kTerminal = 1103;
    constexpr UINT kSystemMonitor = 1104;
    constexpr UINT kTaskManager = 1105;
    constexpr UINT kCloudSettings = 1106;
    constexpr UINT kWindowsSettings = 1107;
    constexpr UINT kHealth = 1108;
    constexpr UINT kLock = 1109;
    constexpr UINT kRestartCloudOS = 1110;
    constexpr UINT kExitCloudOS = 1111;
    constexpr UINT kRestartWindows = 1112;
    constexpr UINT kShutdownWindows = 1113;
    constexpr UINT kPowerShell = 1114;
    constexpr UINT kWsl = 1115;
    constexpr UINT kRun = 1116;
    constexpr UINT kSnip = 1117;
    constexpr UINT kDrive = 1118;
    constexpr UINT kWifi = 1119;
    constexpr UINT kWindowsUpdate = 1120;
    constexpr UINT kCalculator = 1121;
    constexpr UINT kNotepad = 1122;
    constexpr UINT kApps = 1123;

    HMENU menu = CreatePopupMenu();
    HMENU terminals = CreatePopupMenu();
    HMENU tools = CreatePopupMenu();
    HMENU settings = CreatePopupMenu();
    HMENU power = CreatePopupMenu();
    if (menu == nullptr || terminals == nullptr || tools == nullptr ||
        settings == nullptr || power == nullptr)
    {
        if (menu != nullptr) DestroyMenu(menu);
        if (terminals != nullptr) DestroyMenu(terminals);
        if (tools != nullptr) DestroyMenu(tools);
        if (settings != nullptr) DestroyMenu(settings);
        if (power != nullptr) DestroyMenu(power);
        return;
    }

    AppendMenuW(menu, MF_STRING, kCommandCenter, L"Central de Comandos  ·  106 acoes");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kBrowser, L"Navegador");
    AppendMenuW(menu, MF_STRING, kFiles, L"Arquivos");
    AppendMenuW(menu, MF_STRING, kDrive, L"CloudOS Drive");

    AppendMenuW(terminals, MF_STRING, kTerminal, L"Terminal");
    AppendMenuW(terminals, MF_STRING, kPowerShell, L"PowerShell");
    AppendMenuW(terminals, MF_STRING, kWsl, L"WSL / Kali");
    AppendMenuW(
        menu,
        MF_POPUP,
        reinterpret_cast<UINT_PTR>(terminals),
        L"Terminais");

    AppendMenuW(tools, MF_STRING, kRun, L"Executar...");
    AppendMenuW(tools, MF_STRING, kCalculator, L"Calculadora");
    AppendMenuW(tools, MF_STRING, kNotepad, L"Bloco de Notas");
    AppendMenuW(tools, MF_STRING, kSnip, L"Captura de Tela");
    AppendMenuW(tools, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(tools, MF_STRING, kSystemMonitor, L"Monitor do Sistema");
    AppendMenuW(tools, MF_STRING, kTaskManager, L"Gerenciador de Tarefas");
    AppendMenuW(tools, MF_STRING, kApps, L"Todos os Aplicativos");
    AppendMenuW(
        menu,
        MF_POPUP,
        reinterpret_cast<UINT_PTR>(tools),
        L"Ferramentas");

    AppendMenuW(settings, MF_STRING, kCloudSettings, L"Configuracoes do CloudOS");
    AppendMenuW(settings, MF_STRING, kWindowsSettings, L"Configuracoes do Windows");
    AppendMenuW(settings, MF_STRING, kWifi, L"Wi-Fi e rede");
    AppendMenuW(settings, MF_STRING, kWindowsUpdate, L"Windows Update");
    AppendMenuW(settings, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(settings, MF_STRING, kHealth, L"Saude do Sistema");
    AppendMenuW(
        menu,
        MF_POPUP,
        reinterpret_cast<UINT_PTR>(settings),
        L"Sistema e configuracoes");

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kLock, L"Bloquear Windows");
    AppendMenuW(menu, MF_STRING, kRestartCloudOS, L"Reiniciar CloudOS");
    AppendMenuW(menu, MF_STRING, kExitCloudOS, L"Sair do CloudOS");

    AppendMenuW(power, MF_STRING, kRestartWindows, L"Reiniciar Windows...");
    AppendMenuW(power, MF_STRING, kShutdownWindows, L"Desligar Windows...");
    AppendMenuW(
        menu,
        MF_POPUP,
        reinterpret_cast<UINT_PTR>(power),
        L"Energia do Windows");

    if (parent_hwnd != nullptr)
    {
        SetForegroundWindow(parent_hwnd);
    }

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD |
            TPM_NONOTIFY |
            TPM_LEFTALIGN |
            TPM_BOTTOMALIGN |
            TPM_RIGHTBUTTON,
        screen_pt.x,
        screen_pt.y,
        0,
        parent_hwnd,
        nullptr);
    DestroyMenu(menu);

    const HINSTANCE instance = GetModuleHandleW(nullptr);
    switch (command)
    {
    case kCommandCenter:
        CloudOSNativeCommandCenterWindow::Open(instance, parent_hwnd);
        break;
    case kBrowser:
        LaunchById(instance, parent_hwnd, L"browser");
        break;
    case kFiles:
        LaunchById(instance, parent_hwnd, L"files");
        break;
    case kDrive:
        LaunchById(instance, parent_hwnd, L"drive");
        break;
    case kTerminal:
        LaunchById(instance, parent_hwnd, L"terminal");
        break;
    case kPowerShell:
        LaunchById(instance, parent_hwnd, L"powershell");
        break;
    case kWsl:
        LaunchById(instance, parent_hwnd, L"wsl");
        break;
    case kRun:
        LaunchById(instance, parent_hwnd, L"run");
        break;
    case kCalculator:
        LaunchById(instance, parent_hwnd, L"calc");
        break;
    case kNotepad:
        LaunchById(instance, parent_hwnd, L"notepad");
        break;
    case kSnip:
        LaunchById(instance, parent_hwnd, L"snip");
        break;
    case kSystemMonitor:
        LaunchById(instance, parent_hwnd, L"sysmon");
        break;
    case kTaskManager:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"classic.taskmgr");
        break;
    case kApps:
        LaunchById(instance, parent_hwnd, L"apps");
        break;
    case kCloudSettings:
        LaunchById(instance, parent_hwnd, L"settings");
        break;
    case kWindowsSettings:
        (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:");
        break;
    case kWifi:
        (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:network-wifi");
        break;
    case kWindowsUpdate:
        (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:windowsupdate");
        break;
    case kHealth:
        LaunchById(instance, parent_hwnd, L"health");
        break;
    case kLock:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.lock");
        break;
    case kRestartCloudOS:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.restart-cloudos");
        break;
    case kExitCloudOS:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.exit-cloudos");
        break;
    case kRestartWindows:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.restart-windows");
        break;
    case kShutdownWindows:
        (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.shutdown");
        break;
    default:
        break;
    }
}
} // namespace CloudOS