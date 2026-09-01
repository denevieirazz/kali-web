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

bool FileExists(const std::wstring& path)
{
    const DWORD attr = GetFileAttributesW(path.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
}

bool FindExecutableOnPath(const wchar_t* name, std::wstring& result)
{
    WCHAR path[MAX_PATH]{};
    DWORD length = SearchPathW(nullptr, name, nullptr, ARRAYSIZE(path), path, nullptr);
    if (length == 0 || length >= ARRAYSIZE(path))
    {
        return false;
    }
    result.assign(path, length);
    return true;
}

bool FindVsCode(std::wstring& result)
{
    if (FindExecutableOnPath(L"Code.exe", result))
    {
        return true;
    }

    WCHAR local_app_data[MAX_PATH]{};
    if (GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, ARRAYSIZE(local_app_data)) > 0)
    {
        std::wstring candidate = std::wstring(local_app_data) + L"\\Programs\\Microsoft VS Code\\Code.exe";
        if (FileExists(candidate))
        {
            result = std::move(candidate);
            return true;
        }
    }

    WCHAR program_files[MAX_PATH]{};
    if (GetEnvironmentVariableW(L"ProgramFiles", program_files, ARRAYSIZE(program_files)) > 0)
    {
        std::wstring candidate = std::wstring(program_files) + L"\\Microsoft VS Code\\Code.exe";
        if (FileExists(candidate))
        {
            result = std::move(candidate);
            return true;
        }
    }

    return false;
}

bool LaunchDefaultWslTerminal(std::string& err)
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

    const std::wstring args = L"-d \"" + distro + L"\" --cd ~";
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

    // CloudOS surfaces backed by real local Windows operations.
    apps_.push_back({"cloudos:files", "Arquivos", "cloudos", "Filesystem Windows + WSL", "", "Sistema", "CloudOS", true, false, false, "files", true, true});
    apps_.push_back({"cloudos:browser", "Navegador Padrão", "cloudos", "Abre o navegador padrão do Windows", "", "Internet", "Windows", true, false, false, "browser", true, true});
    apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Windows Terminal ou Prompt de Comando", "", "Utilitários", "Windows", true, false, false, "terminal", true, true});
    apps_.push_back({"cloudos:calculator", "Calculadora", "cloudos", "Calculadora do Windows", "", "Utilitários", "Windows", true, false, false, "calculator", false, false});
    apps_.push_back({"cloudos:settings", "Configurações", "cloudos", "Configurações do Windows", "", "Sistema", "Windows", true, false, false, "settings", false, false});
    apps_.push_back({"cloudos:trash", "Lixeira", "cloudos", "Lixeira do Windows", "", "Sistema", "Windows", true, false, false, "trash", false, false});

    // Windows applications that are guaranteed by the OS.
    apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, false, false, "notepad", true, false});
    apps_.push_back({"windows:powershell", "PowerShell", "windows", "PowerShell 7 quando disponível; Windows PowerShell como fallback", "", "Utilitários", "Windows", true, false, false, "powershell", true, true});
    apps_.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false, "taskmgr", false, false});
    apps_.push_back({"windows:cmd", "Prompt de Comando", "windows", "cmd.exe", "", "Utilitários", "Windows", true, false, false, "cmd", false, false});
    apps_.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false, "explorer", false, false});

    // Optional applications only appear when the executable can be resolved.
    std::wstring vscode_path;
    if (FindVsCode(vscode_path))
    {
        apps_.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Desenvolvimento", "Windows", true, false, false, "vscode", true, true});
    }

    // WSL only advertises the one operation we can validate without executing
    // arbitrary commands inside the distro: starting its shell.
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (!distros.empty())
    {
        const std::string& default_distro = distros.front();
        apps_.push_back({
            "wsl:default-terminal",
            default_distro + " Terminal",
            "linux",
            "Linux Shell (" + default_distro + ")",
            default_distro,
            "Linux / WSL",
            default_distro + " (WSL)",
            true,
            false,
            false,
            "terminal",
            true,
            true});
    }

    initialized_.store(true);
}

bool AppServiceV21::LaunchApp(const std::string& app_id, std::string& err)
{
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
        std::wstring path;
        if (!FindVsCode(path))
        {
            err = "Visual Studio Code is not installed or cannot be resolved";
            return false;
        }
        return ShellOpen(path.c_str(), nullptr, err);
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

    // Keep legacy terminal aliases accepted for V21 package compatibility,
    // but do not advertise Ubuntu when the installed distro has another name.
    if (app_id == "wsl:default-terminal" || app_id == "wsl:ubuntu-terminal" ||
        app_id == "linux:ubuntu-terminal" || app_id == "ubuntu-terminal")
    {
        return LaunchDefaultWslTerminal(err);
    }

    err = "Invalid or unverified application identifier: " + app_id;
    return false;
}

} // namespace CloudOS
