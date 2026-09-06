import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../features/browser/presentation/browser_window.dart';
import '../features/files/presentation/files_window.dart';
import '../features/notifications/presentation/notification_center_panel.dart';
import '../features/quick_settings/domain/quick_settings_route.dart';
import '../features/quick_settings/presentation/quick_settings_panel.dart';
import '../features/settings/presentation/settings_window.dart';
import '../features/start/domain/start_running_app.dart';
import '../features/start/presentation/start_panel.dart';
import '../features/taskbar/presentation/cloud_taskbar.dart';
import '../features/terminal/domain/terminal_launch_coordinator.dart';
import '../features/terminal/presentation/terminal_window.dart';
import '../features/calculator/presentation/calculator_window.dart';
import '../features/notes/presentation/notes_window.dart';
import '../features/spotlight/domain/spotlight_item.dart';
import '../features/spotlight/presentation/spotlight_palette.dart';
import '../features/task_manager/presentation/task_manager_window.dart';
import '../models/cloud_app.dart';
import '../models/cloud_notification.dart';
import '../models/cloud_system_snapshot.dart';
import '../core/responsive/cloud_layout_metrics.dart';
import '../core/responsive/cloud_responsive_layout.dart';
import '../services/cloudos_bridge.dart';
import '../widgets/glass_surface.dart';
import 'shell_app_route.dart';
import 'widgets/desktop_icons.dart';
import 'widgets/desktop_status.dart';
import 'widgets/desktop_wallpaper.dart';
import '../features/first_run/presentation/first_run_dialog.dart';
import '../services/cloudos_preferences.dart';
import 'window_manager/alt_tab_switcher.dart';
import 'window_manager/cloud_window_frame.dart';

class CloudOSShell extends StatefulWidget {
  const CloudOSShell({super.key, CloudOSBridge? bridge})
      : bridge = bridge ?? const _DefaultBridge();

  final CloudOSBridge bridge;

  @override
  State<CloudOSShell> createState() => _CloudOSShellState();
}

class _DefaultBridge extends CloudOSBridge {
  const _DefaultBridge();
}

enum WindowSnapMode { none, maximized, left, right }

class _CloudOSShellState extends State<CloudOSShell> {
  List<CloudApp> apps = const <CloudApp>[];
  CloudSystemSnapshot snapshot = CloudOSBridge.degradedSnapshot;
  CloudNotificationState notificationState = CloudNotificationState.empty;
  PerformanceProfileInfo performanceProfile = PerformanceProfileInfo.defaultBalanced;
  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool spotlightOpen = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  late List<DesktopItemData> desktopItems = getDefaultDesktopItems();
  int _customFolderCounter = 1;
  CloudOSPreferences? _preferences;

  // Responsive & Window Snap Tracking
  final Map<String, WindowSnapMode> _windowSnapModes = <String, WindowSnapMode>{};
  StreamSubscription<DisplayChangeEvent>? _displaySub;
  Size? _lastLayoutSize;

  // Window Manager States
  bool filesOpen = true;
  bool filesMinimized = false;
  bool filesMaximized = false;
  Offset filesOffset = const Offset(120, 50);
  Size filesSize = const Size(960, 600);
  Offset? filesPreMaxOffset;
  Size? filesPreMaxSize;
  int filesZIndex = 1;
  String filesRootId = 'home';
  int filesLaunchRevision = 0;

  bool terminalOpen = const bool.fromEnvironment('CLOUDOS_E2E_TERMINAL');
  bool terminalMinimized = false;
  bool terminalMaximized = false;
  Offset terminalOffset = const Offset(180, 80);
  Size terminalSize = const Size(780, 480);
  Offset? terminalPreMaxOffset;
  Size? terminalPreMaxSize;
  int terminalZIndex = 2;

  bool browserOpen = const bool.fromEnvironment('CLOUDOS_E2E_BROWSER');
  bool browserMinimized = false;
  bool browserMaximized = false;
  Offset browserOffset = const Offset(150, 70);
  Size browserSize = const Size(880, 540);
  Offset? browserPreMaxOffset;
  Size? browserPreMaxSize;
  int browserZIndex = 3;

  bool settingsOpen = false;
  bool settingsMinimized = false;
  bool settingsMaximized = false;
  Offset settingsOffset = const Offset(210, 90);
  Size settingsSize = const Size(760, 500);
  Offset? settingsPreMaxOffset;
  Size? settingsPreMaxSize;
  int settingsZIndex = 4;
  SettingsSection settingsSection = SettingsSection.overview;

  bool notesOpen = false;
  bool notesMinimized = false;
  bool notesMaximized = false;
  Offset notesOffset = const Offset(240, 110);
  Size notesSize = const Size(780, 520);
  Offset? notesPreMaxOffset;
  Size? notesPreMaxSize;
  int notesZIndex = 5;

  bool calculatorOpen = false;
  bool calculatorMinimized = false;
  bool calculatorMaximized = false;
  Offset calculatorOffset = const Offset(280, 130);
  Size calculatorSize = const Size(540, 480);
  Offset? calculatorPreMaxOffset;
  Size? calculatorPreMaxSize;
  int calculatorZIndex = 6;

  bool taskManagerOpen = false;
  bool taskManagerMinimized = false;
  bool taskManagerMaximized = false;
  Offset taskManagerOffset = const Offset(200, 100);
  Size taskManagerSize = const Size(720, 480);
  Offset? taskManagerPreMaxOffset;
  Size? taskManagerPreMaxSize;
  int taskManagerZIndex = 7;

  int topZIndex = 8;
  String? activeInternalWindowId = 'files';

  bool altTabOpen = false;
  int altTabSelectedIndex = 0;

  bool _shellStateRefreshInFlight = false;
  CloudWindowSnapshot windowSnapshot = CloudWindowSnapshot.empty;
  Timer? _windowSnapshotTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBridgeData());
    _windowSnapshotTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) unawaited(_refreshWindowSnapshot());
    });
    _displaySub = widget.bridge.onDisplayChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _windowSnapshotTimer?.cancel();
    _displaySub?.cancel();
    super.dispose();
  }

  Future<void> _refreshWindowSnapshot() async {
    try {
      final snap = await widget.bridge.tryLoadWindowSnapshot();
      if (snap != null && mounted) {
        final changed = snap.sequence != windowSnapshot.sequence ||
            snap.windows.length != windowSnapshot.windows.length ||
            snap.windows.any((w) {
              final prev = windowSnapshot.windows.firstWhere(
                (p) => p.hwnd == w.hwnd,
                orElse: () => w,
              );
              return prev.isFocused != w.isFocused ||
                  prev.isMinimized != w.isMinimized ||
                  prev.isMaximized != w.isMaximized ||
                  prev.title != w.title;
            });
        if (changed) {
          setState(() {
            windowSnapshot = snap;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadBridgeData() async {
    final loadedApps = await widget.bridge.tryLoadApps();
    final loadedSnapshot = await widget.bridge.tryLoadSystemSnapshot();
    final loadedNotifications = await widget.bridge.tryLoadNotificationState();
    final surfaceStates = await widget.bridge.tryLoadShellSurfaceStates();
    final nativeWorkspace = await widget.bridge.getCurrentWorkspace();
    final loadedPerf = await widget.bridge.tryLoadPerformanceProfile();
    final loadedWindowSnapshot = await widget.bridge.tryLoadWindowSnapshot();
    final prefs = await CloudOSPreferences.load();
    if (!mounted) return;

    _preferences = prefs;

    // Apply saved icon positions if present
    var initialDesktopItems = getDefaultDesktopItems();
    if (prefs.desktopIconPositions.isNotEmpty) {
      initialDesktopItems = initialDesktopItems.map((item) {
        final savedPos = prefs.getIconPosition(item.id);
        if (savedPos != null) {
          return item.copyWith(position: savedPos);
        }
        return item;
      }).toList();
    }

    if (loadedPerf != null) {
      GlassSurface.disableBlur = loadedPerf.isEconomy;
    }

    setState(() {
      desktopItems = initialDesktopItems;
      if (loadedApps != null) apps = loadedApps;
      if (loadedSnapshot != null) snapshot = loadedSnapshot;
      if (loadedNotifications != null) notificationState = loadedNotifications;
      if (loadedPerf != null) performanceProfile = loadedPerf;
      if (loadedWindowSnapshot != null) windowSnapshot = loadedWindowSnapshot;
      if (surfaceStates != null) {
        if (surfaceStates['browser'] == true) browserOpen = true;
        if (surfaceStates['terminal'] == true) terminalOpen = true;
      }
      currentWorkspace = nativeWorkspace ??
          loadedSnapshot?.currentWorkspace.clamp(1, 4).toInt() ??
          currentWorkspace;
    });

    if (!prefs.firstRunCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FirstRunDialog.showIfNeeded(
            context: context,
            bridge: widget.bridge,
            preferences: prefs,
            snapshot: snapshot,
            onComplete: () {
              if (mounted) setState(() {});
            },
          );
        }
      });
    }
  }

  Future<void> _refreshNativeShellState() async {
    if (_shellStateRefreshInFlight) return;
    _shellStateRefreshInFlight = true;
    try {
      final recoveredApps = apps.isEmpty ? await widget.bridge.tryLoadApps() : null;
      final nativeSnapshot = await widget.bridge.tryLoadSystemSnapshot();
      final nativeWorkspace = await widget.bridge.getCurrentWorkspace();
      final nativeNotifications = await widget.bridge.tryLoadNotificationState();
      final nativePerf = await widget.bridge.tryLoadPerformanceProfile();
      final nativeWindowSnapshot = await widget.bridge.tryLoadWindowSnapshot();
      if (!mounted) return;

      final nextSnapshot = nativeSnapshot ?? snapshot;
      final nextWorkspace = nativeWorkspace ??
          nativeSnapshot?.currentWorkspace.clamp(1, 4).toInt() ??
          currentWorkspace;
      final nextNotifications = nativeNotifications != null &&
              nativeNotifications.revision >= notificationState.revision
          ? nativeNotifications
          : notificationState;
      final nextPerf = nativePerf ?? performanceProfile;
      final nextWindowSnapshot = nativeWindowSnapshot ?? windowSnapshot;

      if (nativePerf != null) {
        GlassSurface.disableBlur = nativePerf.isEconomy;
      }

      if (recoveredApps == null &&
          _sameSystemSnapshot(nextSnapshot, snapshot) &&
          nextWorkspace == currentWorkspace &&
          _sameNotificationState(nextNotifications, notificationState) &&
          nextPerf.profile == performanceProfile.profile &&
          nextWindowSnapshot.sequence == windowSnapshot.sequence) {
        return;
      }

      setState(() {
        if (recoveredApps != null) apps = recoveredApps;
        snapshot = nextSnapshot;
        currentWorkspace = nextWorkspace;
        notificationState = nextNotifications;
        performanceProfile = nextPerf;
        windowSnapshot = nextWindowSnapshot;
      });
    } finally {
      _shellStateRefreshInFlight = false;
    }
  }

  Future<void> _setPerformanceProfile(String profile) async {
    final ok = await widget.bridge.setPerformanceProfile(profile);
    if (ok) {
      final updated = await widget.bridge.tryLoadPerformanceProfile();
      if (!mounted) return;
      setState(() {
        if (updated != null) {
          performanceProfile = updated;
          GlassSurface.disableBlur = updated.isEconomy;
        }
      });
    }
  }

  void _closeTransientPanels() {
    startOpen = false;
    quickSettingsOpen = false;
    notificationsOpen = false;
    altTabOpen = false;
    spotlightOpen = false;
  }

  void _toggleStart() {
    if (startOpen) {
      setState(_closeTransientPanels);
      return;
    }
    setState(() {
      _closeTransientPanels();
      startOpen = true;
    });
    if (apps.isEmpty) {
      unawaited(_refreshNativeShellState());
    }
  }

  void _toggleSpotlight() {
    setState(() {
      final next = !spotlightOpen;
      _closeTransientPanels();
      spotlightOpen = next;
    });
  }

  void _toggleQuickSettings() {
    if (quickSettingsOpen) {
      setState(_closeTransientPanels);
      return;
    }
    setState(() {
      _closeTransientPanels();
      quickSettingsOpen = true;
    });
    unawaited(_refreshNativeShellState());
  }

  void _toggleNotifications() {
    if (notificationsOpen) {
      setState(_closeTransientPanels);
      return;
    }

    setState(() {
      _closeTransientPanels();
      notificationsOpen = true;
    });
    unawaited(_openAuthoritativeNotifications());
  }

  Future<void> _openAuthoritativeNotifications() async {
    final observed = await widget.bridge.tryLoadNotificationState();
    final loaded = observed != null &&
            observed.revision >= notificationState.revision
        ? observed
        : notificationState;
    final marked = await widget.bridge.markNotificationsRead();
    if (!mounted) return;

    final nextState = marked
        ? loaded.copyWith(
            revision: loaded.revision + (loaded.unreadCount > 0 ? 1 : 0),
            unreadCount: 0,
            items: loaded.items
                .map((notification) => notification.copyWith(read: true))
                .toList(growable: false),
          )
        : loaded;
    setState(() {
      notificationState = nextState;
    });
  }

  Future<void> _dismissNotification(String id) async {
    if (!await widget.bridge.dismissNotification(id) || !mounted) return;
    final remaining = notificationState.items
        .where((notification) => notification.id != id)
        .toList(growable: false);
    setState(() {
      notificationState = notificationState.copyWith(
        revision: notificationState.revision + 1,
        unreadCount: remaining.where((notification) => !notification.read).length,
        items: remaining,
      );
    });
  }

  Future<void> _clearNotifications() async {
    if (!await widget.bridge.clearNotifications() || !mounted) return;
    setState(() {
      notificationState = CloudNotificationState(
        revision: notificationState.revision + 1,
        unreadCount: 0,
        items: const <CloudNotification>[],
      );
    });
  }

  // Window Manager Actions
  void _focusWindow(String id) {
    setState(() {
      topZIndex++;
      activeInternalWindowId = id;
      if (id == 'files') {
        filesZIndex = topZIndex;
        filesMinimized = false;
      } else if (id == 'terminal') {
        terminalZIndex = topZIndex;
        terminalMinimized = false;
      } else if (id == 'browser') {
        browserZIndex = topZIndex;
        browserMinimized = false;
      } else if (id == 'settings') {
        settingsZIndex = topZIndex;
        settingsMinimized = false;
      } else if (id == 'notes') {
        notesZIndex = topZIndex;
        notesMinimized = false;
      } else if (id == 'calculator') {
        calculatorZIndex = topZIndex;
        calculatorMinimized = false;
      } else if (id == 'task_manager') {
        taskManagerZIndex = topZIndex;
        taskManagerMinimized = false;
      }
      _closeTransientPanels();
    });
  }

  void _openFilesRoot(String rootId) {
    setState(() {
      filesRootId = rootId;
      filesLaunchRevision++;
      filesOpen = true;
      filesMinimized = false;
      filesZIndex = ++topZIndex;
      activeInternalWindowId = 'files';
      _closeTransientPanels();
    });
  }

  void _toggleOrFocusWindow(String id) {
    setState(() {
      if (id == 'files') {
        if (!filesOpen) {
          filesOpen = true;
          filesMinimized = false;
          filesZIndex = ++topZIndex;
          activeInternalWindowId = 'files';
        } else if (filesMinimized) {
          filesMinimized = false;
          filesZIndex = ++topZIndex;
          activeInternalWindowId = 'files';
        } else if (activeInternalWindowId == 'files') {
          filesMinimized = true;
          activeInternalWindowId = null;
        } else {
          filesZIndex = ++topZIndex;
          activeInternalWindowId = 'files';
        }
      } else if (id == 'terminal') {
        if (!terminalOpen) {
          terminalOpen = true;
          terminalMinimized = false;
          terminalZIndex = ++topZIndex;
          activeInternalWindowId = 'terminal';
        } else if (terminalMinimized) {
          terminalMinimized = false;
          terminalZIndex = ++topZIndex;
          activeInternalWindowId = 'terminal';
        } else if (activeInternalWindowId == 'terminal') {
          terminalMinimized = true;
          activeInternalWindowId = null;
        } else {
          terminalZIndex = ++topZIndex;
          activeInternalWindowId = 'terminal';
        }
      } else if (id == 'browser') {
        if (!browserOpen) {
          browserOpen = true;
          browserMinimized = false;
          browserZIndex = ++topZIndex;
          activeInternalWindowId = 'browser';
        } else if (browserMinimized) {
          browserMinimized = false;
          browserZIndex = ++topZIndex;
          activeInternalWindowId = 'browser';
        } else if (activeInternalWindowId == 'browser') {
          browserMinimized = true;
          activeInternalWindowId = null;
        } else {
          browserZIndex = ++topZIndex;
          activeInternalWindowId = 'browser';
        }
      } else if (id == 'settings') {
        if (!settingsOpen) {
          settingsOpen = true;
          settingsMinimized = false;
          settingsZIndex = ++topZIndex;
          activeInternalWindowId = 'settings';
        } else if (settingsMinimized) {
          settingsMinimized = false;
          settingsZIndex = ++topZIndex;
          activeInternalWindowId = 'settings';
        } else if (activeInternalWindowId == 'settings') {
          settingsMinimized = true;
          activeInternalWindowId = null;
        } else {
          settingsZIndex = ++topZIndex;
          activeInternalWindowId = 'settings';
        }
      } else if (id == 'notes') {
        if (!notesOpen) {
          notesOpen = true;
          notesMinimized = false;
          notesZIndex = ++topZIndex;
          activeInternalWindowId = 'notes';
        } else if (notesMinimized) {
          notesMinimized = false;
          notesZIndex = ++topZIndex;
          activeInternalWindowId = 'notes';
        } else if (activeInternalWindowId == 'notes') {
          notesMinimized = true;
          activeInternalWindowId = null;
        } else {
          notesZIndex = ++topZIndex;
          activeInternalWindowId = 'notes';
        }
      } else if (id == 'calculator') {
        if (!calculatorOpen) {
          calculatorOpen = true;
          calculatorMinimized = false;
          calculatorZIndex = ++topZIndex;
          activeInternalWindowId = 'calculator';
        } else if (calculatorMinimized) {
          calculatorMinimized = false;
          calculatorZIndex = ++topZIndex;
          activeInternalWindowId = 'calculator';
        } else if (activeInternalWindowId == 'calculator') {
          calculatorMinimized = true;
          activeInternalWindowId = null;
        } else {
          calculatorZIndex = ++topZIndex;
          activeInternalWindowId = 'calculator';
        }
      } else if (id == 'task_manager') {
        if (!taskManagerOpen) {
          taskManagerOpen = true;
          taskManagerMinimized = false;
          taskManagerZIndex = ++topZIndex;
          activeInternalWindowId = 'task_manager';
        } else if (taskManagerMinimized) {
          taskManagerMinimized = false;
          taskManagerZIndex = ++topZIndex;
          activeInternalWindowId = 'task_manager';
        } else if (activeInternalWindowId == 'task_manager') {
          taskManagerMinimized = true;
          activeInternalWindowId = null;
        } else {
          taskManagerZIndex = ++topZIndex;
          activeInternalWindowId = 'task_manager';
        }
      }
      _closeTransientPanels();
    });
  }

  void _openSettingsSection(SettingsSection section) {
    setState(() {
      settingsSection = section;
      settingsOpen = true;
      settingsMinimized = false;
      settingsZIndex = ++topZIndex;
      activeInternalWindowId = 'settings';
      _closeTransientPanels();
    });
  }

  void _closeWindow(String id) {
    if (id == 'browser') {
      unawaited(widget.bridge.closeShellSurface('cloudos:browser'));
    } else if (id == 'terminal') {
      unawaited(widget.bridge.closeShellSurface('cloudos:terminal'));
    }
    setState(() {
      if (id == 'files') filesOpen = false;
      if (id == 'terminal') terminalOpen = false;
      if (id == 'browser') browserOpen = false;
      if (id == 'settings') settingsOpen = false;
      if (id == 'notes') notesOpen = false;
      if (id == 'calculator') calculatorOpen = false;
      if (id == 'task_manager') taskManagerOpen = false;
      if (activeInternalWindowId == id) {
        activeInternalWindowId = null;
      }
    });
  }

  List<StartRunningApp> get _startRunningApps => <StartRunningApp>[
        if (filesOpen)
          StartRunningApp(
            id: 'files',
            title: 'Explorador de Arquivos',
            icon: Icons.folder_rounded,
            appIds: const <String>{'files', 'cloudos:files', 'cloudos:drive'},
            isMinimized: filesMinimized,
            isActive: activeInternalWindowId == 'files',
          ),
        if (browserOpen)
          StartRunningApp(
            id: 'browser',
            title: 'Navegador Web',
            icon: Icons.public_rounded,
            appIds: const <String>{'browser', 'cloudos:browser'},
            isMinimized: browserMinimized,
            isActive: activeInternalWindowId == 'browser',
          ),
        if (terminalOpen)
          StartRunningApp(
            id: 'terminal',
            title: 'CloudOS Terminal',
            icon: Icons.terminal_rounded,
            appIds: const <String>{
              'terminal',
              'cloudos:terminal',
              'wsl',
              'wsl:terminal',
            },
            isMinimized: terminalMinimized,
            isActive: activeInternalWindowId == 'terminal',
          ),
        if (settingsOpen)
          StartRunningApp(
            id: 'settings',
            title: 'Configurações',
            icon: Icons.settings_rounded,
            appIds: const <String>{'settings', 'cloudos:settings'},
            isMinimized: settingsMinimized,
            isActive: activeInternalWindowId == 'settings',
          ),
        if (notesOpen)
          StartRunningApp(
            id: 'notes',
            title: 'CloudOS Notes',
            icon: Icons.description_rounded,
            appIds: const <String>{'notes', 'cloudos:notes'},
            isMinimized: notesMinimized,
            isActive: activeInternalWindowId == 'notes',
          ),
        if (calculatorOpen)
          StartRunningApp(
            id: 'calculator',
            title: 'Calculadora',
            icon: Icons.calculate_rounded,
            appIds: const <String>{'calculator', 'cloudos:calculator'},
            isMinimized: calculatorMinimized,
            isActive: activeInternalWindowId == 'calculator',
          ),
        if (taskManagerOpen)
          StartRunningApp(
            id: 'task_manager',
            title: 'Monitor de Sistema',
            icon: Icons.monitor_heart_rounded,
            appIds: const <String>{'task_manager', 'cloudos:task_manager'},
            isMinimized: taskManagerMinimized,
            isActive: activeInternalWindowId == 'task_manager',
          ),
        for (final win in windowSnapshot.windows.where((w) => w.platform != 'cloudos' && w.hwnd != 0))
          StartRunningApp(
            id: 'hwnd-${win.hwnd}',
            title: win.title,
            icon: win.icon,
            appIds: <String>{win.appId, 'hwnd-${win.hwnd}'},
            isMinimized: win.isMinimized,
            isActive: win.isFocused,
          ),
      ];

  void _activateWindowFromStart(String id) {
    if (id.startsWith('hwnd-')) {
      final hwnd = int.tryParse(id.substring(5)) ?? 0;
      if (hwnd != 0) {
        unawaited(widget.bridge.focusWindow(hwnd));
        setState(() => startOpen = false);
        return;
      }
    }
    _focusWindow(id);
  }

  void _closeWindowFromStart(String id) {
    if (id.startsWith('hwnd-')) {
      final hwnd = int.tryParse(id.substring(5)) ?? 0;
      if (hwnd != 0) {
        unawaited(widget.bridge.closeWindow(hwnd));
        return;
      }
    }
    _closeWindow(id);
  }

  List<CloudWindow> _getUnifiedWindows() {
    final list = <CloudWindow>[];
    if (filesOpen) {
      list.add(
        CloudWindow(
          id: 'files',
          title: 'Arquivos',
          icon: Icons.folder_rounded,
          type: CloudWindowType.files,
          position: filesOffset,
          size: filesSize,
          isMinimized: filesMinimized,
          isMaximized: filesMaximized,
          zIndex: filesZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'files',
        ),
      );
    }
    if (terminalOpen) {
      list.add(
        CloudWindow(
          id: 'terminal',
          title: 'Terminal',
          icon: Icons.terminal_rounded,
          type: CloudWindowType.terminal,
          position: terminalOffset,
          size: terminalSize,
          isMinimized: terminalMinimized,
          isMaximized: terminalMaximized,
          zIndex: terminalZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'terminal',
        ),
      );
    }
    if (browserOpen) {
      list.add(
        CloudWindow(
          id: 'browser',
          title: 'Navegador Web',
          icon: Icons.public_rounded,
          type: CloudWindowType.browser,
          position: browserOffset,
          size: browserSize,
          isMinimized: browserMinimized,
          isMaximized: browserMaximized,
          zIndex: browserZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'browser',
        ),
      );
    }
    if (settingsOpen) {
      list.add(
        CloudWindow(
          id: 'settings',
          title: 'Configurações',
          icon: Icons.settings_rounded,
          type: CloudWindowType.settings,
          position: settingsOffset,
          size: settingsSize,
          isMinimized: settingsMinimized,
          isMaximized: settingsMaximized,
          zIndex: settingsZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'settings',
        ),
      );
    }
    if (notesOpen) {
      list.add(
        CloudWindow(
          id: 'notes',
          title: 'Notas',
          icon: Icons.description_rounded,
          type: CloudWindowType.notes,
          position: notesOffset,
          size: notesSize,
          isMinimized: notesMinimized,
          isMaximized: notesMaximized,
          zIndex: notesZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'notes',
        ),
      );
    }
    if (calculatorOpen) {
      list.add(
        CloudWindow(
          id: 'calculator',
          title: 'Calculadora',
          icon: Icons.calculate_rounded,
          type: CloudWindowType.calculator,
          position: calculatorOffset,
          size: calculatorSize,
          isMinimized: calculatorMinimized,
          isMaximized: calculatorMaximized,
          zIndex: calculatorZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'calculator',
        ),
      );
    }
    if (taskManagerOpen) {
      list.add(
        CloudWindow(
          id: 'task_manager',
          title: 'Monitor do Sistema',
          icon: Icons.monitor_heart_rounded,
          type: CloudWindowType.taskManager,
          position: taskManagerOffset,
          size: taskManagerSize,
          isMinimized: taskManagerMinimized,
          isMaximized: taskManagerMaximized,
          zIndex: taskManagerZIndex,
          platform: 'cloudos',
          isFocused: activeInternalWindowId == 'task_manager',
        ),
      );
    }
    for (final win in windowSnapshot.windows) {
      if (win.platform != 'cloudos' && win.hwnd != 0) {
        list.add(win);
      }
    }
    return list;
  }

  void _reconcileWindowBounds(CloudLayoutMetrics metrics) {
    final double workW = metrics.workAreaWidth;
    final double workH = metrics.workAreaHeight;
    final double halfW = (workW / 2.0).clamp(200.0, workW).toDouble();

    void reconcileOne({
      required String id,
      required bool isOpen,
      required bool isMaximized,
      required Offset offset,
      required Size size,
      required void Function(Offset newOffset, Size newSize, bool isMaximized) update,
    }) {
      if (!isOpen) return;
      final snap = _windowSnapModes[id] ??
          (isMaximized ? WindowSnapMode.maximized : WindowSnapMode.none);
      if (snap == WindowSnapMode.maximized) {
        update(Offset.zero, Size(workW, workH), true);
      } else if (snap == WindowSnapMode.left) {
        update(Offset.zero, Size(halfW, workH), false);
      } else if (snap == WindowSnapMode.right) {
        update(Offset(workW - halfW, 0), Size(halfW, workH), false);
      } else {
        final double clampedW = size.width.clamp(320.0, workW).toDouble();
        final double clampedH = size.height.clamp(240.0, workH).toDouble();
        final double maxLeft = (workW - clampedW).clamp(0.0, double.infinity).toDouble();
        final double maxTop = (workH - clampedH).clamp(0.0, double.infinity).toDouble();
        final double clampedX = offset.dx.clamp(0.0, maxLeft).toDouble();
        final double clampedY = offset.dy.clamp(0.0, maxTop).toDouble();
        update(Offset(clampedX, clampedY), Size(clampedW, clampedH), false);
      }
    }

    reconcileOne(
      id: 'files',
      isOpen: filesOpen,
      isMaximized: filesMaximized,
      offset: filesOffset,
      size: filesSize,
      update: (o, s, m) {
        filesOffset = o;
        filesSize = s;
        filesMaximized = m;
      },
    );
    reconcileOne(
      id: 'terminal',
      isOpen: terminalOpen,
      isMaximized: terminalMaximized,
      offset: terminalOffset,
      size: terminalSize,
      update: (o, s, m) {
        terminalOffset = o;
        terminalSize = s;
        terminalMaximized = m;
      },
    );
    reconcileOne(
      id: 'browser',
      isOpen: browserOpen,
      isMaximized: browserMaximized,
      offset: browserOffset,
      size: browserSize,
      update: (o, s, m) {
        browserOffset = o;
        browserSize = s;
        browserMaximized = m;
      },
    );
    reconcileOne(
      id: 'settings',
      isOpen: settingsOpen,
      isMaximized: settingsMaximized,
      offset: settingsOffset,
      size: settingsSize,
      update: (o, s, m) {
        settingsOffset = o;
        settingsSize = s;
        settingsMaximized = m;
      },
    );
    reconcileOne(
      id: 'notes',
      isOpen: notesOpen,
      isMaximized: notesMaximized,
      offset: notesOffset,
      size: notesSize,
      update: (o, s, m) {
        notesOffset = o;
        notesSize = s;
        notesMaximized = m;
      },
    );
    reconcileOne(
      id: 'calculator',
      isOpen: calculatorOpen,
      isMaximized: calculatorMaximized,
      offset: calculatorOffset,
      size: calculatorSize,
      update: (o, s, m) {
        calculatorOffset = o;
        calculatorSize = s;
        calculatorMaximized = m;
      },
    );
    reconcileOne(
      id: 'task_manager',
      isOpen: taskManagerOpen,
      isMaximized: taskManagerMaximized,
      offset: taskManagerOffset,
      size: taskManagerSize,
      update: (o, s, m) {
        taskManagerOffset = o;
        taskManagerSize = s;
        taskManagerMaximized = m;
      },
    );
  }

  void _toggleMaximizeWindow(String id, BoxConstraints constraints) {
    setState(() {
      final maxAvailableHeight = constraints.maxHeight - 56.0;
      final maxAvailableWidth = constraints.maxWidth;

      if (id == 'files') {
        if (filesMaximized) {
          filesOffset = filesPreMaxOffset ?? const Offset(120, 50);
          filesSize = filesPreMaxSize ?? const Size(960, 600);
          filesMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          filesPreMaxOffset = filesOffset;
          filesPreMaxSize = filesSize;
          filesOffset = Offset.zero;
          filesSize = Size(maxAvailableWidth, maxAvailableHeight);
          filesMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'terminal') {
        if (terminalMaximized) {
          terminalOffset = terminalPreMaxOffset ?? const Offset(180, 80);
          terminalSize = terminalPreMaxSize ?? const Size(780, 480);
          terminalMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          terminalPreMaxOffset = terminalOffset;
          terminalPreMaxSize = terminalSize;
          terminalOffset = Offset.zero;
          terminalSize = Size(maxAvailableWidth, maxAvailableHeight);
          terminalMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'browser') {
        if (browserMaximized) {
          browserOffset = browserPreMaxOffset ?? const Offset(150, 70);
          browserSize = browserPreMaxSize ?? const Size(880, 540);
          browserMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          browserPreMaxOffset = browserOffset;
          browserPreMaxSize = browserSize;
          browserOffset = Offset.zero;
          browserSize = Size(maxAvailableWidth, maxAvailableHeight);
          browserMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'settings') {
        if (settingsMaximized) {
          settingsOffset = settingsPreMaxOffset ?? const Offset(210, 90);
          settingsSize = settingsPreMaxSize ?? const Size(760, 500);
          settingsMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          settingsPreMaxOffset = settingsOffset;
          settingsPreMaxSize = settingsSize;
          settingsOffset = Offset.zero;
          settingsSize = Size(maxAvailableWidth, maxAvailableHeight);
          settingsMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'notes') {
        if (notesMaximized) {
          notesOffset = notesPreMaxOffset ?? const Offset(240, 110);
          notesSize = notesPreMaxSize ?? const Size(780, 520);
          notesMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          notesPreMaxOffset = notesOffset;
          notesPreMaxSize = notesSize;
          notesOffset = Offset.zero;
          notesSize = Size(maxAvailableWidth, maxAvailableHeight);
          notesMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'calculator') {
        if (calculatorMaximized) {
          calculatorOffset = calculatorPreMaxOffset ?? const Offset(280, 130);
          calculatorSize = calculatorPreMaxSize ?? const Size(540, 480);
          calculatorMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          calculatorPreMaxOffset = calculatorOffset;
          calculatorPreMaxSize = calculatorSize;
          calculatorOffset = Offset.zero;
          calculatorSize = Size(maxAvailableWidth, maxAvailableHeight);
          calculatorMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      } else if (id == 'task_manager') {
        if (taskManagerMaximized) {
          taskManagerOffset = taskManagerPreMaxOffset ?? const Offset(200, 100);
          taskManagerSize = taskManagerPreMaxSize ?? const Size(720, 480);
          taskManagerMaximized = false;
          _windowSnapModes[id] = WindowSnapMode.none;
        } else {
          taskManagerPreMaxOffset = taskManagerOffset;
          taskManagerPreMaxSize = taskManagerSize;
          taskManagerOffset = Offset.zero;
          taskManagerSize = Size(maxAvailableWidth, maxAvailableHeight);
          taskManagerMaximized = true;
          _windowSnapModes[id] = WindowSnapMode.maximized;
        }
      }
      _focusWindow(id);
    });
  }

  void _snapWindowLeft(String id, BoxConstraints constraints) {
    setState(() {
      final availableHeight = constraints.maxHeight - 56.0;
      final halfWidth = constraints.maxWidth / 2.0;

      _windowSnapModes[id] = WindowSnapMode.left;
      if (id == 'files') {
        filesMaximized = false;
        filesOffset = Offset.zero;
        filesSize = Size(halfWidth, availableHeight);
      } else if (id == 'terminal') {
        terminalMaximized = false;
        terminalOffset = Offset.zero;
        terminalSize = Size(halfWidth, availableHeight);
      } else if (id == 'browser') {
        browserMaximized = false;
        browserOffset = Offset.zero;
        browserSize = Size(halfWidth, availableHeight);
      } else if (id == 'settings') {
        settingsMaximized = false;
        settingsOffset = Offset.zero;
        settingsSize = Size(halfWidth, availableHeight);
      } else if (id == 'notes') {
        notesMaximized = false;
        notesOffset = Offset.zero;
        notesSize = Size(halfWidth, availableHeight);
      } else if (id == 'calculator') {
        calculatorMaximized = false;
        calculatorOffset = Offset.zero;
        calculatorSize = Size(halfWidth, availableHeight);
      } else if (id == 'task_manager') {
        taskManagerMaximized = false;
        taskManagerOffset = Offset.zero;
        taskManagerSize = Size(halfWidth, availableHeight);
      }
      _focusWindow(id);
    });
  }

  void _snapWindowRight(String id, BoxConstraints constraints) {
    setState(() {
      final availableHeight = constraints.maxHeight - 56.0;
      final halfWidth = constraints.maxWidth / 2.0;

      _windowSnapModes[id] = WindowSnapMode.right;
      if (id == 'files') {
        filesMaximized = false;
        filesOffset = Offset(halfWidth, 0);
        filesSize = Size(halfWidth, availableHeight);
      } else if (id == 'terminal') {
        terminalMaximized = false;
        terminalOffset = Offset(halfWidth, 0);
        terminalSize = Size(halfWidth, availableHeight);
      } else if (id == 'browser') {
        browserMaximized = false;
        browserOffset = Offset(halfWidth, 0);
        browserSize = Size(halfWidth, availableHeight);
      } else if (id == 'settings') {
        settingsMaximized = false;
        settingsOffset = Offset(halfWidth, 0);
        settingsSize = Size(halfWidth, availableHeight);
      } else if (id == 'notes') {
        notesMaximized = false;
        notesOffset = Offset(halfWidth, 0);
        notesSize = Size(halfWidth, availableHeight);
      } else if (id == 'calculator') {
        calculatorMaximized = false;
        calculatorOffset = Offset(halfWidth, 0);
        calculatorSize = Size(halfWidth, availableHeight);
      } else if (id == 'task_manager') {
        taskManagerMaximized = false;
        taskManagerOffset = Offset(halfWidth, 0);
        taskManagerSize = Size(halfWidth, availableHeight);
      }
      _focusWindow(id);
    });
  }

  void _moveWindow(String id, Offset delta, BoxConstraints constraints) {
    setState(() {
      _windowSnapModes[id] = WindowSnapMode.none;
      final maxLeft = constraints.maxWidth - 120.0;
      final maxTop = constraints.maxHeight - 80.0;

      if (id == 'files') {
        filesOffset = Offset(
          (filesOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (filesOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'terminal') {
        terminalOffset = Offset(
          (terminalOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (terminalOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'browser') {
        browserOffset = Offset(
          (browserOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (browserOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'settings') {
        settingsOffset = Offset(
          (settingsOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (settingsOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'notes') {
        notesOffset = Offset(
          (notesOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (notesOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'calculator') {
        calculatorOffset = Offset(
          (calculatorOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (calculatorOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      } else if (id == 'task_manager') {
        taskManagerOffset = Offset(
          (taskManagerOffset.dx + delta.dx).clamp(0.0, maxLeft),
          (taskManagerOffset.dy + delta.dy).clamp(0.0, maxTop),
        );
      }
    });
  }

  void _resizeWindow(
    String id,
    Offset delta,
    bool left,
    bool top,
    bool right,
    bool bottom,
    BoxConstraints constraints,
  ) {
    setState(() {
      _windowSnapModes[id] = WindowSnapMode.none;
      const minW = 420.0;
      const minH = 300.0;

      Size currentSize = filesSize;
      Offset currentPos = filesOffset;

      if (id == 'terminal') {
        currentSize = terminalSize;
        currentPos = terminalOffset;
      } else if (id == 'browser') {
        currentSize = browserSize;
        currentPos = browserOffset;
      } else if (id == 'settings') {
        currentSize = settingsSize;
        currentPos = settingsOffset;
      } else if (id == 'notes') {
        currentSize = notesSize;
        currentPos = notesOffset;
      } else if (id == 'calculator') {
        currentSize = calculatorSize;
        currentPos = calculatorOffset;
      } else if (id == 'task_manager') {
        currentSize = taskManagerSize;
        currentPos = taskManagerOffset;
      }

      double newW = currentSize.width;
      double newH = currentSize.height;
      double newX = currentPos.dx;
      double newY = currentPos.dy;

      if (right) newW = (newW + delta.dx).clamp(minW, constraints.maxWidth - newX);
      if (bottom) newH = (newH + delta.dy).clamp(minH, constraints.maxHeight - 56.0 - newY);
      if (left) {
        final possibleW = newW - delta.dx;
        if (possibleW >= minW && newX + delta.dx >= 0) {
          newW = possibleW;
          newX += delta.dx;
        }
      }
      if (top) {
        final possibleH = newH - delta.dy;
        if (possibleH >= minH && newY + delta.dy >= 0) {
          newH = possibleH;
          newY += delta.dy;
        }
      }

      final updatedSize = Size(newW, newH);
      final updatedPos = Offset(newX, newY);

      if (id == 'files') {
        filesSize = updatedSize;
        filesOffset = updatedPos;
      } else if (id == 'terminal') {
        terminalSize = updatedSize;
        terminalOffset = updatedPos;
      } else if (id == 'browser') {
        browserSize = updatedSize;
        browserOffset = updatedPos;
      } else if (id == 'settings') {
        settingsSize = updatedSize;
        settingsOffset = updatedPos;
      } else if (id == 'notes') {
        notesSize = updatedSize;
        notesOffset = updatedPos;
      } else if (id == 'calculator') {
        calculatorSize = updatedSize;
        calculatorOffset = updatedPos;
      } else if (id == 'task_manager') {
        taskManagerSize = updatedSize;
        taskManagerOffset = updatedPos;
      }
    });
  }

  void _cycleAltTab() {
    final openList = _getUnifiedWindows();
    if (openList.isEmpty) return;

    setState(() {
      altTabOpen = true;
      altTabSelectedIndex = (altTabSelectedIndex + 1) % openList.length;
    });
  }

  void _confirmAltTab() {
    final openList = _getUnifiedWindows();
    if (openList.isNotEmpty && altTabSelectedIndex < openList.length) {
      final target = openList[altTabSelectedIndex];
      if (target.platform != 'cloudos' && target.hwnd != 0) {
        unawaited(widget.bridge.focusWindow(target.hwnd));
      } else {
        _focusWindow(target.id);
      }
    }
    setState(() => altTabOpen = false);
  }

  Future<void> _launchBridgeSurface(
    String appId,
    ShellAppRoute route,
  ) async {
    final focused = await widget.bridge.focusShellSurface(appId);
    if (!mounted) return;
    if (focused) {
      setState(() {
        _closeTransientPanels();
        if (route == ShellAppRoute.browser) {
          browserOpen = true;
          browserMinimized = false;
          browserZIndex = ++topZIndex;
          activeInternalWindowId = 'browser';
        }
        if (route == ShellAppRoute.terminal) {
          terminalOpen = true;
          terminalMinimized = false;
          terminalZIndex = ++topZIndex;
          activeInternalWindowId = 'terminal';
        }
      });
      return;
    }

    final launched = await widget.bridge.launchApp(appId);
    if (!mounted) return;
    setState(() {
      _closeTransientPanels();
      if (route == ShellAppRoute.browser) {
        browserOpen = true;
        browserMinimized = false;
        browserZIndex = ++topZIndex;
        activeInternalWindowId = 'browser';
      }
      if (route == ShellAppRoute.terminal) {
        terminalOpen = true;
        terminalMinimized = false;
        terminalZIndex = ++topZIndex;
        activeInternalWindowId = 'terminal';
      }
    });
    if (launched) {
      await _refreshNativeShellState();
    }
  }

  Future<void> _launchBrowser() {
    return _launchBridgeSurface(
      canonicalLaunchId(ShellAppRoute.browser),
      ShellAppRoute.browser,
    );
  }

  Future<void> _launchTerminal() {
    return _launchBridgeSurface(
      canonicalLaunchId(ShellAppRoute.terminal),
      ShellAppRoute.terminal,
    );
  }

  Future<void> _switchWorkspace(int index) async {
    if (index < 1 || index > 4) return;
    final switched = await widget.bridge.switchWorkspace(index);
    if (!mounted) return;

    int? authoritativeWorkspace;
    if (!switched) {
      authoritativeWorkspace = await widget.bridge.getCurrentWorkspace();
      if (!mounted) return;
    }

    setState(() {
      if (switched) {
        currentWorkspace = index;
      } else if (authoritativeWorkspace != null) {
        currentWorkspace = authoritativeWorkspace;
      }
      _closeTransientPanels();
    });
  }

  void _openQuickSettingsRoute(QuickSettingsRoute route) {
    final launchId = quickSettingsLaunchId(route);
    final section = switch (launchId) {
      'cloudos:settings:wifi' => SettingsSection.network,
      'cloudos:settings:bluetooth' => SettingsSection.bluetooth,
      'cloudos:settings:nightlight' => SettingsSection.display,
      'cloudos:settings:focus' => SettingsSection.personalization,
      _ => SettingsSection.display,
    };
    _openSettingsSection(section);
  }

  Future<void> _launchApp(CloudApp app) async {
    _preferences?.recordAppLaunch(app.id);

    if (app.id == 'cloudos:drive' || app.id == 'drive') {
      _openFilesRoot('cloud-drive');
      return;
    }

    if (app.id == 'cloudos:trash' || app.id == 'trash') {
      _openFilesRoot('trash');
      return;
    }

    if (app.id.startsWith('files:')) {
      final root = app.id.substring('files:'.length);
      _openFilesRoot(root);
      return;
    }

    final route = resolveShellAppRoute(app.id);

    if (route == ShellAppRoute.files ||
        app.id == 'files' ||
        app.id == 'cloudos:files') {
      _toggleOrFocusWindow('files');
      return;
    }

    if (route == ShellAppRoute.browser ||
        app.id == 'browser' ||
        app.id == 'cloudos:browser') {
      await _launchBrowser();
      return;
    }

    if (route == ShellAppRoute.terminal ||
        app.id == 'terminal' ||
        app.id == 'cloudos:terminal' ||
        app.id == 'wsl' ||
        app.id == 'wsl:terminal') {
      await _launchTerminal();
      return;
    }

    final appIdLower = app.id.toLowerCase();
    if (appIdLower == 'settings' || appIdLower == 'cloudos:settings') {
      _openSettingsSection(SettingsSection.display);
      return;
    }
    if (appIdLower == 'cloudos:settings:wifi' ||
        appIdLower == 'wifi' ||
        appIdLower == 'network' ||
        appIdLower == 'cloudos:settings:network') {
      _openSettingsSection(SettingsSection.network);
      return;
    }
    if (appIdLower == 'cloudos:settings:bluetooth' ||
        appIdLower == 'bluetooth') {
      _openSettingsSection(SettingsSection.bluetooth);
      return;
    }
    if (appIdLower == 'cloudos:settings:display' ||
        appIdLower == 'display' ||
        appIdLower == 'screen' ||
        appIdLower == 'tela') {
      _openSettingsSection(SettingsSection.display);
      return;
    }
    if (appIdLower == 'cloudos:settings:sound' ||
        appIdLower == 'sound' ||
        appIdLower == 'audio' ||
        appIdLower == 'som') {
      _openSettingsSection(SettingsSection.sound);
      return;
    }
    if (appIdLower == 'cloudos:settings:power' ||
        appIdLower == 'power' ||
        appIdLower == 'battery' ||
        appIdLower == 'energia') {
      _openSettingsSection(SettingsSection.power);
      return;
    }
    if (appIdLower == 'cloudos:settings:storage' ||
        appIdLower == 'storage' ||
        appIdLower == 'armazenamento') {
      _openSettingsSection(SettingsSection.storage);
      return;
    }
    if (appIdLower == 'cloudos:settings:performance' ||
        appIdLower == 'performance' ||
        appIdLower == 'desempenho') {
      _openSettingsSection(SettingsSection.performance);
      return;
    }
    if (appIdLower == 'cloudos:settings:personalization' ||
        appIdLower == 'personalization' ||
        appIdLower == 'personalizacao') {
      _openSettingsSection(SettingsSection.personalization);
      return;
    }
    if (appIdLower == 'cloudos:settings:wsl' ||
        appIdLower == 'wsl' ||
        appIdLower == 'wsl:settings') {
      _openSettingsSection(SettingsSection.wsl);
      return;
    }
    if (appIdLower == 'cloudos:settings:recovery' ||
        appIdLower == 'recovery' ||
        appIdLower == 'recuperacao') {
      _openSettingsSection(SettingsSection.recovery);
      return;
    }
    if (appIdLower == 'cloudos:settings:diagnostics' ||
        appIdLower == 'diagnostics' ||
        appIdLower == 'diagnostico') {
      _openSettingsSection(SettingsSection.diagnostics);
      return;
    }
    if (appIdLower == 'cloudos:settings:about' ||
        appIdLower == 'about' ||
        appIdLower == 'sobre') {
      _openSettingsSection(SettingsSection.about);
      return;
    }

    if (app.id == 'notes' || app.id == 'cloudos:notes') {
      _toggleOrFocusWindow('notes');
      return;
    }

    if (app.id == 'calculator' || app.id == 'cloudos:calculator') {
      _toggleOrFocusWindow('calculator');
      return;
    }

    if (app.id == 'task_manager' || app.id == 'cloudos:task_manager') {
      _toggleOrFocusWindow('task_manager');
      return;
    }

    // External Windows or WSL Linux Application
    setState(_closeTransientPanels);
    try {
      final res = await widget.bridge.launchAppStructured(app.id);
      if (!mounted) return;
      if (!res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message.isNotEmpty
                  ? res.message
                  : 'Não foi possível iniciar ${app.name}.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      final launched = await widget.bridge.launchApp(app.id);
      if (!mounted) return;
      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha ao iniciar ${app.name}.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  List<SpotlightItem> get _spotlightItems {
    final list = <SpotlightItem>[
      SpotlightItem(
        id: 'files',
        title: 'Explorador de Arquivos',
        subtitle: 'Gerencie pastas e documentos do Windows e Linux',
        icon: Icons.folder_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Sistema',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('files');
        },
      ),
      SpotlightItem(
        id: 'terminal',
        title: 'CloudOS Terminal',
        subtitle: 'Terminal nativo WSL Kali Linux e PowerShell',
        icon: Icons.terminal_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Dev',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('terminal');
        },
      ),
      SpotlightItem(
        id: 'browser',
        title: 'Navegador Web',
        subtitle: 'Navegação rápida na Web com isolamento CloudOS',
        icon: Icons.public_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Internet',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('browser');
        },
      ),
      SpotlightItem(
        id: 'notes',
        title: 'CloudOS Notes',
        subtitle: 'Bloco de anotações e rascunhos rápidos com auto-save',
        icon: Icons.description_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Produtividade',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('notes');
        },
      ),
      SpotlightItem(
        id: 'calculator',
        title: 'Calculadora',
        subtitle: 'Cálculos aritméticos, científicos e histórico',
        icon: Icons.calculate_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Utilitário',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('calculator');
        },
      ),
      SpotlightItem(
        id: 'task_manager',
        title: 'Monitor de Sistema',
        subtitle: 'CPU, RAM, tarefas e processos em execução',
        icon: Icons.monitor_heart_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Sistema',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('task_manager');
        },
      ),
      SpotlightItem(
        id: 'settings',
        title: 'Configurações do CloudOS',
        subtitle: 'Aparência, workspaces, áudio, rede e preferências',
        icon: Icons.settings_rounded,
        kind: SpotlightItemKind.app,
        badge: 'Sistema',
        onSelect: () {
          _closeTransientPanels();
          _toggleOrFocusWindow('settings');
        },
      ),
    ];

    for (final app in apps) {
      if (!list.any((item) => item.id == app.id)) {
        list.add(
          SpotlightItem(
            id: app.id,
            title: app.name,
            subtitle: app.subtitle ?? app.category,
            icon: app.icon,
            kind: SpotlightItemKind.app,
            badge: app.platform.name.toUpperCase(),
            onSelect: () {
              _closeTransientPanels();
              unawaited(_launchApp(app));
            },
          ),
        );
      }
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('files'),
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('terminal'),
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('terminal'),
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('browser'),
        const SingleActivator(
          LogicalKeyboardKey.comma,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('settings'),
        const SingleActivator(
          LogicalKeyboardKey.keyQ,
          control: true,
          alt: true,
        ): _toggleQuickSettings,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          alt: true,
        ): _toggleNotifications,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          alt: true,
        ): _toggleStart,
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
          alt: true,
        ): _toggleStart,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          alt: true,
        ): _cycleAltTab,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (altTabOpen) _confirmAltTab();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(_closeTransientPanels),
        const SingleActivator(
          LogicalKeyboardKey.digit1,
          control: true,
          alt: true,
        ): () => unawaited(_switchWorkspace(1)),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): () => unawaited(_switchWorkspace(2)),
        const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ): () => unawaited(_switchWorkspace(3)),
        const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
          alt: true,
        ): () => unawaited(_switchWorkspace(4)),
        const SingleActivator(
          LogicalKeyboardKey.space,
          alt: true,
        ): _toggleSpotlight,
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
        ): _toggleSpotlight,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): () => _toggleOrFocusWindow('notes'),
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          alt: true,
        ): () => _toggleOrFocusWindow('calculator'),
        const SingleActivator(
          LogicalKeyboardKey.escape,
          control: true,
          shift: true,
        ): () => _toggleOrFocusWindow('task_manager'),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final metrics = CloudLayoutMetrics.fromConstraints(constraints);
              final currentSize = Size(constraints.maxWidth, constraints.maxHeight);
              if (_lastLayoutSize == null || _lastLayoutSize != currentSize) {
                _lastLayoutSize = currentSize;
                _reconcileWindowBounds(metrics);
                _reconcileDesktopIcons(currentSize);
              }

              return CloudResponsiveScope(
                metrics: metrics,
                child: GestureDetector(
                  onTap: () {
                    if (startOpen ||
                        quickSettingsOpen ||
                        notificationsOpen ||
                        altTabOpen ||
                        spotlightOpen ||
                        selectedDesktopIcon != null) {
                      setState(() {
                        _closeTransientPanels();
                        selectedDesktopIcon = null;
                      });
                    }
                  },
                  onSecondaryTapUp: (details) =>
                      _showDesktopContextMenu(context, details.globalPosition),
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const RepaintBoundary(child: DesktopWallpaper()),
                      DesktopIcons(
                        items: desktopItems,
                        selectedId: selectedDesktopIcon,
                        onSelect: (id) =>
                            setState(() => selectedDesktopIcon = id),
                        onItemMoved: _moveDesktopItem,
                        onItemDoubleTap: _handleDesktopItemAction,
                        onItemSecondaryTap: (item, pos) =>
                            _showDesktopItemContextMenu(item, pos),
                      ),
                      Positioned(
                        top: 18,
                        right: 18,
                        child: RepaintBoundary(
                          child: DesktopStatus(
                            snapshot: snapshot,
                            currentWorkspace: currentWorkspace,
                          ),
                        ),
                      ),
                      ..._buildInternalWindows(constraints, metrics),
                      _panelSwitcher(),
                      if (altTabOpen) _buildAltTabOverlay(),
                      if (spotlightOpen)
                        SpotlightPalette(
                          items: _spotlightItems,
                          onClose: () => setState(() => spotlightOpen = false),
                        ),
                      CloudTaskbar(
                        startOpen: startOpen,
                        quickSettingsOpen: quickSettingsOpen,
                        notificationsOpen: notificationsOpen,
                        spotlightOpen: spotlightOpen,
                        onSpotlight: _toggleSpotlight,
                        filesRunning: filesOpen,
                        browserRunning: browserOpen,
                        terminalRunning: terminalOpen,
                        settingsRunning: settingsOpen,
                        notesRunning: notesOpen,
                        calculatorRunning: calculatorOpen,
                        taskManagerRunning: taskManagerOpen,
                        filesActive: activeInternalWindowId == 'files',
                        browserActive: activeInternalWindowId == 'browser',
                        terminalActive: activeInternalWindowId == 'terminal',
                        settingsActive: activeInternalWindowId == 'settings',
                        notesActive: activeInternalWindowId == 'notes',
                        calculatorActive: activeInternalWindowId == 'calculator',
                        taskManagerActive: activeInternalWindowId == 'task_manager',
                        currentWorkspace: currentWorkspace,
                        notificationCount: notificationState.unreadCount,
                        onWorkspaceChanged: (index) =>
                            unawaited(_switchWorkspace(index)),
                        onStart: _toggleStart,
                        onFiles: () => _toggleOrFocusWindow('files'),
                        onCloseFiles: () => _closeWindow('files'),
                        onBrowser: () {
                          if (browserOpen && !browserMinimized && activeInternalWindowId == 'browser') {
                            setState(() {
                              browserMinimized = true;
                              activeInternalWindowId = null;
                            });
                          } else {
                            unawaited(_launchBrowser());
                          }
                        },
                        onCloseBrowser: () => _closeWindow('browser'),
                        onTerminal: () {
                          if (terminalOpen && !terminalMinimized && activeInternalWindowId == 'terminal') {
                            setState(() {
                              terminalMinimized = true;
                              activeInternalWindowId = null;
                            });
                          } else {
                            unawaited(_launchTerminal());
                          }
                        },
                        onCloseTerminal: () => _closeWindow('terminal'),
                        onSettings: () => _toggleOrFocusWindow('settings'),
                        onCloseSettings: () => _closeWindow('settings'),
                        onNotes: () => _toggleOrFocusWindow('notes'),
                        onCloseNotes: () => _closeWindow('notes'),
                        onCalculator: () => _toggleOrFocusWindow('calculator'),
                        onCloseCalculator: () => _closeWindow('calculator'),
                        onTaskManager: () => _toggleOrFocusWindow('task_manager'),
                        onCloseTaskManager: () => _closeWindow('task_manager'),
                        managedWindows: _getUnifiedWindows(),
                        onWindowTap: (win) {
                          if (win.platform != 'cloudos' && win.hwnd != 0) {
                            if (win.isFocused && !win.isMinimized) {
                              unawaited(widget.bridge.minimizeWindow(win.hwnd));
                            } else {
                              unawaited(widget.bridge.focusWindow(win.hwnd));
                            }
                          } else {
                            _toggleOrFocusWindow(win.id);
                          }
                        },
                        onCloseWindow: (win) {
                          if (win.platform != 'cloudos' && win.hwnd != 0) {
                            unawaited(widget.bridge.closeWindow(win.hwnd));
                          } else {
                            _closeWindow(win.id);
                          }
                        },
                        onQuickSettings: _toggleQuickSettings,
                        onNotifications: _toggleNotifications,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _moveDesktopItem(String id, Offset globalPos) {
    final size = MediaQuery.of(context).size;
    final clampedX = globalPos.dx.clamp(10.0, (size.width - 90.0).clamp(10.0, double.infinity));
    final clampedY = globalPos.dy.clamp(10.0, (size.height - 130.0).clamp(10.0, double.infinity));
    setState(() {
      desktopItems = desktopItems.map((item) {
        if (item.id == id) {
          return item.copyWith(position: Offset(clampedX, clampedY));
        }
        return item;
      }).toList(growable: true);
    });
    _preferences?.setIconPosition(id, clampedX, clampedY);
  }

  void _handleDesktopItemAction(DesktopItemData item) {
    switch (item.id) {
      case 'files':
        _toggleOrFocusWindow('files');
        break;
      case 'drive':
        _openFilesRoot('cloud-drive');
        break;
      case 'trash':
        _openFilesRoot('trash');
        break;
      case 'apps':
        _toggleStart();
        break;
      case 'ubuntu':
        TerminalLaunchCoordinator.request(TerminalLaunchProfile.wsl, distro: 'Ubuntu');
        _toggleOrFocusWindow('terminal');
        break;
      case 'settings':
        _toggleOrFocusWindow('settings');
        break;
      default:
        if (item.isCustomFolder) {
          setState(() {
            filesRootId = 'desktop';
            filesLaunchRevision++;
          });
          _toggleOrFocusWindow('files');
        } else if (item.isCustomFile) {
          _toggleOrFocusWindow('notes');
        }
        break;
    }
  }

  void _organizeDesktopIcons() {
    final size = MediaQuery.of(context).size;
    const double startX = 20.0;
    const double startY = 20.0;
    const double itemHeight = 94.0;
    const double itemWidth = 90.0;
    final double maxY = (size.height - 120.0).clamp(100.0, double.infinity);

    double currentX = startX;
    double currentY = startY;

    setState(() {
      desktopItems = desktopItems.map((item) {
        final pos = Offset(currentX, currentY);
        currentY += itemHeight;
        if (currentY + itemHeight > maxY) {
          currentY = startY;
          currentX += itemWidth;
        }
        _preferences?.setIconPosition(item.id, pos.dx, pos.dy);
        return item.copyWith(position: pos);
      }).toList(growable: true);
    });
  }

  void _reconcileDesktopIcons(Size currentSize) {
    if (currentSize.width <= 0 || currentSize.height <= 0) return;
    final maxX = (currentSize.width - 90.0).clamp(10.0, double.infinity);
    final maxY = (currentSize.height - 130.0).clamp(10.0, double.infinity);
    bool changed = false;
    final updated = desktopItems.map((item) {
      if (item.position.dx > maxX || item.position.dy > maxY) {
        changed = true;
        final clamped = Offset(
          item.position.dx.clamp(10.0, maxX),
          item.position.dy.clamp(10.0, maxY),
        );
        _preferences?.setIconPosition(item.id, clamped.dx, clamped.dy);
        return item.copyWith(position: clamped);
      }
      return item;
    }).toList();
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => desktopItems = updated);
      });
    }
  }

  Future<void> _promptCreateNewFolder(Offset position) async {
    final defaultName = _customFolderCounter == 1 ? 'Nova Pasta' : 'Nova Pasta $_customFolderCounter';
    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.create_new_folder_rounded, color: CloudOSColors.accent, size: 22),
            SizedBox(width: 8),
            Text('Criar Nova Pasta', style: TextStyle(color: CloudOSColors.text, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Digite o nome da pasta na Área de Trabalho:',
              style: TextStyle(color: CloudOSColors.secondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('new-folder-name-input'),
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: CloudOSColors.text, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: CloudOSColors.elevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: CloudOSColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: CloudOSColors.accent),
                ),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          FilledButton(
            key: const ValueKey<String>('new-folder-submit-btn'),
            style: FilledButton.styleFrom(backgroundColor: CloudOSColors.accent),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Criar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      _customFolderCounter++;
      final size = MediaQuery.of(context).size;
      final clampedX = position.dx.clamp(20.0, (size.width - 90.0).clamp(20.0, double.infinity));
      final clampedY = position.dy.clamp(20.0, (size.height - 130.0).clamp(20.0, double.infinity));
      setState(() {
        desktopItems = <DesktopItemData>[
          ...desktopItems,
          DesktopItemData(
            id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
            label: name,
            icon: Icons.folder_rounded,
            color: const Color(0xFFF6AD55),
            position: Offset(clampedX, clampedY),
            isCustomFolder: true,
          ),
        ];
      });
    }
  }

  Future<void> _promptCreateNewFile(Offset position) async {
    final controller = TextEditingController(text: 'Novo Documento.txt');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.note_add_rounded, color: CloudOSColors.accent, size: 22),
            SizedBox(width: 8),
            Text('Novo Arquivo de Texto', style: TextStyle(color: CloudOSColors.text, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Digite o nome do arquivo:',
              style: TextStyle(color: CloudOSColors.secondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('new-file-name-input'),
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: CloudOSColors.text, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: CloudOSColors.elevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: CloudOSColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: CloudOSColors.accent),
                ),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          FilledButton(
            key: const ValueKey<String>('new-file-submit-btn'),
            style: FilledButton.styleFrom(backgroundColor: CloudOSColors.accent),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Criar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      final size = MediaQuery.of(context).size;
      final clampedX = position.dx.clamp(20.0, (size.width - 90.0).clamp(20.0, double.infinity));
      final clampedY = position.dy.clamp(20.0, (size.height - 130.0).clamp(20.0, double.infinity));
      setState(() {
        desktopItems = <DesktopItemData>[
          ...desktopItems,
          DesktopItemData(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}',
            label: name,
            icon: Icons.description_rounded,
            color: CloudOSColors.secondary,
            position: Offset(clampedX, clampedY),
            isCustomFile: true,
          ),
        ];
      });
    }
  }

  void _showDesktopItemContextMenu(DesktopItemData item, Offset position) {
    _closeTransientPanels();
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF141C2B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: CloudOSColors.border),
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: <Widget>[
              Icon(Icons.open_in_new_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Text('Abrir', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
        if (item.isCustomFolder || item.isCustomFile) ...<PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'rename',
            child: Row(
              children: <Widget>[
                Icon(Icons.edit_rounded, size: 16, color: CloudOSColors.secondary),
                SizedBox(width: 10),
                Text('Renomear', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: <Widget>[
                Icon(Icons.delete_outline_rounded, size: 16, color: CloudOSColors.danger),
                SizedBox(width: 10),
                Text('Excluir', style: TextStyle(color: CloudOSColors.danger, fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    ).then((choice) {
      if (choice == 'open') _handleDesktopItemAction(item);
      if (choice == 'rename') _renameDesktopItem(item);
      if (choice == 'delete') {
        setState(() {
          desktopItems.removeWhere((i) => i.id == item.id);
          if (selectedDesktopIcon == item.id) selectedDesktopIcon = null;
        });
      }
    });
  }

  Future<void> _renameDesktopItem(DesktopItemData item) async {
    final controller = TextEditingController(text: item.label);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Text('Renomear Item', style: TextStyle(color: CloudOSColors.text, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: CloudOSColors.text, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: CloudOSColors.elevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: CloudOSColors.border),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CloudOSColors.accent),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty) {
      setState(() {
        desktopItems = desktopItems.map((i) {
          if (i.id == item.id) return i.copyWith(label: newName);
          return i;
        }).toList(growable: true);
      });
    }
  }

  void _showDesktopContextMenu(BuildContext context, Offset position) {
    _closeTransientPanels();
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF141C2B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: CloudOSColors.border),
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'new_folder',
          child: Row(
            children: <Widget>[
              Icon(Icons.create_new_folder_rounded, size: 16, color: Color(0xFFF6AD55)),
              SizedBox(width: 10),
              Expanded(
                child: Text('Nova Pasta', style: TextStyle(color: CloudOSColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_file',
          child: Row(
            children: <Widget>[
              Icon(Icons.note_add_rounded, size: 16, color: CloudOSColors.secondary),
              SizedBox(width: 10),
              Expanded(
                child: Text('Novo Arquivo de Texto', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'organize',
          child: Row(
            children: <Widget>[
              Icon(Icons.grid_view_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Organizar Ícones', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'terminal',
          child: Row(
            children: <Widget>[
              Icon(Icons.terminal_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Abrir Terminal', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'notes',
          child: Row(
            children: <Widget>[
              Icon(Icons.description_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Nova Anotação', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'calculator',
          child: Row(
            children: <Widget>[
              Icon(Icons.calculate_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Calculadora', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'task_manager',
          child: Row(
            children: <Widget>[
              Icon(Icons.monitor_heart_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Monitor de Sistema', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'spotlight',
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Central de Comando', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: <Widget>[
              Icon(Icons.settings_rounded, size: 16, color: CloudOSColors.text),
              SizedBox(width: 10),
              Expanded(
                child: Text('Configurações', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    ).then((choice) {
      if (choice == 'new_folder') _promptCreateNewFolder(position);
      if (choice == 'new_file') _promptCreateNewFile(position);
      if (choice == 'organize') _organizeDesktopIcons();
      if (choice == 'terminal') _toggleOrFocusWindow('terminal');
      if (choice == 'notes') _toggleOrFocusWindow('notes');
      if (choice == 'calculator') _toggleOrFocusWindow('calculator');
      if (choice == 'task_manager') _toggleOrFocusWindow('task_manager');
      if (choice == 'spotlight') _toggleSpotlight();
      if (choice == 'settings') _toggleOrFocusWindow('settings');
    });
  }

  List<Widget> _buildInternalWindows(BoxConstraints constraints, CloudLayoutMetrics metrics) {
    final entries = <_WindowRenderEntry>[];

    if (filesOpen && !filesMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: filesZIndex,
          widget: Positioned(
            left: filesMaximized ? 0 : filesOffset.dx,
            top: filesMaximized ? 0 : filesOffset.dy,
            width: filesMaximized ? metrics.workAreaWidth : filesSize.width,
            height: filesMaximized ? metrics.workAreaHeight : filesSize.height,
            child: CloudWindowFrame(
              window: CloudWindow(
                id: 'files',
                title: filesRootId == 'home' ? 'Arquivos • Início' : 'Arquivos',
                icon: Icons.folder_rounded,
                type: CloudWindowType.files,
                position: filesOffset,
                size: filesSize,
                isMaximized: filesMaximized,
              ),
              onFocus: () => _focusWindow('files'),
              onClose: () => _closeWindow('files'),
              onMinimize: () => setState(() => filesMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('files', constraints),
              onSnapLeft: () => _snapWindowLeft('files', constraints),
              onSnapRight: () => _snapWindowRight('files', constraints),
              onMove: (delta) => _moveWindow('files', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'files',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
              child: FilesWindow(
                key: ValueKey<String>('files:$filesRootId:$filesLaunchRevision'),
                bridge: widget.bridge,
                initialRootId: filesRootId,
                onClose: () => _closeWindow('files'),
                onMinimize: () => setState(() => filesMinimized = true),
              ),
            ),
          ),
        ),
      );
    }

    if (terminalOpen) {
      entries.add(
        _WindowRenderEntry(
          zIndex: terminalZIndex,
          widget: Positioned(
            left: terminalMaximized ? 0 : terminalOffset.dx,
            top: terminalMaximized ? 0 : terminalOffset.dy,
            width: terminalMaximized ? metrics.workAreaWidth : terminalSize.width,
            height: terminalMaximized ? metrics.workAreaHeight : terminalSize.height,
            child: Offstage(
              offstage: terminalMinimized,
              child: CloudWindowFrame(
              window: CloudWindow(
                id: 'terminal',
                title: 'Terminal CloudOS (ConPTY)',
                icon: Icons.terminal_rounded,
                type: CloudWindowType.terminal,
                position: terminalOffset,
                size: terminalSize,
                isMaximized: terminalMaximized,
              ),
              onFocus: () => _focusWindow('terminal'),
              onClose: () => _closeWindow('terminal'),
              onMinimize: () => setState(() => terminalMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('terminal', constraints),
              onSnapLeft: () => _snapWindowLeft('terminal', constraints),
              onSnapRight: () => _snapWindowRight('terminal', constraints),
              onMove: (delta) => _moveWindow('terminal', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'terminal',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
                child: TerminalWindow(
                  bridge: widget.bridge,
                  isActive: activeInternalWindowId == 'terminal',
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (browserOpen) {
      entries.add(
        _WindowRenderEntry(
          zIndex: browserZIndex,
          widget: Positioned(
            left: browserMaximized ? 0 : browserOffset.dx,
            top: browserMaximized ? 0 : browserOffset.dy,
            width: browserMaximized ? metrics.workAreaWidth : browserSize.width,
            height: browserMaximized ? metrics.workAreaHeight : browserSize.height,
            child: Offstage(
              offstage: browserMinimized,
              child: CloudWindowFrame(
              window: CloudWindow(
                id: 'browser',
                title: 'Navegador Web (WebView2)',
                icon: Icons.public_rounded,
                type: CloudWindowType.browser,
                position: browserOffset,
                size: browserSize,
                isMaximized: browserMaximized,
              ),
              onFocus: () => _focusWindow('browser'),
              onClose: () => _closeWindow('browser'),
              onMinimize: () => setState(() => browserMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('browser', constraints),
              onSnapLeft: () => _snapWindowLeft('browser', constraints),
              onSnapRight: () => _snapWindowRight('browser', constraints),
              onMove: (delta) => _moveWindow('browser', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'browser',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
                child: const BrowserWindow(),
              ),
            ),
          ),
        ),
      );
    }

    if (settingsOpen && !settingsMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: settingsZIndex,
          widget: Positioned(
            left: settingsMaximized ? 0 : settingsOffset.dx,
            top: settingsMaximized ? 0 : settingsOffset.dy,
            width: settingsMaximized ? metrics.workAreaWidth : settingsSize.width,
            height: settingsMaximized ? metrics.workAreaHeight : settingsSize.height,
            child: CloudWindowFrame(
              window: CloudWindow(
                id: 'settings',
                title: 'Configurações do CloudOS',
                icon: Icons.settings_rounded,
                type: CloudWindowType.settings,
                position: settingsOffset,
                size: settingsSize,
                isMaximized: settingsMaximized,
              ),
              onFocus: () => _focusWindow('settings'),
              onClose: () => _closeWindow('settings'),
              onMinimize: () => setState(() => settingsMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('settings', constraints),
              onSnapLeft: () => _snapWindowLeft('settings', constraints),
              onSnapRight: () => _snapWindowRight('settings', constraints),
              onMove: (delta) => _moveWindow('settings', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'settings',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
              child: SettingsWindow(
                snapshot: snapshot,
                bridge: widget.bridge,
                initialSection: settingsSection,
              ),
            ),
          ),
        ),
      );
    }

    if (notesOpen && !notesMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: notesZIndex,
          widget: Positioned(
            left: notesMaximized ? 0 : notesOffset.dx,
            top: notesMaximized ? 0 : notesOffset.dy,
            width: notesMaximized ? metrics.workAreaWidth : notesSize.width,
            height: notesMaximized ? metrics.workAreaHeight : notesSize.height,
            child: CloudWindowFrame(
              window: CloudWindow(
                id: 'notes',
                title: 'CloudOS Notes',
                icon: Icons.description_rounded,
                type: CloudWindowType.notes,
                position: notesOffset,
                size: notesSize,
                isMaximized: notesMaximized,
              ),
              onFocus: () => _focusWindow('notes'),
              onClose: () => _closeWindow('notes'),
              onMinimize: () => setState(() => notesMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('notes', constraints),
              onSnapLeft: () => _snapWindowLeft('notes', constraints),
              onSnapRight: () => _snapWindowRight('notes', constraints),
              onMove: (delta) => _moveWindow('notes', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'notes',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
              child: const NotesWindow(),
            ),
          ),
        ),
      );
    }

    if (calculatorOpen && !calculatorMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: calculatorZIndex,
          widget: Positioned(
            left: calculatorMaximized ? 0 : calculatorOffset.dx,
            top: calculatorMaximized ? 0 : calculatorOffset.dy,
            width: calculatorMaximized ? metrics.workAreaWidth : calculatorSize.width,
            height: calculatorMaximized ? metrics.workAreaHeight : calculatorSize.height,
            child: CloudWindowFrame(
              window: CloudWindow(
                id: 'calculator',
                title: 'Calculadora',
                icon: Icons.calculate_rounded,
                type: CloudWindowType.calculator,
                position: calculatorOffset,
                size: calculatorSize,
                isMaximized: calculatorMaximized,
              ),
              onFocus: () => _focusWindow('calculator'),
              onClose: () => _closeWindow('calculator'),
              onMinimize: () => setState(() => calculatorMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('calculator', constraints),
              onSnapLeft: () => _snapWindowLeft('calculator', constraints),
              onSnapRight: () => _snapWindowRight('calculator', constraints),
              onMove: (delta) => _moveWindow('calculator', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'calculator',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
              child: const CalculatorWindow(),
            ),
          ),
        ),
      );
    }

    if (taskManagerOpen && !taskManagerMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: taskManagerZIndex,
          widget: Positioned(
            left: taskManagerMaximized ? 0 : taskManagerOffset.dx,
            top: taskManagerMaximized ? 0 : taskManagerOffset.dy,
            width: taskManagerMaximized ? metrics.workAreaWidth : taskManagerSize.width,
            height: taskManagerMaximized ? metrics.workAreaHeight : taskManagerSize.height,
            child: CloudWindowFrame(
              window: CloudWindow(
                id: 'task_manager',
                title: 'Monitor de Sistema',
                icon: Icons.monitor_heart_rounded,
                type: CloudWindowType.taskManager,
                position: taskManagerOffset,
                size: taskManagerSize,
                isMaximized: taskManagerMaximized,
              ),
              onFocus: () => _focusWindow('task_manager'),
              onClose: () => _closeWindow('task_manager'),
              onMinimize: () => setState(() => taskManagerMinimized = true),
              onToggleMaximize: () =>
                  _toggleMaximizeWindow('task_manager', constraints),
              onSnapLeft: () => _snapWindowLeft('task_manager', constraints),
              onSnapRight: () => _snapWindowRight('task_manager', constraints),
              onMove: (delta) => _moveWindow('task_manager', delta, constraints),
              onResize: (delta, left, top, right, bottom) => _resizeWindow(
                'task_manager',
                delta,
                left,
                top,
                right,
                bottom,
                constraints,
              ),
              child: TaskManagerWindow(
                snapshot: snapshot,
                runningApps: _startRunningApps,
                onSwitchToApp: (id) => _toggleOrFocusWindow(id),
                onCloseApp: (id) => _closeWindow(id),
                bridge: widget.bridge,
              ),
            ),
          ),
        ),
      );
    }

    entries.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return entries.map((e) => e.widget).toList(growable: false);
  }

  Widget _buildAltTabOverlay() {
    final list = _getUnifiedWindows();
    if (list.isEmpty) return const SizedBox.shrink();

    return AltTabSwitcher(
      windows: list,
      selectedIndex: altTabSelectedIndex.clamp(0, list.length - 1),
      onSelect: (index) {
        if (index < list.length) {
          final target = list[index];
          if (target.platform != 'cloudos' && target.hwnd != 0) {
            unawaited(widget.bridge.focusWindow(target.hwnd));
          } else {
            _focusWindow(target.id);
          }
        }
        setState(() => altTabOpen = false);
      },
    );
  }

  Widget _panelSwitcher() {
    Widget child = const SizedBox.shrink(key: ValueKey<String>('none'));
    if (startOpen) {
      final displayApps = apps.map((app) {
        final isPinned = _preferences?.isAppPinned(app.id) ?? app.isPinned;
        final isRecent = _preferences?.isAppRecent(app.id) ?? app.isRecent;
        return app.copyWith(isPinned: isPinned, isRecent: isRecent);
      }).toList();

      child = StartPanel(
        key: const ValueKey<String>('start'),
        apps: displayApps,
        onLaunch: _launchApp,
        runningApps: _startRunningApps,
        onActivateWindow: _activateWindowFromStart,
        onCloseWindow: _closeWindowFromStart,
        onClose: () => setState(() => startOpen = false),
        onLockSession: () {
          unawaited(widget.bridge.lockSystem());
          setState(_closeTransientPanels);
        },
        onPowerOptions: () => _openSettingsSection(SettingsSection.power),
        onPinToggle: (app) {
          _preferences?.togglePin(app.id);
          setState(() {});
        },
      );
    } else if (quickSettingsOpen) {
      child = QuickSettingsPanel(
        key: const ValueKey<String>('quick-settings'),
        snapshot: snapshot,
        performanceProfile: performanceProfile,
        onSetPerformanceProfile: _setPerformanceProfile,
        onSetVolume: widget.bridge.setVolume,
        onSetBrightness: widget.bridge.setBrightness,
        onOpenSettings: () => _toggleOrFocusWindow('settings'),
        onOpenNetworkSettings: () =>
            _openQuickSettingsRoute(QuickSettingsRoute.wifi),
        onOpenBluetoothSettings: () =>
            _openQuickSettingsRoute(QuickSettingsRoute.bluetooth),
        onOpenNightLightSettings: () =>
            _openQuickSettingsRoute(QuickSettingsRoute.nightLight),
        onOpenFocusSettings: () =>
            _openQuickSettingsRoute(QuickSettingsRoute.focus),
      );
    } else if (notificationsOpen) {
      child = NotificationCenterPanel(
        key: const ValueKey<String>('notifications'),
        notifications: notificationState.items,
        onDismiss: _dismissNotification,
        onClearAll: _clearNotifications,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }

  bool _sameSystemSnapshot(CloudSystemSnapshot a, CloudSystemSnapshot b) {
    if (identical(a, b)) return true;
    if (a.deviceName != b.deviceName ||
        a.networkAvailable != b.networkAvailable ||
        a.networkName != b.networkName ||
        a.volumeAvailable != b.volumeAvailable ||
        a.volume != b.volume ||
        a.brightnessAvailable != b.brightnessAvailable ||
        a.brightness != b.brightness ||
        a.batteryAvailable != b.batteryAvailable ||
        a.batteryPercent != b.batteryPercent ||
        a.wslAvailable != b.wslAvailable ||
        a.currentWorkspace != b.currentWorkspace ||
        a.distros.length != b.distros.length) {
      return false;
    }
    for (var i = 0; i < a.distros.length; i++) {
      if (a.distros[i] != b.distros[i]) return false;
    }
    return true;
  }

  bool _sameNotificationState(
    CloudNotificationState a,
    CloudNotificationState b,
  ) {
    if (identical(a, b)) return true;
    return a.revision == b.revision &&
        a.unreadCount == b.unreadCount &&
        a.items.length == b.items.length;
  }
}

class _WindowRenderEntry {
  const _WindowRenderEntry({required this.zIndex, required this.widget});
  final int zIndex;
  final Widget widget;
}
