#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <shellapi.h>

namespace CloudOS
{

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
    apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "Chromium / Web Browser", "", "Produtividade", "CloudOS", true, false, false, "browser", true, true});
    apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Prompt de Comando / Shell", "", "Utilitários", "CloudOS", true, false, false, "terminal", true, true});
    apps_.push_back({"cloudos:calculator", "Calculadora", "cloudos", "Calculadora de Sistema", "", "Utilitários", "CloudOS", true, false, false, "calculator", false, false});
    apps_.push_back({"cloudos:settings", "Configurações", "cloudos", "Painel de Controle e Ajustes", "", "Sistema", "CloudOS", true, false, false, "settings", false, false});
    apps_.push_back({"cloudos:drive", "CloudOS Drive", "cloudos", "Workspace & Projetos", "", "Produtividade", "CloudOS", true, false, false, "drive", false, false});
    apps_.push_back({"cloudos:trash", "Lixeira", "cloudos", "Itens e Pastas Deletados", "", "Sistema", "CloudOS", true, false, false, "trash", false, false});

    // 2. Windows Native Applications
    apps_.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Produtividade", "Windows", true, true, false, "vscode", true, true});
    apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, false, false, "notepad", true, false});
    apps_.push_back({"windows:powershell", "PowerShell 7", "windows", "Windows Terminal & Shell", "", "Utilitários", "Windows", true, true, false, "powershell", true, true});
    apps_.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false, "taskmgr", false, false});
    apps_.push_back({"windows:cmd", "Prompt de Comando", "windows", "cmd.exe", "", "Utilitários", "Windows", true, false, false, "cmd", false, false});
    apps_.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false, "explorer", false, false});

    // 3. Linux / WSLg GUI Applications
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (!distros.empty())
    {
        const std::string default_distro = distros.front();
        apps_.push_back({"wsl:ubuntu-terminal", "Ubuntu Terminal", "linux", "Linux Bash Shell (" + default_distro + ")", default_distro, "Linux / WSL", "Ubuntu (WSL)", true, false, false, "terminal", true, true});
        apps_.push_back({"wsl:gimp", "GIMP Image Editor", "linux", "GNU Image Manipulation Program (WSLg)", default_distro, "Produtividade", "Ubuntu (WSL)", true, true, false, "gimp", true, false});
        apps_.push_back({"wsl:wireshark", "Wireshark", "linux", "Network Protocol Analyzer (WSLg)", default_distro, "Utilitários", "Ubuntu (WSL)", true, true, false, "wireshark", false, false});
        apps_.push_back({"wsl:zenmap", "Zenmap", "linux", "Security Scanner GUI (WSLg)", default_distro, "Utilitários", "Ubuntu (WSL)", true, true, false, "zenmap", false, false});
        apps_.push_back({"wsl:xterm", "XTerm", "linux", "X11 Terminal Emulator (WSLg)", default_distro, "Linux / WSL", "Ubuntu (WSL)", true, true, false, "terminal", false, false});
    }

    initialized_.store(true);
}

bool AppServiceV21::LaunchApp(const std::string& app_id, std::string& err)
{
    // Defensive whitelist resolution: reject arbitrary command injection
    if (app_id == "files" || app_id == "cloudos:files")
    {
        ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "browser" || app_id == "cloudos:browser")
    {
        ShellExecuteW(nullptr, L"open", L"https://google.com", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "terminal" || app_id == "cloudos:terminal")
    {
        ShellExecuteW(nullptr, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "calculator" || app_id == "cloudos:calculator")
    {
        ShellExecuteW(nullptr, L"open", L"calc.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "settings" || app_id == "cloudos:settings")
    {
        ShellExecuteW(nullptr, L"open", L"ms-settings:", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "drive" || app_id == "cloudos:drive")
    {
        WCHAR user_profile[MAX_PATH];
        if (GetEnvironmentVariableW(L"USERPROFILE", user_profile, MAX_PATH) > 0)
        {
            ShellExecuteW(nullptr, L"open", user_profile, nullptr, nullptr, SW_SHOWNORMAL);
            return true;
        }
        return true;
    }
    if (app_id == "trash" || app_id == "cloudos:trash")
    {
        ShellExecuteW(nullptr, L"open", L"shell:RecycleBinFolder", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }

    // Windows Native Apps
    if (app_id == "windows:notepad")
    {
        ShellExecuteW(nullptr, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:vscode")
    {
        ShellExecuteW(nullptr, L"open", L"code.cmd", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:powershell")
    {
        ShellExecuteW(nullptr, L"open", L"powershell.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:taskmgr")
    {
        ShellExecuteW(nullptr, L"open", L"taskmgr.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:cmd")
    {
        ShellExecuteW(nullptr, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "windows:explorer")
    {
        ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL);
        return true;
    }

    // Linux / WSLg Apps
    if (app_id == "wsl:ubuntu-terminal" || app_id == "linux:ubuntu-terminal" || app_id == "ubuntu-terminal")
    {
        ShellExecuteW(nullptr, L"open", L"wsl.exe", L"~", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:gimp" || app_id == "linux:gimp" || app_id == "gimp")
    {
        ShellExecuteW(nullptr, L"open", L"wsl.exe", L"-d Ubuntu -- gimp", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:wireshark" || app_id == "linux:wireshark")
    {
        ShellExecuteW(nullptr, L"open", L"wsl.exe", L"-d Ubuntu -- wireshark", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:zenmap" || app_id == "linux:zenmap")
    {
        ShellExecuteW(nullptr, L"open", L"wsl.exe", L"-d Ubuntu -- zenmap", nullptr, SW_SHOWNORMAL);
        return true;
    }
    if (app_id == "wsl:xterm" || app_id == "linux:xterm")
    {
        ShellExecuteW(nullptr, L"open", L"wsl.exe", L"-d Ubuntu -- xterm", nullptr, SW_SHOWNORMAL);
        return true;
    }

    err = "Invalid or unverified application identifier: " + app_id;
    return false;
}

} // namespace CloudOS
