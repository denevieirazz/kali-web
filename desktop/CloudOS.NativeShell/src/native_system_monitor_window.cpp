#include "native_system_monitor_window.h"
#include "native_theme.h"

#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <new>
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
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
            L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS)
        return L"Processador Windows";

    std::array<wchar_t, 256> value{};
    DWORD type = 0;
    DWORD size = static_cast<DWORD>(value.size() * sizeof(wchar_t));
    const LONG result = RegQueryValueExW(key, L"ProcessorNameString", nullptr, &type,
        reinterpret_cast<BYTE*>(value.data()), &size);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) return L"Processador Windows";
    return value.data();
}

DWORD CountProcesses()
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
    DWORD count = 0;
    if (Process32FirstW(snapshot, &entry))
        do { ++count; } while (Process32NextW(snapshot, &entry));
    CloseHandle(snapshot);
    return count;
}

void Refresh(MonitorState& state)
{
    FILETIME idle{}, kernel{}, user{};
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
                state.cpu_percent = std::clamp((static_cast<double>(busy) * 100.0) / static_cast<double>(total), 0.0, 100.0);
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

void Card(HDC device, RECT rectangle)
{
    HBRUSH brush = CreateSolidBrush(CloudOS::WebSkin::BgSecondary);
    HPEN pen = CreatePen(PS_SOLID, 1, CloudOS::WebSkin::BorderDefault);
    HGDIOBJ old_brush = SelectObject(device, brush);
    HGDIOBJ old_pen = SelectObject(device, pen);
    RoundRect(device, rectangle.left, rectangle.top, rectangle.right, rectangle.bottom, 18, 18);
    SelectObject(device, old_pen);
    SelectObject(device, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void DrawTextLine(HDC device, const std::wstring& text, RECT rectangle, int point_size, int weight, COLORREF color)
{
    const int dpi = GetDeviceCaps(device, LOGPIXELSY);
    HFONT font = CreateFontW(-MulDiv(point_size, dpi > 0 ? dpi : 96, 72), 0, 0, 0, weight,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    HGDIOBJ previous = font != nullptr ? SelectObject(device, font) : nullptr;
    SetBkMode(device, TRANSPARENT);
    SetTextColor(device, color);
    DrawTextW(device, text.c_str(), -1, &rectangle,
        DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    if (previous != nullptr) SelectObject(device, previous);
    if (font != nullptr) DeleteObject(font);
}

void DrawBar(HDC device, RECT rectangle, double percent, COLORREF color)
{
    HBRUSH track = CreateSolidBrush(CloudOS::WebSkin::BgTertiary);
    HBRUSH fill = CreateSolidBrush(color);
    RoundRect(device, rectangle.left, rectangle.top, rectangle.right, rectangle.bottom, 10, 10);
    FillRect(device, &rectangle, track);
    const LONG width = rectangle.right - rectangle.left;
    rectangle.right = rectangle.left + static_cast<LONG>((static_cast<double>(width) * std::clamp(percent, 0.0, 100.0)) / 100.0);
    if (rectangle.right > rectangle.left) FillRect(device, &rectangle, fill);
    DeleteObject(track);
    DeleteObject(fill);
}

void Paint(HWND window, const MonitorState& state)
{
    PAINTSTRUCT paint{};
    HDC device = BeginPaint(window, &paint);
    RECT client{}; GetClientRect(window, &client);
    CloudOS::WebSkin::PaintWindowBackground(device, client);

    const UINT dpi = GetDpiForWindow(window);
    const int margin = CloudOS::Scale(28, dpi);
    const int client_width = static_cast<int>(client.right - client.left);
    RECT title{margin, CloudOS::Scale(20, dpi), client.right - margin, CloudOS::Scale(62, dpi)};
    DrawTextLine(device, L"Monitor do Sistema", title, 22, FW_SEMIBOLD, CloudOS::WebSkin::TextPrimary);
    RECT subtitle{margin, CloudOS::Scale(60, dpi), client.right - margin, CloudOS::Scale(92, dpi)};
    DrawTextLine(device, state.cpu_name, subtitle, 10, FW_NORMAL, CloudOS::WebSkin::TextSecondary);

    const int card_width = std::max(260, (client_width - margin * 3) / 2);
    RECT cpu_card{margin, CloudOS::Scale(112, dpi), margin + card_width, CloudOS::Scale(276, dpi)};
    RECT mem_card{cpu_card.right + margin, CloudOS::Scale(112, dpi), client.right - margin, CloudOS::Scale(276, dpi)};
    Card(device, cpu_card); Card(device, mem_card);

    RECT cpu_label{cpu_card.left + 20, cpu_card.top + 12, cpu_card.right - 20, cpu_card.top + 46};
    DrawTextLine(device, L"Processador (CPU)", cpu_label, 11, FW_SEMIBOLD, CloudOS::WebSkin::TextPrimary);
    wchar_t cpu_value[64]{}; swprintf_s(cpu_value, L"%.1f%% uso", state.cpu_percent);
    RECT cpu_number{cpu_card.left + 20, cpu_card.top + 48, cpu_card.right - 20, cpu_card.top + 102};
    DrawTextLine(device, cpu_value, cpu_number, 24, FW_BOLD, CloudOS::WebSkin::AccentHover);
    RECT cpu_bar{cpu_card.left + 20, cpu_card.bottom - 34, cpu_card.right - 20, cpu_card.bottom - 24};
    DrawBar(device, cpu_bar, state.cpu_percent, CloudOS::WebSkin::Accent);

    const double total_gb = static_cast<double>(state.memory.ullTotalPhys) / (1024.0 * 1024.0 * 1024.0);
    const double used_gb = static_cast<double>(state.memory.ullTotalPhys - state.memory.ullAvailPhys) / (1024.0 * 1024.0 * 1024.0);
    const double memory_percent = state.memory.dwMemoryLoad;
    RECT mem_label{mem_card.left + 20, mem_card.top + 12, mem_card.right - 20, mem_card.top + 46};
    DrawTextLine(device, L"Memoria RAM", mem_label, 11, FW_SEMIBOLD, CloudOS::WebSkin::TextPrimary);
    wchar_t mem_value[96]{}; swprintf_s(mem_value, L"%.1f GB / %.1f GB  (%.0f%%)", used_gb, total_gb, memory_percent);
    RECT mem_number{mem_card.left + 20, mem_card.top + 48, mem_card.right - 20, mem_card.top + 102};
    DrawTextLine(device, mem_value, mem_number, 18, FW_BOLD, RGB(94, 234, 178));
    RECT mem_bar{mem_card.left + 20, mem_card.bottom - 34, mem_card.right - 20, mem_card.bottom - 24};
    DrawBar(device, mem_bar, memory_percent, RGB(74, 210, 153));

    RECT system_card{margin, CloudOS::Scale(298, dpi), client.right - margin, CloudOS::Scale(424, dpi)};
    Card(device, system_card);
    RECT system_title{system_card.left + 20, system_card.top + 10, system_card.right - 20, system_card.top + 44};
    DrawTextLine(device, L"Sessao e host Windows", system_title, 11, FW_SEMIBOLD, CloudOS::WebSkin::TextPrimary);
    const ULONGLONG uptime_seconds = GetTickCount64() / 1000ULL;
    const DWORD logical_cpus = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    wchar_t details[256]{};
    swprintf_s(details, L"Arquitetura: x64   ·   CPUs logicas: %lu   ·   Processos: %lu   ·   Uptime: %llu min",
        logical_cpus, state.process_count, uptime_seconds / 60ULL);
    RECT details_rect{system_card.left + 20, system_card.top + 48, system_card.right - 20, system_card.bottom - 14};
    DrawTextLine(device, details, details_rect, 11, FW_NORMAL, CloudOS::WebSkin::TextSecondary);

    EndPaint(window, &paint);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* state = reinterpret_cast<MonitorState*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        state = new (std::nothrow) MonitorState();
        if (state == nullptr) return FALSE;
        state->cpu_name = ReadCpuName();
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }
    switch (message)
    {
    case WM_CREATE:
        Refresh(*state); SetTimer(window, kRefreshTimer, 1000, nullptr); return 0;
    case WM_TIMER:
        if (w_param == kRefreshTimer) { Refresh(*state); InvalidateRect(window, nullptr, FALSE); }
        return 0;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: Paint(window, *state); return 0;
    case WM_CLOSE: DestroyWindow(window); return 0;
    case WM_NCDESTROY:
        KillTimer(window, kRefreshTimer);
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        delete state;
        return 0;
    default: break;
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
    if (!EnsureClass(instance)) return nullptr;
    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW, kClassName, L"Monitor do Sistema - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 940, 560,
        nullptr, nullptr, instance, nullptr);
    if (window != nullptr)
    {
        CloudOS::ApplyWebWindowMaterial(window);
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
    }
    return window;
}
