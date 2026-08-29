#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>

#include <memory>
#include <vector>

#include "native_app_launcher.h"
#include "native_desktop_surface.h"
#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_quick_settings_window.h"
#include "native_start_menu_window.h"
#include "native_task_switcher_window.h"
#include "native_taskbar_appbar.h"
#include "native_theme.h"
#include "native_window_manager.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "gdiplus.lib")

namespace CloudOS
{
namespace
{
constexpr int kHotTaskSwitcher = 1001;
constexpr int kHotTaskSwitcherReverse = 1002;
constexpr int kHotQuickSettings = 1003;
constexpr int kHotNotifications = 1004;
constexpr int kHotMonitorLeft = 1005;
constexpr int kHotMonitorRight = 1006;
constexpr int kHotMonitorLeftFallback = 1007;
constexpr int kHotMonitorRightFallback = 1008;
}

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
        LayoutDesktop();

        // AppBars reserve the monitor work areas themselves. The old synthetic
        // bottom reservation must stay disabled in the window manager.
        window_manager_.SetReservedBottomPixels(0);
        if (!window_manager_.Initialize(desktop_.Hwnd()))
        {
            Shutdown();
            return false;
        }
        window_manager_initialized_ = true;

        if (!start_menu_.Create(instance_) ||
            !quick_settings_.Create(instance_) ||
            !notification_center_.Create(instance_) ||
            !task_switcher_.Create(instance_, &window_manager_))
        {
            Shutdown();
            return false;
        }

        monitor_signature_ = NativeMonitorManager::Signature();
        if (!BuildTaskbars())
        {
            Shutdown();
            return false;
        }

        LayoutDesktop();
        RegisterHotKeys();

        if (SetTimer(desktop_.Hwnd(), kReconcileTimer, 1000, nullptr) != 0)
        {
            reconcile_timer_active_ = true;
        }
        if (SetTimer(desktop_.Hwnd(), kMetricsTimer, 1000, nullptr) != 0)
        {
            metrics_timer_active_ = true;
        }

        CloudOSNativeNotificationCenter::Post(
            L"CloudOS pronto",
            L"Taskbar AppBar, Start independente, Alt+Tab DWM, drag-and-drop e configuracoes rapidas carregados.");

        RefreshShell();
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
    void SetupCallbacks()
    {
        desktop_.SetActionCallback(
            [this](int action_id)
            {
                if (action_id >= 1 && action_id <= static_cast<int>(kAllApps.size()))
                {
                    NativeAppLauncher::Launch(
                        instance_,
                        desktop_.Hwnd(),
                        kAllApps[static_cast<std::size_t>(action_id - 1)]);
                    window_manager_.Reconcile();
                    RefreshShell();
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
                window_manager_.Reconcile();
                RebuildForDisplayChangeIfNeeded();
                RefreshShell();
            });
    }

    bool BuildTaskbars()
    {
        taskbars_.clear();
        const auto monitors = NativeMonitorManager::Enumerate();
        if (monitors.empty())
        {
            return false;
        }

        for (const auto& monitor : monitors)
        {
            auto taskbar = std::make_unique<CloudOSTaskbarAppBar>();
            if (!taskbar->Create(instance_, &window_manager_, monitor.handle, monitor.primary))
            {
                continue;
            }

            taskbar->SetStartCallback(
                [this](const RECT& anchor)
                {
                    quick_settings_.Hide();
                    notification_center_.Hide();
                    start_menu_.ToggleNear(anchor);
                });
            taskbar->SetQuickSettingsCallback(
                [this](const RECT& anchor)
                {
                    start_menu_.Hide();
                    notification_center_.Hide();
                    quick_settings_.ToggleNear(anchor);
                });
            taskbar->SetNotificationsCallback(
                [this](const RECT& anchor)
                {
                    start_menu_.Hide();
                    quick_settings_.Hide();
                    notification_center_.ToggleNear(anchor);
                    RefreshTaskbars();
                });

            taskbars_.push_back(std::move(taskbar));
        }

        return !taskbars_.empty();
    }

    RECT PrimaryTaskbarBounds() const noexcept
    {
        const HMONITOR primary = NativeMonitorManager::PrimaryMonitor();
        for (const auto& taskbar : taskbars_)
        {
            if (taskbar != nullptr && taskbar->Monitor() == primary)
            {
                return taskbar->Bounds();
            }
        }
        if (!taskbars_.empty() && taskbars_.front() != nullptr)
        {
            return taskbars_.front()->Bounds();
        }
        RECT fallback{};
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
        fallback.top = fallback.bottom;
        return fallback;
    }

    void LayoutDesktop()
    {
        desktop_.UpdateLayout(NativeMonitorManager::VirtualBounds());
    }

    void RebuildForDisplayChangeIfNeeded()
    {
        const std::wstring signature = NativeMonitorManager::Signature();
        if (signature == monitor_signature_)
        {
            return;
        }

        start_menu_.Hide();
        quick_settings_.Hide();
        notification_center_.Hide();
        task_switcher_.Hide();
        taskbars_.clear();
        monitor_signature_ = signature;
        (void)BuildTaskbars();
        LayoutDesktop();
        CloudOSNativeNotificationCenter::Post(
            L"Monitores atualizados",
            L"A topologia de telas mudou e as AppBars foram reconstruidas.");
    }

    void RefreshTaskbars()
    {
        for (const auto& taskbar : taskbars_)
        {
            if (taskbar != nullptr)
            {
                taskbar->Refresh();
            }
        }
    }

    void RefreshShell()
    {
        desktop_.Redraw();
        RefreshTaskbars();
        notification_center_.Refresh();
    }

    void HandleHotKey(int id)
    {
        if (id >= HotWorkspace1 && id <= HotWorkspace4)
        {
            window_manager_.SwitchWorkspace(id - HotWorkspace1);
            RefreshShell();
            return;
        }
        if (id >= HotMoveWorkspace1 && id <= HotMoveWorkspace4)
        {
            window_manager_.MoveActiveToWorkspace(id - HotMoveWorkspace1);
            RefreshShell();
            return;
        }

        switch (id)
        {
        case HotTerminal:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"terminal");
            break;
        case HotWslTerminal:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"wsl");
            break;
        case HotFiles:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"files");
            break;
        case HotApps:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"apps");
            break;
        case HotProcesses:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"sysmon");
            break;
        case HotRun:
            NativeAppLauncher::LaunchById(instance_, desktop_.Hwnd(), L"run");
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
        case HotSearch:
            start_menu_.ShowNear(PrimaryTaskbarBounds());
            return;
        case HotExit:
            PostQuitMessage(0);
            return;
        case kHotTaskSwitcher:
            task_switcher_.ShowCycle(false);
            return;
        case kHotTaskSwitcherReverse:
            task_switcher_.ShowCycle(true);
            return;
        case kHotQuickSettings:
            quick_settings_.ToggleNear(PrimaryTaskbarBounds());
            return;
        case kHotNotifications:
            notification_center_.ToggleNear(PrimaryTaskbarBounds());
            return;
        case kHotMonitorLeft:
        case kHotMonitorLeftFallback:
            (void)NativeMonitorManager::MoveWindowToAdjacentMonitor(
                window_manager_.ActiveManagedWindow(),
                -1);
            break;
        case kHotMonitorRight:
        case kHotMonitorRightFallback:
            (void)NativeMonitorManager::MoveWindowToAdjacentMonitor(
                window_manager_.ActiveManagedWindow(),
                1);
            break;
        default:
            return;
        }

        window_manager_.Reconcile();
        RefreshShell();
    }

    bool RegisterOne(int id, UINT modifiers, UINT key)
    {
        const HWND window = desktop_.Hwnd();
        if (window == nullptr)
        {
            return false;
        }
        if (!RegisterHotKey(window, id, modifiers, key))
        {
            return false;
        }
        registered_hotkeys_.push_back(id);
        return true;
    }

    void RegisterHotKeys()
    {
        const UINT modifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        const UINT move_modifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;

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
            {kHotQuickSettings, modifiers, L'V'},
            {kHotNotifications, modifiers, L'N'},
            {kHotMonitorLeftFallback, move_modifiers, VK_LEFT},
            {kHotMonitorRightFallback, move_modifiers, VK_RIGHT},
        };

        registered_hotkeys_.clear();
        for (const auto& binding : bindings)
        {
            (void)RegisterOne(binding.id, binding.modifiers, binding.key);
        }

        // Windows may reserve Alt+Tab and Win+Shift+Arrow. CloudOS attempts the
        // canonical bindings, but keeps explicit Ctrl+Alt fallbacks above.
        if (!RegisterOne(kHotTaskSwitcher, MOD_ALT | MOD_NOREPEAT, VK_TAB))
        {
            (void)RegisterOne(kHotTaskSwitcher, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_TAB);
        }
        (void)RegisterOne(kHotTaskSwitcherReverse, MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, VK_TAB);
        (void)RegisterOne(kHotMonitorLeft, MOD_WIN | MOD_SHIFT | MOD_NOREPEAT, VK_LEFT);
        (void)RegisterOne(kHotMonitorRight, MOD_WIN | MOD_SHIFT | MOD_NOREPEAT, VK_RIGHT);
    }

    void UnregisterHotKeys() noexcept
    {
        const HWND window = desktop_.Hwnd();
        if (window != nullptr)
        {
            for (const int id : registered_hotkeys_)
            {
                (void)UnregisterHotKey(window, id);
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
                (void)KillTimer(window, kReconcileTimer);
                reconcile_timer_active_ = false;
            }
            if (metrics_timer_active_)
            {
                (void)KillTimer(window, kMetricsTimer);
                metrics_timer_active_ = false;
            }
        }

        UnregisterHotKeys();
        task_switcher_.Destroy();
        notification_center_.Destroy();
        quick_settings_.Destroy();
        start_menu_.Destroy();
        taskbars_.clear();

        if (window_manager_initialized_)
        {
            window_manager_.Shutdown();
            window_manager_initialized_ = false;
        }

        desktop_.Destroy();
        if (gdiplus_token_ != 0)
        {
            Gdiplus::GdiplusShutdown(gdiplus_token_);
            gdiplus_token_ = 0;
        }
    }

    HINSTANCE instance_{};
    ULONG_PTR gdiplus_token_{};
    CloudOSNativeWindowManager window_manager_;
    CloudOSDesktopSurface desktop_;
    CloudOSNativeStartMenuWindow start_menu_;
    CloudOSNativeQuickSettingsWindow quick_settings_;
    CloudOSNativeNotificationCenter notification_center_;
    CloudOSNativeTaskSwitcherWindow task_switcher_;
    std::vector<std::unique_ptr<CloudOSTaskbarAppBar>> taskbars_;
    std::wstring monitor_signature_;
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
    common_controls.dwSize = sizeof(common_controls);
    common_controls.dwICC =
        ICC_LISTVIEW_CLASSES |
        ICC_BAR_CLASSES |
        ICC_STANDARD_CLASSES |
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

    const HRESULT com_result = OleInitialize(nullptr);
    const bool uninitialize_com = SUCCEEDED(com_result);

    CloudOS::CloudOSApplication application(instance);
    if (!application.Initialize())
    {
        if (uninitialize_com)
        {
            OleUninitialize();
        }
        MessageBoxW(
            nullptr,
            L"O CloudOS Native nao conseguiu inicializar o shell multi-HWND.",
            L"CloudOS Native",
            MB_OK | MB_ICONERROR);
        return 1;
    }

    const int exit_code = application.Run();
    if (uninitialize_com)
    {
        OleUninitialize();
    }
    return exit_code;
}
