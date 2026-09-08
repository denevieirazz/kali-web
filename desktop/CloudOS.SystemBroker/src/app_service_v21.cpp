#include "app_service_v21.h"
#include "event_bus_v21.h"
#include "wsl_service_v21.h"

#include <Windows.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <unordered_set>

namespace CloudOS
{

namespace
{
bool LaunchSucceeded(HINSTANCE result)
{
    return reinterpret_cast<intptr_t>(result) > 32;
}

std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
            static_cast<int>(value.size()), result.data(), length) != length)
    {
        return {};
    }
    return result;
}

bool ExecutableExists(const wchar_t* name)
{
    std::array<wchar_t, 32768> path{};
    const DWORD length = SearchPathW(nullptr, name, nullptr, static_cast<DWORD>(path.size()), path.data(), nullptr);
    return length > 0 && length < path.size();
}

std::wstring QuoteArgument(std::wstring_view value)
{
    std::wstring result = L"\"";
    for (wchar_t character : value)
    {
        if (character == L'"') result += L"\\\"";
        else result.push_back(character);
    }
    result.push_back(L'"');
    return result;
}

bool IsWslCommandAvailable(const std::string& distro, const std::string& command)
{
    static const std::unordered_set<std::string> allowed = {"gimp", "wireshark", "zenmap", "xterm"};
    if (allowed.find(command) == allowed.end()) return false;

    const std::wstring wide_distro = Utf8ToWide(distro);
    const std::wstring wide_command = Utf8ToWide(command);
    if (wide_distro.empty() || wide_command.empty()) return false;
    const std::wstring command_line = L"wsl.exe -d " + QuoteArgument(wide_distro) +
        L" -- which " + wide_command;
    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process))
    {
        return false;
    }
    const DWORD wait = WaitForSingleObject(process.hProcess, 4000);
    DWORD exit_code = ERROR_GEN_FAILURE;
    if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &exit_code);
    else TerminateProcess(process.hProcess, ERROR_TIMEOUT);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return wait == WAIT_OBJECT_0 && exit_code == 0;
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
    apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "Chromium / Web Browser", "", "Produtividade", "CloudOS", true, false, false, "browser", true, true});
    apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Prompt de Comando / Shell", "", "Utilitários", "CloudOS", true, false, false, "terminal", true, true});
    apps_.push_back({"cloudos:calculator", "Calculadora", "cloudos", "Calculadora de Sistema", "", "Utilitários", "CloudOS", true, false, false, "calculator", false, false});
    apps_.push_back({"cloudos:settings", "Configurações", "cloudos", "Painel de Controle e Ajustes", "", "Sistema", "CloudOS", true, false, false, "settings", false, false});
    apps_.push_back({"cloudos:drive", "CloudOS Drive", "cloudos", "Workspace & Projetos", "", "Produtividade", "CloudOS", true, false, false, "drive", false, false});
    apps_.push_back({"cloudos:trash", "Lixeira", "cloudos", "Itens e Pastas Deletados", "", "Sistema", "CloudOS", true, false, false, "trash", false, false});

    // 2. Windows Native Applications
    if (ExecutableExists(L"code.exe")) apps_.push_back({"windows:vscode", "Visual Studio Code", "windows", "Code Editor & IDE", "", "Produtividade", "Windows", true, true, false, "vscode", true, true});
    if (ExecutableExists(L"notepad.exe")) apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, false, false, "notepad", true, false});
    if (ExecutableExists(L"pwsh.exe")) apps_.push_back({"windows:powershell", "PowerShell 7", "windows", "Windows Terminal & Shell", "", "Utilitários", "Windows", true, true, false, "powershell", true, true});
    if (ExecutableExists(L"taskmgr.exe")) apps_.push_back({"windows:taskmgr", "Gerenciador de Tarefas", "windows", "Monitor de Recursos do Sistema", "", "Sistema", "Windows", true, false, false, "taskmgr", false, false});
    if (ExecutableExists(L"cmd.exe")) apps_.push_back({"windows:cmd", "Prompt de Comando", "windows", "cmd.exe", "", "Utilitários", "Windows", true, false, false, "cmd", false, false});
    if (ExecutableExists(L"explorer.exe")) apps_.push_back({"windows:explorer", "Windows Explorer", "windows", "Explorador de Arquivos do Windows", "", "Sistema", "Windows", true, false, false, "explorer", false, false});

    // 3. Linux / WSLg GUI Applications
    const auto distros = WslServiceV21::Instance().GetDistributions();
    if (!distros.empty())
    {
        for (const auto& distro : distros)
        {
            const std::string source = distro + " (WSL)";
            apps_.push_back({"wsl:" + distro + ":terminal", distro + " Terminal", "linux", "Linux shell (" + distro + ")", distro, "Linux / WSL", source, true, false, false, "terminal", true, true});
            if (IsWslCommandAvailable(distro, "gimp")) apps_.push_back({"wsl:" + distro + ":gimp", "GIMP Image Editor", "linux", "GNU Image Manipulation Program (WSLg)", distro, "Produtividade", source, true, true, false, "gimp", false, false});
            if (IsWslCommandAvailable(distro, "wireshark")) apps_.push_back({"wsl:" + distro + ":wireshark", "Wireshark", "linux", "Network Protocol Analyzer (WSLg)", distro, "Utilitários", source, true, true, false, "wireshark", false, false});
            if (IsWslCommandAvailable(distro, "zenmap")) apps_.push_back({"wsl:" + distro + ":zenmap", "Zenmap", "linux", "Security Scanner GUI (WSLg)", distro, "Utilitários", source, true, true, false, "zenmap", false, false});
            if (IsWslCommandAvailable(distro, "xterm")) apps_.push_back({"wsl:" + distro + ":xterm", "XTerm", "linux", "X11 Terminal Emulator (WSLg)", distro, "Linux / WSL", source, true, true, false, "terminal", false, false});
        }
    }

    initialized_.store(true);
}

bool AppServiceV21::LaunchApp(const std::string& app_id, std::string& err)
{
    // Defensive whitelist resolution: reject arbitrary command injection
    if (app_id == "files" || app_id == "cloudos:files")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "browser" || app_id == "cloudos:browser")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"https://google.com", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "terminal" || app_id == "cloudos:terminal")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "calculator" || app_id == "cloudos:calculator")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"calc.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "settings" || app_id == "cloudos:settings")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"ms-settings:", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "drive" || app_id == "cloudos:drive")
    {
        WCHAR user_profile[MAX_PATH];
        if (GetEnvironmentVariableW(L"USERPROFILE", user_profile, MAX_PATH) > 0)
        {
            return LaunchSucceeded(ShellExecuteW(nullptr, L"open", user_profile, nullptr, nullptr, SW_SHOWNORMAL));
        }
        return false;
    }
    if (app_id == "trash" || app_id == "cloudos:trash")
    {
        return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"shell:RecycleBinFolder", nullptr, nullptr, SW_SHOWNORMAL));
    }

    // Windows Native Apps
    if (app_id == "windows:notepad")
    {
        return ExecutableExists(L"notepad.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:vscode")
    {
        return ExecutableExists(L"code.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"code.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:powershell")
    {
        return ExecutableExists(L"pwsh.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"pwsh.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:taskmgr")
    {
        return ExecutableExists(L"taskmgr.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"taskmgr.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:cmd")
    {
        return ExecutableExists(L"cmd.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"cmd.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }
    if (app_id == "windows:explorer")
    {
        return ExecutableExists(L"explorer.exe") && LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"explorer.exe", nullptr, nullptr, SW_SHOWNORMAL));
    }

    // Linux / WSLg Apps
    if (app_id.rfind("wsl:", 0) == 0)
    {
        const size_t second_colon = app_id.find(':', 4);
        if (second_colon != std::string::npos)
        {
            const std::string distro = app_id.substr(4, second_colon - 4);
            const std::string command = app_id.substr(second_colon + 1);
            const auto distros = WslServiceV21::Instance().GetDistributions();
            if (std::find(distros.begin(), distros.end(), distro) == distros.end())
            {
                err = "WSL distribution is unavailable: " + distro;
                return false;
            }
            if (command != "terminal" && !IsWslCommandAvailable(distro, command))
            {
                err = "Linux application is unavailable: " + command;
                return false;
            }
            const std::wstring wide_distro = Utf8ToWide(distro);
            const std::wstring wide_command = Utf8ToWide(command);
            if (wide_distro.empty() || (command != "terminal" && wide_command.empty()))
            {
                err = "Application identifier contains invalid UTF-8";
                return false;
            }
            const std::wstring parameters = L"-d " + QuoteArgument(wide_distro) +
                (command == "terminal" ? L"" : L" -- " + QuoteArgument(wide_command));
            return LaunchSucceeded(ShellExecuteW(nullptr, L"open", L"wsl.exe", parameters.c_str(), nullptr, SW_SHOWNORMAL));
        }
    }

    err = "Invalid or unverified application identifier: " + app_id;
    return false;
}

} // namespace CloudOS
