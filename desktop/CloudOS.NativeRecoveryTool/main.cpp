#include <windows.h>
#include <tlhelp32.h>
#include <shlobj.h>
#include <commctrl.h>
#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#pragma comment(lib, "comctl32.lib")

namespace
{
std::wstring GetRecoveryDir()
{
    wchar_t localAppData[MAX_PATH] = {0};
    if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData) == S_OK)
    {
        std::filesystem::path p(localAppData);
        p /= L"CloudOS";
        p /= L"Recovery";
        std::error_code ec;
        std::filesystem::create_directories(p, ec);
        return p.wstring();
    }
    return L"";
}

void LogRecoveryEvent(const std::wstring& msg)
{
    std::wstring recDir = GetRecoveryDir();
    if (recDir.empty()) return;
    std::filesystem::path logFile = std::filesystem::path(recDir) / L"recovery.log";
    std::wofstream out(logFile, std::ios::app);
    if (out.is_open())
    {
        const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        out << L"[" << now << L"] " << msg << std::endl;
    }
}

bool IsProcessRunning(const wchar_t* exeName)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool found = false;
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            if (_wcsicmp(entry.szExeFile, exeName) == 0)
            {
                found = true;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

std::wstring ReadRegistryString(HKEY root, const wchar_t* subKey, const wchar_t* valueName)
{
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS)
    {
        return L"";
    }

    wchar_t buffer[1024] = {0};
    DWORD bufferSize = sizeof(buffer);
    DWORD type = 0;
    LONG result = RegQueryValueExW(hKey, valueName, nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &bufferSize);
    RegCloseKey(hKey);

    if (result == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ))
    {
        return buffer;
    }
    return L"";
}

bool DeleteRegistryValueSafe(HKEY root, const wchar_t* subKey, const wchar_t* valueName)
{
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_SET_VALUE, &hKey) != ERROR_SUCCESS)
    {
        return true; // Key doesn't exist, already safe
    }
    LONG result = RegDeleteValueW(hKey, valueName);
    RegCloseKey(hKey);
    return (result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
}

bool EnsureExplorerRunning()
{
    if (IsProcessRunning(L"explorer.exe"))
    {
        return true;
    }

    wchar_t winDir[MAX_PATH] = {0};
    GetWindowsDirectoryW(winDir, MAX_PATH);
    std::wstring explorerPath = std::wstring(winDir) + L"\\explorer.exe";

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (CreateProcessW(explorerPath.c_str(), nullptr, nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
    {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        LogRecoveryEvent(L"Spawned explorer.exe during recovery.");
        return true;
    }
    return false;
}

std::string WideToUtf8(std::wstring_view wide)
{
    if (wide.empty()) return {};
    const int req = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    if (req <= 0) return {};
    std::string out(static_cast<size_t>(req), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), out.data(), req, nullptr, nullptr);
    return out;
}

std::string EscapeJson(const std::string& input)
{
    std::string out;
    for (char c : input)
    {
        if (c == '\\')
        {
            out += "\\\\";
        }
        else if (c == '"')
        {
            out += "\\\"";
        }
        else if (c == '\n')
        {
            out += "\\n";
        }
        else if (c == '\r')
        {
            out += "\\r";
        }
        else if (c == '\t')
        {
            out += "\\t";
        }
        else
        {
            out += c;
        }
    }
    return out;
}

int ActionStatus(bool outputJson = true)
{
    const std::wstring hkcuPolicyShell = ReadRegistryString(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", L"Shell");
    const std::wstring hkcuWinlogonShell = ReadRegistryString(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
    const std::wstring hklmWinlogonShell = ReadRegistryString(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");
    const std::wstring hklmUserinit = ReadRegistryString(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Userinit");
    const bool explorerActive = IsProcessRunning(L"explorer.exe");
    const bool cloudosActive = IsProcessRunning(L"CloudOS.ShellBootstrap.exe") || IsProcessRunning(L"cloudos_flutter_shell.exe");

    std::wstring effectiveShell = L"explorer.exe";
    std::string shellStatus = "EXPLORER";

    if (!hkcuPolicyShell.empty())
    {
        effectiveShell = hkcuPolicyShell;
        shellStatus = "CLOUDOS_ACTIVE";
    }
    else if (!hkcuWinlogonShell.empty())
    {
        effectiveShell = hkcuWinlogonShell;
        shellStatus = "CLOUDOS_ACTIVE";
    }

    if (outputJson)
    {
        std::cout << "{\n"
                  << "  \"status\": \"" << EscapeJson(shellStatus) << "\",\n"
                  << "  \"effective_shell\": \"" << EscapeJson(WideToUtf8(effectiveShell)) << "\",\n"
                  << "  \"hkcu_policy_shell\": \"" << EscapeJson(WideToUtf8(hkcuPolicyShell)) << "\",\n"
                  << "  \"hkcu_winlogon_shell\": \"" << EscapeJson(WideToUtf8(hkcuWinlogonShell)) << "\",\n"
                  << "  \"hklm_winlogon_shell\": \"" << EscapeJson(WideToUtf8(hklmWinlogonShell)) << "\",\n"
                  << "  \"userinit\": \"" << EscapeJson(WideToUtf8(hklmUserinit)) << "\",\n"
                  << "  \"userinit_intact\": " << (hklmUserinit.find(L"userinit.exe") != std::wstring::npos ? "true" : "false") << ",\n"
                  << "  \"explorer_running\": " << (explorerActive ? "true" : "false") << ",\n"
                  << "  \"cloudos_running\": " << (cloudosActive ? "true" : "false") << "\n"
                  << "}\n";
    }
    else
    {
        std::wcout << L"=== CloudOS Shell Recovery Status ===" << std::endl;
        std::wcout << L"Status Atual do Shell: " << (shellStatus == "EXPLORER" ? L"EXPLORER (Padrao do Windows)" : L"CLOUDOS_ACTIVE") << std::endl;
        std::wcout << L"Shell Efetivo: " << effectiveShell << std::endl;
        std::wcout << L"HKCU Policy Shell: " << (hkcuPolicyShell.empty() ? L"(Nao configurado / Padrao)" : hkcuPolicyShell) << std::endl;
        std::wcout << L"HKCU Winlogon Shell: " << (hkcuWinlogonShell.empty() ? L"(Nao configurado / Padrao)" : hkcuWinlogonShell) << std::endl;
        std::wcout << L"HKLM Winlogon Shell: " << hklmWinlogonShell << std::endl;
        std::wcout << L"Userinit: " << hklmUserinit << std::endl;
        std::wcout << L"Windows Explorer Ativo: " << (explorerActive ? L"SIM" : L"NAO") << std::endl;
        std::wcout << L"CloudOS Ativo: " << (cloudosActive ? L"SIM" : L"NAO") << std::endl;
    }
    return 0;
}

int ActionRestoreExplorerShell()
{
    LogRecoveryEvent(L"ACTION: restore-explorer-shell invoked.");

    bool ok1 = DeleteRegistryValueSafe(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", L"Shell");
    bool ok2 = DeleteRegistryValueSafe(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", L"Shell");

    bool explorerLaunched = EnsureExplorerRunning();

    LogRecoveryEvent(L"ACTION RESULT: Deleted HKCU Policies Shell=" + std::to_wstring(ok1) +
                     L", Deleted HKCU Winlogon Shell=" + std::to_wstring(ok2) +
                     L", Explorer Running=" + std::to_wstring(explorerLaunched));

    std::cout << "{\n"
              << "  \"success\": " << ((ok1 && ok2 && explorerLaunched) ? "true" : "false") << ",\n"
              << "  \"action\": \"restore-explorer-shell\",\n"
              << "  \"message\": \"Windows Explorer shell successfully restored as default.\",\n"
              << "  \"explorer_running\": " << (explorerLaunched ? "true" : "false") << "\n"
              << "}\n";

    return (ok1 && ok2 && explorerLaunched) ? 0 : 1;
}

int ActionDisableCloudOSShell()
{
    LogRecoveryEvent(L"ACTION: disable-cloudos-shell invoked.");
    DeleteRegistryValueSafe(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", L"CloudOS");
    return ActionRestoreExplorerShell();
}

int ActionVerify()
{
    wchar_t ownModule[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, ownModule, MAX_PATH);
    std::filesystem::path binDir = std::filesystem::path(ownModule).parent_path();

    const std::vector<std::wstring> required = {
        L"CloudOS.exe",
        L"CloudOS.Supervisor.exe",
        L"CloudOS.SystemBroker.exe",
        L"CloudOS.ShellBootstrap.exe",
        L"CloudOS.Recovery.exe",
        L"cloudos_flutter_shell.exe"
    };

    int missing = 0;
    for (const auto& name : required)
    {
        std::filesystem::path p = binDir / name;
        if (!std::filesystem::exists(p) || std::filesystem::file_size(p) == 0)
        {
            missing++;
        }
    }

    std::cout << "{\n"
              << "  \"verified\": " << (missing == 0 ? "true" : "false") << ",\n"
              << "  \"missing_components\": " << missing << ",\n"
              << "  \"install_dir\": \"" << EscapeJson(WideToUtf8(binDir.wstring())) << "\"\n"
              << "}\n";
    return (missing == 0) ? 0 : 1;
}

int ActionUI()
{
    const std::wstring hkcuPolicyShell = ReadRegistryString(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", L"Shell");
    std::wstring msg = L"Central de Recuperacao do CloudOS (Recuperacao de Emergencia)\n\n";
    if (!hkcuPolicyShell.empty())
    {
        msg += L"O CloudOS esta atualmente registrado como seu Shell personalizado.\n";
        msg += L"Arquivo configurado: " + hkcuPolicyShell + L"\n\n";
        msg += L"Deseja restaurar imediatamente o Windows Explorer como shell oficial e iniciar a area de trabalho?";
    }
    else
    {
        msg += L"O Windows Explorer ja e o shell padrao ativo do sistema.\n\n";
        msg += L"Deseja garantir a execucao do Explorer agora?";
    }

    int choice = MessageBoxW(
        nullptr,
        msg.c_str(),
        L"CloudOS Recovery Tool",
        MB_YESNO | MB_ICONQUESTION | MB_TOPMOST);

    if (choice == IDYES)
    {
        ActionRestoreExplorerShell();
        MessageBoxW(nullptr, L"Windows Explorer restaurado com sucesso!", L"Recuperado", MB_OK | MB_ICONINFORMATION);
        return 0;
    }
    return 0;
}
} // namespace

int wmain(int argc, wchar_t* argv[])
{
    if (argc > 1)
    {
        std::wstring verb = argv[1];
        if (verb == L"status") return ActionStatus(true);
        if (verb == L"restore-explorer-shell") return ActionRestoreExplorerShell();
        if (verb == L"disable-cloudos-shell") return ActionDisableCloudOSShell();
        if (verb == L"verify") return ActionVerify();
        if (verb == L"ui") return ActionUI();
    }

    // Default: If run without arguments, check if we have console or should show UI
    HWND consoleWnd = GetConsoleWindow();
    DWORD consolePid = 0;
    GetWindowThreadProcessId(consoleWnd, &consolePid);

    if (consoleWnd != nullptr && consolePid == GetCurrentProcessId())
    {
        // Interactive console
        ActionStatus(false);
        std::wcout << L"\nComandos disponiveis:" << std::endl;
        std::wcout << L"  CloudOS.Recovery.exe status" << std::endl;
        std::wcout << L"  CloudOS.Recovery.exe restore-explorer-shell" << std::endl;
        std::wcout << L"  CloudOS.Recovery.exe disable-cloudos-shell" << std::endl;
        std::wcout << L"  CloudOS.Recovery.exe verify" << std::endl;
        std::wcout << L"  CloudOS.Recovery.exe ui" << std::endl;
        return 0;
    }

    return ActionUI();
}
