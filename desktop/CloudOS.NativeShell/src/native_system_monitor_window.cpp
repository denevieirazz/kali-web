#include "native_system_monitor_window.h"

#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.SystemMonitor.v1";
constexpr UINT_PTR kRefreshTimer = 1;

struct MonitorState final
{
    FILETIME previous_idle{};
    FILETIME previous_kernel{};
    FILETIME previous_user{};
    bool has_previous_cpu{};
    double cpu_percent{};
    MEMORYSTATUSEX memory{};
    DWORD process_count{};
    std::wstring cpu_name;
};

ULONGLONG FileTimeValue(const FILETIME& value) noexcept
{
    ULARGE_INTEGER number{};
    number.LowPart = value.dwLowDateTime;
    number.HighPart = value.dwHighDateTime;
    return number.QuadPart;
}

std::wstring ReadCpuName()
{
    HKEY key{};
    if (RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
            0,
            KEY_QUERY_VALUE,
            &key) != ERROR_SUCCESS)
    {
        return L"Processador Windows";
    }

    std::array<wchar_t, 256> value{};
    DWORD type = 0;
    DWORD size = static_cast<DWORD>(value.size() * sizeof(wchar_t));
    const LONG result = RegQueryValueExW(
        key,
        L"ProcessorNameString",
        nullptr,
        &type,
        reinterpret_cast<BYTE*>(value.data()),
        &size);
    RegCloseKey(key);

    if (result != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ))
    {
        return L"Processador Windows";
    }
    return value.data();
}

DWORD CountProcesses()
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return 0;
    }

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    DWORD count = 0;
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            ++count;
        }
        while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return count;
}

void Refresh(MonitorState& state)
{
    FILETIME idle{};
    FILETIME kernel{};
    FILETIME user{};
    if (GetSystemTimes(&idle, &kernel, &user))
    {
        if (state.has_previous_cpu)
        {
            const ULONGLONG idle_delta = FileTimeValue(idle) - FileTimeValue(state.previous_idle);
            const ULONGLONG kernel_delta = FileTimeValue(kernel) - FileTimeValue(state.previous_kernel);
            const ULONGLONG user_delta = FileTimeValue(user) - FileTimeValue(state.previous_user);
            const ULONGLONG total = kernel_delta + user_delta;
            if (total != 0)
            {
                const ULONGLONG busy = total > idle_delta ? total - idle_delta : 0;
                state.cpu_percent = std::clamp(
                    (static_cast<double>(busy) * 100.0) / static_cast<double>(total),
                    0.0,
                    100.0);
            }
        }
        state.previous_idle = idle;
        state.previous_kernel = kernel;
        state.previous_user = user;
        state.has_previous_cpu = true;
    }

    state.memory.dwLength = sizeof(state.memory);
    (void)GlobalMemoryStatusEx(&state.memory);
    state.process_count = CountProcesses();
}

void Fill(HDC device, const RECT& rectangle, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    FillRect(device, &rectangle, brush);
    DeleteObject(brush);
}

void DrawTextLine(
    HDC device,
    const std::wstring& text,
    RECT rectangle,
    int point_size,
    int weight,
    COLORREF color)
{
    const int dpi = GetDeviceCaps(device, LOGPIXELSY);
    HFONT font = CreateFontW(
        -MulDiv(point_size, dpi > 0 ? dpi : 96, 72),
        0,
        0,
        0,
        weight,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH,
        L"Segoe UI");
    HGDIOBJ previous = font != nullptr ? SelectObject(device, font) : nullptr;
    SetBkMode(device, TRANSPARENT);
    SetTextColor(device, color);
    DrawTextW(device, text.c_str(), -1, &rectangle, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    if (previous != nullptr)
    {
        SelectObject(device, previous);
    }
    if (font != nullptr)
    {
        DeleteObject(font);
    }
}

void DrawBar(HDC device, RECT rectangle, double percent, COLORREF color)
{
    Fill(device, rectangle, RGB(46, 53, 67));
    const LONG width = rectangle.right - rectangle.left;
    rectangle.right = rectangle.left + static_cast<LONG>(
        (static_cast<double>(width) * std::clamp(percent, 0.0, 100.0)) / 100.0);
    if (rectangle.right > rectangle.left)
    {
        Fill(device, rectangle, color);
    }
}

void Paint(HWND window, const MonitorState& state)
{
    PAINTSTRUCT paint{};
    HDC device = BeginPaint(window, &paint);
    RECT client{};
    GetClientRect(window, &client);
    Fill(device, client, RGB(14, 17, 24));

    const int margin = 24;
    RECT title{margin, 18, client.right - margin, 58};
    DrawTextLine(device, L"System Monitor - CloudOS", title, 22, FW_SEMIBOLD, RGB(242, 246, 251));

    RECT subtitle{margin, 58, client.right - margin, 88};
    DrawTextLine(device, state.cpu_name, subtitle, 10, FW_NORMAL, RGB(160, 172, 190));

    const int card_width = std::max(260, (client.right - margin * 3) / 2);
    RECT cpu_card{margin, 105, margin + card_width, 255};
    RECT mem_card{cpu_card.right + margin, 105, client.right - margin, 255};
    Fill(device, cpu_card, RGB(27, 32, 43));
    Fill(device, mem_card, RGB(27, 32, 43));

    RECT cpu_label{cpu_card.left + 18, cpu_card.top + 10, cpu_card.right - 18, cpu_card.top + 42};
    DrawTextLine(device, L"Processador (CPU)", cpu_label, 11, FW_SEMIBOLD, RGB(242, 246, 251));
    wchar_t cpu_value[64]{};
    swprintf_s(cpu_value, L"%.1f%% uso", state.cpu_percent);
    RECT cpu_number{cpu_card.left + 18, cpu_card.top + 45, cpu_card.right - 18, cpu_card.top + 92};
    DrawTextLine(device, cpu_value, cpu_number, 24, FW_BOLD, RGB(56, 189, 248));
    RECT cpu_bar{cpu_card.left + 18, cpu_card.bottom - 32, cpu_card.right - 18, cpu_card.bottom - 22};
    DrawBar(device, cpu_bar, state.cpu_percent, RGB(56, 189, 248));

    const double total_gb = static_cast<double>(state.memory.ullTotalPhys) / (1024.0 * 1024.0 * 1024.0);
    const double used_gb = static_cast<double>(state.memory.ullTotalPhys - state.memory.ullAvailPhys) / (1024.0 * 1024.0 * 1024.0);
    const double memory_percent = state.memory.dwMemoryLoad;
    RECT mem_label{mem_card.left + 18, mem_card.top + 10, mem_card.right - 18, mem_card.top + 42};
    DrawTextLine(device, L"Memoria RAM", mem_label, 11, FW_SEMIBOLD, RGB(242, 246, 251));
    wchar_t mem_value[96]{};
    swprintf_s(mem_value, L"%.1f GB / %.1f GB  (%.0f%%)", used_gb, total_gb, memory_percent);
    RECT mem_number{mem_card.left + 18, mem_card.top + 45, mem_card.right - 18, mem_card.top + 92};
    DrawTextLine(device, mem_value, mem_number, 18, FW_BOLD, RGB(52, 211, 153));
    RECT mem_bar{mem_card.left + 18, mem_card.bottom - 32, mem_card.right - 18, mem_card.bottom - 22};
    DrawBar(device, mem_bar, memory_percent, RGB(52, 211, 153));

    RECT system_card{margin, 275, client.right - margin, 390};
    Fill(device, system_card, RGB(27, 32, 43));
    RECT system_title{system_card.left + 18, system_card.top + 8, system_card.right - 18, system_card.top + 40};
    DrawTextLine(device, L"Sistema operacional host", system_title, 11, FW_SEMIBOLD, RGB(242, 246, 251));

    const ULONGLONG uptime_seconds = GetTickCount64() / 1000ULL;
    const DWORD logical_cpus = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    wchar_t details[256]{};
    swprintf_s(
        details,
        L"Arquitetura: x64   |   CPUs logicas: %lu   |   Processos: %lu   |   Uptime: %llu min",
        logical_cpus,
        state.process_count,
        uptime_seconds / 60ULL);
    RECT details_rect{system_card.left + 18, system_card.top + 46, system_card.right - 18, system_card.bottom - 12};
    DrawTextLine(device, details, details_rect, 11, FW_NORMAL, RGB(203, 213, 225));

    EndPaint(window, &paint);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<MonitorState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new (std::nothrow) MonitorState();
        if (state == nullptr)
        {
            return FALSE;
        }
        state->cpu_name = ReadCpuName();
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }

    switch (message)
    {
    case WM_CREATE:
        Refresh(*state);
        SetTimer(window, kRefreshTimer, 1000, nullptr);
        return 0;

    case WM_TIMER:
        if (w_param == kRefreshTimer)
        {
            Refresh(*state);
            InvalidateRect(window, nullptr, FALSE);
        }
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT:
        Paint(window, *state);
        return 0;

    case WM_CLOSE:
        DestroyWindow(window);
        return 0;

    case WM_NCDESTROY:
        KillTimer(window, kRefreshTimer);
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
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    window_class.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
    return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}
} // namespace

HWND CloudOSNativeSystemMonitorWindow::Open(HINSTANCE instance)
{
    if (!EnsureClass(instance))
    {
        return nullptr;
    }

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"System Monitor - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        900,
        520,
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
