#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>

#include <array>
#include <cstddef>
#include <vector>

#include "native_app_launcher.h"
#include "native_desktop_window.h"
#include "native_settings_window.h"
#include "native_theme.h"
#include "native_window_manager.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "gdiplus.lib")

namespace CloudOS
{
class CloudOSApplication final
{
public:
    explicit CloudOSApplication(HINSTANCE instance) noexcept
        : instance_(instance)
    {
    }

    ~CloudOSApplication()
    {
        Shutdown();
    }

    bool Initialize()
    {
        Gdiplus::GdiplusStartupInput gdi_input;
        if (Gdiplus::GdiplusStartup(&gdiplus_token_, &gdi_input, nullptr) != Gdiplus::Ok)
        {
            gdiplus_token_ = 0;
            return false;
        }

        if (!desktop_.Create(instance_, &window_manager_))
        {
            Shutdown();
            return false;
        }

        SetupCallbacks();
        Layout();

        const UINT dpi = GetDpiForWindow(desktop_.Hwnd());
        window_manager_.SetReservedBottomPixels(
            Scale(kBottomBarHeight, dpi) + Scale(8, dpi));
        if (!window_manager_.Initialize(desktop_.Hwnd()))
        {
            Shutdown();
            return false;
        }
        window_manager_initialized_ = true;

        const CloudOSNativeSettings settings =
            CloudOSNativeSettingsWindow::Load();
        if (settings.tiling_on_start &&
            !window_manager_.TilingEnabled())
        {
            window_manager_.ToggleTiling();
        }

        RegisterHotKeys();
        if (SetTimer(
                desktop_.Hwnd(),
                kReconcileTimer,
                1000,
                nullptr) != 0)
        {
            reconcile_timer_active_ = true;
        }
        if (SetTimer(
                desktop_.Hwnd(),
                kMetricsTimer,
                1000,
                nullptr) != 0)
        {
            metrics_timer_active_ = true;
        }

        desktop_.Redraw();
        return true;
    }

    int Run()
    {
        MSG message{};
        while (GetMessageW(
                   &message,
                   nullptr,
                   0,
                   0) > 0)
        {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return static_cast<int>(message.wParam);
    }

private:
    void SetupCallbacks()
    {
        desktop_.SetActionCallback(
            [this](int action_id)
            {
                if (action_id >= 1 &&
                    action_id <=
                        static_cast<int>(kAllApps.size()))
                {
                    NativeAppLauncher::Launch(
                        instance_,
                        desktop_.Hwnd(),
                        kAllApps[
                            static_cast<std::size_t>(
                                action_id - 1)]);
                    window_manager_.Reconcile();
                    desktop_.Redraw();
                }
            });

        desktop_.SetHotKeyCallback(
            [this](int hotkey_id)
            {
                HandleHotKey(hotkey_id);
            });

        desktop_.SetTimerCallback(
            [this]()
            {
                LayoutIfWorkAreaChanged();
                window_manager_.Reconcile();
            });
    }

    static bool SameRect(
        const RECT& first,
        const RECT& second) noexcept
    {
        return
            first.left == second.left &&
            first.top == second.top &&
            first.right == second.right &&
            first.bottom == second.bottom;
    }

    bool QueryWorkArea(RECT* work_area) const noexcept
    {
        if (work_area == nullptr)
        {
            return false;
        }
        *work_area = RECT{};
        return SystemParametersInfoW(
            SPI_GETWORKAREA,
            0,
            work_area,
            0) != FALSE;
    }

    void Layout()
    {
        RECT work_area{};
        if (!QueryWorkArea(&work_area))
        {
            return;
        }

        last_work_area_ = work_area;
        have_work_area_ = true;
        desktop_.UpdateLayout(work_area);

        if (desktop_.Hwnd() != nullptr)
        {
            const UINT dpi =
                GetDpiForWindow(desktop_.Hwnd());
            window_manager_.SetReservedBottomPixels(
                Scale(kBottomBarHeight, dpi) +
                Scale(8, dpi));
        }
    }

    void LayoutIfWorkAreaChanged()
    {
        RECT work_area{};
        if (!QueryWorkArea(&work_area))
        {
            return;
        }

        if (!have_work_area_ ||
            !SameRect(last_work_area_, work_area))
        {
            Layout();
        }
    }

    void HandleHotKey(int id)
    {
        if (id >= HotWorkspace1 &&
            id <= HotWorkspace4)
        {
            window_manager_.SwitchWorkspace(
                id - HotWorkspace1);
            desktop_.Redraw();
            return;
        }

        if (id >= HotMoveWorkspace1 &&
            id <= HotMoveWorkspace4)
        {
            window_manager_.MoveActiveToWorkspace(
                id - HotMoveWorkspace1);
            desktop_.Redraw();
            return;
        }

        switch (id)
        {
        case HotTerminal:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"terminal");
            break;
        case HotWslTerminal:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"wsl");
            break;
        case HotFiles:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"files");
            break;
        case HotApps:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"apps");
            break;
        case HotProcesses:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"sysmon");
            break;
        case HotRun:
            NativeAppLauncher::LaunchById(
                instance_,
                desktop_.Hwnd(),
                L"run");
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
            window_manager_.SnapActive(
                CloudOSSnapDirection::Left);
            break;
        case HotSnapRight:
            window_manager_.SnapActive(
                CloudOSSnapDirection::Right);
            break;
        case HotSnapUp:
            window_manager_.SnapActive(
                CloudOSSnapDirection::Up);
            break;
        case HotSnapDown:
            window_manager_.SnapActive(
                CloudOSSnapDirection::Down);
            break;
        case HotSearch:
            desktop_.FocusSearch();
            return;
        case HotExit:
            PostQuitMessage(0);
            return;
        default:
            return;
        }

        window_manager_.Reconcile();
        desktop_.Redraw();
    }

    void RegisterHotKeys()
    {
        const HWND window = desktop_.Hwnd();
        if (window == nullptr)
        {
            return;
        }

        const UINT modifiers =
            MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        const UINT move_modifiers =
            MOD_CONTROL |
            MOD_ALT |
            MOD_SHIFT |
            MOD_NOREPEAT;

        const struct Binding final
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
            {HotSearch, modifiers, VK_SPACE},
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
            if (RegisterHotKey(
                    window,
                    binding.id,
                    binding.modifiers,
                    binding.key))
            {
                registered_hotkeys_.push_back(
                    binding.id);
            }
        }
    }

    void UnregisterHotKeys() noexcept
    {
        const HWND window = desktop_.Hwnd();
        if (window != nullptr)
        {
            for (const int id : registered_hotkeys_)
            {
                (void)UnregisterHotKey(
                    window,
                    id);
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

        const HWND window = desktop_.Hwnd();
        if (window != nullptr)
        {
            if (reconcile_timer_active_)
            {
                (void)KillTimer(
                    window,
                    kReconcileTimer);
                reconcile_timer_active_ = false;
            }
            if (metrics_timer_active_)
            {
                (void)KillTimer(
                    window,
                    kMetricsTimer);
                metrics_timer_active_ = false;
            }
        }

        UnregisterHotKeys();
        if (window_manager_initialized_)
        {
            window_manager_.Shutdown();
            window_manager_initialized_ = false;
        }
        desktop_.Destroy();

        if (gdiplus_token_ != 0)
        {
            Gdiplus::GdiplusShutdown(
                gdiplus_token_);
            gdiplus_token_ = 0;
        }
    }

    HINSTANCE instance_{};
    ULONG_PTR gdiplus_token_{};
    CloudOSNativeWindowManager window_manager_;
    CloudOSNativeDesktopWindow desktop_;
    RECT last_work_area_{};
    bool have_work_area_{};
    bool window_manager_initialized_{};
    bool reconcile_timer_active_{};
    bool metrics_timer_active_{};
    bool shutting_down_{};
    std::vector<int> registered_hotkeys_;
};

} // namespace CloudOS

int WINAPI wWinMain(
    HINSTANCE instance,
    HINSTANCE,
    PWSTR,
    int)
{
    INITCOMMONCONTROLSEX common_controls{};
    common_controls.dwSize =
        sizeof(common_controls);
    common_controls.dwICC =
        ICC_LISTVIEW_CLASSES |
        ICC_WIN95_CLASSES;
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
        COINIT_APARTMENTTHREADED |
            COINIT_DISABLE_OLE1DDE);
    const bool uninitialize_com =
        SUCCEEDED(com_result);

    CloudOS::CloudOSApplication application(
        instance);
    if (!application.Initialize())
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

    const int exit_code = application.Run();
    if (uninitialize_com)
    {
        CoUninitialize();
    }
    return exit_code;
}
