#include "native_process_window.h"

#include <commctrl.h>
#include <psapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <new>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "psapi.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.Processes.v1";
constexpr int kListId = 1101;
constexpr int kRefreshId = 1102;
constexpr int kTerminateId = 1103;
constexpr int kFocusId = 1104;

bool RegisterWindowClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &CloudOSNativeProcessWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

struct FindWindowContext final
{
    DWORD process_id{};
    HWND found{};
};

BOOL CALLBACK FindMainWindow(HWND window, LPARAM parameter)
{
    auto* context = reinterpret_cast<FindWindowContext*>(parameter);
    if (context == nullptr)
    {
        return FALSE;
    }

    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    if (process_id == context->process_id &&
        IsWindowVisible(window) &&
        GetWindow(window, GW_OWNER) == nullptr)
    {
        context->found = window;
        return FALSE;
    }
    return TRUE;
}
}

CloudOSNativeProcessWindow::CloudOSNativeProcessWindow(HINSTANCE instance)
    : instance_(instance)
{
}

void CloudOSNativeProcessWindow::Open(HINSTANCE instance)
{
    auto* window = new (std::nothrow) CloudOSNativeProcessWindow(instance);
    if (window == nullptr || !window->Create())
    {
        delete window;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Processos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeProcessWindow::Create()
{
    if (!RegisterWindowClass(instance_))
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Processos - CloudOS",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        860,
        580,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kListId),
        instance_,
        nullptr);

    if (list_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    ListView_SetExtendedListViewStyle(list_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);

    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.cx = 90;
    column.pszText = const_cast<wchar_t*>(L"PID");
    ListView_InsertColumn(list_, 0, &column);
    column.cx = 430;
    column.pszText = const_cast<wchar_t*>(L"Processo");
    ListView_InsertColumn(list_, 1, &column);
    column.cx = 140;
    column.pszText = const_cast<wchar_t*>(L"Memoria");
    ListView_InsertColumn(list_, 2, &column);

    refresh_button_ = CreateWindowW(
        L"BUTTON",
        L"Atualizar",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kRefreshId),
        instance_,
        nullptr);
    terminate_button_ = CreateWindowW(
        L"BUTTON",
        L"Encerrar",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kTerminateId),
        instance_,
        nullptr);
    focus_button_ = CreateWindowW(
        L"BUTTON",
        L"Focar janela",
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        0,
        window_,
        reinterpret_cast<HMENU>(kFocusId),
        instance_,
        nullptr);

    if (refresh_button_ == nullptr || terminate_button_ == nullptr || focus_button_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    SetTimer(window_, 1, 2000, nullptr);
    Refresh();
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeProcessWindow::Layout()
{
    RECT client{};
    if (!GetClientRect(window_, &client))
    {
        return;
    }

    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    MoveWindow(list_, 12, 12, std::max(100, width - 24), std::max(100, height - 66), TRUE);
    MoveWindow(refresh_button_, 12, std::max(12, height - 44), 100, 30, TRUE);
    MoveWindow(focus_button_, 122, std::max(12, height - 44), 120, 30, TRUE);
    MoveWindow(terminate_button_, 252, std::max(12, height - 44), 100, 30, TRUE);
}

SIZE_T CloudOSNativeProcessWindow::QueryWorkingSet(DWORD process_id)
{
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, process_id);
    if (process == nullptr)
    {
        return 0;
    }

    PROCESS_MEMORY_COUNTERS counters{};
    const SIZE_T working_set = GetProcessMemoryInfo(
        process,
        &counters,
        static_cast<DWORD>(sizeof(counters)))
        ? counters.WorkingSetSize
        : 0;
    CloseHandle(process);
    return working_set;
}

std::wstring CloudOSNativeProcessWindow::FormatMemory(SIZE_T bytes)
{
    wchar_t text[64]{};
    const double megabytes = static_cast<double>(bytes) / (1024.0 * 1024.0);
    swprintf_s(text, L"%.1f MB", megabytes);
    return text;
}

void CloudOSNativeProcessWindow::Refresh()
{
    processes_.clear();

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return;
    }

    PROCESSENTRY32W entry{};
    entry.dwSize = static_cast<DWORD>(sizeof(entry));
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            ProcessEntry process{};
            process.process_id = entry.th32ProcessID;
            process.name = entry.szExeFile;
            process.working_set = QueryWorkingSet(process.process_id);
            processes_.push_back(std::move(process));
        }
        while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    std::sort(
        processes_.begin(),
        processes_.end(),
        [](const ProcessEntry& left, const ProcessEntry& right)
        {
            if (left.working_set != right.working_set)
            {
                return left.working_set > right.working_set;
            }
            return left.process_id < right.process_id;
        });

    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < processes_.size(); ++index)
    {
        wchar_t process_id[32]{};
        swprintf_s(process_id, L"%lu", processes_[index].process_id);

        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = process_id;
        ListView_InsertItem(list_, &item);

        ListView_SetItemText(
            list_,
            static_cast<int>(index),
            1,
            processes_[index].name.data());
        auto memory = FormatMemory(processes_[index].working_set);
        ListView_SetItemText(
            list_,
            static_cast<int>(index),
            2,
            memory.data());
    }
}

void CloudOSNativeProcessWindow::TerminateSelected()
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= processes_.size())
    {
        return;
    }

    const DWORD process_id = processes_[static_cast<std::size_t>(selected)].process_id;
    if (process_id == 0 || process_id == 4)
    {
        MessageBoxW(
            window_,
            L"Este processo pertence ao nucleo do Windows e nao pode ser encerrado pelo CloudOS.",
            L"CloudOS",
            MB_OK | MB_ICONWARNING);
        return;
    }
    if (process_id == GetCurrentProcessId())
    {
        MessageBoxW(
            window_,
            L"Use Sair do CloudOS para encerrar o shell.",
            L"CloudOS",
            MB_OK | MB_ICONINFORMATION);
        return;
    }

    if (MessageBoxW(
            window_,
            L"Encerrar o processo selecionado?",
            L"CloudOS",
            MB_YESNO | MB_ICONWARNING) != IDYES)
    {
        return;
    }

    HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, process_id);
    if (process == nullptr)
    {
        MessageBoxW(
            window_,
            L"O Windows negou acesso para encerrar este processo.",
            L"CloudOS",
            MB_OK | MB_ICONWARNING);
        return;
    }

    const BOOL terminated = TerminateProcess(process, 1);
    CloseHandle(process);
    if (!terminated)
    {
        MessageBoxW(
            window_,
            L"Nao foi possivel encerrar o processo.",
            L"CloudOS",
            MB_OK | MB_ICONWARNING);
    }
    Refresh();
}

void CloudOSNativeProcessWindow::FocusSelectedProcess()
{
    const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (selected < 0 || static_cast<std::size_t>(selected) >= processes_.size())
    {
        return;
    }

    FindWindowContext context{};
    context.process_id = processes_[static_cast<std::size_t>(selected)].process_id;
    EnumWindows(&FindMainWindow, reinterpret_cast<LPARAM>(&context));
    if (context.found != nullptr)
    {
        if (IsIconic(context.found))
        {
            ShowWindow(context.found, SW_RESTORE);
        }
        SetForegroundWindow(context.found);
        BringWindowToTop(context.found);
    }
}

LRESULT CloudOSNativeProcessWindow::HandleMessage(UINT message, WPARAM w_param, LPARAM)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;

    case WM_TIMER:
        Refresh();
        return 0;

    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kRefreshId:
            Refresh();
            return 0;
        case kTerminateId:
            TerminateSelected();
            return 0;
        case kFocusId:
            FocusSelectedProcess();
            return 0;
        default:
            break;
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;

    case WM_NCDESTROY:
        KillTimer(window_, 1);
        window_ = nullptr;
        delete this;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window_, message, w_param, 0);
}

LRESULT CALLBACK CloudOSNativeProcessWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeProcessWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeProcessWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeProcessWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
