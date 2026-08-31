#include "cloudos_flutter_bridge_v20.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <sstream>

namespace CloudOS
{

namespace
{
constexpr const char* kChannelName = "cloudos/native/v19";

std::string WideToUtf8(const std::wstring& wstr)
{
    if (wstr.empty()) return {};
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (size_needed <= 0) return {};
    std::string result(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), result.data(), size_needed, nullptr, nullptr);
    return result;
}

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return {};
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), nullptr, 0);
    if (size_needed <= 0) return {};
    std::wstring result(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), result.data(), size_needed);
    return result;
}

bool SafeFileExists(const std::wstring& path)
{
    DWORD attr = GetFileAttributesW(path.c_str());
    return (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY));
}
} // namespace

void CloudOSFlutterBridgeV20::RegisterWithMessenger(
    flutter::BinaryMessenger* messenger,
    HWND window_handle)
{
    auto& bridge = Instance();
    bridge.Initialize(window_handle);

    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            CloudOSFlutterBridgeV20::Instance().HandleMethodCall(call, std::move(result));
        });

    bridge.is_registered_.store(true);
}

CloudOSFlutterBridgeV20& CloudOSFlutterBridgeV20::Instance()
{
    static CloudOSFlutterBridgeV20 instance;
    return instance;
}

void CloudOSFlutterBridgeV20::Initialize(HWND window_handle)
{
    window_handle_ = window_handle;
    RefreshAppCatalog();
    RefreshSystemSnapshot();
}

void CloudOSFlutterBridgeV20::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    const std::string& method = method_call.method_name();

    if (method == "getApps")
    {
        const auto apps = GetApps();
        flutter::EncodableList list;
        list.reserve(apps.size());

        for (const auto& app : apps)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("id")] = flutter::EncodableValue(app.id);
            map[flutter::EncodableValue("name")] = flutter::EncodableValue(app.name);
            map[flutter::EncodableValue("platform")] = flutter::EncodableValue(app.platform);
            map[flutter::EncodableValue("subtitle")] = flutter::EncodableValue(app.subtitle);
            map[flutter::EncodableValue("distro")] = flutter::EncodableValue(app.distro);
            map[flutter::EncodableValue("category")] = flutter::EncodableValue(app.category);
            map[flutter::EncodableValue("source")] = flutter::EncodableValue(app.source);
            map[flutter::EncodableValue("canLaunch")] = flutter::EncodableValue(app.can_launch);
            map[flutter::EncodableValue("pinned")] = flutter::EncodableValue(app.pinned);
            map[flutter::EncodableValue("recent")] = flutter::EncodableValue(app.recent);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }

        result->Success(flutter::EncodableValue(std::move(list)));
        return;
    }

    if (method == "getSystemSnapshot")
    {
        const auto snapshot = GetSystemSnapshot();
        flutter::EncodableMap map;
        map[flutter::EncodableValue("deviceName")] = flutter::EncodableValue(snapshot.device_name);
        map[flutter::EncodableValue("networkName")] = flutter::EncodableValue(snapshot.network_name);
        map[flutter::EncodableValue("volume")] = flutter::EncodableValue(snapshot.volume);
        map[flutter::EncodableValue("brightness")] = flutter::EncodableValue(snapshot.brightness);
        map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(snapshot.battery_percent);
        map[flutter::EncodableValue("wslAvailable")] = flutter::EncodableValue(snapshot.wsl_available);
        map[flutter::EncodableValue("currentWorkspace")] = flutter::EncodableValue(snapshot.current_workspace);

        flutter::EncodableList distros_list;
        for (const auto& d : snapshot.distros)
        {
            distros_list.push_back(flutter::EncodableValue(d));
        }
        map[flutter::EncodableValue("distros")] = flutter::EncodableValue(std::move(distros_list));

        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "launchApp")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (!args)
        {
            result->Error("INVALID_ARGUMENT", "launchApp requires a map with an 'id' property");
            return;
        }

        auto it = args->find(flutter::EncodableValue("id"));
        if (it == args->end() || !std::holds_alternative<std::string>(it->second))
        {
            result->Error("INVALID_ARGUMENT", "Missing or invalid 'id' parameter");
            return;
        }

        const std::string app_id = std::get<std::string>(it->second);
        bool ok = LaunchApp(app_id);
        if (ok)
        {
            result->Success(flutter::EncodableValue(true));
        }
        else
        {
            result->Error("LAUNCH_FAILED", "Failed to launch application with ID: " + app_id);
        }
        return;
    }

    if (method == "setVolume")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                SetVolume(std::get<double>(it->second));
                result->Success(flutter::EncodableValue(true));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setVolume requires a double 'value'");
        return;
    }

    if (method == "setBrightness")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                SetBrightness(std::get<double>(it->second));
                result->Success(flutter::EncodableValue(true));
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setBrightness requires a double 'value'");
        return;
    }

    if (method == "getBridgeInfo")
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("schema")] = flutter::EncodableValue(20);
        map[flutter::EncodableValue("version")] = flutter::EncodableValue("v20");
        map[flutter::EncodableValue("bridge_type")] = flutter::EncodableValue("CloudOSFlutterBridgeV20");
        map[flutter::EncodableValue("channel")] = flutter::EncodableValue(kChannelName);
        map[flutter::EncodableValue("arbitrary_command_api")] = flutter::EncodableValue(false);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    result->NotImplemented();
}

std::vector<BridgeAppItem> CloudOSFlutterBridgeV20::GetApps()
{
    std::lock_guard<std::mutex> lock(catalog_mutex_);
    if (!catalog_initialized_.load())
    {
        RefreshAppCatalog();
    }
    return cached_apps_;
}

BridgeSystemSnapshot CloudOSFlutterBridgeV20::GetSystemSnapshot()
{
    std::lock_guard<std::mutex> lock(snapshot_mutex_);
    if (!snapshot_initialized_.load())
    {
        RefreshSystemSnapshot();
    }
    return cached_snapshot_;
}

std::vector<std::string> CloudOSFlutterBridgeV20::QueryWslDistributions()
{
    std::vector<std::string> distros;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Lxss", 0, KEY_READ, &key) == ERROR_SUCCESS)
    {
        DWORD index = 0;
        WCHAR subkey_name[256];
        DWORD name_len = ARRAYSIZE(subkey_name);

        while (RegEnumKeyExW(key, index++, subkey_name, &name_len, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
        {
            HKEY distro_key = nullptr;
            if (RegOpenKeyExW(key, subkey_name, 0, KEY_READ, &distro_key) == ERROR_SUCCESS)
            {
                WCHAR distro_name[256];
                DWORD distro_name_size = sizeof(distro_name);
                DWORD type = 0;
                if (RegQueryValueExW(distro_key, L"DistributionName", nullptr, &type, reinterpret_cast<LPBYTE>(distro_name), &distro_name_size) == ERROR_SUCCESS)
                {
                    distros.push_back(WideToUtf8(distro_name));
                }
                RegCloseKey(distro_key);
            }
            name_len = ARRAYSIZE(subkey_name);
        }
        RegCloseKey(key);
    }

    if (distros.empty())
    {
        WCHAR sys_dir[MAX_PATH];
        GetSystemDirectoryW(sys_dir, MAX_PATH);
        std::wstring wsl_exe = std::wstring(sys_dir) + L"\\wsl.exe";
        if (SafeFileExists(wsl_exe))
        {
            distros.push_back("Ubuntu");
        }
    }

    return distros;
}

void CloudOSFlutterBridgeV20::RefreshAppCatalog()
{
    std::vector<BridgeAppItem> apps;

    // 1. CloudOS Built-in Apps
    apps.push_back({"files", "Arquivos", "cloudos", "Windows + Linux (WSL2)", "", "Sistema", "CloudOS", true, true, false});
    apps.push_back({"browser", "Navegador Web", "cloudos", "Chromium / Web Browser", "", "Produtividade", "CloudOS", true, true, true});
    apps.push_back({"terminal", "Terminal", "cloudos", "Prompt de Comando / Shell", "", "Utilitários", "CloudOS", true, true, true});
    apps.push_back({"calculator", "Calculadora", "cloudos", "Calculadora de Sistema", "", "Utilitários", "CloudOS", true, false, false});
    apps.push_back({"settings", "Configurações", "cloudos", "Painel de Controle e Ajustes", "", "Sistema", "CloudOS", true, false, false});
    apps.push_back({"drive", "CloudOS Drive", "cloudos", "Workspace & Projetos", "", "Produtividade", "CloudOS", true, false, false});
    apps.push_back({"trash", "Lixeira", "cloudos", "Itens e Pastas Deletados", "", "Sistema", "CloudOS", true, false, false});

    // 2. Windows Native Applications
    apps.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Produtividade", "Windows", true, true, true});
    apps.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, true, false});
    apps.push_back({"windows:powershell", "PowerShell 7", "windows", "Windows Terminal & Shell", "", "Utilitários", "Windows", true, true, true});
    apps.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false});
    apps.push_back({"windows:cmd", "Prompt de Comando", "windows", "cmd.exe", "", "Utilitários", "Windows", true, false, false});
    apps.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false});

    // 3. Linux / WSLg GUI Applications
    const auto distros = QueryWslDistributions();
    if (!distros.empty())
    {
        const std::string default_distro = distros.front();
        apps.push_back({"wsl:ubuntu-terminal", "Ubuntu Terminal", "linux", "Linux Bash Shell (" + default_distro + ")", default_distro, "Linux / WSL", "Ubuntu (WSL)", true, true, true});
        apps.push_back({"wsl:gimp", "GIMP Image Editor", "linux", "GNU Image Manipulation Program (WSLg)", default_distro, "Produtividade", "Ubuntu (WSL)", true, true, false});
        apps.push_back({"wsl:wireshark", "Wireshark", "linux", "Network Protocol Analyzer (WSLg)", default_distro, "Utilitários", "Ubuntu (WSL)", true, false, false});
        apps.push_back({"wsl:zenmap", "Zenmap", "linux", "Security Scanner GUI (WSLg)", default_distro, "Utilitários", "Ubuntu (WSL)", true, false, false});
        apps.push_back({"wsl:xterm", "XTerm", "linux", "X11 Terminal Emulator (WSLg)", default_distro, "Linux / WSL", "Ubuntu (WSL)", true, false, false});
    }

    cached_apps_ = std::move(apps);
    catalog_initialized_.store(true);
}

void CloudOSFlutterBridgeV20::RefreshSystemSnapshot()
{
    BridgeSystemSnapshot snap;

    // Device name
    WCHAR computer_name[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD size = ARRAYSIZE(computer_name);
    if (GetComputerNameW(computer_name, &size))
    {
        snap.device_name = WideToUtf8(computer_name);
    }
    else
    {
        snap.device_name = "CloudOS Desktop";
    }

    // Network name
    snap.network_name = "CloudOS Network • Wi-Fi 6";

    // Battery
    SYSTEM_POWER_STATUS power;
    if (GetSystemPowerStatus(&power) && power.BatteryLifePercent != 255)
    {
        snap.battery_percent = static_cast<int>(power.BatteryLifePercent);
    }
    else
    {
        snap.battery_percent = 100;
    }

    // Volume & Brightness
    snap.volume = 0.72;
    snap.brightness = 0.85;

    // WSL status
    snap.distros = QueryWslDistributions();
    snap.wsl_available = !snap.distros.empty();
    snap.current_workspace = 1;

    cached_snapshot_ = std::move(snap);
    snapshot_initialized_.store(true);
}

bool CloudOSFlutterBridgeV20::LaunchApp(const std::string& app_id)
{
    if (app_id == "files" || app_id == "cloudos:files")
    {
        ShellExecuteW(window_handle_, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "browser" || app_id == "cloudos:browser")
    {
        ShellExecuteW(window_handle_, L"open", L"https://google.com", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "terminal" || app_id == "cloudos:terminal")
    {
        ShellExecuteW(window_handle_, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "calculator" || app_id == "cloudos:calculator")
    {
        ShellExecuteW(window_handle_, L"open", L"calc.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "settings" || app_id == "cloudos:settings")
    {
        ShellExecuteW(window_handle_, L"open", L"ms-settings:", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "drive" || app_id == "cloudos:drive")
    {
        WCHAR user_profile[MAX_PATH];
        if (GetEnvironmentVariableW(L"USERPROFILE", user_profile, MAX_PATH) > 0)
        {
            ShellExecuteW(window_handle_, L"open", user_profile, nullptr, nullptr, SW_SHOWNORMAL);
            return true;
        }
        return true;
    }
    if (app_id == "trash" || app_id == "cloudos:trash")
    {
        ShellExecuteW(window_handle_, L"open", L"shell:RecycleBinFolder", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }

    // Windows Native Apps
    if (app_id == "windows:notepad")
    {
        ShellExecuteW(window_handle_, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:vscode")
    {
        ShellExecuteW(window_handle_, L"open", L"code.cmd", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:powershell")
    {
        ShellExecuteW(window_handle_, L"open", L"powershell.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:taskmgr")
    {
        ShellExecuteW(window_handle_, L"open", L"taskmgr.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:cmd")
    {
        ShellExecuteW(window_handle_, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:explorer")
    {
        ShellExecuteW(window_handle_, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }

    // Linux / WSLg Apps
    if (app_id == "wsl:ubuntu-terminal" || app_id == "linux:ubuntu-terminal" || app_id == "ubuntu-terminal")
    {
        ShellExecuteW(window_handle_, L"open", L"wsl.exe", L"~", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:gimp" || app_id == "linux:gimp" || app_id == "gimp")
    {
        ShellExecuteW(window_handle_, L"open", L"wsl.exe", L"-d Ubuntu -- gimp", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:wireshark" || app_id == "linux:wireshark")
    {
        ShellExecuteW(window_handle_, L"open", L"wsl.exe", L"-d Ubuntu -- wireshark", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:zenmap" || app_id == "linux:zenmap")
    {
        ShellExecuteW(window_handle_, L"open", L"wsl.exe", L"-d Ubuntu -- zenmap", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:xterm" || app_id == "linux:xterm")
    {
        ShellExecuteW(window_handle_, L"open", L"wsl.exe", L"-d Ubuntu -- xterm", nullptr, SW_SHOWNORMAL);
        return true;
    }

    return false;
}

bool CloudOSFlutterBridgeV20::SetVolume(double volume)
{
    std::lock_guard<std::mutex> lock(snapshot_mutex_);
    cached_snapshot_.volume = std::clamp(volume, 0.0, 1.0);
    return true;
}

bool CloudOSFlutterBridgeV20::SetBrightness(double brightness)
{
    std::lock_guard<std::mutex> lock(snapshot_mutex_);
    cached_snapshot_.brightness = std::clamp(brightness, 0.0, 1.0);
    return true;
}

} // namespace CloudOS
