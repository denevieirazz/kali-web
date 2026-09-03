#include "native_app_launcher.h"

#include "cloudos_native_runtime.h"
#include "native_apps_window.h"
#include "native_browser_window.h"
#include "native_calculator_window.h"
#include "native_cloudos_drive.h"
#include "native_command_center_window.h"
#include "native_env_doctor_window.h"
#include "native_files_window.h"
#include "native_notepad_window.h"
#include "native_projects_window.h"
#include "native_run_window.h"
#include "native_settings_window.h"
#include "native_shell_actions.h"
#include "native_shell_bridge.h"
#include "native_shell_platform.h"
#include "native_start_menu_mru.h"
#include "native_system_monitor_window.h"
#include "native_terminal_window.h"

#include <shellapi.h>

#include <array>
#include <cwctype>
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
        if (character == L'\"') result += L"\\\"";
        else result += character;
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

bool HasProtocolScheme(std::wstring_view target) noexcept
{
    const std::size_t colon = target.find(L':');
    if (colon == std::wstring_view::npos) return false;
    if (colon == 1u && std::iswalpha(target.front())) return false; // drive path
    return colon > 0u;
}

bool EndsWithInsensitive(std::wstring_view value, std::wstring_view suffix) noexcept
{
    if (value.size() < suffix.size()) return false;
    const std::size_t offset = value.size() - suffix.size();
    return _wcsnicmp(value.data() + offset, suffix.data(), suffix.size()) == 0;
}

bool LaunchExternalBreakawayProcess(
    const std::wstring& file,
    const std::wstring& parameters,
    const std::wstring& working_directory)
{
    if (file.empty() || HasProtocolScheme(file)) return false;

    std::wstring command;
    if (EndsWithInsensitive(file, L".cmd") || EndsWithInsensitive(file, L".bat"))
    {
        command = L"cmd.exe /d /s /c \"";
        command += QuoteArgument(file);
        if (!parameters.empty()) command += L" " + parameters;
        command += L"\"";
    }
    else if (EndsWithInsensitive(file, L".msc"))
    {
        command = L"mmc.exe ";
        command += QuoteArgument(file);
        if (!parameters.empty()) command += L" " + parameters;
    }
    else
    {
        command = QuoteArgument(file);
        if (!parameters.empty()) command += L" " + parameters;
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            nullptr,
            command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_BREAKAWAY_FROM_JOB | CREATE_DEFAULT_ERROR_MODE,
            nullptr,
            working_directory.empty() ? nullptr : working_directory.c_str(),
            &startup,
            &process))
    {
        return false;
    }

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

bool LaunchWindowsTarget(
    HWND owner,
    const std::wstring& file,
    const std::wstring& parameters = {},
    const std::wstring& working_directory = {},
    bool report_error = true)
{
    // External Win32 executables are explicitly detached from the Supervisor's
    // Job Object. Internal CloudOS apps never pass through this function.
    // Protocol activation/UAC-sensitive targets fall back to ShellExecuteExW.
    if (LaunchExternalBreakawayProcess(file, parameters, working_directory)) return true;

    SHELLEXECUTEINFOW execution{};
    execution.cbSize = sizeof(execution);
    execution.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI | SEE_MASK_ASYNCOK;
    execution.hwnd = owner;
    execution.lpVerb = L"open";
    execution.lpFile = file.c_str();
    execution.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
    execution.lpDirectory = working_directory.empty() ? nullptr : working_directory.c_str();
    execution.nShow = SW_SHOWNORMAL;

    if (!ShellExecuteExW(&execution))
    {
        if (report_error) ShowLaunchError(owner, file);
        return false;
    }
    if (execution.hProcess != nullptr) CloseHandle(execution.hProcess);
    return true;
}

bool IsRegisteredDistribution(const std::wstring& distribution)
{
    if (distribution.empty()) return false;
    BOOL registered = FALSE;
    return cloudos_native_wsl_is_registered(distribution.c_str(), &registered) != FALSE && registered != FALSE;
}

std::wstring ResolveWslDistribution()
{
    const CloudOSNativeSettings settings = CloudOSNativeSettingsWindow::Load();
    if (IsRegisteredDistribution(settings.default_wsl_distribution)) return settings.default_wsl_distribution;
    if (_wcsicmp(settings.default_wsl_distribution.c_str(), L"kali-linux") != 0 && IsRegisteredDistribution(L"kali-linux"))
        return L"kali-linux";
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
        title = L"WSL / " + distribution + L" - CloudOS";
    }
    CloudOSNativeTerminalWindow::Open(instance, command, title);
}

std::wstring CanonicalAppId(std::wstring_view id)
{
    if (id == L"comms") return L"terminal";
    if (id == L"mail") return L"notepad";
    if (id == L"more") return L"apps";
    if (id == L"disk" || id == L"local-drive") return L"systemdrive";
    if (id == L"commands" || id == L"command-center" || id == L"action-center") return L"control";
    if (id == L"workspace" || id == L"overview" || id == L"task-view" ||
        id == L"mission-control" || id == L"areas") return L"workspaces";
    return std::wstring(id);
}

bool IsCatalogAppId(std::wstring_view id)
{
    for (const AppItem& app : kAllApps)
        if (id == app.id) return true;
    return false;
}

bool ExecuteNamedShellAction(HINSTANCE instance, HWND owner, std::wstring_view id)
{
    const ShellAction* action = NativeShellActions::Find(id);
    return action != nullptr && NativeShellActions::Execute(instance, owner, *action);
}
} // namespace

void NativeAppLauncher::Launch(HINSTANCE instance, HWND parent_hwnd, const AppItem& app)
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

    if (id == L"workspaces")
    {
        launched = NativeShellBridge::OpenWorkspaceOverview();
        if (!launched) ShowLaunchError(parent_hwnd, L"a Visao de Trabalho");
    }
    else if (id == L"control") CloudOSNativeCommandCenterWindow::Open(instance, parent_hwnd);
    else if (id == L"terminal") CloudOSNativeTerminalWindow::Open(instance, L"cmd.exe", L"Terminal - CloudOS");
    else if (id == L"projects") CloudOSNativeProjectsWindow::Open(instance);
    else if (id == L"wsl") OpenWslTerminal(instance);
    else if (id == L"powershell")
    {
        CloudOSNativeTerminalWindow::Open(instance, L"powershell.exe -NoLogo -NoProfile", L"PowerShell - CloudOS");
    }
    else if (id == L"files") CloudOSNativeFilesWindow::Open(instance);
    else if (id == L"drive")
    {
        std::wstring error;
        if (!NativeCloudOSDrive::EnsureReady(&error))
        {
            std::wstring message = L"CloudOS Drive indisponivel.";
            if (!error.empty()) message += L"\n\n" + error;
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
            else CloudOSNativeFilesWindow::Open(instance, root);
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
        else CloudOSNativeFilesWindow::Open(instance, system_volume);
    }
    else if (id == L"notepad") CloudOSNativeNotepadWindow::Open(instance);
    else if (id == L"code")
    {
        launched = LaunchWindowsTarget(parent_hwnd, L"code.cmd", L".", {}, false);
        if (!launched)
        {
            CloudOSNativeNotepadWindow::Open(instance);
            launched = true;
        }
    }
    else if (id == L"calc") CloudOSNativeCalculatorWindow::Open(instance);
    else if (id == L"sysmon") CloudOSNativeSystemMonitorWindow::Open(instance);
    else if (id == L"settings") CloudOSNativeSettingsWindow::Open(instance);
    else if (id == L"apps") CloudOSNativeAppsWindow::Open(instance);
    else if (id == L"run") CloudOSNativeRunWindow::Open(instance);
    else if (id == L"health")
    {
        launched = CloudOSNativeEnvDoctorWindow::Open(instance) != nullptr;
        if (!launched) ShowLaunchError(parent_hwnd, L"Saude do Sistema");
    }
    else if (id == L"browser") CloudOSNativeBrowserWindow::Open(instance, L"https://www.google.com/");
    else if (id == L"paint") launched = LaunchWindowsTarget(parent_hwnd, L"mspaint.exe");
    else if (id == L"media")
    {
        launched = LaunchWindowsTarget(parent_hwnd, L"mswindowsmusic:", {}, {}, false);
        if (!launched) launched = LaunchWindowsTarget(parent_hwnd, L"wmplayer.exe");
    }
    else if (id == L"regedit") launched = LaunchWindowsTarget(parent_hwnd, L"regedit.exe");
    else if (id == L"snip") launched = LaunchWindowsTarget(parent_hwnd, L"SnippingTool.exe");
    else if (id == L"weather") CloudOSNativeBrowserWindow::Open(instance, L"https://www.msn.com/weather");
    else if (id == L"datetime") launched = LaunchWindowsTarget(parent_hwnd, L"ms-settings:dateandtime");
    else launched = false;

    if (launched && IsCatalogAppId(id)) StartMenuMRUTracker::Instance().RecordLaunch(id.c_str());
}

void NativeAppLauncher::ShowQuickPowerMenu(HWND parent_hwnd, POINT screen_pt)
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
    constexpr UINT kProjects = 1124;
    constexpr UINT kCode = 1125;
    constexpr UINT kPaint = 1126;
    constexpr UINT kMedia = 1127;
    constexpr UINT kWeather = 1128;
    constexpr UINT kDateTime = 1129;
    constexpr UINT kRegedit = 1130;
    constexpr UINT kDisplay = 1131;
    constexpr UINT kSound = 1132;
    constexpr UINT kBluetooth = 1133;
    constexpr UINT kStorage = 1134;
    constexpr UINT kClipboard = 1135;
    constexpr UINT kDevelopers = 1136;
    constexpr UINT kSecurity = 1137;
    constexpr UINT kNetwork = 1138;
    constexpr UINT kSystemDrive = 1139;
    constexpr UINT kDeviceManager = 1140;
    constexpr UINT kWorkspaces = 1141;
    constexpr UINT kShowDesktop = 1142;

    HMENU menu = CreatePopupMenu();
    HMENU cloud = CreatePopupMenu();
    HMENU terminals = CreatePopupMenu();
    HMENU productivity = CreatePopupMenu();
    HMENU tools = CreatePopupMenu();
    HMENU settings = CreatePopupMenu();
    HMENU power = CreatePopupMenu();
    if (menu == nullptr || cloud == nullptr || terminals == nullptr ||
        productivity == nullptr || tools == nullptr || settings == nullptr || power == nullptr)
    {
        if (menu != nullptr) DestroyMenu(menu);
        if (cloud != nullptr) DestroyMenu(cloud);
        if (terminals != nullptr) DestroyMenu(terminals);
        if (productivity != nullptr) DestroyMenu(productivity);
        if (tools != nullptr) DestroyMenu(tools);
        if (settings != nullptr) DestroyMenu(settings);
        if (power != nullptr) DestroyMenu(power);
        return;
    }

    AppendMenuW(menu, MF_STRING, kCommandCenter, L"Central de Comandos  ·  106 acoes");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    AppendMenuW(cloud, MF_STRING, kWorkspaces, L"Visão de Trabalho  ·  Ctrl+Alt+O");
    AppendMenuW(cloud, MF_STRING, kBrowser, L"Navegador");
    AppendMenuW(cloud, MF_STRING, kFiles, L"Arquivos");
    AppendMenuW(cloud, MF_STRING, kDrive, L"CloudOS Drive");
    AppendMenuW(cloud, MF_STRING, kProjects, L"Projetos");
    AppendMenuW(cloud, MF_STRING, kCode, L"VS Code");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(cloud), L"CloudOS e desenvolvimento");

    AppendMenuW(terminals, MF_STRING, kTerminal, L"Terminal");
    AppendMenuW(terminals, MF_STRING, kPowerShell, L"PowerShell");
    AppendMenuW(terminals, MF_STRING, kWsl, L"WSL / Kali");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(terminals), L"Terminais");

    AppendMenuW(productivity, MF_STRING, kRun, L"Executar...");
    AppendMenuW(productivity, MF_STRING, kCalculator, L"Calculadora");
    AppendMenuW(productivity, MF_STRING, kNotepad, L"Bloco de Notas");
    AppendMenuW(productivity, MF_STRING, kPaint, L"Paint");
    AppendMenuW(productivity, MF_STRING, kSnip, L"Captura de Tela");
    AppendMenuW(productivity, MF_STRING, kMedia, L"Midia / Musica");
    AppendMenuW(productivity, MF_STRING, kWeather, L"Clima");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(productivity), L"Produtividade");

    AppendMenuW(tools, MF_STRING, kSystemMonitor, L"Monitor do Sistema");
    AppendMenuW(tools, MF_STRING, kTaskManager, L"Gerenciador de Tarefas");
    AppendMenuW(tools, MF_STRING, kDeviceManager, L"Gerenciador de Dispositivos");
    AppendMenuW(tools, MF_STRING, kRegedit, L"Editor do Registro");
    AppendMenuW(tools, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(tools, MF_STRING, kSystemDrive, L"Disco do Sistema");
    AppendMenuW(tools, MF_STRING, kApps, L"Todos os Aplicativos");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(tools), L"Ferramentas do sistema");

    AppendMenuW(settings, MF_STRING, kCloudSettings, L"Configuracoes do CloudOS");
    AppendMenuW(settings, MF_STRING, kWindowsSettings, L"Configuracoes do Windows");
    AppendMenuW(settings, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(settings, MF_STRING, kDisplay, L"Tela e monitores");
    AppendMenuW(settings, MF_STRING, kSound, L"Som e audio");
    AppendMenuW(settings, MF_STRING, kNetwork, L"Rede e Internet");
    AppendMenuW(settings, MF_STRING, kWifi, L"Wi-Fi");
    AppendMenuW(settings, MF_STRING, kBluetooth, L"Bluetooth");
    AppendMenuW(settings, MF_STRING, kStorage, L"Armazenamento");
    AppendMenuW(settings, MF_STRING, kClipboard, L"Area de transferencia");
    AppendMenuW(settings, MF_STRING, kDateTime, L"Data e hora");
    AppendMenuW(settings, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(settings, MF_STRING, kDevelopers, L"Para desenvolvedores");
    AppendMenuW(settings, MF_STRING, kSecurity, L"Seguranca do Windows");
    AppendMenuW(settings, MF_STRING, kWindowsUpdate, L"Windows Update");
    AppendMenuW(settings, MF_STRING, kHealth, L"Saude do Sistema");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(settings), L"Sistema e configuracoes");

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kShowDesktop, L"Mostrar Área de Trabalho  ·  Ctrl+Alt+D");
    AppendMenuW(menu, MF_STRING, kLock, L"Bloquear Windows");
    AppendMenuW(menu, MF_STRING, kRestartCloudOS, L"Reiniciar CloudOS");
    AppendMenuW(menu, MF_STRING, kExitCloudOS, L"Sair do CloudOS");

    AppendMenuW(power, MF_STRING, kRestartWindows, L"Reiniciar Windows...");
    AppendMenuW(power, MF_STRING, kShutdownWindows, L"Desligar Windows...");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(power), L"Energia do Windows");

    if (parent_hwnd != nullptr) SetForegroundWindow(parent_hwnd);

    const int command = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON,
        screen_pt.x, screen_pt.y, 0, parent_hwnd, nullptr);
    DestroyMenu(menu);

    const HINSTANCE instance = GetModuleHandleW(nullptr);
    switch (command)
    {
    case kCommandCenter: CloudOSNativeCommandCenterWindow::Open(instance, parent_hwnd); break;
    case kWorkspaces: LaunchById(instance, parent_hwnd, L"workspaces"); break;
    case kBrowser: LaunchById(instance, parent_hwnd, L"browser"); break;
    case kFiles: LaunchById(instance, parent_hwnd, L"files"); break;
    case kDrive: LaunchById(instance, parent_hwnd, L"drive"); break;
    case kProjects: LaunchById(instance, parent_hwnd, L"projects"); break;
    case kCode: LaunchById(instance, parent_hwnd, L"code"); break;
    case kTerminal: LaunchById(instance, parent_hwnd, L"terminal"); break;
    case kPowerShell: LaunchById(instance, parent_hwnd, L"powershell"); break;
    case kWsl: LaunchById(instance, parent_hwnd, L"wsl"); break;
    case kRun: LaunchById(instance, parent_hwnd, L"run"); break;
    case kCalculator: LaunchById(instance, parent_hwnd, L"calc"); break;
    case kNotepad: LaunchById(instance, parent_hwnd, L"notepad"); break;
    case kPaint: LaunchById(instance, parent_hwnd, L"paint"); break;
    case kSnip: LaunchById(instance, parent_hwnd, L"snip"); break;
    case kMedia: LaunchById(instance, parent_hwnd, L"media"); break;
    case kWeather: LaunchById(instance, parent_hwnd, L"weather"); break;
    case kSystemMonitor: LaunchById(instance, parent_hwnd, L"sysmon"); break;
    case kTaskManager: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"classic.taskmgr"); break;
    case kDeviceManager: (void)LaunchWindowsTarget(parent_hwnd, L"devmgmt.msc"); break;
    case kRegedit: LaunchById(instance, parent_hwnd, L"regedit"); break;
    case kSystemDrive: LaunchById(instance, parent_hwnd, L"systemdrive"); break;
    case kApps: LaunchById(instance, parent_hwnd, L"apps"); break;
    case kCloudSettings: LaunchById(instance, parent_hwnd, L"settings"); break;
    case kWindowsSettings: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:"); break;
    case kDisplay: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:display"); break;
    case kSound: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:sound"); break;
    case kNetwork: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:network-status"); break;
    case kWifi: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:network-wifi"); break;
    case kBluetooth: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:bluetooth"); break;
    case kStorage: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:storagesense"); break;
    case kClipboard: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:clipboard"); break;
    case kDateTime: LaunchById(instance, parent_hwnd, L"datetime"); break;
    case kDevelopers: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:developers"); break;
    case kSecurity: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:windowsdefender"); break;
    case kWindowsUpdate: (void)LaunchWindowsTarget(parent_hwnd, L"ms-settings:windowsupdate"); break;
    case kHealth: LaunchById(instance, parent_hwnd, L"health"); break;
    case kShowDesktop: (void)NativeShellBridge::ToggleShowDesktop(); break;
    case kLock: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.lock"); break;
    case kRestartCloudOS: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.restart-cloudos"); break;
    case kExitCloudOS: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.exit-cloudos"); break;
    case kRestartWindows: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.restart-windows"); break;
    case kShutdownWindows: (void)ExecuteNamedShellAction(instance, parent_hwnd, L"session.shutdown"); break;
    default: break;
    }
}
} // namespace CloudOS
