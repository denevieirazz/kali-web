#include "native_env_doctor_window.h"

#include "cloudos_native_runtime.h"
#include "native_settings_window.h"

#include <commctrl.h>
#include <dwmapi.h>

#include <array>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.EnvDoctor.v1";
constexpr int kRunButtonId = 4101;
constexpr int kListId = 4102;

struct CheckItem final
{
    std::wstring name;
    bool ok{};
    std::wstring detail;
};

struct DoctorState final
{
    HWND button{};
    HWND list{};
};

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

CheckItem CheckRuntimeAbi()
{
    const std::uint32_t abi = cloudos_native_runtime_abi();
    return {
        L"Runtime nativo",
        abi == CLOUDOS_NATIVE_RUNTIME_ABI,
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
        available,
        available ? L"Pseudo console nativa disponivel" : L"CreatePseudoConsole nao foi encontrado",
    };
}

CheckItem CheckWsl()
{
    if (!ExistsOnPath(L"wsl.exe"))
    {
        return {L"WSL", false, L"wsl.exe nao encontrado no Windows"};
    }

    const CloudOSNativeSettings settings = CloudOSNativeSettingsWindow::Load();
    BOOL registered = FALSE;
    const BOOL queried = cloudos_native_wsl_is_registered(
        settings.default_wsl_distribution.c_str(),
        &registered);
    if (!queried)
    {
        return {
            L"WSL",
            false,
            L"API nativa do WSL indisponivel para consultar " + settings.default_wsl_distribution,
        };
    }

    return {
        L"WSL",
        registered != FALSE,
        registered
            ? settings.default_wsl_distribution + L" registrada"
            : settings.default_wsl_distribution + L" nao registrada",
    };
}

CheckItem CheckDwm()
{
    BOOL enabled = FALSE;
    const HRESULT result = DwmIsCompositionEnabled(&enabled);
    return {
        L"DWM",
        SUCCEEDED(result) && enabled,
        SUCCEEDED(result) && enabled ? L"Composicao do Desktop ativa" : L"Composicao DWM indisponivel",
    };
}

CheckItem CheckShell()
{
    HWND shell = GetShellWindow();
    DWORD process_id = 0;
    if (shell != nullptr)
    {
        GetWindowThreadProcessId(shell, &process_id);
    }
    return {
        L"Shell do Windows",
        shell != nullptr && process_id != 0,
        shell != nullptr
            ? L"Shell HWND ativo, PID " + std::to_wstring(process_id)
            : L"Nenhum shell de sistema detectado",
    };
}

CheckItem CheckGraphics()
{
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    HMODULE gdi32 = GetModuleHandleW(L"gdi32.dll");
    const bool ok = user32 != nullptr && gdi32 != nullptr;
    return {
        L"Subsistema grafico Win32",
        ok,
        ok ? L"user32.dll e gdi32.dll carregadas" : L"Componente grafico critico ausente",
    };
}

CheckItem CheckStorage()
{
    std::array<wchar_t, MAX_PATH + 1> temp{};
    const DWORD temp_length = GetTempPathW(static_cast<DWORD>(temp.size()), temp.data());
    if (temp_length == 0 || temp_length >= temp.size())
    {
        return {L"Armazenamento temporario", false, L"GetTempPathW falhou"};
    }

    std::wstring path = temp.data();
    path += L"cloudos-native-health.tmp";
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return {L"Armazenamento temporario", false, L"Diretorio temporario nao e gravavel"};
    }
    CloseHandle(file);
    return {L"Armazenamento temporario", true, L"Leitura/escrita local disponivel"};
}

CheckItem CheckMemory()
{
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    const bool ok = GlobalMemoryStatusEx(&memory) != FALSE && memory.ullTotalPhys > 0;
    if (!ok)
    {
        return {L"Memoria", false, L"GlobalMemoryStatusEx falhou"};
    }
    const ULONGLONG total_mb = memory.ullTotalPhys / (1024ULL * 1024ULL);
    const ULONGLONG available_mb = memory.ullAvailPhys / (1024ULL * 1024ULL);
    return {
        L"Memoria",
        true,
        std::to_wstring(available_mb) + L" MB livres de " + std::to_wstring(total_mb) + L" MB",
    };
}

std::vector<CheckItem> RunChecks()
{
    return {
        CheckRuntimeAbi(),
        CheckConPty(),
        CheckWsl(),
        CheckDwm(),
        CheckShell(),
        CheckGraphics(),
        CheckStorage(),
        CheckMemory(),
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

        std::wstring status = checks[index].ok ? L"OK" : L"ATENCAO";
        ListView_SetItemText(list, static_cast<int>(index), 1, status.data());
        ListView_SetItemText(list, static_cast<int>(index), 2, checks[index].detail.data());
    }
}

void Layout(HWND window, DoctorState& state)
{
    RECT client{};
    GetClientRect(window, &client);
    const int margin = 12;
    const int button_height = 34;
    MoveWindow(state.button, margin, margin, 180, button_height, TRUE);
    MoveWindow(
        state.list,
        margin,
        margin + button_height + 10,
        std::max(120, static_cast<int>(client.right) - margin * 2),
        std::max(100, static_cast<int>(client.bottom) - (margin * 2 + button_height + 10)),
        TRUE);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<DoctorState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new (std::nothrow) DoctorState();
        if (state == nullptr)
        {
            return FALSE;
        }
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
        if (state->button == nullptr || state->list == nullptr)
        {
            return -1;
        }

        ListView_SetExtendedListViewStyle(
            state->list,
            LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
        LVCOLUMNW column{};
        column.mask = LVCF_TEXT | LVCF_WIDTH;
        column.cx = 210;
        column.pszText = const_cast<wchar_t*>(L"Verificacao");
        ListView_InsertColumn(state->list, 0, &column);
        column.cx = 100;
        column.pszText = const_cast<wchar_t*>(L"Status");
        ListView_InsertColumn(state->list, 1, &column);
        column.cx = 500;
        column.pszText = const_cast<wchar_t*>(L"Detalhe");
        ListView_InsertColumn(state->list, 2, &column);

        Layout(window, *state);
        Populate(state->list);
        return 0;
    }

    case WM_SIZE:
        Layout(window, *state);
        return 0;

    case WM_COMMAND:
        if (LOWORD(w_param) == kRunButtonId && HIWORD(w_param) == BN_CLICKED)
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
        delete state;
        return 0;

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
    if (!EnsureClass(instance))
    {
        return nullptr;
    }

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Saude do Sistema - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        900,
        560,
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
