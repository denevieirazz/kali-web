#include <windows.h>
#include <commctrl.h>
#include <tlhelp32.h>
#include <shellapi.h>
#include <array>
#include <string>
#include <vector>

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

namespace
{
struct Handle final
{
    HANDLE value{};
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    explicit Handle(HANDLE handle = nullptr) : value(handle) {}
};

std::wstring ImagePath(HANDLE process)
{
    std::array<wchar_t, 32768> buffer{};
    DWORD size = static_cast<DWORD>(buffer.size());
    return QueryFullProcessImageNameW(process, 0, buffer.data(), &size)
        ? std::wstring(buffer.data(), size) : std::wstring{};
}

std::wstring ShellPath()
{
    const auto own = ImagePath(GetCurrentProcess());
    const auto slash = own.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring{} : own.substr(0, slash + 1) + L"CloudOS.exe";
}

std::vector<BYTE> TokenUserData(HANDLE token)
{
    DWORD bytes = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
    if (bytes == 0) return {};
    std::vector<BYTE> data(bytes);
    if (!GetTokenInformation(token, TokenUser, data.data(), bytes, &bytes)) return {};
    return data;
}

bool IsAllowedTarget(HANDLE process, const std::wstring& expected)
{
    if (expected.empty()) return false;
    const auto path = ImagePath(process);
    if (path.empty() || _wcsicmp(path.c_str(), expected.c_str()) != 0) return false;
    Handle target_token, own_token;
    if (!OpenProcessToken(process, TOKEN_QUERY, &target_token.value) ||
        !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &own_token.value)) return false;
    DWORD target_session = 0, own_session = 0, bytes = 0;
    if (!GetTokenInformation(target_token.value, TokenSessionId, &target_session, sizeof(DWORD), &bytes) ||
        !GetTokenInformation(own_token.value, TokenSessionId, &own_session, sizeof(DWORD), &bytes) ||
        target_session != own_session) return false;
    const auto target_user = TokenUserData(target_token.value);
    const auto own_user = TokenUserData(own_token.value);
    return !target_user.empty() && !own_user.empty() && EqualSid(
        reinterpret_cast<const TOKEN_USER*>(target_user.data())->User.Sid,
        reinterpret_cast<const TOKEN_USER*>(own_user.data())->User.Sid) != FALSE;
}

bool StopInstallationShell(unsigned& stopped)
{
    const auto expected = ShellPath();
    if (expected.empty()) return false;
    Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    if (snapshot.value == INVALID_HANDLE_VALUE) return false;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool success = true;
    if (!Process32FirstW(snapshot.value, &entry)) return false;
    do
    {
        if (_wcsicmp(entry.szExeFile, L"CloudOS.exe") != 0) continue;
        Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE,
            FALSE, entry.th32ProcessID));
        if (!process.value) { success = false; continue; }
        // Validate and act on the SAME handle: PID reuse cannot redirect a kill.
        if (!IsAllowedTarget(process.value, expected)) continue;
        if (TerminateProcess(process.value, 1))
        {
            ++stopped;
            if (WaitForSingleObject(process.value, 2000) != WAIT_OBJECT_0) success = false;
        }
        else if (WaitForSingleObject(process.value, 0) != WAIT_OBJECT_0) success = false;
    } while (Process32NextW(snapshot.value, &entry));
    return success;
}

bool OpenWindowsExplorer()
{
    std::array<wchar_t, MAX_PATH> directory{};
    const UINT size = GetWindowsDirectoryW(directory.data(), static_cast<UINT>(directory.size()));
    if (size == 0 || size >= directory.size()) return false;
    const std::wstring executable = std::wstring(directory.data(), size) + L"\\explorer.exe";
    DWORD shell_pid = 0;
    GetWindowThreadProcessId(GetShellWindow(), &shell_pid);
    Handle shell(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, shell_pid));
    if (shell.value && IsAllowedTarget(shell.value, executable)) return true;
    std::wstring command = L"\"" + executable + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE, 0,
        nullptr, directory.data(), &startup, &process)) return false;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

int SelfTest()
{
    // No termination, launch, registry or file operations in this mode.
    const auto own = ImagePath(GetCurrentProcess());
    if (own.empty() || !IsAllowedTarget(GetCurrentProcess(), own)) return 1;
    if (IsAllowedTarget(GetCurrentProcess(), L"")) return 2;
    if (IsAllowedTarget(GetCurrentProcess(), ShellPath())) return 3;
    if (IsAllowedTarget(GetCurrentProcess(), own + L".other")) return 4;
    return 0;
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR arguments, int)
{
    if (arguments && wcscmp(arguments, L"--self-test") == 0) return SelfTest();
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&controls);
    const TASKDIALOG_BUTTON buttons[] = {
        {101, L"Abrir Explorer do Windows\nNao altera o shell padrao nem encerra aplicativos."},
        {102, L"Encerrar CloudOS desta instalacao\nApenas processos do mesmo usuario e sessao. Requer confirmacao."}
    };
    for (;;)
    {
        TASKDIALOGCONFIG config{};
        config.cbSize = sizeof(config);
        config.hInstance = instance;
        config.dwFlags = TDF_USE_COMMAND_LINKS | TDF_ALLOW_DIALOG_CANCELLATION | TDF_SIZE_TO_CONTENT;
        config.dwCommonButtons = TDCBF_CLOSE_BUTTON;
        config.pszWindowTitle = L"CloudOS Recovery";
        config.pszMainInstruction = L"Recuperacao independente do CloudOS";
        config.pszContent = L"Este utilitario funciona sem carregar CloudOS.exe, seu runtime ou WebView2.\n"
            L"Nenhuma acao e automatica. Seus arquivos, pins e configuracoes nao serao apagados.\n"
            L"Para diagnosticos sem dados pessoais, use collect-native-diagnostics.ps1.";
        config.pszMainIcon = TD_INFORMATION_ICON;
        config.cButtons = static_cast<UINT>(std::size(buttons));
        config.pButtons = buttons;
        config.nDefaultButton = IDCLOSE;
        int choice = IDCLOSE;
        if (FAILED(TaskDialogIndirect(&config, &choice, nullptr, nullptr)))
        {
            MessageBoxW(nullptr, L"Nao foi possivel abrir a interface de recuperacao.", L"CloudOS Recovery", MB_OK | MB_ICONERROR);
            return 1;
        }
        if (choice == 101)
        {
            const bool opened = OpenWindowsExplorer();
            MessageBoxW(nullptr, opened ? L"Explorer ja estava ativo ou sua inicializacao foi solicitada."
                : L"Nao foi possivel iniciar Explorer. Nenhum processo foi encerrado.",
                L"CloudOS Recovery", MB_OK | (opened ? MB_ICONINFORMATION : MB_ICONERROR));
        }
        else if (choice == 102)
        {
            if (MessageBoxW(nullptr,
                L"Forcar o encerramento pode perder edicoes nao salvas nos apps internos do CloudOS.\n"
                L"Outros aplicativos e instalacoes nao serao encerrados. Continuar?",
                L"Confirmar recuperacao", MB_YESNO | MB_DEFBUTTON2 | MB_ICONWARNING) != IDYES) continue;
            unsigned stopped = 0;
            const bool ok = StopInstallationShell(stopped);
            const std::wstring result = L"Processos CloudOS encerrados: " + std::to_wstring(stopped) +
                (ok ? L". Nenhum arquivo de estado foi apagado." : L". Alguns processos nao puderam ser consultados/encerrados.");
            MessageBoxW(nullptr, result.c_str(), L"CloudOS Recovery", MB_OK | (ok ? MB_ICONINFORMATION : MB_ICONWARNING));
        }
        else return 0;
    }
}
