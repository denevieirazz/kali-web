#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "cloudos_native_runtime.h"
#include "native_apps_window.h"
#include "native_files_window.h"
#include "native_process_window.h"
#include "native_run_window.h"
#include "native_terminal_window.h"
#include "native_window_manager.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

namespace
{
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.Desktop.v2";
constexpr wchar_t kTaskbarClass[] = L"CloudOS.NativeShell.Taskbar.v2";
constexpr wchar_t kStartClass[] = L"CloudOS.NativeShell.Start.v2";
constexpr int kBaseTaskbarHeight = 58;
constexpr int kBaseStartWidth = 390;
constexpr int kBaseStartHeight = 520;
constexpr UINT_PTR kReconcileTimer = 1;

constexpr COLORREF kDesktopBackground = RGB(14, 17, 24);
constexpr COLORREF kPanelBackground = RGB(27, 32, 43);
constexpr COLORREF kPanelHover = RGB(42, 50, 66);
constexpr COLORREF kBorder = RGB(61, 72, 92);
constexpr COLORREF kAccent = RGB(91, 140, 255);
constexpr COLORREF kPrimaryText = RGB(242, 246, 251);
constexpr COLORREF kSecondaryText = RGB(160, 172, 190);

struct TaskHit final
{
    HWND window{};
    RECT bounds{};
};

enum HotKeyId : int
{
    HotTerminal = 1,
    HotWslTerminal,
    HotFiles,
    HotApps,
    HotProcesses,
    HotRun,
    HotTiling,
    HotFloating,
    HotFocusNext,
    HotFocusPrevious,
    HotClose,
    HotMinimize,
    HotMaximize,
    HotSnapLeft,
    HotSnapRight,
    HotSnapUp,
    HotSnapDown,
    HotExit,
    HotWorkspace1 = 30,
    HotWorkspace2,
    HotWorkspace3,
    HotWorkspace4,
    HotMoveWorkspace1 = 40,
    HotMoveWorkspace2,
    HotMoveWorkspace3,
    HotMoveWorkspace4,
};

int ScaleForDpi(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

bool PointInside(const RECT& rectangle, POINT point) noexcept
{
    return point.x >= rectangle.left && point.x < rectangle.right &&
        point.y >= rectangle.top && point.y < rectangle.bottom;
}

std::wstring ResolveExecutable(const wchar_t* executable)
{
    std::array<wchar_t, 32768> buffer{};
    const DWORD length = SearchPathW(
        nullptr,
        executable,
        nullptr,
        static_cast<DWORD>(buffer.size()),
        buffer.data(),
        nullptr);
    if (length > 0 && length < buffer.size())
    {
        return buffer.data();
    }
    return executable;
}

std::wstring QuoteExecutable(const std::wstring& executable)
{
    return L"\"" + executable + L"\"";
}

void FillSolid(HDC device, const RECT& rectangle, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    FillRect(device, &rectangle, brush);
    DeleteObject(brush);
}

void DrawPanel(HDC device, const RECT& rectangle, COLORREF fill, COLORREF outline, int radius)
{
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, outline);
    const HGDIOBJ previous_brush = SelectObject(device, brush);
    const HGDIOBJ previous_pen = SelectObject(device, pen);
    RoundRect(
        device,
        rectangle.left,
        rectangle.top,
        rectangle.right,
        rectangle.bottom,
        radius,
        radius);
    SelectObject(device, previous_pen);
    SelectObject(device, previous_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void DrawTextValue(
    HDC device,
    std::wstring_view text,
    RECT rectangle,
    int point_size,
    int weight,
    COLORREF color,
    UINT format = DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS)
{
    const UINT dpi = GetDeviceCaps(device, LOGPIXELSY);
    HFONT font = CreateFontW(
        -MulDiv(point_size, static_cast<int>(dpi == 0 ? 96 : dpi), 72),
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
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI");
    const HGDIOBJ previous_font = font != nullptr ? SelectObject(device, font) : nullptr;
    SetBkMode(device, TRANSPARENT);
    SetTextColor(device, color);
    DrawTextW(
        device,
        text.data(),
        static_cast<int>(text.size()),
        &rectangle,
        format | DT_NOPREFIX);
    if (previous_font != nullptr)
    {
        SelectObject(device, previous_font);
    }
    if (font != nullptr)
    {
        DeleteObject(font);
    }
}

class CloudOSShell final
{
public:
    explicit CloudOSShell(HINSTANCE instance) noexcept
        : instance_(instance)
    {
    }

    ~CloudOSShell()
    {
        Shutdown();
    }

    bool Initialize()
    {
        if (!RegisterClasses())
        {
            return false;
        }

        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        if (!GetMonitorInfoW(MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY), &monitor))
        {
            return false;
        }

        desktop_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
            kDesktopClass,
            L"CloudOS Native Desktop",
            WS_POPUP,
            monitor.rcWork.left,
            monitor.rcWork.top,
            monitor.rcWork.right - monitor.rcWork.left,
            monitor.rcWork.bottom - monitor.rcWork.top,
            nullptr,
            nullptr,
            instance_,
            this);
        if (desktop_ == nullptr)
        {
            return false;
        }

        taskbar_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
            kTaskbarClass,
            L"CloudOS Native Taskbar",
            WS_POPUP,
            0,
            0,
            0,
            0,
            nullptr,
            nullptr,
            instance_,
            this);
        if (taskbar_ == nullptr)
        {
            Shutdown();
            return false;
        }

        start_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
            kStartClass,
            L"CloudOS Start",
            WS_POPUP,
            0,
            0,
            0,
            0,
            taskbar_,
            nullptr,
            instance_,
            this);
        if (start_ == nullptr)
        {
            Shutdown();
            return false;
        }

        const BOOL dark_mode = TRUE;
        constexpr DWORD immersive_dark_mode_attribute = 20;
        (void)DwmSetWindowAttribute(
            start_,
            immersive_dark_mode_attribute,
            &dark_mode,
            static_cast<DWORD>(sizeof(dark_mode)));

        RepositionShellWindows();
        ShowWindow(desktop_, SW_SHOWNOACTIVATE);
        SetWindowPos(
            desktop_,
            HWND_BOTTOM,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        ShowWindow(taskbar_, SW_SHOWNOACTIVATE);
        ShowWindow(start_, SW_HIDE);

        window_manager_.SetReservedBottomPixels(TaskbarHeight());
        if (!window_manager_.Initialize(desktop_))
        {
            Shutdown();
            return false;
        }

        RegisterHotKeys();
        SetTimer(desktop_, kReconcileTimer, 1000, nullptr);
        InvalidateAll();
        return true;
    }

    int Run()
    {
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0)
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return static_cast<int>(message.wParam);
    }

private:
    bool RegisterClasses()
    {
        const struct ClassDefinition
        {
            const wchar_t* name;
            WNDPROC procedure;
            HCURSOR cursor;
        } definitions[] = {
            {kDesktopClass, &CloudOSShell::DesktopProcedure, LoadCursorW(nullptr, IDC_ARROW)},
            {kTaskbarClass, &CloudOSShell::TaskbarProcedure, LoadCursorW(nullptr, IDC_HAND)},
            {kStartClass, &CloudOSShell::StartProcedure, LoadCursorW(nullptr, IDC_ARROW)},
        };

        for (const auto& definition : definitions)
        {
            WNDCLASSEXW window_class{};
            window_class.cbSize = sizeof(window_class);
            window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
            window_class.lpfnWndProc = definition.procedure;
            window_class.hInstance = instance_;
            window_class.hCursor = definition.cursor;
            window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
            window_class.hbrBackground = nullptr;
            window_class.lpszClassName = definition.name;
            window_class.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
            if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            {
                return false;
            }
        }
        return true;
    }

    int TaskbarHeight() const noexcept
    {
        const UINT dpi = taskbar_ != nullptr ? GetDpiForWindow(taskbar_) : 96;
        return ScaleForDpi(kBaseTaskbarHeight, dpi);
    }

    void RepositionShellWindows()
    {
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        const HMONITOR primary = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
        if (!GetMonitorInfoW(primary, &monitor))
        {
            return;
        }

        const int taskbar_height = TaskbarHeight();
        const int work_width = static_cast<int>(monitor.rcWork.right - monitor.rcWork.left);
        const int work_height = static_cast<int>(monitor.rcWork.bottom - monitor.rcWork.top);

        if (desktop_ != nullptr)
        {
            SetWindowPos(
                desktop_,
                HWND_BOTTOM,
                monitor.rcWork.left,
                monitor.rcWork.top,
                work_width,
                work_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        if (taskbar_ != nullptr)
        {
            SetWindowPos(
                taskbar_,
                HWND_TOPMOST,
                monitor.rcWork.left,
                monitor.rcWork.bottom - taskbar_height,
                work_width,
                taskbar_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        if (start_ != nullptr)
        {
            const UINT dpi = GetDpiForWindow(start_);
            const int start_width = ScaleForDpi(kBaseStartWidth, dpi);
            const int start_height = ScaleForDpi(kBaseStartHeight, dpi);
            const int margin = ScaleForDpi(12, dpi);
            SetWindowPos(
                start_,
                HWND_TOPMOST,
                monitor.rcWork.left + margin,
                monitor.rcWork.bottom - taskbar_height - start_height - margin,
                start_width,
                start_height,
                SWP_NOACTIVATE | (IsWindowVisible(start_) ? SWP_SHOWWINDOW : 0));
        }

        window_manager_.SetReservedBottomPixels(taskbar_height);
    }

    void RegisterHotKeys()
    {
        const UINT modifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        const UINT move_modifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;

        const struct Binding
        {
            int id;
            UINT modifiers;
            UINT key;
        } bindings[] = {
            {HotTerminal, modifiers, VK_RETURN},
            {HotWslTerminal, modifiers, L'K'},
            {HotFiles, modifiers, L'E'},
            {HotApps, modifiers, L'A'},
            {HotProcesses, modifiers, L'P'},
            {HotRun, modifiers, L'R'},
            {HotTiling, modifiers, L'T'},
            {HotFloating, modifiers, L'F'},
            {HotFocusNext, modifiers, L'J'},
            {HotFocusPrevious, modifiers, L'H'},
            {HotClose, modifiers, L'Q'},
            {HotMinimize, modifiers, L'M'},
            {HotMaximize, modifiers, L'Z'},
            {HotSnapLeft, modifiers, VK_LEFT},
            {HotSnapRight, modifiers, VK_RIGHT},
            {HotSnapUp, modifiers, VK_UP},
            {HotSnapDown, modifiers, VK_DOWN},
            {HotExit, modifiers, L'X'},
            {HotWorkspace1, modifiers, L'1'},
            {HotWorkspace2, modifiers, L'2'},
            {HotWorkspace3, modifiers, L'3'},
            {HotWorkspace4, modifiers, L'4'},
            {HotMoveWorkspace1, move_modifiers, L'1'},
            {HotMoveWorkspace2, move_modifiers, L'2'},
            {HotMoveWorkspace3, move_modifiers, L'3'},
            {HotMoveWorkspace4, move_modifiers, L'4'},
        };

        registered_hotkeys_.clear();
        for (const auto& binding : bindings)
        {
            if (RegisterHotKey(desktop_, binding.id, binding.modifiers, binding.key))
            {
                registered_hotkeys_.push_back(binding.id);
            }
        }
    }

    void UnregisterHotKeys() noexcept
    {
        if (desktop_ != nullptr)
        {
            for (int id : registered_hotkeys_)
            {
                UnregisterHotKey(desktop_, id);
            }
        }
        registered_hotkeys_.clear();
    }

    void Shutdown() noexcept
    {
        if (shutting_down_)
        {
            return;
        }
        shutting_down_ = true;

        if (desktop_ != nullptr)
        {
            KillTimer(desktop_, kReconcileTimer);
        }
        UnregisterHotKeys();
        window_manager_.Shutdown();

        if (start_ != nullptr && IsWindow(start_))
        {
            DestroyWindow(start_);
        }
        start_ = nullptr;

        if (taskbar_ != nullptr && IsWindow(taskbar_))
        {
            DestroyWindow(taskbar_);
        }
        taskbar_ = nullptr;

        if (desktop_ != nullptr && IsWindow(desktop_))
        {
            DestroyWindow(desktop_);
        }
        desktop_ = nullptr;
    }

    void InvalidateAll()
    {
        if (desktop_ != nullptr)
        {
            InvalidateRect(desktop_, nullptr, FALSE);
        }
        if (taskbar_ != nullptr)
        {
            InvalidateRect(taskbar_, nullptr, FALSE);
        }
        if (start_ != nullptr && IsWindowVisible(start_))
        {
            InvalidateRect(start_, nullptr, FALSE);
        }
    }

    void ToggleStartMenu()
    {
        if (start_ == nullptr)
        {
            return;
        }

        if (IsWindowVisible(start_))
        {
            ShowWindow(start_, SW_HIDE);
            return;
        }

        RepositionShellWindows();
        ShowWindow(start_, SW_SHOW);
        SetWindowPos(
            start_,
            HWND_TOPMOST,
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetForegroundWindow(start_);
        InvalidateRect(start_, nullptr, FALSE);
    }

    void HideStartMenu()
    {
        if (start_ != nullptr && IsWindowVisible(start_))
        {
            ShowWindow(start_, SW_HIDE);
        }
    }

    void OpenTerminal()
    {
        const std::wstring executable = ResolveExecutable(L"powershell.exe");
        const std::wstring command = QuoteExecutable(executable) + L" -NoLogo -NoProfile";
        CloudOSNativeTerminalWindow::Open(instance_, command, L"Terminal - CloudOS");
        window_manager_.Reconcile();
        InvalidateAll();
    }

    void OpenWslTerminal()
    {
        const std::wstring executable = ResolveExecutable(L"wsl.exe");
        if (executable == L"wsl.exe" && GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES)
        {
            MessageBoxW(
                desktop_,
                L"WSL nao foi encontrado neste Windows.",
                L"CloudOS",
                MB_OK | MB_ICONINFORMATION);
            return;
        }

        BOOL kali_registered = FALSE;
        std::wstring command = QuoteExecutable(executable);
        if (cloudos_native_wsl_is_registered(L"kali-linux", &kali_registered) && kali_registered)
        {
            command += L" -d kali-linux";
        }

        CloudOSNativeTerminalWindow::Open(instance_, command, L"WSL / Kali - CloudOS");
        window_manager_.Reconcile();
        InvalidateAll();
    }

    void LaunchStartItem(std::size_t index)
    {
        HideStartMenu();
        switch (index)
        {
        case 0:
            OpenTerminal();
            break;
        case 1:
            OpenWslTerminal();
            break;
        case 2:
            CloudOSNativeAppsWindow::Open(instance_);
            break;
        case 3:
            CloudOSNativeFilesWindow::Open(instance_);
            break;
        case 4:
            CloudOSNativeProcessWindow::Open(instance_);
            break;
        case 5:
            CloudOSNativeRunWindow::Open(instance_);
            break;
        case 6:
            window_manager_.ToggleTiling();
            break;
        case 7:
            PostMessageW(desktop_, WM_CLOSE, 0, 0);
            return;
        default:
            return;
        }

        window_manager_.Reconcile();
        InvalidateAll();
    }

    void HandleHotKey(int id)
    {
        if (id >= HotWorkspace1 && id <= HotWorkspace4)
        {
            window_manager_.SwitchWorkspace(id - HotWorkspace1);
            HideStartMenu();
            InvalidateAll();
            return;
        }
        if (id >= HotMoveWorkspace1 && id <= HotMoveWorkspace4)
        {
            window_manager_.MoveActiveToWorkspace(id - HotMoveWorkspace1);
            InvalidateAll();
            return;
        }

        switch (id)
        {
        case HotTerminal:
            OpenTerminal();
            break;
        case HotWslTerminal:
            OpenWslTerminal();
            break;
        case HotFiles:
            CloudOSNativeFilesWindow::Open(instance_);
            break;
        case HotApps:
            CloudOSNativeAppsWindow::Open(instance_);
            break;
        case HotProcesses:
            CloudOSNativeProcessWindow::Open(instance_);
            break;
        case HotRun:
            CloudOSNativeRunWindow::Open(instance_);
            break;
        case HotTiling:
            window_manager_.ToggleTiling();
            break;
        case HotFloating:
            window_manager_.ToggleFloatingActive();
            break;
        case HotFocusNext:
            window_manager_.FocusNext(false);
            break;
        case HotFocusPrevious:
            window_manager_.FocusNext(true);
            break;
        case HotClose:
            window_manager_.CloseActive();
            break;
        case HotMinimize:
            window_manager_.MinimizeActive();
            break;
        case HotMaximize:
            window_manager_.ToggleMaximizeActive();
            break;
        case HotSnapLeft:
            window_manager_.SnapActive(CloudOSSnapDirection::Left);
            break;
        case HotSnapRight:
            window_manager_.SnapActive(CloudOSSnapDirection::Right);
            break;
        case HotSnapUp:
            window_manager_.SnapActive(CloudOSSnapDirection::Up);
            break;
        case HotSnapDown:
            window_manager_.SnapActive(CloudOSSnapDirection::Down);
            break;
        case HotExit:
            PostMessageW(desktop_, WM_CLOSE, 0, 0);
            return;
        default:
            break;
        }

        window_manager_.Reconcile();
        InvalidateAll();
    }

    void PaintDesktop()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(desktop_, &paint);
        RECT client{};
        GetClientRect(desktop_, &client);
        FillSolid(device, client, kDesktopBackground);

        const UINT dpi = GetDpiForWindow(desktop_);
        RECT card{
            ScaleForDpi(28, dpi),
            ScaleForDpi(28, dpi),
            ScaleForDpi(570, dpi),
            ScaleForDpi(205, dpi),
        };
        DrawPanel(device, card, kPanelBackground, kBorder, ScaleForDpi(18, dpi));

        RECT title{
            card.left + ScaleForDpi(24, dpi),
            card.top + ScaleForDpi(20, dpi),
            card.right - ScaleForDpi(20, dpi),
            card.top + ScaleForDpi(65, dpi),
        };
        DrawTextValue(device, L"CloudOS Native", title, 25, FW_SEMIBOLD, kPrimaryText);

        RECT subtitle{
            title.left,
            title.bottom,
            card.right - ScaleForDpi(20, dpi),
            title.bottom + ScaleForDpi(30, dpi),
        };
        DrawTextValue(
            device,
            L"C++ / Win32 / ConPTY / WSL / HWND real",
            subtitle,
            11,
            FW_NORMAL,
            kSecondaryText);

        const std::wstring status =
            L"Workspace " + std::to_wstring(window_manager_.CurrentWorkspace() + 1) +
            L"  |  Janelas " + std::to_wstring(window_manager_.ManagedWindowCount()) +
            L"  |  Tiling " + (window_manager_.TilingEnabled() ? L"ON" : L"OFF");
        RECT status_rect{
            title.left,
            subtitle.bottom + ScaleForDpi(12, dpi),
            card.right - ScaleForDpi(20, dpi),
            subtitle.bottom + ScaleForDpi(42, dpi),
        };
        DrawTextValue(device, status, status_rect, 11, FW_SEMIBOLD, kAccent);

        RECT runtime_rect{
            title.left,
            status_rect.bottom + ScaleForDpi(6, dpi),
            card.right - ScaleForDpi(20, dpi),
            status_rect.bottom + ScaleForDpi(34, dpi),
        };
        DrawTextValue(
            device,
            L"WEB RUNTIME: OFF  |  React / Vite / Node / WebView2: fora do boot",
            runtime_rect,
            10,
            FW_SEMIBOLD,
            kPrimaryText);

        RECT help{
            ScaleForDpi(30, dpi),
            client.bottom - TaskbarHeight() - ScaleForDpi(76, dpi),
            client.right - ScaleForDpi(30, dpi),
            client.bottom - TaskbarHeight() - ScaleForDpi(20, dpi),
        };
        DrawTextValue(
            device,
            L"Ctrl+Alt: Enter terminal | K WSL | E arquivos | A apps | P processos | R executar | T tiling | 1-4 workspaces",
            help,
            10,
            FW_NORMAL,
            kSecondaryText,
            DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_CENTER);

        EndPaint(desktop_, &paint);
    }

    void PaintTaskbar()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(taskbar_, &paint);
        RECT client{};
        GetClientRect(taskbar_, &client);
        FillSolid(device, client, RGB(20, 24, 33));

        const UINT dpi = GetDpiForWindow(taskbar_);
        const int margin = ScaleForDpi(8, dpi);
        const int client_height = static_cast<int>(client.bottom - client.top);
        const int button_height = std::max(26, client_height - margin * 2);

        start_button_rect_ = RECT{
            margin,
            margin,
            margin + ScaleForDpi(112, dpi),
            margin + button_height,
        };
        DrawPanel(
            device,
            start_button_rect_,
            IsWindowVisible(start_) ? kPanelHover : kPanelBackground,
            IsWindowVisible(start_) ? kAccent : kBorder,
            ScaleForDpi(10, dpi));
        RECT start_text = start_button_rect_;
        start_text.left += ScaleForDpi(14, dpi);
        DrawTextValue(device, L"CloudOS", start_text, 11, FW_SEMIBOLD, kPrimaryText);

        workspace_rects_.fill(RECT{});
        const int workspace_width = ScaleForDpi(34, dpi);
        const int workspace_gap = ScaleForDpi(6, dpi);
        const int clock_width = ScaleForDpi(92, dpi);
        int right = client.right - margin - clock_width;
        for (int workspace = 3; workspace >= 0; --workspace)
        {
            RECT rectangle{
                right - workspace_width,
                margin,
                right,
                margin + button_height,
            };
            workspace_rects_[static_cast<std::size_t>(workspace)] = rectangle;
            DrawPanel(
                device,
                rectangle,
                workspace == window_manager_.CurrentWorkspace() ? kAccent : kPanelBackground,
                workspace == window_manager_.CurrentWorkspace() ? kAccent : kBorder,
                ScaleForDpi(8, dpi));
            const std::wstring label = std::to_wstring(workspace + 1);
            DrawTextValue(
                device,
                label,
                rectangle,
                10,
                FW_SEMIBOLD,
                kPrimaryText,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            right = rectangle.left - workspace_gap;
        }

        SYSTEMTIME local_time{};
        GetLocalTime(&local_time);
        wchar_t clock[32]{};
        swprintf_s(clock, L"%02u:%02u", local_time.wHour, local_time.wMinute);
        RECT clock_rect{
            client.right - margin - clock_width,
            margin,
            client.right - margin,
            margin + button_height,
        };
        DrawTextValue(
            device,
            clock,
            clock_rect,
            10,
            FW_SEMIBOLD,
            kPrimaryText,
            DT_SINGLELINE | DT_VCENTER | DT_RIGHT);

        const int tasks_left = start_button_rect_.right + margin;
        const int tasks_right = right - margin;
        task_hits_.clear();
        const auto windows = window_manager_.CurrentWorkspaceWindows();
        const std::size_t visible_count = std::min<std::size_t>(windows.size(), 8u);
        if (visible_count > 0 && tasks_right > tasks_left)
        {
            const int available = tasks_right - tasks_left;
            const int button_width = std::clamp(
                available / static_cast<int>(visible_count),
                ScaleForDpi(92, dpi),
                ScaleForDpi(220, dpi));
            int left = tasks_left;
            for (std::size_t index = 0; index < visible_count && left < tasks_right; ++index)
            {
                RECT rectangle{
                    left,
                    margin,
                    std::min(tasks_right, left + button_width - workspace_gap),
                    margin + button_height,
                };
                if (rectangle.right <= rectangle.left)
                {
                    break;
                }

                const bool active = windows[index].hwnd == window_manager_.ActiveManagedWindow();
                DrawPanel(
                    device,
                    rectangle,
                    active ? kPanelHover : kPanelBackground,
                    active ? kAccent : kBorder,
                    ScaleForDpi(8, dpi));

                RECT text_rectangle = rectangle;
                text_rectangle.left += ScaleForDpi(10, dpi);
                text_rectangle.right -= ScaleForDpi(8, dpi);
                DrawTextValue(
                    device,
                    windows[index].title,
                    text_rectangle,
                    9,
                    active ? FW_SEMIBOLD : FW_NORMAL,
                    active ? kPrimaryText : kSecondaryText);
                task_hits_.push_back({windows[index].hwnd, rectangle});
                left += button_width;
            }
        }

        EndPaint(taskbar_, &paint);
    }

    std::array<std::wstring, 8> StartLabels() const
    {
        return {
            L"Terminal nativo (ConPTY)",
            L"WSL / Kali terminal",
            L"Aplicativos do Windows",
            L"Arquivos Windows + WSL",
            L"Processos",
            L"Executar",
            window_manager_.TilingEnabled() ? L"Desativar tiling" : L"Ativar tiling",
            L"Sair do CloudOS",
        };
    }

    void PaintStart()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(start_, &paint);
        RECT client{};
        GetClientRect(start_, &client);
        FillSolid(device, client, RGB(22, 27, 37));

        const UINT dpi = GetDpiForWindow(start_);
        RECT title{
            ScaleForDpi(24, dpi),
            ScaleForDpi(18, dpi),
            client.right - ScaleForDpi(20, dpi),
            ScaleForDpi(58, dpi),
        };
        DrawTextValue(device, L"CloudOS", title, 22, FW_SEMIBOLD, kPrimaryText);

        RECT subtitle{
            title.left,
            title.bottom,
            title.right,
            title.bottom + ScaleForDpi(26, dpi),
        };
        DrawTextValue(device, L"Sistema nativo do Windows", subtitle, 10, FW_NORMAL, kSecondaryText);

        const auto labels = StartLabels();
        const int row_height = ScaleForDpi(48, dpi);
        const int gap = ScaleForDpi(7, dpi);
        int top = subtitle.bottom + ScaleForDpi(18, dpi);
        start_item_rects_.fill(RECT{});

        for (std::size_t index = 0; index < labels.size(); ++index)
        {
            RECT row{
                ScaleForDpi(18, dpi),
                top,
                client.right - ScaleForDpi(18, dpi),
                top + row_height,
            };
            start_item_rects_[index] = row;
            DrawPanel(device, row, kPanelBackground, kBorder, ScaleForDpi(10, dpi));
            RECT text = row;
            text.left += ScaleForDpi(16, dpi);
            text.right -= ScaleForDpi(12, dpi);
            DrawTextValue(
                device,
                labels[index],
                text,
                10,
                index == 7 ? FW_SEMIBOLD : FW_NORMAL,
                index == 7 ? RGB(255, 175, 175) : kPrimaryText);
            top += row_height + gap;
        }

        EndPaint(start_, &paint);
    }

    LRESULT HandleDesktopMessage(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT:
            PaintDesktop();
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_TIMER:
            if (w_param == kReconcileTimer)
            {
                window_manager_.Reconcile();
                SetWindowPos(
                    desktop_,
                    HWND_BOTTOM,
                    0,
                    0,
                    0,
                    0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                SetWindowPos(
                    taskbar_,
                    HWND_TOPMOST,
                    0,
                    0,
                    0,
                    0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
                InvalidateAll();
            }
            return 0;

        case CLOUDOS_WM_NATIVE_WINDOW_EVENT:
            window_manager_.HandleRuntimeEvent(
                static_cast<cloudos_native_window_event_kind>(w_param),
                reinterpret_cast<HWND>(l_param));
            InvalidateAll();
            return 0;

        case WM_HOTKEY:
            HandleHotKey(static_cast<int>(w_param));
            return 0;

        case WM_DISPLAYCHANGE:
        case WM_SETTINGCHANGE:
            RepositionShellWindows();
            InvalidateAll();
            return 0;

        case WM_LBUTTONUP:
            HideStartMenu();
            SetWindowPos(
                desktop_,
                HWND_BOTTOM,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            return 0;

        case WM_CLOSE:
            window_manager_.Shutdown();
            if (start_ != nullptr && IsWindow(start_))
            {
                DestroyWindow(start_);
                start_ = nullptr;
            }
            if (taskbar_ != nullptr && IsWindow(taskbar_))
            {
                DestroyWindow(taskbar_);
                taskbar_ = nullptr;
            }
            DestroyWindow(desktop_);
            return 0;

        case WM_DESTROY:
            desktop_ = nullptr;
            PostQuitMessage(0);
            return 0;

        default:
            break;
        }

        return DefWindowProcW(desktop_, message, w_param, l_param);
    }

    LRESULT HandleTaskbarMessage(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT:
            PaintTaskbar();
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_LBUTTONUP:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            if (PointInside(start_button_rect_, point))
            {
                ToggleStartMenu();
                InvalidateRect(taskbar_, nullptr, FALSE);
                return 0;
            }

            for (const auto& hit : task_hits_)
            {
                if (PointInside(hit.bounds, point))
                {
                    HideStartMenu();
                    window_manager_.FocusWindow(hit.window);
                    InvalidateAll();
                    return 0;
                }
            }

            for (std::size_t workspace = 0; workspace < workspace_rects_.size(); ++workspace)
            {
                if (PointInside(workspace_rects_[workspace], point))
                {
                    HideStartMenu();
                    window_manager_.SwitchWorkspace(static_cast<int>(workspace));
                    InvalidateAll();
                    return 0;
                }
            }
            return 0;
        }

        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            RepositionShellWindows();
            InvalidateAll();
            return 0;

        case WM_DESTROY:
            taskbar_ = nullptr;
            return 0;

        default:
            break;
        }

        return DefWindowProcW(taskbar_, message, w_param, l_param);
    }

    LRESULT HandleStartMessage(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT:
            PaintStart();
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_LBUTTONUP:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < start_item_rects_.size(); ++index)
            {
                if (PointInside(start_item_rects_[index], point))
                {
                    LaunchStartItem(index);
                    return 0;
                }
            }
            return 0;
        }

        case WM_KEYDOWN:
            if (w_param == VK_ESCAPE)
            {
                HideStartMenu();
                return 0;
            }
            break;

        case WM_KILLFOCUS:
            if (reinterpret_cast<HWND>(w_param) != taskbar_)
            {
                HideStartMenu();
            }
            return 0;

        case WM_DPICHANGED:
            RepositionShellWindows();
            InvalidateAll();
            return 0;

        case WM_DESTROY:
            start_ = nullptr;
            return 0;

        default:
            break;
        }

        return DefWindowProcW(start_, message, w_param, l_param);
    }

    static CloudOSShell* ResolveShell(HWND window, UINT message, LPARAM l_param)
    {
        CloudOSShell* shell = nullptr;
        if (message == WM_NCCREATE)
        {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
            shell = static_cast<CloudOSShell*>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(shell));
        }
        else
        {
            shell = reinterpret_cast<CloudOSShell*>(GetWindowLongPtrW(window, GWLP_USERDATA));
        }
        return shell;
    }

    static LRESULT CALLBACK DesktopProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param)
    {
        auto* shell = ResolveShell(window, message, l_param);
        if (shell != nullptr && shell->desktop_ == nullptr && message == WM_NCCREATE)
        {
            shell->desktop_ = window;
        }
        return shell != nullptr
            ? shell->HandleDesktopMessage(message, w_param, l_param)
            : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK TaskbarProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param)
    {
        auto* shell = ResolveShell(window, message, l_param);
        if (shell != nullptr && shell->taskbar_ == nullptr && message == WM_NCCREATE)
        {
            shell->taskbar_ = window;
        }
        return shell != nullptr
            ? shell->HandleTaskbarMessage(message, w_param, l_param)
            : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK StartProcedure(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param)
    {
        auto* shell = ResolveShell(window, message, l_param);
        if (shell != nullptr && shell->start_ == nullptr && message == WM_NCCREATE)
        {
            shell->start_ = window;
        }
        return shell != nullptr
            ? shell->HandleStartMessage(message, w_param, l_param)
            : DefWindowProcW(window, message, w_param, l_param);
    }

    HINSTANCE instance_{};
    HWND desktop_{};
    HWND taskbar_{};
    HWND start_{};
    bool shutting_down_{};

    RECT start_button_rect_{};
    std::array<RECT, 4> workspace_rects_{};
    std::array<RECT, 8> start_item_rects_{};
    std::vector<TaskHit> task_hits_;
    std::vector<int> registered_hotkeys_;
    CloudOSNativeWindowManager window_manager_;
};
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int)
{
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    INITCOMMONCONTROLSEX common_controls{};
    common_controls.dwSize = sizeof(common_controls);
    common_controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES;
    if (!InitCommonControlsEx(&common_controls))
    {
        MessageBoxW(
            nullptr,
            L"O CloudOS Native nao conseguiu inicializar os controles Win32.",
            L"CloudOS Native",
            MB_OK | MB_ICONERROR);
        return 1;
    }

    const HRESULT com_result = CoInitializeEx(
        nullptr,
        COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool uninitialize_com = SUCCEEDED(com_result);

    CloudOSShell shell(instance);
    if (!shell.Initialize())
    {
        if (uninitialize_com)
        {
            CoUninitialize();
        }
        MessageBoxW(
            nullptr,
            L"O CloudOS Native nao conseguiu inicializar o shell Win32.",
            L"CloudOS Native",
            MB_OK | MB_ICONERROR);
        return 1;
    }

    const int exit_code = shell.Run();
    if (uninitialize_com)
    {
        CoUninitialize();
    }
    return exit_code;
}
