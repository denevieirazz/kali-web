#include "native_env_doctor_window.h"

#include "cloudos_native_runtime.h"
#include "native_settings_window.h"

#include <WebView2.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <ShlObj.h>
#include <TlHelp32.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <new>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "shell32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.EnvDoctor.v1";
constexpr int kRunButtonId = 4101;
constexpr int kListId = 4102;

enum class CheckSeverity
{
    Ok,
    Warning,
    Info,
};

struct CheckItem final
{
    std::wstring name;
    CheckSeverity severity{CheckSeverity::Info};
    std::wstring detail;
};

struct DoctorState final
{
    HWND button{};
    HWND list{};
    HFONT font{};
};

const wchar_t* SeverityLabel(CheckSeverity severity) noexcept
{
    switch (severity)
    {
    case CheckSeverity::Ok: return L"OK";
    case CheckSeverity::Warning: return L"ATENCAO";
    case CheckSeverity::Info:
    default: return L"INFO";
    }
}

bool ExistsOnPath(const wchar_t* executable)
{
    std::array<wchar_t, 32768> path{};
    const DWORD length = SearchPathW(
        nullptr,
        executable,
        nullptr,
        static_cast<DWORD>(path.size()),
        path.data(),
        nullptr);
    return length > 0 && length < path.size();
}

std::wstring LocalAppDataPath()
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &raw)) ||
        raw == nullptr)
    {
        if (raw != nullptr) CoTaskMemFree(raw);
        return {};
    }
    std::wstring value(raw);
    CoTaskMemFree(raw);
    return value;
}

std::vector<std::wstring> CurrentSessionCloudOSProcesses()
{
    std::vector<std::wstring> result;
    const DWORD current_session = []
    {
        DWORD session = 0;
        (void)ProcessIdToSessionId(GetCurrentProcessId(), &session);
        return session;
    }();

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return result;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            DWORD session = 0;
            if (!ProcessIdToSessionId(entry.th32ProcessID, &session) || session != current_session)
                continue;

            const wchar_t* name = entry.szExeFile;
            if (_wcsicmp(name, L"CloudOS.exe") == 0 ||
                _wcsicmp(name, L"CloudOS.Supervisor.exe") == 0 ||
                _wcsicmp(name, L"CloudOS.SystemBroker.exe") == 0 ||
                _wcsicmp(name, L"CloudOS.BrokerProbe.exe") == 0 ||
                _wcsicmp(name, L"cloudos_flutter_shell.exe") == 0)
            {
                result.emplace_back(name);
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    std::sort(result.begin(), result.end());
    result.erase(std::unique(result.begin(), result.end()), result.end());
    return result;
}

CheckItem CheckRuntimeAbi()
{
    const std::uint32_t abi = cloudos_native_runtime_abi();
    return {
        L"Runtime nativo",
        abi == CLOUDOS_NATIVE_RUNTIME_ABI ? CheckSeverity::Ok : CheckSeverity::Warning,
        L"ABI carregada: " + std::to_wstring(abi) + L" / esperada: " +
            std::to_wstring(CLOUDOS_NATIVE_RUNTIME_ABI),
    };
}

CheckItem CheckConPty()
{
    HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
    const bool available = kernel != nullptr &&
        GetProcAddress(kernel, "CreatePseudoConsole") != nullptr &&
        GetProcAddress(kernel, "ResizePseudoConsole") != nullptr;
    return {
        L"ConPTY",
        available ? CheckSeverity::Ok : CheckSeverity::Warning,
        available ? L"Pseudo console nativa disponivel" : L"CreatePseudoConsole nao foi encontrado",
    };
}

CheckItem CheckWebView2()
{
    LPWSTR version = nullptr;
    const HRESULT result = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (FAILED(result) || version == nullptr)
    {
        if (version != nullptr) CoTaskMemFree(version);
        return {
            L"WebView2 Runtime",
            CheckSeverity::Warning,
            L"Evergreen WebView2 Runtime nao foi detectado",
        };
    }

    std::wstring detail = L"Runtime detectado: ";
    detail += version;
    CoTaskMemFree(version);
    return {L"WebView2 Runtime", CheckSeverity::Ok, std::move(detail)};
}

CheckItem CheckWsl()
{
    if (!ExistsOnPath(L"wsl.exe"))
    {
        return {L"WSL", CheckSeverity::Warning, L"wsl.exe nao encontrado no Windows"};
    }

    const CloudOSNativeSettings settings = CloudOSNativeSettingsWindow::Load();
    if (settings.default_wsl_distribution.empty())
    {
        return {
            L"WSL",
            CheckSeverity::Info,
            L"Mecanismo WSL existe, mas nenhuma distro padrao foi configurada no CloudOS",
        };
    }

    BOOL registered = FALSE;
    const BOOL queried = cloudos_native_wsl_is_registered(
        settings.default_wsl_distribution.c_str(),
        &registered);
    if (!queried)
    {
        return {
            L"WSL",
            CheckSeverity::Warning,
            L"API nativa do WSL nao conseguiu consultar " + settings.default_wsl_distribution,
        };
    }

    if (!registered)
    {
        return {
            L"WSL",
            CheckSeverity::Warning,
            settings.default_wsl_distribution + L" esta configurada no CloudOS, mas nao registrada no Windows",
        };
    }

    cloudos_native_wsl_configuration configuration{};
    const bool configuration_available = cloudos_native_wsl_get_configuration(
        settings.default_wsl_distribution.c_str(),
        &configuration) != FALSE;
    std::wstring detail = settings.default_wsl_distribution + L" registrada";
    if (configuration_available)
    {
        detail += L"; configuracao WSL acessivel; UID padrao=" +
            std::to_wstring(configuration.default_uid);
    }
    else
    {
        detail += L"; registro existe, mas a configuracao detalhada nao foi lida";
    }
    return {
        L"WSL",
        configuration_available ? CheckSeverity::Ok : CheckSeverity::Info,
        std::move(detail),
    };
}

CheckItem CheckDwm()
{
    BOOL enabled = FALSE;
    const HRESULT result = DwmIsCompositionEnabled(&enabled);
    return {
        L"DWM",
        SUCCEEDED(result) && enabled ? CheckSeverity::Ok : CheckSeverity::Warning,
        SUCCEEDED(result) && enabled ? L"Composicao do Desktop ativa" : L"Composicao DWM indisponivel",
    };
}

CheckItem CheckGraphics()
{
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    HMODULE gdi32 = GetModuleHandleW(L"gdi32.dll");
    const bool ok = user32 != nullptr && gdi32 != nullptr;
    return {
        L"Subsistema grafico Win32",
        ok ? CheckSeverity::Ok : CheckSeverity::Warning,
        ok ? L"user32.dll e gdi32.dll carregadas" : L"Componente grafico critico ausente",
    };
}

CheckItem CheckDisplaysAndDpi()
{
    const int monitors = GetSystemMetrics(SM_CMONITORS);
    const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    const UINT dpi = GetDpiForSystem();
    const DPI_AWARENESS awareness = GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext());

    std::wstring detail = std::to_wstring(std::max(0, monitors)) + L" monitor(es), desktop virtual " +
        std::to_wstring(std::max(0, width)) + L"x" + std::to_wstring(std::max(0, height)) +
        L", DPI sistema=" + std::to_wstring(dpi) + L", contexto=";
    switch (awareness)
    {
    case DPI_AWARENESS_PER_MONITOR_AWARE: detail += L"per-monitor"; break;
    case DPI_AWARENESS_SYSTEM_AWARE: detail += L"system-aware"; break;
    case DPI_AWARENESS_UNAWARE: detail += L"unaware"; break;
    default: detail += L"desconhecido"; break;
    }

    return {
        L"Monitores e DPI",
        monitors > 0 && awareness == DPI_AWARENESS_PER_MONITOR_AWARE
            ? CheckSeverity::Ok
            : CheckSeverity::Warning,
        std::move(detail),
    };
}

CheckItem CheckStorage()
{
    const std::wstring local = LocalAppDataPath();
    if (local.empty())
    {
        return {L"Armazenamento local", CheckSeverity::Warning, L"LocalAppData nao foi resolvido"};
    }

    ULARGE_INTEGER available{};
    ULARGE_INTEGER total{};
    if (!GetDiskFreeSpaceExW(local.c_str(), &available, &total, nullptr))
    {
        return {L"Armazenamento local", CheckSeverity::Warning, L"GetDiskFreeSpaceExW falhou"};
    }

    const ULONGLONG free_mb = available.QuadPart / (1024ULL * 1024ULL);
    const ULONGLONG total_mb = total.QuadPart / (1024ULL * 1024ULL);
    return {
        L"Armazenamento local",
        free_mb >= 1024 ? CheckSeverity::Ok : CheckSeverity::Warning,
        std::to_wstring(free_mb) + L" MB livres de " + std::to_wstring(total_mb) + L" MB em LocalAppData",
    };
}

CheckItem CheckMemory()
{
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    const bool ok = GlobalMemoryStatusEx(&memory) != FALSE && memory.ullTotalPhys > 0;
    if (!ok)
    {
        return {L"Memoria", CheckSeverity::Warning, L"GlobalMemoryStatusEx falhou"};
    }
    const ULONGLONG total_mb = memory.ullTotalPhys / (1024ULL * 1024ULL);
    const ULONGLONG available_mb = memory.ullAvailPhys / (1024ULL * 1024ULL);
    return {
        L"Memoria",
        available_mb >= 512 ? CheckSeverity::Ok : CheckSeverity::Warning,
        std::to_wstring(available_mb) + L" MB livres de " + std::to_wstring(total_mb) + L" MB",
    };
}

CheckItem CheckSupervisorJournal()
{
    const std::wstring local = LocalAppDataPath();
    if (local.empty())
        return {L"Recovery V22", CheckSeverity::Info, L"LocalAppData indisponivel para consultar journal"};

    const std::wstring path = local + L"\\CloudOS\\Recovery\\supervisor-state-v22.json";
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data))
    {
        return {
            L"Recovery V22",
            CheckSeverity::Info,
            L"Journal V22 ainda nao foi criado nesta sessao/instalacao",
        };
    }

    ULARGE_INTEGER stamp{};
    stamp.HighPart = data.ftLastWriteTime.dwHighDateTime;
    stamp.LowPart = data.ftLastWriteTime.dwLowDateTime;
    FILETIME now_file{};
    GetSystemTimeAsFileTime(&now_file);
    ULARGE_INTEGER now{};
    now.HighPart = now_file.dwHighDateTime;
    now.LowPart = now_file.dwLowDateTime;
    const ULONGLONG age_seconds = now.QuadPart >= stamp.QuadPart
        ? (now.QuadPart - stamp.QuadPart) / 10000000ULL
        : 0ULL;

    return {
        L"Recovery V22",
        CheckSeverity::Info,
        L"Journal local presente; ultima atualizacao ha aproximadamente " +
            std::to_wstring(age_seconds) + L" s. Presenca nao equivale a health PASS.",
    };
}

CheckItem CheckRuntimeProcesses()
{
    const auto processes = CurrentSessionCloudOSProcesses();
    if (processes.empty())
    {
        return {
            L"Processos CloudOS",
            CheckSeverity::Info,
            L"Nenhum outro processo CloudOS conhecido foi enumerado nesta sessao",
        };
    }

    std::wstring detail = L"Presentes: ";
    for (std::size_t index = 0; index < processes.size(); ++index)
    {
        if (index != 0) detail += L", ";
        detail += processes[index];
    }
    detail += L". Presenca de processo e evidencia operacional, nao prova de saude.";
    return {L"Processos CloudOS", CheckSeverity::Info, std::move(detail)};
}

std::vector<CheckItem> RunChecks()
{
    return {
        CheckRuntimeAbi(),
        CheckConPty(),
        CheckWebView2(),
        CheckWsl(),
        CheckDwm(),
        CheckGraphics(),
        CheckDisplaysAndDpi(),
        CheckStorage(),
        CheckMemory(),
        CheckSupervisorJournal(),
        CheckRuntimeProcesses(),
    };
}

void Populate(HWND list)
{
    const auto checks = RunChecks();
    ListView_DeleteAllItems(list);
    for (std::size_t index = 0; index < checks.size(); ++index)
    {
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = const_cast<wchar_t*>(checks[index].name.c_str());
        ListView_InsertItem(list, &item);

        std::wstring status = SeverityLabel(checks[index].severity);
        ListView_SetItemText(list, static_cast<int>(index), 1, status.data());
        ListView_SetItemText(
            list,
            static_cast<int>(index),
            2,
            const_cast<wchar_t*>(checks[index].detail.c_str()));
    }
}

void RefreshFont(HWND window, DoctorState& state)
{
    if (state.font != nullptr)
    {
        DeleteObject(state.font);
        state.font = nullptr;
    }
    const UINT dpi = GetDpiForWindow(window);
    state.font = CreateFontW(
        -MulDiv(15, static_cast<int>(dpi == 0 ? 96 : dpi), 96),
        0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Variable Text");
    if (state.font != nullptr)
    {
        if (state.button != nullptr) SendMessageW(state.button, WM_SETFONT, reinterpret_cast<WPARAM>(state.font), TRUE);
        if (state.list != nullptr) SendMessageW(state.list, WM_SETFONT, reinterpret_cast<WPARAM>(state.font), TRUE);
    }
}

void Layout(HWND window, DoctorState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const UINT dpi = GetDpiForWindow(window);
    const int margin = MulDiv(12, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
    const int button_height = MulDiv(34, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
    const int button_width = MulDiv(190, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
    const int gap = MulDiv(10, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
    const int client_width = static_cast<int>(client.right - client.left);
    const int client_height = static_cast<int>(client.bottom - client.top);
    MoveWindow(state.button, margin, margin, button_width, button_height, TRUE);
    MoveWindow(
        state.list,
        margin,
        margin + button_height + gap,
        std::max(120, client_width - margin * 2),
        std::max(100, client_height - (margin * 2 + button_height + gap)),
        TRUE);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<DoctorState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new (std::nothrow) DoctorState();
        if (state == nullptr) return FALSE;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }

    switch (message)
    {
    case WM_CREATE:
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        state->button = CreateWindowExW(
            0,
            L"BUTTON",
            L"Executar diagnostico",
            WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
            0, 0, 0, 0,
            window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kRunButtonId)),
            create->hInstance,
            nullptr);
        state->list = CreateWindowExW(
            WS_EX_CLIENTEDGE,
            WC_LISTVIEWW,
            L"",
            WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL,
            0, 0, 0, 0,
            window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
            create->hInstance,
            nullptr);
        if (state->button == nullptr || state->list == nullptr) return -1;

        ListView_SetExtendedListViewStyle(
            state->list,
            LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
        LVCOLUMNW column{};
        column.mask = LVCF_TEXT | LVCF_WIDTH;
        column.cx = 220;
        column.pszText = const_cast<wchar_t*>(L"Verificacao");
        ListView_InsertColumn(state->list, 0, &column);
        column.cx = 110;
        column.pszText = const_cast<wchar_t*>(L"Status");
        ListView_InsertColumn(state->list, 1, &column);
        column.cx = 650;
        column.pszText = const_cast<wchar_t*>(L"Detalhe");
        ListView_InsertColumn(state->list, 2, &column);

        RefreshFont(window, *state);
        Layout(window, *state);
        Populate(state->list);
        return 0;
    }

    case WM_SIZE:
        if (state != nullptr) Layout(window, *state);
        return 0;

    case WM_DPICHANGED:
        if (state != nullptr)
        {
            const auto* suggested = reinterpret_cast<const RECT*>(l_param);
            if (suggested != nullptr)
            {
                SetWindowPos(
                    window,
                    nullptr,
                    suggested->left,
                    suggested->top,
                    suggested->right - suggested->left,
                    suggested->bottom - suggested->top,
                    SWP_NOZORDER | SWP_NOACTIVATE);
            }
            RefreshFont(window, *state);
            Layout(window, *state);
        }
        return 0;

    case WM_COMMAND:
        if (state != nullptr && LOWORD(w_param) == kRunButtonId && HIWORD(w_param) == BN_CLICKED)
        {
            Populate(state->list);
            return 0;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window);
        return 0;

    case WM_NCDESTROY:
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        if (state != nullptr)
        {
            if (state->font != nullptr) DeleteObject(state->font);
            delete state;
        }
        return DefWindowProcW(window, message, w_param, l_param);

    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

bool EnsureClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    window_class.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
} // namespace

HWND CloudOSNativeEnvDoctorWindow::Open(HINSTANCE instance)
{
    if (!EnsureClass(instance)) return nullptr;

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Saude do Sistema - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1050,
        620,
        nullptr,
        nullptr,
        instance,
        nullptr);
    if (window != nullptr)
    {
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
    }
    return window;
}
