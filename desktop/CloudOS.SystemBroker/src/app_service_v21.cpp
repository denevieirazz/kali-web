#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "native_shell_activation_client_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <string_view>

namespace CloudOS
{

namespace
{
bool LaunchSucceeded(HINSTANCE result)
{
    return reinterpret_cast<intptr_t>(result) > 32;
}

struct SettingsRoute final
{
    std::string_view app_id;
    const wchar_t* uri;
};

const wchar_t* ResolveSettingsUri(std::string_view app_id) noexcept
{
    static constexpr std::array<SettingsRoute, 6> kRoutes = {{
        {"settings", L"ms-settings:"},
        {"cloudos:settings", L"ms-settings:"},
        {"cloudos:settings:wifi", L"ms-settings:network-wifi"},
        {"cloudos:settings:bluetooth", L"ms-settings:bluetooth"},
        {"cloudos:settings:nightlight", L"ms-settings:nightlight"},
        {"cloudos:settings:focus", L"ms-settings:quiethours"},
    }};
    for (const SettingsRoute& route : kRoutes)
    {
        if (app_id == route.app_id) return route.uri;
    }
    return nullptr;
}

std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) return {};

    std::wstring result(static_cast<size_t>(length), L'\0');
    return MultiByteToWideChar(
               CP_UTF8,
               MB_ERR_INVALID_CHARS,
               value.data(),
               static_cast<int>(value.size()),
               result.data(),
               length) == length
        ? result
        : std::wstring{};
}

std::wstring QuoteArgument(std::wstring_view value)
{
    std::wstring result = L"\"";
    size_t backslashes = 0;
    for (const wchar_t character : value)
    {
        if (character == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (character == L'"')
        {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'"');
            backslashes = 0;
            continue;
        }
        result.append(backslashes, L'\\');
        backslashes = 0;
        result.push_back(character);
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'"');
    return result;
}

bool IsAllowedLinuxCommand(std::string_view command)
{
    static constexpr std::array<std::string_view, 4> kAllowedCommands = {
        "gimp",
        "wireshark",
        "zenmap",
        "xterm",
    };
    return std::find(kAllowedCommands.begin(), kAllowedCommands.end(), command) !=
        kAllowedCommands.end();
}

bool ResolveWslLaunch(
    const std::string& app_id,
    const std::vector<std::string>& distros,
    const std::string& default_distro,
    std::string& out_distro,
    std::string& out_command)
{
    for (const std::string& distro : distros)
    {
        const std::string prefix = "wsl:" + distro + ":";
        if (app_id == prefix + "terminal")
        {
            out_distro = distro;
            out_command.clear();
            return true;
        }
        for (const std::string_view command : {std::string_view("gimp"), std::string_view("wireshark"), std::string_view("zenmap"), std::string_view("xterm")})
        {
            if (app_id == prefix + std::string(command))
            {
                out_distro = distro;
                out_command = command;
                return true;
            }
        }
    }

    if (default_distro.empty()) return false;

    if (app_id == "wsl:ubuntu-terminal" || app_id == "linux:ubuntu-terminal" || app_id == "ubuntu-terminal")
    {
        out_distro = default_distro;
        out_command.clear();
        return true;
    }
    if (app_id == "wsl:gimp" || app_id == "linux:gimp" || app_id == "gimp")
    {
        out_distro = default_distro;
        out_command = "gimp";
        return true;
    }
    if (app_id == "wsl:wireshark" || app_id == "linux:wireshark")
    {
        out_distro = default_distro;
        out_command = "wireshark";
        return true;
    }
    if (app_id == "wsl:zenmap" || app_id == "linux:zenmap")
    {
        out_distro = default_distro;
        out_command = "zenmap";
        return true;
    }
    if (app_id == "wsl:xterm" || app_id == "linux:xterm")
    {
        out_distro = default_distro;
        out_command = "xterm";
        return true;
    }
    return false;
}

bool LaunchWsl(const std::string& distro, const std::string& command, std::string& err)
{
    const std::wstring wide_distro = Utf8ToWide(distro);
    if (wide_distro.empty())
    {
        err = "WSL distribution contains invalid UTF-8";
        return false;
    }

    std::wstring parameters = L"-d " + QuoteArgument(wide_distro);
    if (!command.empty())
    {
        if (!IsAllowedLinuxCommand(command))
        {
            err = "Linux command is not allowlisted";
            return false;
        }
        const std::wstring wide_command = Utf8ToWide(command);
        if (wide_command.empty())
        {
            err = "Linux command contains invalid UTF-8";
            return false;
        }
        parameters += L" -- " + QuoteArgument(wide_command);
    }

    if (!LaunchSucceeded(ShellExecuteW(
            nullptr,
            L"open",
            L"wsl.exe",
            parameters.c_str(),
            nullptr,
            SW_SHOWNORMAL)))
    {
        err = "Failed to dispatch WSL application";
        return false;
    }

    JsonObject payload;
    payload["distro"] = JsonValue(distro);
    payload["surface"] = JsonValue(command.empty() ? "terminal" : command);
    EventBusV21::Instance().Publish("wsl.launchRequested", payload);
    return true;
}

bool ActivateNativeCloudOSApp(
    ShellActivationV21::App app,
    const char* surface,
    std::string& err)
{
    if (!NativeShellActivationClientV21::Activate(app, &err))
    {
        return false;
    }

    JsonObject payload;
    payload["surface"] = JsonValue(surface);
    payload["authority"] = JsonValue("CloudOS.NativeShell");
    EventBusV21::Instance().Publish("shell.activationRequested", payload);
    return true;
}
} // namespace

JsonObject AppItem::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = JsonValue(id);
    obj["name"] = JsonValue(name);
    obj["platform"] = JsonValue(platform);
    obj["subtitle"] = JsonValue(subtitle);
    obj["distro"] = JsonValue(distro);
    obj["category"] = JsonValue(category);
    obj["source"] = JsonValue(source);
    obj["canLaunch"] = JsonValue(can_launch);
    obj["canUninstall"] = JsonValue(can_uninstall);
    obj["canUpdate"] = JsonValue(can_update);
    obj["iconKey"] = JsonValue(icon_key.empty() ? id : icon_key);
    obj["pinned"] = JsonValue(pinned);
    obj["recent"] = JsonValue(recent);
    return obj;
}

AppServiceV21& AppServiceV21::Instance()
{
    static AppServiceV21 instance;
    return instance;
}

std::vector<AppItem> AppServiceV21::GetApps()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_.load())
    {
        Refresh();
    }
    return apps_;
}

void AppServiceV21::Invalidate()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        Refresh();
        generation_++;
    }

    JsonObject payload;
    payload["generation"] = JsonValue(static_cast<int64_t>(generation_.load()));
    EventBusV21::Instance().Publish("apps.catalogChanged", payload);
}

void AppServiceV21::Refresh()
{
    apps_.clear();

    // 1. CloudOS First-Party Applications
    apps_.push_back({"cloudos:files", "Arquivos", "cloudos", "Windows + Linux (WSL2)", "", "Sistema", "CloudOS", true, false, false, "files", true, false});
    apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "WebView2 nativo do CloudOS", "", "Produtividade", "CloudOS", true, false, false, "browser", true, true});
    apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Terminal nativo / ConPTY", "", "Utilitários", "CloudOS", true, false, false, "terminal", true, true});
    apps_.push_back({"cloudos:calculator", "Calculadora", "cloudos", "Calculadora de Sistema", "", "Utilitários", "CloudOS", true, false, false, "calculator", false, false});
    apps_.push_back({"cloudos:settings", "Configurações", "cloudos", "Painel de Controle e Ajustes", "", "Sistema", "CloudOS", true, false, false, "settings", false, false});
    apps_.push_back({"cloudos:drive", "CloudOS Drive", "cloudos", "Workspace & Projetos", "", "Produtividade", "CloudOS", true, false, false, "drive", false, false});
    apps_.push_back({"cloudos:trash", "Lixeira", "cloudos", "Indisponível até a superfície first-party de lixeira", "", "Sistema", "CloudOS", false, false, false, "trash", false, false});

    // 2. Windows Native Applications. CMD and PowerShell remain discoverable
    // catalog profiles, but the CloudOS Flutter shell owns their ConPTY launch.
    apps_.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Produtividade", "Windows", true, true, false, "vscode", true, true});
    apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, false, false, "notepad", true, false});
    apps_.push_back({"windows:powershell", "PowerShell", "windows", "CloudOS Terminal / ConPTY", "", "Utilitários", "Windows", true, true, false, "powershell", true, true});
    apps_.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false, "taskmgr", false, false});
    apps_.push_back({"windows:cmd", "Prompt de Comando", "windows", "CloudOS Terminal / ConPTY", "", "Utilitários", "Windows", true, false, false, "cmd", false, false});
    apps_.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false, "explorer", false, false});

    // 3. Linux / WSL. Catalog discovery stays passive: it never starts a distro.
    // Only registered distros are advertised, and only the terminal is guaranteed
    // without probing packages inside Linux. WSLg apps may still be launched through
    // the explicit legacy/dynamic allowlist, which is an intentional user action.
    const auto distros = WslServiceV21::Instance().GetDistributions();
    for (const std::string& distro : distros)
    {
        const std::string source = distro + " (WSL)";
        apps_.push_back({
            "wsl:" + distro + ":terminal",
            distro + " Terminal",
            "linux",
            "Linux shell (lazy start)",
            distro,
            "Linux / WSL",
            source,
            true,
            false,
            false,
            "terminal",
            true,
            true,
        });
    }

    initialized_.store(true);
}

bool AppServiceV21::LaunchApp(const std::string& app_id, std::string& err)
{
    // CloudOS first-party Browser/Terminal are owned by the NativeShell. The Broker
    // asks the authoritative shell to activate them instead of dispatching substitute
    // Windows applications from the broker process.
    if (app_id == "browser" || app_id == "cloudos:browser")
    {
        return ActivateNativeCloudOSApp(
            ShellActivationV21::App::Browser,
            "browser",
            err);
    }
    if (app_id == "terminal" || app_id == "cloudos:terminal")
    {
        return ActivateNativeCloudOSApp(
            ShellActivationV21::App::Terminal,
            "terminal",
            err);
    }

    // CMD/PowerShell are terminal profiles, not external Windows applications.
    // Reject broker-level execution so a caller cannot bypass the Flutter ConPTY
    // surface and make a console escape onto the Windows desktop.
    if (app_id == "windows:cmd" || app_id == "windows:powershell")
    {
        err = "Windows console profiles must be opened through CloudOS Terminal / ConPTY";
        return false;
    }

    // Defensive whitelist resolution: reject arbitrary command injection.
    if (app_id == "files" || app_id == "cloudos:files")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "calculator" || app_id == "cloudos:calculator")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"calc.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (const wchar_t* settings_uri = ResolveSettingsUri(app_id); settings_uri != nullptr)
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", settings_uri, nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "drive" || app_id == "cloudos:drive")
    {
        err = "CloudOS Drive is a first-party Files location and must be opened by the CloudOS shell";
        return false;
    }
    if (app_id == "trash" || app_id == "cloudos:trash")
    {
        err = "CloudOS Trash has no approved first-party surface yet";
        return false;
    }

    // Windows Native Apps
    if (app_id == "windows:notepad")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:vscode")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"code.cmd", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:taskmgr")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"taskmgr.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:explorer")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }

    // Linux / WSLg apps are the lazy-start boundary. Merely opening Start/Search or
    // loading system state never invokes wsl.exe. Only an explicit launch arrives here.
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (!distros.empty() && WslServiceV21::Instance().IsWslAvailable())
    {
        std::string distro;
        std::string command;
        if (ResolveWslLaunch(
                app_id,
                distros,
                WslServiceV21::Instance().GetDefaultDistribution(),
                distro,
                command))
        {
            return LaunchWsl(distro, command, err);
        }
    }

    err = "Invalid or unavailable application identifier: " + app_id;
    return false;
}

} // namespace CloudOS
