#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <shellapi.h>

#include <string>

namespace CloudOS
{

namespace
{
std::wstring Utf8ToWide(const std::string& value)
{
    if (value.empty()) return {};
    const int needed = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (needed <= 0) return {};

    std::wstring result(needed, L'\0');
    MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        needed);
    return result;
}

bool ShellOpen(const wchar_t* target, const wchar_t* parameters, std::string& err)
{
    const HINSTANCE result = ShellExecuteW(
        nullptr,
        L"open",
        target,
        parameters,
        nullptr,
        SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) > 32)
    {
        return true;
    }

    err = "Windows rejected launch request";
    return false;
}

bool LaunchDefaultWsl(const wchar_t* command, std::string& err)
{
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (distros.empty())
    {
        err = "No registered WSL distribution is available";
        return false;
    }

    const std::wstring distro = Utf8ToWide(distros.front());
    if (distro.empty())
    {
        err = "Default WSL distribution name is invalid";
        return false;
    }

    std::wstring args = L"-d \"" + distro + L"\" ";
    args += command;
    return ShellOpen(L"wsl.exe", args.c_str(), err);
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

    // 1. CloudOS first-party applications.
    apps_.push_back({"cloudos:files", "Arquivos", "cloudos", "Windows + Linux (WSL2)", "", "Sistema", "CloudOS", true, false, false, "files", true, false});
    apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "Navegador Web", "", "Produtividade", "CloudOS", true, false, false, "browser", true, true});
    apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Terminal do Sistema", "", "Utilitários", "CloudOS", true, false, false, "terminal", true, true});
    apps_.push_back({"cloudos:calculator", "Calculadora", "cloudos", "Calculadora do Sistema", "", "Utilitários", "CloudOS", true, false, false, "calculator", false, false});
    apps_.push_back({"cloudos:settings", "Configurações", "cloudos", "Ajustes do Sistema", "", "Sistema", "CloudOS", true, false, false, "settings", false, false});
    apps_.push_back({"cloudos:drive", "CloudOS Drive", "cloudos", "Workspace & Projetos", "", "Produtividade", "CloudOS", true, false, false, "drive", false, false});
    apps_.push_back({"cloudos:trash", "Lixeira", "cloudos", "Itens e Pastas Excluídos", "", "Sistema", "CloudOS", true, false, false, "trash", false, false});

    // 2. Windows native applications.
    apps_.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Produtividade", "Windows", true, false, false, "vscode", true, true});
    apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, false, false, "notepad", true, false});
    apps_.push_back({"windows:powershell", "PowerShell", "windows", "PowerShell 7 quando disponível", "", "Utilitários", "Windows", true, false, false, "powershell", true, true});
    apps_.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false, "taskmgr", false, false});
    apps_.push_back({"windows:cmd", "Prompt de Comando", "windows", "cmd.exe", "", "Utilitários", "Windows", true, false, false, "cmd", false, false});
    apps_.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false, "explorer", false, false});

    // 3. Linux / WSLg applications for the actual first registered distro.
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (!distros.empty())
    {
        const std::string& default_distro = distros.front();
        const std::string source = default_distro + " (WSL)";
        apps_.push_back({"wsl:ubuntu-terminal", default_distro + " Terminal", "linux", "Linux Shell (" + default_distro + ")", default_distro, "Linux / WSL", source, true, false, false, "terminal", true, true});
        apps_.push_back({"wsl:gimp", "GIMP Image Editor", "linux", "GNU Image Manipulation Program (WSLg)", default_distro, "Produtividade", source, true, false, false, "gimp", true, false});
        apps_.push_back({"wsl:wireshark", "Wireshark", "linux", "Network Protocol Analyzer (WSLg)", default_distro, "Utilitários", source, true, false, false, "wireshark", false, false});
        apps_.push_back({"wsl:zenmap", "Zenmap", "linux", "Security Scanner GUI (WSLg)", default_distro, "Utilitários", source, true, false, false, "zenmap", false, false});
        apps_.push_back({"wsl:xterm", "XTerm", "linux", "X11 Terminal Emulator (WSLg)", default_distro, "Linux / WSL", source, true, false, false, "terminal", false, false});
    }

    initialized_.store(true);
}

bool AppServiceV21::LaunchApp(const std::string& app_id, std::string& err)
{
    // Defensive whitelist resolution: no arbitrary command string crosses the
    // public broker protocol.
    if (app_id == "files" || app_id == "cloudos:files")
    {
        return ShellOpen(L"explorer.exe", nullptr, err);
    }
    if (app_id == "browser" || app_id == "cloudos:browser")
    {
        return ShellOpen(L"https://www.google.com", nullptr, err);
    }
    if (app_id == "terminal" || app_id == "cloudos:terminal")
    {
        return ShellOpen(L"wt.exe", nullptr, err) || ShellOpen(L"cmd.exe", nullptr, err);
    }
    if (app_id == "calculator" || app_id == "cloudos:calculator")
    {
        return ShellOpen(L"calc.exe", nullptr, err);
    }
    if (app_id == "settings" || app_id == "cloudos:settings")
    {
        return ShellOpen(L"ms-settings:", nullptr, err);
    }
    if (app_id == "drive" || app_id == "cloudos:drive")
    {
        WCHAR user_profile[MAX_PATH]{};
        if (GetEnvironmentVariableW(L"USERPROFILE", user_profile, ARRAYSIZE(user_profile)) == 0)
        {
            err = "USERPROFILE is unavailable";
            return false;
        }
        return ShellOpen(user_profile, nullptr, err);
    }
    if (app_id == "trash" || app_id == "cloudos:trash")
    {
        return ShellOpen(L"shell:RecycleBinFolder", nullptr, err);
    }

    if (app_id == "windows:notepad")
    {
        return ShellOpen(L"notepad.exe", nullptr, err);
    }
    if (app_id == "windows:vscode")
    {
        return ShellOpen(L"code.cmd", nullptr, err) || ShellOpen(L"Code.exe", nullptr, err);
    }
    if (app_id == "windows:powershell")
    {
        return ShellOpen(L"pwsh.exe", nullptr, err) || ShellOpen(L"powershell.exe", nullptr, err);
    }
    if (app_id == "windows:taskmgr")
    {
        return ShellOpen(L"taskmgr.exe", nullptr, err);
    }
    if (app_id == "windows:cmd")
    {
        return ShellOpen(L"cmd.exe", nullptr, err);
    }
    if (app_id == "windows:explorer")
    {
        return ShellOpen(L"explorer.exe", nullptr, err);
    }

    if (app_id == "wsl:ubuntu-terminal" || app_id == "wsl:default-terminal" ||
        app_id == "linux:ubuntu-terminal" || app_id == "ubuntu-terminal")
    {
        return LaunchDefaultWsl(L"--cd ~", err);
    }
    if (app_id == "wsl:gimp" || app_id == "linux:gimp" || app_id == "gimp")
    {
        return LaunchDefaultWsl(L"-- gimp", err);
    }
    if (app_id == "wsl:wireshark" || app_id == "linux:wireshark")
    {
        return LaunchDefaultWsl(L"-- wireshark", err);
    }
    if (app_id == "wsl:zenmap" || app_id == "linux:zenmap")
    {
        return LaunchDefaultWsl(L"-- zenmap", err);
    }
    if (app_id == "wsl:xterm" || app_id == "linux:xterm")
    {
        return LaunchDefaultWsl(L"-- xterm", err);
    }

    err = "Invalid or unverified application identifier: " + app_id;
    return false;
}

} // namespace CloudOS
