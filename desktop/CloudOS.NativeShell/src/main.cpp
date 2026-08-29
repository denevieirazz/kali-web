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
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.Desktop.v3";
constexpr wchar_t kDockClass[] = L"CloudOS.NativeShell.Dock.v3";
constexpr wchar_t kMenuBarClass[] = L"CloudOS.NativeShell.MenuBar.v3";
constexpr wchar_t kStartClass[] = L"CloudOS.NativeShell.Launchpad.v3";

constexpr int kBaseDockHeight = 78;
constexpr int kBaseDockWidth = 920;
constexpr int kBaseMenuBarHeight = 32;
constexpr int kBaseStartWidth = 570;
constexpr int kBaseStartHeight = 470;
constexpr int kBaseShellMargin = 12;
constexpr UINT_PTR kReconcileTimer = 1;

constexpr COLORREF kDesktopTop = RGB(12, 17, 29);
constexpr COLORREF kDesktopBottom = RGB(20, 16, 40);
constexpr COLORREF kDesktopGlowA = RGB(31, 29, 67);
constexpr COLORREF kDesktopGlowB = RGB(20, 47, 66);
constexpr COLORREF kPanelBackground = RGB(28, 32, 43);
constexpr COLORREF kPanelBackgroundDeep = RGB(20, 23, 32);
constexpr COLORREF kPanelHover = RGB(45, 51, 68);
constexpr COLORREF kPanelSelected = RGB(54, 63, 86);
constexpr COLORREF kBorder = RGB(74, 83, 105);
constexpr COLORREF kBorderSoft = RGB(49, 57, 75);
constexpr COLORREF kAccent = RGB(103, 150, 255);
constexpr COLORREF kAccentSoft = RGB(133, 171, 255);
constexpr COLORREF kPrimaryText = RGB(244, 247, 252);
constexpr COLORREF kSecondaryText = RGB(163, 174, 193);
constexpr COLORREF kMutedText = RGB(116, 127, 148);
constexpr COLORREF kDanger = RGB(255, 152, 152);
constexpr COLORREF kGreen = RGB(91, 208, 139);

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

constexpr std::array<const wchar_t*, 7> kDockNames{{
    L"CloudOS", L"Terminal", L"Kali", L"Arquivos", L"Apps", L"Processos", L"Executar",
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

int ScaleForDpi(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi == 0 ? 96 : dpi), 96);
}

bool PointInside(const RECT& rectangle, POINT point) noexcept
{
    return point.x >= rectangle.left && point.x < rectangle.right &&
        point.y >= rectangle.top && point.y < rectangle.bottom;
}

int RectangleWidth(const RECT& rectangle) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rectangle.right - rectangle.left));
}

int RectangleHeight(const RECT& rectangle) noexcept
{
    return static_cast<int>(std::max<LONG>(0, rectangle.bottom - rectangle.top));
}

COLORREF BlendColor(COLORREF from, COLORREF to, int numerator, int denominator) noexcept
{
    denominator = std::max(1, denominator);
    numerator = std::clamp(numerator, 0, denominator);
    const int red = GetRValue(from) +
        (GetRValue(to) - GetRValue(from)) * numerator / denominator;
    const int green = GetGValue(from) +
        (GetGValue(to) - GetGValue(from)) * numerator / denominator;
    const int blue = GetBValue(from) +
        (GetBValue(to) - GetBValue(from)) * numerator / denominator;
    return RGB(red, green, blue);
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

void FillVerticalGradient(HDC device, const RECT& rectangle, COLORREF top, COLORREF bottom)
{
    const int height = std::max(1, RectangleHeight(rectangle));
    constexpr int bands = 96;
    for (int band = 0; band < bands; ++band)
    {
        const int y0 = rectangle.top + height * band / bands;
        const int y1 = rectangle.top + height * (band + 1) / bands;
        RECT strip{rectangle.left, y0, rectangle.right, std::max(y0 + 1, y1)};
        FillSolid(device, strip, BlendColor(top, bottom, band, bands - 1));
    }
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

void DrawCircle(HDC device, const RECT& rectangle, COLORREF fill, COLORREF outline)
{
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, outline);
    const HGDIOBJ old_brush = SelectObject(device, brush);
    const HGDIOBJ old_pen = SelectObject(device, pen);
    Ellipse(device, rectangle.left, rectangle.top, rectangle.right, rectangle.bottom);
    SelectObject(device, old_pen);
    SelectObject(device, old_brush);
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

void ApplyRoundedWindowRegion(HWND window, int radius)
{
    if (window == nullptr || !IsWindow(window))
    {
        return;
    }
    RECT client{};
    if (!GetClientRect(window, &client) || RectangleWidth(client) <= 0 || RectangleHeight(client) <= 0)
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
    if (region != nullptr)
    {
        if (!SetWindowRgn(window, region, TRUE))
        {
            DeleteObject(region);
        }
    }
}

void ApplyDarkWindow(HWND window, bool rounded)
{
    if (window == nullptr)
    {
        return;
    }
    const BOOL dark_mode = TRUE;
    constexpr DWORD immersive_dark_mode_attribute = 20;
    (void)DwmSetWindowAttribute(
        window,
        immersive_dark_mode_attribute,
        &dark_mode,
        static_cast<DWORD>(sizeof(dark_mode)));

    if (rounded)
    {
        constexpr DWORD corner_preference_attribute = 33;
        const DWORD round_preference = 2;
        (void)DwmSetWindowAttribute(
            window,
            corner_preference_attribute,
            &round_preference,
            static_cast<DWORD>(sizeof(round_preference)));
    }
}

HICON WindowIcon(HWND window)
{
    DWORD_PTR icon_value = 0;
    if (window != nullptr)
    {
        (void)SendMessageTimeoutW(
            window,
            WM_GETICON,
            ICON_SMALL2,
            0,
            SMTO_ABORTIFHUNG,
            80,
            &icon_value);
    }
    HICON icon = reinterpret_cast<HICON>(icon_value);
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

        menu_bar_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
            kMenuBarClass,
            L"CloudOS Native Menu Bar",
            WS_POPUP,
            0,
            0,
            0,
            0,
            nullptr,
            nullptr,
            instance_,
            this);
        if (menu_bar_ == nullptr)
        {
            Shutdown();
            return false;
        }

        taskbar_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
            kDockClass,
            L"CloudOS Native Dock",
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
            L"CloudOS Launchpad",
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

        ApplyDarkWindow(menu_bar_, false);
        ApplyDarkWindow(taskbar_, true);
        ApplyDarkWindow(start_, true);

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
        ShowWindow(menu_bar_, SW_SHOWNOACTIVATE);
        ShowWindow(taskbar_, SW_SHOWNOACTIVATE);
        ShowWindow(start_, SW_HIDE);

        window_manager_.SetReservedBottomPixels(ReservedBottomPixels());
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
            {kMenuBarClass, &CloudOSShell::MenuBarProcedure, LoadCursorW(nullptr, IDC_ARROW)},
            {kDockClass, &CloudOSShell::TaskbarProcedure, LoadCursorW(nullptr, IDC_HAND)},
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

    int DockHeight() const noexcept
    {
        const UINT dpi = taskbar_ != nullptr ? GetDpiForWindow(taskbar_) : 96;
        return ScaleForDpi(kBaseDockHeight, dpi);
    }

    int MenuBarHeight() const noexcept
    {
        const UINT dpi = menu_bar_ != nullptr ? GetDpiForWindow(menu_bar_) : 96;
        return ScaleForDpi(kBaseMenuBarHeight, dpi);
    }

    int ReservedBottomPixels() const noexcept
    {
        const UINT dpi = taskbar_ != nullptr ? GetDpiForWindow(taskbar_) : 96;
        return DockHeight() + ScaleForDpi(kBaseShellMargin * 2, dpi);
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

        const int work_width = static_cast<int>(monitor.rcWork.right - monitor.rcWork.left);
        const int work_height = static_cast<int>(monitor.rcWork.bottom - monitor.rcWork.top);
        const UINT desktop_dpi = desktop_ != nullptr ? GetDpiForWindow(desktop_) : 96;
        const int margin = ScaleForDpi(kBaseShellMargin, desktop_dpi);
        const int dock_height = DockHeight();
        const int dock_width = std::min(
            std::max(ScaleForDpi(610, desktop_dpi), work_width - ScaleForDpi(520, desktop_dpi)),
            std::min(work_width - margin * 2, ScaleForDpi(kBaseDockWidth, desktop_dpi)));
        const int menu_height = MenuBarHeight();

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

        if (menu_bar_ != nullptr)
        {
            SetWindowPos(
                menu_bar_,
                HWND_TOPMOST,
                monitor.rcWork.left,
                monitor.rcWork.top,
                work_width,
                menu_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        if (taskbar_ != nullptr)
        {
            const int dock_left = monitor.rcWork.left + (work_width - dock_width) / 2;
            const int dock_top = monitor.rcWork.bottom - dock_height - margin;
            SetWindowPos(
                taskbar_,
                HWND_TOPMOST,
                dock_left,
                dock_top,
                dock_width,
                dock_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW);
            ApplyRoundedWindowRegion(taskbar_, ScaleForDpi(24, GetDpiForWindow(taskbar_)));
        }

        if (start_ != nullptr)
        {
            const UINT dpi = GetDpiForWindow(start_);
            const int start_width = std::min(ScaleForDpi(kBaseStartWidth, dpi), work_width - margin * 2);
            const int start_height = std::min(ScaleForDpi(kBaseStartHeight, dpi), work_height - menu_height - dock_height - margin * 4);
            const int start_left = monitor.rcWork.left + (work_width - start_width) / 2;
            const int start_top = monitor.rcWork.bottom - dock_height - margin * 2 - start_height;
            SetWindowPos(
                start_,
                HWND_TOPMOST,
                start_left,
                start_top,
                start_width,
                start_height,
                SWP_NOACTIVATE | (IsWindowVisible(start_) ? SWP_SHOWWINDOW : 0));
            ApplyRoundedWindowRegion(start_, ScaleForDpi(24, dpi));
        }

        window_manager_.SetReservedBottomPixels(ReservedBottomPixels());
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

        if (menu_bar_ != nullptr && IsWindow(menu_bar_))
        {
            DestroyWindow(menu_bar_);
        }
        menu_bar_ = nullptr;

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
        if (menu_bar_ != nullptr)
        {
            InvalidateRect(menu_bar_, nullptr, FALSE);
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
            InvalidateAll();
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
        InvalidateAll();
    }

    void HideStartMenu()
    {
        if (start_ != nullptr && IsWindowVisible(start_))
        {
            ShowWindow(start_, SW_HIDE);
            InvalidateRect(taskbar_, nullptr, FALSE);
            InvalidateRect(menu_bar_, nullptr, FALSE);
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

    void OpenDockShortcut(std::size_t index)
    {
        HideStartMenu();
        switch (index)
        {
        case 0:
            ToggleStartMenu();
            return;
        case 1:
            OpenTerminal();
            break;
        case 2:
            OpenWslTerminal();
            break;
        case 3:
            CloudOSNativeFilesWindow::Open(instance_);
            break;
        case 4:
            CloudOSNativeAppsWindow::Open(instance_);
            break;
        case 5:
            CloudOSNativeProcessWindow::Open(instance_);
            break;
        case 6:
            CloudOSNativeRunWindow::Open(instance_);
            break;
        default:
            return;
        }
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

    void OpenDesktopShortcut(std::size_t index)
    {
        switch (index)
        {
        case 0:
            CloudOSNativeFilesWindow::Open(instance_);
            break;
        case 1:
            OpenTerminal();
            break;
        case 2:
            CloudOSNativeAppsWindow::Open(instance_);
            break;
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

    std::wstring ActiveWindowTitle() const
    {
        const HWND active = window_manager_.ActiveManagedWindow();
        if (active == nullptr)
        {
            return L"Finder";
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
        FillVerticalGradient(device, client, kDesktopTop, kDesktopBottom);

        const UINT dpi = GetDpiForWindow(desktop_);

        // Subtle wallpaper depth: two large native GDI forms keep the desktop
        // visually alive without introducing a browser compositor or bitmap dependency.
        HBRUSH glow_a = CreateSolidBrush(kDesktopGlowA);
        HBRUSH glow_b = CreateSolidBrush(kDesktopGlowB);
        HPEN null_pen = CreatePen(PS_NULL, 0, 0);
        const HGDIOBJ old_pen = SelectObject(device, null_pen);
        const HGDIOBJ old_brush = SelectObject(device, glow_a);
        Ellipse(
            device,
            client.left - ScaleForDpi(260, dpi),
            client.top + ScaleForDpi(110, dpi),
            client.left + ScaleForDpi(650, dpi),
            client.top + ScaleForDpi(1020, dpi));
        SelectObject(device, glow_b);
        Ellipse(
            device,
            client.right - ScaleForDpi(720, dpi),
            client.bottom - ScaleForDpi(700, dpi),
            client.right + ScaleForDpi(180, dpi),
            client.bottom + ScaleForDpi(200, dpi));
        SelectObject(device, old_brush);
        SelectObject(device, old_pen);
        DeleteObject(null_pen);
        DeleteObject(glow_a);
        DeleteObject(glow_b);

        RECT brand{
            ScaleForDpi(30, dpi),
            client.bottom - ReservedBottomPixels() - ScaleForDpi(92, dpi),
            ScaleForDpi(500, dpi),
            client.bottom - ReservedBottomPixels() - ScaleForDpi(48, dpi),
        };
        DrawTextValue(device, L"CloudOS", brand, 31, FW_SEMIBOLD, RGB(221, 228, 244));
        RECT brand_subtitle{
            brand.left + ScaleForDpi(2, dpi),
            brand.bottom - ScaleForDpi(4, dpi),
            brand.right,
            brand.bottom + ScaleForDpi(28, dpi),
        };
        DrawTextValue(
            device,
            L"Native workspace  |  C++ / Win32 / ConPTY / WSL",
            brand_subtitle,
            10,
            FW_NORMAL,
            kSecondaryText);

        desktop_shortcut_rects_.fill(RECT{});
        const int icon_size = ScaleForDpi(56, dpi);
        const int cell_width = ScaleForDpi(118, dpi);
        const int cell_height = ScaleForDpi(104, dpi);
        const int right_margin = ScaleForDpi(26, dpi);
        int top = MenuBarHeight() + ScaleForDpi(28, dpi);

        for (std::size_t index = 0; index < kDesktopShortcuts.size(); ++index)
        {
            RECT cell{
                client.right - right_margin - cell_width,
                top,
                client.right - right_margin,
                top + cell_height,
            };
            desktop_shortcut_rects_[index] = cell;

            const bool selected = selected_desktop_shortcut_ == static_cast<int>(index);
            if (selected)
            {
                DrawPanel(device, cell, RGB(36, 43, 59), RGB(72, 86, 115), ScaleForDpi(12, dpi));
            }

            RECT icon{
                cell.left + (cell_width - icon_size) / 2,
                cell.top + ScaleForDpi(7, dpi),
                cell.left + (cell_width + icon_size) / 2,
                cell.top + ScaleForDpi(7, dpi) + icon_size,
            };
            DrawPanel(
                device,
                icon,
                index == 0 ? RGB(73, 111, 191) : (index == 1 ? RGB(45, 49, 62) : RGB(91, 76, 158)),
                selected ? kAccentSoft : kBorder,
                ScaleForDpi(14, dpi));
            DrawTextValue(
                device,
                kDesktopShortcuts[index].glyph,
                icon,
                index == 1 ? 13 : 18,
                FW_SEMIBOLD,
                kPrimaryText,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER);

            RECT label{cell.left, icon.bottom + ScaleForDpi(5, dpi), cell.right, cell.bottom};
            DrawTextValue(
                device,
                kDesktopShortcuts[index].label,
                label,
                9,
                selected ? FW_SEMIBOLD : FW_NORMAL,
                kPrimaryText,
                DT_SINGLELINE | DT_TOP | DT_CENTER | DT_END_ELLIPSIS);
            top += cell_height + ScaleForDpi(6, dpi);
        }

        EndPaint(desktop_, &paint);
    }

    void PaintMenuBar()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(menu_bar_, &paint);
        RECT client{};
        GetClientRect(menu_bar_, &client);
        FillSolid(device, client, RGB(17, 20, 28));

        const UINT dpi = GetDpiForWindow(menu_bar_);
        const int padding = ScaleForDpi(14, dpi);
        menu_cloudos_rect_ = RECT{padding, 0, padding + ScaleForDpi(92, dpi), client.bottom};
        DrawTextValue(
            device,
            L"CloudOS",
            menu_cloudos_rect_,
            10,
            FW_BOLD,
            kPrimaryText,
            DT_SINGLELINE | DT_VCENTER | DT_LEFT);

        int left = menu_cloudos_rect_.right + ScaleForDpi(4, dpi);
        const std::array<const wchar_t*, 5> menus{{L"Arquivo", L"Janelas", L"Ir", L"Aplicativos", L"Ajuda"}};
        const std::array<int, 5> widths{{58, 62, 34, 82, 48}};
        for (std::size_t index = 0; index < menus.size(); ++index)
        {
            RECT item{left, 0, left + ScaleForDpi(widths[index], dpi), client.bottom};
            DrawTextValue(device, menus[index], item, 9, FW_NORMAL, kSecondaryText, DT_SINGLELINE | DT_VCENTER | DT_LEFT);
            left = item.right + ScaleForDpi(8, dpi);
        }

        const std::wstring active_title = ActiveWindowTitle();
        RECT active{
            std::max(left + ScaleForDpi(12, dpi), client.right / 2 - ScaleForDpi(190, dpi)),
            0,
            std::min(client.right - ScaleForDpi(390, dpi), client.right / 2 + ScaleForDpi(190, dpi)),
            client.bottom,
        };
        if (active.right > active.left)
        {
            DrawTextValue(
                device,
                active_title,
                active,
                9,
                FW_SEMIBOLD,
                kPrimaryText,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_END_ELLIPSIS);
        }

        SYSTEMTIME local_time{};
        GetLocalTime(&local_time);
        wchar_t clock[64]{};
        swprintf_s(
            clock,
            L"W%d  |  %s  |  %02u:%02u  %02u/%02u",
            window_manager_.CurrentWorkspace() + 1,
            window_manager_.TilingEnabled() ? L"Tiling" : L"Floating",
            local_time.wHour,
            local_time.wMinute,
            local_time.wDay,
            local_time.wMonth);
        RECT status{
            std::max(client.left, client.right - ScaleForDpi(330, dpi)),
            0,
            client.right - padding,
            client.bottom,
        };
        DrawTextValue(
            device,
            clock,
            status,
            9,
            FW_SEMIBOLD,
            kPrimaryText,
            DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_END_ELLIPSIS);

        EndPaint(menu_bar_, &paint);
    }

    void PaintTaskbar()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(taskbar_, &paint);
        RECT client{};
        GetClientRect(taskbar_, &client);
        FillSolid(device, client, RGB(18, 21, 29));

        const UINT dpi = GetDpiForWindow(taskbar_);
        const int margin = ScaleForDpi(9, dpi);
        const int base_item = ScaleForDpi(52, dpi);
        const int gap = ScaleForDpi(6, dpi);
        const int hover_extra = ScaleForDpi(5, dpi);
        const int separator_width = ScaleForDpi(1, dpi);
        const int workspace_width = ScaleForDpi(31, dpi);

        dock_shortcut_rects_.fill(RECT{});
        workspace_rects_.fill(RECT{});
        task_hits_.clear();

        int left = margin;
        for (std::size_t index = 0; index < kDockGlyphs.size(); ++index)
        {
            const bool hovered = hovered_dock_shortcut_ == static_cast<int>(index);
            const int extra = hovered ? hover_extra : 0;
            RECT button{
                left - extra / 2,
                margin - extra,
                left + base_item + extra / 2,
                margin + base_item,
            };
            dock_shortcut_rects_[index] = button;
            const bool launcher_open = index == 0 && IsWindowVisible(start_);
            DrawPanel(
                device,
                button,
                launcher_open ? kPanelSelected : (hovered ? kPanelHover : kPanelBackground),
                launcher_open ? kAccent : (hovered ? kBorder : kBorderSoft),
                ScaleForDpi(14, dpi));

            RECT glyph = button;
            DrawTextValue(
                device,
                kDockGlyphs[index],
                glyph,
                index == 1 ? 11 : 15,
                FW_SEMIBOLD,
                index == 0 ? kAccentSoft : kPrimaryText,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER);

            if (hovered)
            {
                RECT label{
                    std::max(client.left, button.left - ScaleForDpi(34, dpi)),
                    client.top,
                    std::min(client.right, button.right + ScaleForDpi(34, dpi)),
                    button.top + ScaleForDpi(12, dpi),
                };
                DrawTextValue(device, kDockNames[index], label, 7, FW_SEMIBOLD, kSecondaryText, DT_SINGLELINE | DT_TOP | DT_CENTER);
            }
            left += base_item + gap;
        }

        left += gap;
        RECT separator{left, ScaleForDpi(16, dpi), left + separator_width, client.bottom - ScaleForDpi(16, dpi)};
        FillSolid(device, separator, kBorderSoft);
        left += gap * 2;

        const int right_reserved = margin + (workspace_width + gap) * 4 + ScaleForDpi(8, dpi);
        const int tasks_right = client.right - right_reserved;
        const auto windows = window_manager_.CurrentWorkspaceWindows();
        const std::size_t visible_count = std::min<std::size_t>(windows.size(), 5u);
        if (visible_count > 0 && tasks_right > left + ScaleForDpi(40, dpi))
        {
            const int available = tasks_right - left;
            const int item = std::clamp(
                available / static_cast<int>(visible_count),
                ScaleForDpi(46, dpi),
                ScaleForDpi(62, dpi));

            for (std::size_t index = 0; index < visible_count && left + item <= tasks_right + gap; ++index)
            {
                RECT button{left, margin, left + item - gap, margin + base_item};
                const bool active = windows[index].hwnd == window_manager_.ActiveManagedWindow();
                DrawPanel(
                    device,
                    button,
                    active ? kPanelSelected : kPanelBackgroundDeep,
                    active ? kAccent : kBorderSoft,
                    ScaleForDpi(13, dpi));

                HICON icon = WindowIcon(windows[index].hwnd);
                if (icon != nullptr)
                {
                    const int icon_size = ScaleForDpi(28, dpi);
                    const int x = button.left + (RectangleWidth(button) - icon_size) / 2;
                    const int y = button.top + ScaleForDpi(8, dpi);
                    DrawIconEx(device, x, y, icon, icon_size, icon_size, 0, nullptr, DI_NORMAL);
                }
                else
                {
                    RECT glyph = button;
                    glyph.bottom -= ScaleForDpi(8, dpi);
                    DrawTextValue(device, L"●", glyph, 13, FW_NORMAL, active ? kAccentSoft : kSecondaryText, DT_SINGLELINE | DT_VCENTER | DT_CENTER);
                }

                if (active)
                {
                    RECT dot{
                        button.left + RectangleWidth(button) / 2 - ScaleForDpi(2, dpi),
                        button.bottom - ScaleForDpi(6, dpi),
                        button.left + RectangleWidth(button) / 2 + ScaleForDpi(2, dpi),
                        button.bottom - ScaleForDpi(2, dpi),
                    };
                    DrawCircle(device, dot, kAccent, kAccent);
                }
                task_hits_.push_back({windows[index].hwnd, button});
                left += item;
            }
        }

        int workspace_left = client.right - margin - (workspace_width + gap) * 4 + gap;
        for (int workspace = 0; workspace < 4; ++workspace)
        {
            RECT rectangle{
                workspace_left,
                ScaleForDpi(20, dpi),
                workspace_left + workspace_width,
                client.bottom - ScaleForDpi(20, dpi),
            };
            workspace_rects_[static_cast<std::size_t>(workspace)] = rectangle;
            const bool current = workspace == window_manager_.CurrentWorkspace();
            DrawPanel(
                device,
                rectangle,
                current ? kAccent : kPanelBackgroundDeep,
                current ? kAccent : kBorderSoft,
                ScaleForDpi(10, dpi));
            const std::wstring label = std::to_wstring(workspace + 1);
            DrawTextValue(
                device,
                label,
                rectangle,
                8,
                FW_SEMIBOLD,
                current ? kPrimaryText : kSecondaryText,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER);
            workspace_left += workspace_width + gap;
        }

        EndPaint(taskbar_, &paint);
    }

    std::array<std::wstring, 8> StartLabels() const
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

    void PaintStart()
    {
        PAINTSTRUCT paint{};
        HDC device = BeginPaint(start_, &paint);
        RECT client{};
        GetClientRect(start_, &client);
        FillVerticalGradient(device, client, RGB(24, 28, 38), RGB(18, 20, 29));

        const UINT dpi = GetDpiForWindow(start_);
        RECT title{
            ScaleForDpi(26, dpi),
            ScaleForDpi(18, dpi),
            client.right - ScaleForDpi(24, dpi),
            ScaleForDpi(55, dpi),
        };
        DrawTextValue(device, L"Aplicativos", title, 21, FW_SEMIBOLD, kPrimaryText);

        RECT subtitle{
            title.left,
            title.bottom,
            title.right,
            title.bottom + ScaleForDpi(25, dpi),
        };
        DrawTextValue(
            device,
            L"CloudOS Native  •  sem runtime web no boot",
            subtitle,
            9,
            FW_NORMAL,
            kSecondaryText);

        const auto labels = StartLabels();
        const std::array<const wchar_t*, 8> glyphs{{L">_", L"K", L"A", L"F", L"P", L"R", L"T", L"⏻"}};
        const int outer = ScaleForDpi(24, dpi);
        const int gap = ScaleForDpi(12, dpi);
        const int columns = 2;
        const int available_width = client.right - outer * 2 - gap;
        const int tile_width = std::max(90, available_width / columns);
        const int tile_height = ScaleForDpi(72, dpi);
        const int first_top = subtitle.bottom + ScaleForDpi(20, dpi);
        start_item_rects_.fill(RECT{});

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
            start_item_rects_[index] = tile;
            const bool power = index == 7;
            DrawPanel(
                device,
                tile,
                kPanelBackground,
                power ? RGB(111, 62, 70) : kBorderSoft,
                ScaleForDpi(14, dpi));

            RECT icon{
                tile.left + ScaleForDpi(12, dpi),
                tile.top + ScaleForDpi(12, dpi),
                tile.left + ScaleForDpi(56, dpi),
                tile.bottom - ScaleForDpi(12, dpi),
            };
            DrawPanel(
                device,
                icon,
                power ? RGB(104, 48, 57) : RGB(38, 44, 59),
                power ? RGB(153, 82, 91) : kBorder,
                ScaleForDpi(11, dpi));
            DrawTextValue(
                device,
                glyphs[index],
                icon,
                index == 0 ? 10 : 13,
                FW_SEMIBOLD,
                power ? kDanger : kAccentSoft,
                DT_SINGLELINE | DT_VCENTER | DT_CENTER);

            RECT text{
                icon.right + ScaleForDpi(12, dpi),
                tile.top,
                tile.right - ScaleForDpi(10, dpi),
                tile.bottom,
            };
            DrawTextValue(
                device,
                labels[index],
                text,
                10,
                power ? FW_SEMIBOLD : FW_NORMAL,
                power ? kDanger : kPrimaryText);
        }

        EndPaint(start_, &paint);
    }

    void KeepShellZOrder()
    {
        if (desktop_ != nullptr)
        {
            SetWindowPos(
                desktop_,
                HWND_BOTTOM,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        if (menu_bar_ != nullptr)
        {
            SetWindowPos(
                menu_bar_,
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        if (taskbar_ != nullptr)
        {
            SetWindowPos(
                taskbar_,
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
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
                KeepShellZOrder();
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
            RepositionShellWindows();
            InvalidateAll();
            return 0;

        case WM_LBUTTONUP:
        {
            HideStartMenu();
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            selected_desktop_shortcut_ = -1;
            for (std::size_t index = 0; index < desktop_shortcut_rects_.size(); ++index)
            {
                if (PointInside(desktop_shortcut_rects_[index], point))
                {
                    selected_desktop_shortcut_ = static_cast<int>(index);
                    break;
                }
            }
            InvalidateRect(desktop_, nullptr, FALSE);
            SetWindowPos(
                desktop_,
                HWND_BOTTOM,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            return 0;
        }

        case WM_LBUTTONDBLCLK:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < desktop_shortcut_rects_.size(); ++index)
            {
                if (PointInside(desktop_shortcut_rects_[index], point))
                {
                    OpenDesktopShortcut(index);
                    return 0;
                }
            }
            return 0;
        }

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
            if (menu_bar_ != nullptr && IsWindow(menu_bar_))
            {
                DestroyWindow(menu_bar_);
                menu_bar_ = nullptr;
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

    LRESULT HandleMenuBarMessage(UINT message, WPARAM, LPARAM l_param)
    {
        switch (message)
        {
        case WM_PAINT:
            PaintMenuBar();
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_LBUTTONUP:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            if (PointInside(menu_cloudos_rect_, point))
            {
                ToggleStartMenu();
                return 0;
            }
            return 0;
        }

        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            RepositionShellWindows();
            InvalidateAll();
            return 0;

        case WM_DESTROY:
            menu_bar_ = nullptr;
            return 0;

        default:
            break;
        }
        return DefWindowProcW(menu_bar_, message, 0, l_param);
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

        case WM_MOUSEMOVE:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            int hovered = -1;
            for (std::size_t index = 0; index < dock_shortcut_rects_.size(); ++index)
            {
                if (PointInside(dock_shortcut_rects_[index], point))
                {
                    hovered = static_cast<int>(index);
                    break;
                }
            }
            if (hovered != hovered_dock_shortcut_)
            {
                hovered_dock_shortcut_ = hovered;
                InvalidateRect(taskbar_, nullptr, FALSE);
            }
            if (!tracking_dock_mouse_)
            {
                TRACKMOUSEEVENT tracking{};
                tracking.cbSize = sizeof(tracking);
                tracking.dwFlags = TME_LEAVE;
                tracking.hwndTrack = taskbar_;
                if (TrackMouseEvent(&tracking))
                {
                    tracking_dock_mouse_ = true;
                }
            }
            return 0;
        }

        case WM_MOUSELEAVE:
            tracking_dock_mouse_ = false;
            if (hovered_dock_shortcut_ != -1)
            {
                hovered_dock_shortcut_ = -1;
                InvalidateRect(taskbar_, nullptr, FALSE);
            }
            return 0;

        case WM_LBUTTONUP:
        {
            POINT point{GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param)};
            for (std::size_t index = 0; index < dock_shortcut_rects_.size(); ++index)
            {
                if (PointInside(dock_shortcut_rects_[index], point))
                {
                    OpenDockShortcut(index);
                    return 0;
                }
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
            if (reinterpret_cast<HWND>(w_param) != taskbar_ &&
                reinterpret_cast<HWND>(w_param) != menu_bar_)
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

    static LRESULT CALLBACK DesktopProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
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

    static LRESULT CALLBACK MenuBarProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
    {
        auto* shell = ResolveShell(window, message, l_param);
        if (shell != nullptr && shell->menu_bar_ == nullptr && message == WM_NCCREATE)
        {
            shell->menu_bar_ = window;
        }
        return shell != nullptr
            ? shell->HandleMenuBarMessage(message, w_param, l_param)
            : DefWindowProcW(window, message, w_param, l_param);
    }

    static LRESULT CALLBACK TaskbarProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
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

    static LRESULT CALLBACK StartProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
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
    HWND menu_bar_{};
    HWND taskbar_{};
    HWND start_{};
    bool shutting_down_{};
    bool tracking_dock_mouse_{};
    int hovered_dock_shortcut_{-1};
    int selected_desktop_shortcut_{-1};

    RECT menu_cloudos_rect_{};
    std::array<RECT, 3> desktop_shortcut_rects_{};
    std::array<RECT, 7> dock_shortcut_rects_{};
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
    common_controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_WIN95_CLASSES;
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
