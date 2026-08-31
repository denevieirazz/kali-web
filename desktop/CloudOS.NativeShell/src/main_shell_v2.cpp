#include "native_cloudos_tray.h"
#include "native_workspace_studio_service.h"
#include "native_session_continuity_service.h"
#include "native_performance_v12.h"
#include "native_appearance_manager.h"
#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>

#include <memory>
#include <vector>

#include "native_app_launcher.h"
#include "native_desktop_surface.h"
#include "native_health_bootstrap_v9.h"
#include "native_monitor_manager.h"
#include "native_notification_center.h"
#include "native_quick_settings_window.h"
#include "native_session_recovery.h"
#include "native_shell_bridge.h"
#include "native_snap_assist.h"
#include "native_start_menu_window.h"
#include "native_task_switcher_window.h"
#include "native_taskbar_appbar.h"
#include "native_taskbar_hover_preview.h"
#include "native_theme.h"
#include "native_watchdog.h"
#include "native_window_manager.h"
#include "native_workspace_overview_window.h"

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
constexpr int kHotWorkspaceOverview = 1009;
constexpr int kHotWorkspacePrevious = 1010;
constexpr int kHotWorkspaceNext = 1011;
constexpr int kHotMoveWorkspacePrevious = 1012;
constexpr int kHotMoveWorkspaceNext = 1013;
constexpr int kHotShowDesktop = 1014;
constexpr UINT_PTR kSessionLifecycleSubclass = 0xC501;

int WrappedWorkspace(int current, int direction) noexcept
{
    constexpr int kWorkspaceCount = 4;
    if (current < 0 || current >= kWorkspaceCount)
    {
        current = 0;
    }
    return (current + direction + kWorkspaceCount) % kWorkspaceCount;
}
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
        PerformanceV12::Initialize();
        (void)NativeAppearanceManager::Current();
        Gdiplus::GdiplusStartupInput gdi_input;
        if (Gdiplus::GdiplusStartup(&gdiplus_token_, &gdi_input, nullptr) != Gdiplus::Ok)
        {
            gdiplus_token_ = 0;
            return false;
        }

        (void)session_recovery_.BeginSession();

        if (!desktop_.Create(instance_, &window_manager_))
        {
            OutputDebugStringW(L"[CloudOS Init] desktop_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] desktop_.Create OK\n");

        lifecycle_subclass_attached_ = SetWindowSubclass(
            desktop_.Hwnd(),
            &CloudOSApplication::SessionLifecycleSubclass,
            kSessionLifecycleSubclass,
            reinterpret_cast<DWORD_PTR>(this)) != FALSE;

        SetupCallbacks();
        LayoutDesktop();

        // AppBars reserve the monitor work areas themselves. The old synthetic
        // bottom reservation must stay disabled in the window manager.
        window_manager_.SetReservedBottomPixels(0);
        if (!window_manager_.Initialize(desktop_.Hwnd()))
        {
            OutputDebugStringW(L"[CloudOS Init] window_manager_.Initialize failed\n");
            Shutdown();
            return false;
        }
        window_manager_initialized_ = true;
        OutputDebugStringW(L"[CloudOS Init] window_manager_.Initialize OK\n");

        if (!start_menu_.Create(instance_))
        {
            OutputDebugStringW(L"[CloudOS Init] start_menu_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] start_menu_.Create OK\n");

        if (!quick_settings_.Create(instance_))
        {
            OutputDebugStringW(L"[CloudOS Init] quick_settings_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] quick_settings_.Create OK\n");

        if (!notification_center_.Create(instance_))
        {
            OutputDebugStringW(L"[CloudOS Init] notification_center_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] notification_center_.Create OK\n");

        if (!task_switcher_.Create(instance_, &window_manager_))
        {
            OutputDebugStringW(L"[CloudOS Init] task_switcher_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] task_switcher_.Create OK\n");

        if (!workspace_overview_.Create(instance_, &window_manager_))
        {
            OutputDebugStringW(L"[CloudOS Init] workspace_overview_.Create failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] workspace_overview_.Create OK\n");

        SetupShellBridge();

        monitor_signature_ = NativeMonitorManager::Signature();
        if (!BuildTaskbars())
        {
            OutputDebugStringW(L"[CloudOS Init] BuildTaskbars failed\n");
            Shutdown();
            return false;
        }
        OutputDebugStringW(L"[CloudOS Init] BuildTaskbars OK\n");

        LayoutDesktop();
        RegisterHotKeys();

        snap_assist_active_ = snap_assist_.Start(instance_, &window_manager_);
        if (!snap_assist_active_)
        {
            CloudOSNativeNotificationCenter::Post(
                L"Snap Assist indisponivel",
                L"Os atalhos de snap continuam ativos, mas o detector de arrasto nao iniciou.");
        }

        const bool previous_unclean = session_recovery_.PreviousSessionUnclean();
        session_recovery_.Restore(instance_, desktop_.Hwnd(), window_manager_);
        if (previous_unclean)
        {
            CloudOSNativeNotificationCenter::Post(
                L"Sessao recuperada",
                L"O CloudOS detectou uma finalizacao inesperada e restaurou o ultimo estado salvo.");
        }

        if (SetTimer(desktop_.Hwnd(), kReconcileTimer, 30000, nullptr) != 0)
        {
            reconcile_timer_active_ = true;
        }
        CloudOSNativeNotificationCenter::Post(
            L"CloudOS pronto",
            L"Visao de Trabalho ativa: Ctrl+Alt+O abre as 4 areas; Ctrl+Alt+PgUp/PgDn alterna entre elas.");

        RefreshShell();

        // V12 boots to Desktop + Taskbar; Start is user initiated.

        return true;
    }

    int Run()
    {
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0)
        {
            if (quick_settings_.Translate(&message)) continue;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return static_cast<int>(message.wParam);
    }

private:
    static LRESULT CALLBACK SessionLifecycleSubclass(
        HWND window,
        UINT message,
        WPARAM w_param,
        LPARAM l_param,
        UINT_PTR subclass_id,
        DWORD_PTR reference_data)
    {
        auto* self = reinterpret_cast<CloudOSApplication*>(reference_data);
        if (self != nullptr)
        {
            if (message == WM_APP + 0x61B && self->performance_probe_v12_)
            {
                RECT anchor{}; GetWindowRect(window,&anchor); anchor.top=anchor.bottom-52;
                if(w_param==1) self->start_menu_.ShowNear(anchor);
                if(w_param==2) self->quick_settings_.ShowNear(anchor);
                if(w_param==3) { self->start_menu_.Hide(); self->quick_settings_.Hide(); }
                return 1;
            }
            if (message == CLOUDOS_WM_MODEL_CHANGED_V12)
            { if (!self->view_update_pending_) { self->view_update_pending_ = true; SetTimer(window, 0xC512, 50, nullptr); } self->recovery_dirty_ = true; return 0; }
            if (message == WM_TIMER && w_param == 0xC512)
            { KillTimer(window, 0xC512); self->view_update_pending_ = false; self->RefreshShell(); return 0; }
            if (message == WM_DISPLAYCHANGE || message == WM_DPICHANGED || message == WM_SETTINGCHANGE)
                PostMessageW(window, WM_APP + 0x616, 0, 0);
            if (message == WM_APP + 0x616)
            { self->RebuildForDisplayChangeIfNeeded(); self->LayoutDesktop(); return 0; }
            if (message == WM_QUERYENDSESSION)
            {
                self->window_manager_.Reconcile();
                self->session_recovery_.Save(self->window_manager_);
            }
            else if (message == WM_ENDSESSION && w_param != FALSE)
            {
                self->window_manager_.Reconcile();
                self->session_recovery_.MarkCleanExit(self->window_manager_);
            }
            else if (message == WM_POWERBROADCAST && w_param == PBT_APMSUSPEND)
            {
                self->window_manager_.Reconcile();
                self->session_recovery_.Save(self->window_manager_);
            }
            else if (message == WM_NCDESTROY)
            {
                RemoveWindowSubclass(
                    window,
                    &CloudOSApplication::SessionLifecycleSubclass,
                    subclass_id);
                self->lifecycle_subclass_attached_ = false;
            }
        }
        return DefSubclassProc(window, message, w_param, l_param);
    }

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
                if (recovery_dirty_) { session_recovery_.Tick(window_manager_); recovery_dirty_ = false; }
            });
    }

    void SetupShellBridge()
    {
        NativeShellBridge::SetWorkspaceOverviewCallback(
            [this]()
            {
                start_menu_.Hide();
                quick_settings_.Hide();
                notification_center_.Hide();
                workspace_overview_.Toggle(desktop_.Hwnd());
            });
        NativeShellBridge::SetShowDesktopCallback(
            [this]()
            {
                ToggleShowDesktopCurrentWorkspace();
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
                    workspace_overview_.Hide();
                    quick_settings_.Hide();
                    notification_center_.Hide();
                    start_menu_.ToggleNear(anchor);
                });
            taskbar->SetQuickSettingsCallback(
                [this](const RECT& anchor)
                {
                    workspace_overview_.Hide();
                    start_menu_.Hide();
                    notification_center_.Hide();
                    quick_settings_.ToggleNear(anchor);
                });
            taskbar->SetNotificationsCallback(
                [this](const RECT& anchor)
                {
                    workspace_overview_.Hide();
                    start_menu_.Hide();
                    quick_settings_.Hide();
                    notification_center_.ToggleNear(anchor);
                    RefreshTaskbars();
                });

            // Hover previews are attached as a subclass to the actual AppBar.
            // Their lifetime is tied to the taskbar HWND and they unregister all
            // DWM thumbnail relationships during WM_NCDESTROY.
            (void)NativeTaskbarHoverPreview::Attach(
                instance_,
                taskbar->Hwnd(),
                monitor.handle,
                &window_manager_);

            taskbars_.push_back(std::move(taskbar));
        }

        NativeCloudOSTrayService::Instance().Refresh();
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

        session_recovery_.Save(window_manager_);
        workspace_overview_.Hide();
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
            L"A topologia de telas mudou e as AppBars/previews foram reconstruidas.");
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
        PerformanceV12::Add(PerformanceV12::RefreshShell);
        NativeWorkspaceStudioService::Instance().NotifyModelChangedV12();
        NativeSessionContinuityService::Instance().NotifyModelChangedV12();
        recovery_dirty_ = true;
        RefreshTaskbars();
        notification_center_.Refresh();
        if (workspace_overview_.Visible())
        {
            workspace_overview_.Refresh();
        }
    }

    void SwitchWorkspaceRelative(int direction)
    {
        if (direction == 0)
        {
            return;
        }
        window_manager_.SwitchWorkspace(
            WrappedWorkspace(window_manager_.CurrentWorkspace(), direction));
    }

    void MoveActiveToRelativeWorkspace(int direction, bool follow)
    {
        if (direction == 0 || window_manager_.ActiveManagedWindow() == nullptr)
        {
            return;
        }
        const int target = WrappedWorkspace(window_manager_.CurrentWorkspace(), direction);
        window_manager_.MoveActiveToWorkspace(target);
        if (follow)
        {
            window_manager_.SwitchWorkspace(target);
        }
    }

    void ToggleShowDesktopCurrentWorkspace()
    {
        const auto windows = window_manager_.CurrentWorkspaceWindows();
        bool has_visible = false;
        for (const CloudOSManagedWindow& item : windows)
        {
            if (item.hwnd != nullptr && IsWindow(item.hwnd) &&
                IsWindowVisible(item.hwnd) && !IsIconic(item.hwnd))
            {
                has_visible = true;
                break;
            }
        }

        for (const CloudOSManagedWindow& item : windows)
        {
            if (item.hwnd == nullptr || !IsWindow(item.hwnd))
            {
                continue;
            }
            if (has_visible)
            {
                if (IsWindowVisible(item.hwnd) && !IsIconic(item.hwnd))
                {
                    ShowWindow(item.hwnd, SW_MINIMIZE);
                }
            }
            else if (IsIconic(item.hwnd))
            {
                ShowWindow(item.hwnd, SW_RESTORE);
            }
        }

        window_manager_.Reconcile();
        session_recovery_.Save(window_manager_);
        RefreshShell();
    }

    void HandleHotKey(int id)
    {
        if(performance_probe_v12_) return;
        if (id >= HotWorkspace1 && id <= HotWorkspace4)
        {
            window_manager_.SwitchWorkspace(id - HotWorkspace1);
            session_recovery_.Save(window_manager_);
            RefreshShell();
            return;
        }
        if (id >= HotMoveWorkspace1 && id <= HotMoveWorkspace4)
        {
            window_manager_.MoveActiveToWorkspace(id - HotMoveWorkspace1);
            session_recovery_.Save(window_manager_);
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
            workspace_overview_.Hide();
            start_menu_.ShowNear(PrimaryTaskbarBounds());
            return;
        case HotExit:
            PostQuitMessage(0);
            return;
        case kHotTaskSwitcher:
            workspace_overview_.Hide();
            task_switcher_.ShowCycle(false);
            return;
        case kHotTaskSwitcherReverse:
            workspace_overview_.Hide();
            task_switcher_.ShowCycle(true);
            return;
        case kHotQuickSettings:
            workspace_overview_.Hide();
            quick_settings_.ToggleNear(PrimaryTaskbarBounds());
            return;
        case kHotNotifications:
            workspace_overview_.Hide();
            notification_center_.ToggleNear(PrimaryTaskbarBounds());
            return;
        case kHotWorkspaceOverview:
            workspace_overview_.Toggle(desktop_.Hwnd());
            return;
        case kHotWorkspacePrevious:
            SwitchWorkspaceRelative(-1);
            break;
        case kHotWorkspaceNext:
            SwitchWorkspaceRelative(1);
            break;
        case kHotMoveWorkspacePrevious:
            MoveActiveToRelativeWorkspace(-1, true);
            break;
        case kHotMoveWorkspaceNext:
            MoveActiveToRelativeWorkspace(1, true);
            break;
        case kHotShowDesktop:
            ToggleShowDesktopCurrentWorkspace();
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
        session_recovery_.Save(window_manager_);
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
            {kHotWorkspaceOverview, modifiers, L'O'},
            {kHotWorkspacePrevious, modifiers, VK_PRIOR},
            {kHotWorkspaceNext, modifiers, VK_NEXT},
            {kHotMoveWorkspacePrevious, move_modifiers, VK_PRIOR},
            {kHotMoveWorkspaceNext, move_modifiers, VK_NEXT},
            {kHotShowDesktop, modifiers, L'D'},
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

        NativeShellBridge::Clear();

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

        if (window_manager_initialized_)
        {
            window_manager_.Reconcile();
        }
        session_recovery_.MarkCleanExit(window_manager_);

        if (snap_assist_active_)
        {
            snap_assist_.Stop();
            snap_assist_active_ = false;
        }

        UnregisterHotKeys();
        workspace_overview_.Destroy();
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

        if (lifecycle_subclass_attached_ && window != nullptr && IsWindow(window))
        {
            RemoveWindowSubclass(
                window,
                &CloudOSApplication::SessionLifecycleSubclass,
                kSessionLifecycleSubclass);
            lifecycle_subclass_attached_ = false;
        }

        desktop_.Destroy();
        if (gdiplus_token_ != 0)
        {
            Gdiplus::GdiplusShutdown(gdiplus_token_);
            gdiplus_token_ = 0;
        }
    }

    bool performance_probe_v12_{HealthBootstrapV9::HasCommandLineArgument(L"--stability-probe")};
    bool recovery_dirty_{true};
    bool view_update_pending_{};
    HINSTANCE instance_{};
    ULONG_PTR gdiplus_token_{};
    CloudOSNativeWindowManager window_manager_;
    CloudOSDesktopSurface desktop_;
    CloudOSNativeStartMenuWindow start_menu_;
    CloudOSNativeQuickSettingsWindow quick_settings_;
    CloudOSNativeNotificationCenter notification_center_;
    CloudOSNativeTaskSwitcherWindow task_switcher_;
    CloudOSNativeWorkspaceOverviewWindow workspace_overview_;
    NativeSnapAssist snap_assist_;
    NativeSessionRecovery session_recovery_;
    std::vector<std::unique_ptr<CloudOSTaskbarAppBar>> taskbars_;
    std::wstring monitor_signature_;
    bool window_manager_initialized_{};
    bool reconcile_timer_active_{};
    bool metrics_timer_active_{};
    bool lifecycle_subclass_attached_{};
    bool snap_assist_active_{};
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
    if (CloudOS::NativeWatchdog::IsWatchdogInvocation())
    {
        return CloudOS::NativeWatchdog::RunWatchdogInvocation();
    }

    HANDLE session_mutex = CloudOS::NativeWatchdog::AcquireSessionMutex();
    if (session_mutex == nullptr)
    {
        return 0;
    }

    INITCOMMONCONTROLSEX common_controls{};
    common_controls.dwSize = sizeof(common_controls);
    common_controls.dwICC =
        ICC_LISTVIEW_CLASSES |
        ICC_BAR_CLASSES |
        ICC_PROGRESS_CLASS |
        ICC_WIN95_CLASSES;
    if (!InitCommonControlsEx(&common_controls))
    {
        common_controls.dwICC = ICC_WIN95_CLASSES;
        if (!InitCommonControlsEx(&common_controls))
        {
            InitCommonControls();
        }
    }

    const HRESULT com_result = OleInitialize(nullptr);
    const bool uninitialize_com = SUCCEEDED(com_result);

    int exit_code = 1;
    {
        CloudOS::CloudOSApplication application(instance);
        if (!application.Initialize())
        {
            MessageBoxW(
                nullptr,
                L"O CloudOS Native nao conseguiu inicializar o shell multi-HWND.",
                L"CloudOS Native",
                MB_OK | MB_ICONERROR);
        }
        else
        {
            CloudOS::HealthBootstrapV9::bootstrap.AttachAfterInitialization();
            (void)CloudOS::NativeWatchdog::StartForCurrentProcess();
            exit_code = application.Run();
        }
    }

    if (uninitialize_com)
    {
        OleUninitialize();
    }
    CloudOS::NativeWatchdog::ReleaseSessionMutex(session_mutex);
    return exit_code;
}
