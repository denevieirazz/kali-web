#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdio>
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
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.Desktop.v4";
constexpr wchar_t kMenuBarClass[] = L"CloudOS.NativeShell.MenuBar.v4";
constexpr wchar_t kDockClass[] = L"CloudOS.NativeShell.Dock.v4";
constexpr wchar_t kLaunchpadClass[] = L"CloudOS.NativeShell.Launchpad.v4";

constexpr int kDockHeight = 78;
constexpr int kDockWidth = 900;
constexpr int kMenuBarHeight = 32;
constexpr int kLaunchpadWidth = 570;
constexpr int kLaunchpadHeight = 455;
constexpr int kShellMargin = 12;
constexpr UINT_PTR kReconcileTimer = 1;

constexpr COLORREF kDesktopTop = RGB(11, 16, 29);
constexpr COLORREF kDesktopBottom = RGB(24, 18, 43);
constexpr COLORREF kGlowLeft = RGB(31, 29, 67);
constexpr COLORREF kGlowRight = RGB(20, 46, 65);
constexpr COLORREF kSurface = RGB(27, 31, 42);
constexpr COLORREF kSurfaceDeep = RGB(18, 21, 29);
constexpr COLORREF kSurfaceRaised = RGB(43, 49, 65);
constexpr COLORREF kBorder = RGB(68, 77, 98);
constexpr COLORREF kBorderSoft = RGB(47, 54, 71);
constexpr COLORREF kAccent = RGB(104, 151, 255);
constexpr COLORREF kAccentSoft = RGB(137, 173, 255);
constexpr COLORREF kText = RGB(244, 247, 252);
constexpr COLORREF kTextSecondary = RGB(165, 176, 194);
constexpr COLORREF kTextMuted = RGB(118, 129, 148);
constexpr COLORREF kDanger = RGB(255, 151, 151);

struct TaskHit final
{
    HWND window{};
    RECT bounds{};
};

struct DesktopShortcut final
{
    const wchar_t* glyph;
    const wchar_t* label;
};

constexpr std::array<DesktopShortcut, 3> kDesktopShortcuts{{
    {L"D", L"CloudOS Drive"},
    {L">_", L"Terminal"},
    {L"A", L"Aplicativos"},
}};

constexpr std::array<const wchar_t*, 7> kDockGlyphs{{
    L"C", L">_", L"K", L"F", L"A", L"P", L"R",
}};

constexpr std::array<const wchar_t*, 8> kLaunchpadGlyphs{{
    L">_", L"K", L"A", L"F", L"P", L"R", L"T", L"\u23fb",
}};

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

int Scale(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

int Width(const RECT& rectangle) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rectangle.right - rectangle.left));
}

int Height(const RECT& rectangle) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rectangle.bottom - rectangle.top));
}

bool Contains(const RECT& rectangle, POINT point) noexcept
{
    return point.x >= rectangle.left && point.x < rectangle.right &&
        point.y >= rectangle.top && point.y < rectangle.bottom;
}

COLORREF Blend(COLORREF first, COLORREF second, int position, int total) noexcept
{
    total = std::max(1, total);
    position = std::clamp(position, 0, total);
    return RGB(
        GetRValue(first) + (GetRValue(second) - GetRValue(first)) * position / total,
        GetGValue(first) + (GetGValue(second) - GetGValue(first)) * position / total,
        GetBValue(first) + (GetBValue(second) - GetBValue(first)) * position / total);
}

void Fill(HDC device, const RECT& rectangle, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    FillRect(device, &rectangle, brush);
    DeleteObject(brush);
}

void Gradient(HDC device, const RECT& rectangle, COLORREF top, COLORREF bottom)
{
    constexpr int band_count = 96;
    const int height = std::max(1, Height(rectangle));
    for (int band = 0; band < band_count; ++band)
    {
        const int first = static_cast<int>(rectangle.top) + height * band / band_count;
        const int last = static_cast<int>(rectangle.top) + height * (band + 1) / band_count;
        RECT strip{
            rectangle.left,
            static_cast<LONG>(first),
            rectangle.right,
            static_cast<LONG>(std::max(first + 1, last)),
        };
        Fill(device, strip, Blend(top, bottom, band, band_count - 1));
    }
}

void Panel(HDC device, const RECT& rectangle, COLORREF fill, COLORREF outline, int radius)
{
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, outline);
    HGDIOBJ old_brush = SelectObject(device, brush);
    HGDIOBJ old_pen = SelectObject(device, pen);
    RoundRect(
        device,
        rectangle.left,
        rectangle.top,
        rectangle.right,
        rectangle.bottom,
        radius,
        radius);
    SelectObject(device, old_pen);
    SelectObject(device, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void Circle(HDC device, const RECT& rectangle, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    HPEN pen = CreatePen(PS_SOLID, 1, color);
    HGDIOBJ old_brush = SelectObject(device, brush);
    HGDIOBJ old_pen = SelectObject(device, pen);
    Ellipse(device, rectangle.left, rectangle.top, rectangle.right, rectangle.bottom);
    SelectObject(device, old_pen);
    SelectObject(device, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void Text(
    HDC device,
    std::wstring_view value,
    RECT rectangle,
    int point_size,
    int weight,
    COLORREF color,
    UINT format = DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS)
{
    const UINT dpi = static_cast<UINT>(std::max(96, GetDeviceCaps(device, LOGPIXELSY)));
    HFONT font = CreateFontW(
        -MulDiv(point_size, static_cast<int>(dpi), 72),
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
    HGDIOBJ old_font = font != nullptr ? SelectObject(device, font) : nullptr;
    SetBkMode(device, TRANSPARENT);
    SetTextColor(device, color);
    DrawTextW(device, value.data(), static_cast<int>(value.size()), &rectangle, format | DT_NOPREFIX);
    if (old_font != nullptr)
    {
        SelectObject(device, old_font);
    }
    if (font != nullptr)
    {
        DeleteObject(font);
    }
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
    return length > 0 && length < buffer.size() ? std::wstring(buffer.data()) : std::wstring(executable);
}

std::wstring Quote(const std::wstring& value)
{
    return L"\"" + value + L"\"";
}

void DarkWindow(HWND window, bool rounded)
{
    if (window == nullptr)
    {
        return;
    }
    const BOOL dark = TRUE;
    constexpr DWORD dark_attribute = 20;
    (void)DwmSetWindowAttribute(window, dark_attribute, &dark, sizeof(dark));
    if (rounded)
    {
        constexpr DWORD corner_attribute = 33;
        const DWORD rounded_preference = 2;
        (void)DwmSetWindowAttribute(window, corner_attribute, &rounded_preference, sizeof(rounded_preference));
    }
}

void RoundWindow(HWND window, int radius)
{
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }
    RECT client{};
    if (!GetClientRect(window, &client) || Width(client) <= 0 || Height(client) <= 0)
    {
        return;
    }
    HRGN region = CreateRoundRectRgn(
        client.left,
        client.top,
        client.right + 1,
        client.bottom + 1,
        radius,
        radius);
    if (region != nullptr && !SetWindowRgn(window, region, TRUE))
    {
        DeleteObject(region);
    }
}

HICON ReadWindowIcon(HWND window)
{
    DWORD_PTR result = 0;
    if (window != nullptr)
    {
        (void)SendMessageTimeoutW(
            window,
            WM_GETICON,
            ICON_SMALL2,
            0,
            SMTO_ABORTIFHUNG,
            80,
            &result);
    }
    HICON icon = reinterpret_cast<HICON>(result);
    if (icon == nullptr && window != nullptr)
    {
        icon = reinterpret_cast<HICON>(GetClassLongPtrW(window, GCLP_HICONSM));
    }
    if (icon == nullptr && window != nullptr)
    {
        icon = reinterpret_cast<HICON>(GetClassLongPtrW(window, GCLP_HICON));
    }
    return icon;
}

class CloudOSShell final
{
public:
    explicit CloudOSShell(HINSTANCE instance) noexcept : instance_(instance) {}
    ~CloudOSShell() { Shutdown(); }

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
            L"CloudOS Desktop",
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

        menu_bar_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
            kMenuBarClass,
            L"CloudOS Menu Bar",
            WS_POPUP,
            0, 0, 0, 0,
            nullptr,
            nullptr,
            instance_,
            this);
        taskbar_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
            kDockClass,
            L"CloudOS Dock",
            WS_POPUP,
            0, 0, 0, 0,
            nullptr,
            nullptr,
            instance_,
            this);
        start_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
            kLaunchpadClass,
            L"CloudOS Launchpad",
            WS_POPUP,
            0, 0, 0, 0,
            taskbar_,
            nullptr,
            instance_,
            this);
        if (menu_bar_ == nullptr || taskbar_ == nullptr || start_ == nullptr)
        {
            Shutdown();
            return false;
        }

        DarkWindow(menu_bar_, false);
        DarkWindow(taskbar_, true);
        DarkWindow(start_, true);
        LayoutShell();

        ShowWindow(desktop_, SW_SHOWNOACTIVATE);
        SetWindowPos(desktop_, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        ShowWindow(menu_bar_, SW_SHOWNOACTIVATE);
        ShowWindow(taskbar_, SW_SHOWNOACTIVATE);
        ShowWindow(start_, SW_HIDE);

        window_manager_.SetReservedBottomPixels(ReservedBottom());
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
        struct Definition
        {
            const wchar_t* name;
            WNDPROC procedure;
            HCURSOR cursor;
        };
        const Definition definitions[] = {
            {kDesktopClass, &CloudOSShell::DesktopProcedure, LoadCursorW(nullptr, IDC_ARROW)},
            {kMenuBarClass, &CloudOSShell::MenuBarProcedure, LoadCursorW(nullptr, IDC_ARROW)},
            {kDockClass, &CloudOSShell::DockProcedure, LoadCursorW(nullptr, IDC_HAND)},
            {kLaunchpadClass, &CloudOSShell::LaunchpadProcedure, LoadCursorW(nullptr, IDC_ARROW)},
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
            window_class.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
            window_class.hbrBackground = nullptr;
            window_class.lpszClassName = definition.name;
            if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            {
                return false;
            }
        }
        return true;
    }

    int DockPixels() const noexcept
    {
        return Scale(kDockHeight, taskbar_ != nullptr ? GetDpiForWindow(taskbar_) : 96);
    }

    int MenuPixels() const noexcept
    {
        return Scale(kMenuBarHeight, menu_bar_ != nullptr ? GetDpiForWindow(menu_bar_) : 96);
    }

    int ReservedBottom() const noexcept
    {
        const UINT dpi = taskbar_ != nullptr ? GetDpiForWindow(taskbar_) : 96;
        return DockPixels() + Scale(kShellMargin * 2, dpi);
    }

    void LayoutShell()
    {
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        if (!GetMonitorInfoW(MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY), &monitor))
        {
            return;
        }

        const int work_width = static_cast<int>(monitor.rcWork.right - monitor.rcWork.left);
        const int work_height = static_cast<int>(monitor.rcWork.bottom - monitor.rcWork.top);
        const UINT dpi = desktop_ != nullptr ? GetDpiForWindow(desktop_) : 96;
        const int margin = Scale(kShellMargin, dpi);
        const int menu_height = MenuPixels();
        const int dock_height = DockPixels();
        const int dock_width = std::clamp(Scale(kDockWidth, dpi), Scale(620, dpi), std::max(Scale(620, dpi), work_width - margin * 2));

        if (desktop_ != nullptr)
        {
            SetWindowPos(
                desktop_, HWND_BOTTOM,
                monitor.rcWork.left, monitor.rcWork.top,
                work_width, work_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        if (menu_bar_ != nullptr)
        {
            SetWindowPos(
                menu_bar_, HWND_TOPMOST,
                monitor.rcWork.left, monitor.rcWork.top,
                work_width, menu_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        if (taskbar_ != nullptr)
        {
            SetWindowPos(
                taskbar_, HWND_TOPMOST,
                monitor.rcWork.left + (work_width - dock_width) / 2,
                monitor.rcWork.bottom - dock_height - margin,
                dock_width, dock_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
            RoundWindow(taskbar_, Scale(24, GetDpiForWindow(taskbar_)));
        }
        if (start_ != nullptr)
        {
            const UINT start_dpi = GetDpiForWindow(start_);
            const int width = std::min(Scale(kLaunchpadWidth, start_dpi), work_width - margin * 2);
            const int height = std::min(
                Scale(kLaunchpadHeight, start_dpi),
                std::max(Scale(280, start_dpi), work_height - menu_height - dock_height - margin * 4));
            SetWindowPos(
                start_, HWND_TOPMOST,
                monitor.rcWork.left + (work_width - width) / 2,
                monitor.rcWork.bottom - dock_height - margin * 2 - height,
                width, height,
                SWP_NOACTIVATE | (IsWindowVisible(start_) ? SWP_SHOWWINDOW : 0));
            RoundWindow(start_, Scale(24, start_dpi));
        }
        window_manager_.SetReservedBottomPixels(ReservedBottom());
    }

    void RegisterHotKeys()
    {
        const UINT normal = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        const UINT moving = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;
        struct Binding { int id; UINT modifiers; UINT key; };
        const Binding bindings[] = {
            {HotTerminal, normal, VK_RETURN}, {HotWslTerminal, normal, L'K'},
            {HotFiles, normal, L'E'}, {HotApps, normal, L'A'},
            {HotProcesses, normal, L'P'}, {HotRun, normal, L'R'},
            {HotTiling, normal, L'T'}, {HotFloating, normal, L'F'},
            {HotFocusNext, normal, L'J'}, {HotFocusPrevious, normal, L'H'},
            {HotClose, normal, L'Q'}, {HotMinimize, normal, L'M'},
            {HotMaximize, normal, L'Z'},
            {HotSnapLeft, normal, VK_LEFT}, {HotSnapRight, normal, VK_RIGHT},
            {HotSnapUp, normal, VK_UP}, {HotSnapDown, normal, VK_DOWN},
            {HotExit, normal, L'X'},
            {HotWorkspace1, normal, L'1'}, {HotWorkspace2, normal, L'2'},
            {HotWorkspace3, normal, L'3'}, {HotWorkspace4, normal, L'4'},
            {HotMoveWorkspace1, moving, L'1'}, {HotMoveWorkspace2, moving, L'2'},
            {HotMoveWorkspace3, moving, L'3'}, {HotMoveWorkspace4, moving, L'4'},
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
            for (int id : registered_hotkeys_)
            {
                UnregisterHotKey(desktop_, id);
            }
        }
        registered_hotkeys_.clear();
        window_manager_.Shutdown();

        if (start_ != nullptr && IsWindow(start_)) DestroyWindow(start_);
        if (taskbar_ != nullptr && IsWindow(taskbar_)) DestroyWindow(taskbar_);
        if (menu_bar_ != nullptr && IsWindow(menu_bar_)) DestroyWindow(menu_bar_);
        if (desktop_ != nullptr && IsWindow(desktop_)) DestroyWindow(desktop_);
        start_ = nullptr;
        taskbar_ = nullptr;
        menu_bar_ = nullptr;
        desktop_ = nullptr;
    }

    void InvalidateAll()
    {
        if (desktop_ != nullptr) InvalidateRect(desktop_, nullptr, FALSE);
        if (menu_bar_ != nullptr) InvalidateRect(menu_bar_, nullptr, FALSE);
        if (taskbar_ != nullptr) InvalidateRect(taskbar_, nullptr, FALSE);
        if (start_ != nullptr && IsWindowVisible(start_)) InvalidateRect(start_, nullptr, FALSE);
    }

    void HideLaunchpad()
    {
        if (start_ != nullptr && IsWindowVisible(start_))
        {
            ShowWindow(start_, SW_HIDE);
            InvalidateAll();
        }
    }

    void ToggleLaunchpad()
    {
        if (start_ == nullptr)
        {
            return;
        }
        if (IsWindowVisible(start_))
        {
            HideLaunchpad();
            return;
        }
        LayoutShell();
        ShowWindow(start_, SW_SHOW);
        SetWindowPos(start_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetForegroundWindow(start_);
        InvalidateAll();
    }

    void OpenTerminal()
    {
        const std::wstring executable = ResolveExecutable(L"powershell.exe");
        CloudOSNativeTerminalWindow::Open(
            instance_,
            Quote(executable) + L" -NoLogo -NoProfile",
            L"Terminal - CloudOS");
        window_manager_.Reconcile();
        InvalidateAll();
    }

    void OpenWsl()
    {
        const std::wstring executable = ResolveExecutable(L"wsl.exe");
        BOOL kali_registered = FALSE;
        std::wstring command = Quote(executable);
        if (cloudos_native_wsl_is_registered(L"kali-linux", &kali_registered) && kali_registered)
        {
            command += L" -d kali-linux";
        }
        CloudOSNativeTerminalWindow::Open(instance_, command, L"WSL / Kali - CloudOS");
        window_manager_.Reconcile();
        InvalidateAll();
    }

    void OpenAction(std::size_t action)
    {
        HideLaunchpad();
        switch (action)
        {
        case 0: OpenTerminal(); break;
        case 1: OpenWsl(); break;
        case 2: CloudOSNativeAppsWindow::Open(instance_); break;
        case 3: CloudOSNativeFilesWindow::Open(instance_); break;
        case 4: CloudOSNativeProcessWindow::Open(instance_); break;
        case 5: CloudOSNativeRunWindow::Open(instance_); break;
        case 6: window_manager_.ToggleTiling(); break;
        case 7: PostMessageW(desktop_, WM_CLOSE, 0, 0); return;
        default: return;
        }
        window_manager_.Reconcile();
        InvalidateAll();
    }

    void OpenDock(std::size_t item)
    {
        if (item == 0)
        {
            ToggleLaunchpad();
            return;
        }
        const std::array<std::size_t, 6> actions{{0, 1, 3, 2, 4, 5}};
        if (item - 1 < actions.size())
        {
            OpenAction(actions[item - 1]);
        }
    }

    void OpenDesktop(std::size_t item)
    {
        if (item == 0) OpenAction(3);
        else if (item == 1) OpenAction(0);
        else if (item == 2) OpenAction(2);
    }

    void HandleHotKey(int id)
    {
        if (id >= HotWorkspace1 && id <= HotWorkspace4)
        {
            window_manager_.SwitchWorkspace(id - HotWorkspace1);
            HideLaunchpad();
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
        case HotTerminal: OpenTerminal(); break;
        case HotWslTerminal: OpenWsl(); break;
        case HotFiles: CloudOSNativeFilesWindow::Open(instance_); break;
        case HotApps: CloudOSNativeAppsWindow::Open(instance_); break;
        case HotProcesses: CloudOSNativeProcessWindow::Open(instance_); break;
        case HotRun: CloudOSNativeRunWindow::Open(instance_); break;
        case HotTiling: window_manager_.ToggleTiling(); break;
        case HotFloating: window_manager_.ToggleFloatingActive(); break;
        case HotFocusNext: window_manager_.FocusNext(false); break;
        case HotFocusPrevious: window_manager_.FocusNext(true); break;
        case HotClose: window_manager_.CloseActive(); break;
        case HotMinimize: window_manager_.MinimizeActive(); break;
        case HotMaximize: window_manager_.ToggleMaximizeActive(); break;
        case HotSnapLeft: window_manager_.SnapActive(CloudOSSnapDirection::Left); break;
        case HotSnapRight: window_manager_.SnapActive(CloudOSSnapDirection::Right); break;
        case HotSnapUp: window_manager_.SnapActive(CloudOSSnapDirection::Up); break;
        case HotSnapDown: window_manager_.SnapActive(CloudOSSnapDirection::Down); break;
        case HotExit: PostMessageW(desktop_, WM_CLOSE, 0, 0); return;
        default: break;
        }
        window_manager_.Reconcile();
        InvalidateAll();
    }

    std::wstring ActiveTitle() const
    {
        const HWND active = window_manager_.ActiveManagedWindow();
        if (active == nullptr)
        {
            return L"Desktop";
        }
        for (const auto& item : window_manager_.CurrentWorkspaceWindows())
        {
            if (item.hwnd == active && !item.title.empty())
            {
                return item.title;
            }
        }
        return L"CloudOS";
    }

    void PaintDesktop()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(desktop_, &paint);
        RECT client{};
        GetClientRect(desktop_, &client);
        Gradient(device, client, kDesktopTop, kDesktopBottom);
        const UINT dpi = GetDpiForWindow(desktop_);

        HBRUSH left_brush = CreateSolidBrush(kGlowLeft);
        HBRUSH right_brush = CreateSolidBrush(kGlowRight);
        HPEN no_pen = CreatePen(PS_NULL, 0, 0);
        HGDIOBJ old_pen = SelectObject(device, no_pen);
        HGDIOBJ old_brush = SelectObject(device, left_brush);
        Ellipse(
            device,
            client.left - Scale(260, dpi), client.top + Scale(160, dpi),
            client.left + Scale(600, dpi), client.top + Scale(1020, dpi));
        SelectObject(device, right_brush);
        Ellipse(
            device,
            client.right - Scale(690, dpi), client.bottom - Scale(650, dpi),
            client.right + Scale(150, dpi), client.bottom + Scale(190, dpi));
        SelectObject(device, old_brush);
        SelectObject(device, old_pen);
        DeleteObject(no_pen);
        DeleteObject(left_brush);
        DeleteObject(right_brush);

        RECT brand{
            Scale(30, dpi),
            client.bottom - ReservedBottom() - Scale(90, dpi),
            Scale(500, dpi),
            client.bottom - ReservedBottom() - Scale(47, dpi),
        };
        Text(device, L"CloudOS", brand, 30, FW_SEMIBOLD, RGB(222, 229, 245));
        RECT subtitle{brand.left + Scale(2, dpi), brand.bottom - Scale(3, dpi), brand.right, brand.bottom + Scale(27, dpi)};
        Text(device, L"Native workspace  |  C++ / Win32 / ConPTY / WSL", subtitle, 10, FW_NORMAL, kTextSecondary);

        shortcut_rects_.fill(RECT{});
        const int cell_width = Scale(116, dpi);
        const int cell_height = Scale(103, dpi);
        const int icon_size = Scale(55, dpi);
        const int right_margin = Scale(25, dpi);
        int top = MenuPixels() + Scale(28, dpi);
        for (std::size_t index = 0; index < kDesktopShortcuts.size(); ++index)
        {
            RECT cell{
                client.right - right_margin - cell_width,
                top,
                client.right - right_margin,
                top + cell_height,
            };
            shortcut_rects_[index] = cell;
            const bool selected = selected_shortcut_ == static_cast<int>(index);
            if (selected)
            {
                Panel(device, cell, RGB(36, 42, 57), RGB(72, 85, 113), Scale(12, dpi));
            }
            RECT icon{
                cell.left + (cell_width - icon_size) / 2,
                cell.top + Scale(7, dpi),
                cell.left + (cell_width + icon_size) / 2,
                cell.top + Scale(7, dpi) + icon_size,
            };
            const COLORREF icon_color = index == 0 ? RGB(72, 109, 190) : (index == 1 ? RGB(43, 48, 60) : RGB(89, 75, 156));
            Panel(device, icon, icon_color, selected ? kAccentSoft : kBorder, Scale(14, dpi));
            Text(device, kDesktopShortcuts[index].glyph, icon, index == 1 ? 12 : 17, FW_SEMIBOLD, kText, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            RECT label{cell.left, icon.bottom + Scale(5, dpi), cell.right, cell.bottom};
            Text(device, kDesktopShortcuts[index].label, label, 9, selected ? FW_SEMIBOLD : FW_NORMAL, kText, DT_SINGLELINE | DT_TOP | DT_CENTER | DT_END_ELLIPSIS);
            top += cell_height + Scale(6, dpi);
        }
        EndPaint(desktop_, &paint);
    }

    void PaintMenuBar()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(menu_bar_, &paint);
        RECT client{};
        GetClientRect(menu_bar_, &client);
        Fill(device, client, RGB(16, 19, 27));
        const UINT dpi = GetDpiForWindow(menu_bar_);

        cloudos_menu_rect_ = RECT{Scale(14, dpi), 0, Scale(102, dpi), client.bottom};
        Text(device, L"CloudOS", cloudos_menu_rect_, 10, FW_BOLD, kText, DT_SINGLELINE | DT_VCENTER | DT_LEFT);

        int left = static_cast<int>(cloudos_menu_rect_.right) + Scale(4, dpi);
        const std::array<const wchar_t*, 5> menus{{L"Arquivo", L"Janelas", L"Ir", L"Aplicativos", L"Ajuda"}};
        const std::array<int, 5> widths{{58, 62, 34, 82, 48}};
        for (std::size_t index = 0; index < menus.size(); ++index)
        {
            RECT item{left, 0, left + Scale(widths[index], dpi), client.bottom};
            Text(device, menus[index], item, 9, FW_NORMAL, kTextSecondary, DT_SINGLELINE | DT_VCENTER | DT_LEFT);
            left = static_cast<int>(item.right) + Scale(8, dpi);
        }

        const int client_right = static_cast<int>(client.right);
        RECT active{
            static_cast<LONG>(std::max(left + Scale(10, dpi), client_right / 2 - Scale(180, dpi))),
            0,
            static_cast<LONG>(std::min(client_right - Scale(335, dpi), client_right / 2 + Scale(180, dpi))),
            client.bottom,
        };
        if (active.right > active.left)
        {
            Text(device, ActiveTitle(), active, 9, FW_SEMIBOLD, kText, DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_END_ELLIPSIS);
        }

        SYSTEMTIME local_time{};
        GetLocalTime(&local_time);
        wchar_t status_text[96]{};
        swprintf_s(
            status_text,
            L"W%d  |  %s  |  %02u:%02u  %02u/%02u",
            window_manager_.CurrentWorkspace() + 1,
            window_manager_.TilingEnabled() ? L"Tiling" : L"Floating",
            local_time.wHour,
            local_time.wMinute,
            local_time.wDay,
            local_time.wMonth);
        RECT status{client.right - Scale(325, dpi), 0, client.right - Scale(14, dpi), client.bottom};
        Text(device, status_text, status, 9, FW_SEMIBOLD, kText, DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_END_ELLIPSIS);
        EndPaint(menu_bar_, &paint);
    }

    void PaintDock()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(taskbar_, &paint);
        RECT client{};
        GetClientRect(taskbar_, &client);
        Fill(device, client, RGB(17, 20, 28));
        const UINT dpi = GetDpiForWindow(taskbar_);
        const int margin = Scale(9, dpi);
        const int item_size = Scale(52, dpi);
        const int gap = Scale(6, dpi);

        dock_rects_.fill(RECT{});
        workspace_rects_.fill(RECT{});
        task_hits_.clear();

        int left = margin;
        for (std::size_t index = 0; index < kDockGlyphs.size(); ++index)
        {
            RECT button{left, margin, left + item_size, margin + item_size};
            dock_rects_[index] = button;
            const bool launchpad_open = index == 0 && IsWindowVisible(start_);
            Panel(
                device,
                button,
                launchpad_open ? kSurfaceRaised : kSurface,
                launchpad_open ? kAccent : kBorderSoft,
                Scale(14, dpi));
            Text(device, kDockGlyphs[index], button, index == 1 ? 11 : 15, FW_SEMIBOLD, index == 0 ? kAccentSoft : kText, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            left += item_size + gap;
        }

        left += gap;
        RECT divider{left, Scale(16, dpi), left + 1, client.bottom - Scale(16, dpi)};
        Fill(device, divider, kBorderSoft);
        left += gap * 2;

        const int workspace_width = Scale(30, dpi);
        const int workspace_area = (workspace_width + gap) * 4 + margin;
        const int tasks_right = static_cast<int>(client.right) - workspace_area;
        const auto windows = window_manager_.CurrentWorkspaceWindows();
        const std::size_t task_count = std::min<std::size_t>(windows.size(), 4u);
        const int task_size = Scale(52, dpi);
        for (std::size_t index = 0; index < task_count && left + task_size <= tasks_right; ++index)
        {
            RECT task{left, margin, left + task_size, margin + item_size};
            const bool active = windows[index].hwnd == window_manager_.ActiveManagedWindow();
            Panel(device, task, active ? kSurfaceRaised : kSurfaceDeep, active ? kAccent : kBorderSoft, Scale(14, dpi));
            HICON icon = ReadWindowIcon(windows[index].hwnd);
            if (icon != nullptr)
            {
                const int icon_size = Scale(28, dpi);
                DrawIconEx(
                    device,
                    task.left + (Width(task) - icon_size) / 2,
                    task.top + Scale(8, dpi),
                    icon,
                    icon_size,
                    icon_size,
                    0,
                    nullptr,
                    DI_NORMAL);
            }
            else
            {
                Text(device, L"\u25cf", task, 12, FW_NORMAL, kTextSecondary, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            }
            if (active)
            {
                const LONG center = task.left + Width(task) / 2;
                RECT dot{center - Scale(2, dpi), task.bottom - Scale(6, dpi), center + Scale(2, dpi), task.bottom - Scale(2, dpi)};
                Circle(device, dot, kAccent);
            }
            task_hits_.push_back({windows[index].hwnd, task});
            left += task_size + gap;
        }

        int workspace_left = static_cast<int>(client.right) - workspace_area + gap;
        for (int workspace = 0; workspace < 4; ++workspace)
        {
            RECT item{
                workspace_left,
                Scale(21, dpi),
                workspace_left + workspace_width,
                client.bottom - Scale(21, dpi),
            };
            workspace_rects_[static_cast<std::size_t>(workspace)] = item;
            const bool current = workspace == window_manager_.CurrentWorkspace();
            Panel(device, item, current ? kAccent : kSurfaceDeep, current ? kAccent : kBorderSoft, Scale(10, dpi));
            Text(device, std::to_wstring(workspace + 1), item, 8, FW_SEMIBOLD, current ? kText : kTextSecondary, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            workspace_left += workspace_width + gap;
        }
        EndPaint(taskbar_, &paint);
    }

    std::array<std::wstring, 8> LaunchpadLabels() const
    {
        return {
            L"Terminal",
            L"WSL / Kali",
            L"Aplicativos",
            L"Arquivos",
            L"Processos",
            L"Executar",
            window_manager_.TilingEnabled() ? L"Desativar tiling" : L"Ativar tiling",
            L"Desligar CloudOS",
        };
    }

    void PaintLaunchpad()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(start_, &paint);
        RECT client{};
        GetClientRect(start_, &client);
        Gradient(device, client, RGB(24, 28, 38), RGB(17, 20, 28));
        const UINT dpi = GetDpiForWindow(start_);

        RECT title{Scale(26, dpi), Scale(18, dpi), client.right - Scale(24, dpi), Scale(54, dpi)};
        Text(device, L"Aplicativos", title, 21, FW_SEMIBOLD, kText);
        RECT subtitle{title.left, title.bottom, title.right, title.bottom + Scale(25, dpi)};
        Text(device, L"CloudOS Native  \u2022  runtime web fora do boot", subtitle, 9, FW_NORMAL, kTextSecondary);

        const auto labels = LaunchpadLabels();
        const int outer = Scale(24, dpi);
        const int gap = Scale(12, dpi);
        const int tile_width = std::max(100, (static_cast<int>(client.right) - outer * 2 - gap) / 2);
        const int tile_height = Scale(72, dpi);
        const int first_top = static_cast<int>(subtitle.bottom) + Scale(18, dpi);
        launchpad_rects_.fill(RECT{});

        for (std::size_t index = 0; index < labels.size(); ++index)
        {
            const int column = static_cast<int>(index % 2u);
            const int row = static_cast<int>(index / 2u);
            RECT tile{
                outer + column * (tile_width + gap),
                first_top + row * (tile_height + gap),
                outer + column * (tile_width + gap) + tile_width,
                first_top + row * (tile_height + gap) + tile_height,
            };
            launchpad_rects_[index] = tile;
            const bool power = index == 7;
            Panel(device, tile, kSurface, power ? RGB(111, 61, 69) : kBorderSoft, Scale(14, dpi));
            RECT glyph_box{tile.left + Scale(12, dpi), tile.top + Scale(12, dpi), tile.left + Scale(56, dpi), tile.bottom - Scale(12, dpi)};
            Panel(device, glyph_box, power ? RGB(101, 47, 55) : RGB(38, 44, 59), power ? RGB(151, 80, 89) : kBorder, Scale(11, dpi));
            Text(device, kLaunchpadGlyphs[index], glyph_box, index == 0 ? 10 : 13, FW_SEMIBOLD, power ? kDanger : kAccentSoft, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            RECT text{glyph_box.right + Scale(12, dpi), tile.top, tile.right - Scale(10, dpi), tile.bottom};
            Text(device, labels[index], text, 10, power ? FW_SEMIBOLD : FW_NORMAL, power ? kDanger : kText);
        }
        EndPaint(start_, &paint);
    }

    void KeepZOrder()
    {
        if (desktop_ != nullptr)
        {
            SetWindowPos(desktop_, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        if (menu_bar_ != nullptr)
        {
            SetWindowPos(menu_bar_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        if (taskbar_ != nullptr)
        {
            SetWindowPos(taskbar_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
    }

    LRESULT HandleDesktop(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT: PaintDesktop(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_TIMER:
            if (w_param == kReconcileTimer)
            {
                window_manager_.Reconcile();
                KeepZOrder();
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
        case WM_DPICHANGED:
            LayoutShell();
            InvalidateAll();
            return 0;
        case WM_LBUTTONUP:
        {
            HideLaunchpad();
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            selected_shortcut_ = -1;
            for (std::size_t index = 0; index < shortcut_rects_.size(); ++index)
            {
                if (Contains(shortcut_rects_[index], point))
                {
                    selected_shortcut_ = static_cast<int>(index);
                    break;
                }
            }
            InvalidateRect(desktop_, nullptr, FALSE);
            SetWindowPos(desktop_, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            return 0;
        }
        case WM_LBUTTONDBLCLK:
        {
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < shortcut_rects_.size(); ++index)
            {
                if (Contains(shortcut_rects_[index], point))
                {
                    OpenDesktop(index);
                    return 0;
                }
            }
            return 0;
        }
        case WM_CLOSE:
            window_manager_.Shutdown();
            if (start_ != nullptr && IsWindow(start_)) DestroyWindow(start_);
            if (taskbar_ != nullptr && IsWindow(taskbar_)) DestroyWindow(taskbar_);
            if (menu_bar_ != nullptr && IsWindow(menu_bar_)) DestroyWindow(menu_bar_);
            DestroyWindow(desktop_);
            return 0;
        case WM_DESTROY:
            desktop_ = nullptr;
            PostQuitMessage(0);
            return 0;
        default: break;
        }
        return DefWindowProcW(desktop_, message, w_param, l_param);
    }

    LRESULT HandleMenuBar(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT: PaintMenuBar(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_LBUTTONUP:
        {
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            if (Contains(cloudos_menu_rect_, point))
            {
                ToggleLaunchpad();
            }
            return 0;
        }
        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            LayoutShell();
            InvalidateAll();
            return 0;
        case WM_DESTROY:
            menu_bar_ = nullptr;
            return 0;
        default: break;
        }
        return DefWindowProcW(menu_bar_, message, w_param, l_param);
    }

    LRESULT HandleDock(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT: PaintDock(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_LBUTTONUP:
        {
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < dock_rects_.size(); ++index)
            {
                if (Contains(dock_rects_[index], point))
                {
                    OpenDock(index);
                    return 0;
                }
            }
            for (const auto& task : task_hits_)
            {
                if (Contains(task.bounds, point))
                {
                    HideLaunchpad();
                    window_manager_.FocusWindow(task.window);
                    InvalidateAll();
                    return 0;
                }
            }
            for (std::size_t workspace = 0; workspace < workspace_rects_.size(); ++workspace)
            {
                if (Contains(workspace_rects_[workspace], point))
                {
                    HideLaunchpad();
                    window_manager_.SwitchWorkspace(static_cast<int>(workspace));
                    InvalidateAll();
                    return 0;
                }
            }
            return 0;
        }
        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            LayoutShell();
            InvalidateAll();
            return 0;
        case WM_DESTROY:
            taskbar_ = nullptr;
            return 0;
        default: break;
        }
        return DefWindowProcW(taskbar_, message, w_param, l_param);
    }

    LRESULT HandleLaunchpad(UINT message, WPARAM w_param, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT: PaintLaunchpad(); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_LBUTTONUP:
        {
            const POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < launchpad_rects_.size(); ++index)
            {
                if (Contains(launchpad_rects_[index], point))
                {
                    OpenAction(index);
                    return 0;
                }
            }
            return 0;
        }
        case WM_KEYDOWN:
            if (w_param == VK_ESCAPE)
            {
                HideLaunchpad();
                return 0;
            }
            break;
        case WM_KILLFOCUS:
            if (reinterpret_cast<HWND>(w_param) != taskbar_ && reinterpret_cast<HWND>(w_param) != menu_bar_)
            {
                HideLaunchpad();
            }
            return 0;
        case WM_DPICHANGED:
            LayoutShell();
            InvalidateAll();
            return 0;
        case WM_DESTROY:
            start_ = nullptr;
            return 0;
        default: break;
        }
        return DefWindowProcW(start_, message, w_param, l_param);
    }

    static CloudOSShell* Resolve(HWND window, UINT message, LPARAM l_param)
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

    static LRESULT CALLBACK DesktopProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
    {
        auto* shell = Resolve(window, message, l_param);
        if (shell != nullptr && shell->desktop_ == nullptr && message == WM_NCCREATE) shell->desktop_ = window;
        return shell != nullptr ? shell->HandleDesktop(message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK MenuBarProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
    {
        auto* shell = Resolve(window, message, l_param);
        if (shell != nullptr && shell->menu_bar_ == nullptr && message == WM_NCCREATE) shell->menu_bar_ = window;
        return shell != nullptr ? shell->HandleMenuBar(message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK DockProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
    {
        auto* shell = Resolve(window, message, l_param);
        if (shell != nullptr && shell->taskbar_ == nullptr && message == WM_NCCREATE) shell->taskbar_ = window;
        return shell != nullptr ? shell->HandleDock(message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK LaunchpadProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
    {
        auto* shell = Resolve(window, message, l_param);
        if (shell != nullptr && shell->start_ == nullptr && message == WM_NCCREATE) shell->start_ = window;
        return shell != nullptr ? shell->HandleLaunchpad(message, w_param, l_param) : DefWindowProcW(window, message, w_param, l_param);
    }

    HINSTANCE instance_{};
    HWND desktop_{};
    HWND menu_bar_{};
    HWND taskbar_{};
    HWND start_{};
    bool shutting_down_{};
    int selected_shortcut_{-1};

    RECT cloudos_menu_rect_{};
    std::array<RECT, 3> shortcut_rects_{};
    std::array<RECT, 7> dock_rects_{};
    std::array<RECT, 4> workspace_rects_{};
    std::array<RECT, 8> launchpad_rects_{};
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
    common_controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_WIN95_CLASSES;
    if (!InitCommonControlsEx(&common_controls))
    {
        MessageBoxW(nullptr, L"O CloudOS Native nao conseguiu inicializar os controles Win32.", L"CloudOS Native", MB_OK | MB_ICONERROR);
        return 1;
    }

    const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool uninitialize_com = SUCCEEDED(com_result);

    CloudOSShell shell(instance);
    if (!shell.Initialize())
    {
        if (uninitialize_com) CoUninitialize();
        MessageBoxW(nullptr, L"O CloudOS Native nao conseguiu inicializar o shell Win32.", L"CloudOS Native", MB_OK | MB_ICONERROR);
        return 1;
    }

    const int exit_code = shell.Run();
    if (uninitialize_com) CoUninitialize();
    return exit_code;
}
