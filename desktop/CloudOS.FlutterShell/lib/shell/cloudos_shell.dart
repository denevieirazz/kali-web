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
import '../features/terminal/presentation/terminal_window.dart';
import '../features/calculator/presentation/calculator_window.dart';
import '../features/notes/presentation/notes_window.dart';
import '../features/spotlight/domain/spotlight_item.dart';
import '../features/spotlight/presentation/spotlight_palette.dart';
import '../features/task_manager/presentation/task_manager_window.dart';
import '../models/cloud_app.dart';
import '../models/cloud_notification.dart';
import '../models/cloud_system_snapshot.dart';
import '../services/cloudos_bridge.dart';
import 'shell_app_route.dart';
import 'widgets/desktop_icons.dart';
import 'widgets/desktop_status.dart';
import 'widgets/desktop_wallpaper.dart';
import 'window_manager/alt_tab_switcher.dart';
import 'window_manager/cloud_window.dart';
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

class _CloudOSShellState extends State<CloudOSShell> {
  List<CloudApp> apps = const <CloudApp>[];
  CloudSystemSnapshot snapshot = CloudOSBridge.degradedSnapshot;
  CloudNotificationState notificationState = CloudNotificationState.empty;
  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool spotlightOpen = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;

  // Window Manager States
  bool filesOpen = true;
  bool filesMinimized = false;
  bool filesMaximized = false;
  Offset filesOffset = const Offset(120, 50);
  Size filesSize = const Size(960, 600);
  Offset? filesPreMaxOffset;
  Size? filesPreMaxSize;
  int filesZIndex = 1;

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

  Timer? _shellStateTimer;
  bool _shellStateRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBridgeData());
  }

  @override
  void dispose() {
    _shellStateTimer?.cancel();
    _shellStateTimer = null;
    super.dispose();
  }

  Future<void> _loadBridgeData() async {
    final loadedApps = await widget.bridge.tryLoadApps();
    final loadedSnapshot = await widget.bridge.tryLoadSystemSnapshot();
    final loadedNotifications = await widget.bridge.tryLoadNotificationState();
    final surfaceStates = await widget.bridge.tryLoadShellSurfaceStates();
    final nativeWorkspace = await widget.bridge.getCurrentWorkspace();
    if (!mounted) return;

    setState(() {
      if (loadedApps != null) apps = loadedApps;
      if (loadedSnapshot != null) snapshot = loadedSnapshot;
      if (loadedNotifications != null) notificationState = loadedNotifications;
      if (surfaceStates != null) {
        if (surfaceStates['browser'] == true) browserOpen = true;
        if (surfaceStates['terminal'] == true) terminalOpen = true;
      }
      currentWorkspace = nativeWorkspace ??
          loadedSnapshot?.currentWorkspace.clamp(1, 4).toInt() ??
          currentWorkspace;
    });

    _shellStateTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshNativeShellState()),
    );
  }

  Future<void> _refreshNativeShellState() async {
    if (_shellStateRefreshInFlight) return;
    _shellStateRefreshInFlight = true;
    try {
      final recoveredApps = apps.isEmpty ? await widget.bridge.tryLoadApps() : null;
      final nativeSnapshot = await widget.bridge.tryLoadSystemSnapshot();
      final nativeWorkspace = await widget.bridge.getCurrentWorkspace();
      final nativeNotifications = await widget.bridge.tryLoadNotificationState();
      if (!mounted) return;

      final nextSnapshot = nativeSnapshot ?? snapshot;
      final nextWorkspace = nativeWorkspace ??
          nativeSnapshot?.currentWorkspace.clamp(1, 4).toInt() ??
          currentWorkspace;
      final nextNotifications = nativeNotifications != null &&
              nativeNotifications.revision >= notificationState.revision
          ? nativeNotifications
          : notificationState;

      if (recoveredApps == null &&
          _sameSystemSnapshot(nextSnapshot, snapshot) &&
          nextWorkspace == currentWorkspace &&
          _sameNotificationState(nextNotifications, notificationState)) {
        return;
      }

      setState(() {
        if (recoveredApps != null) apps = recoveredApps;
        snapshot = nextSnapshot;
        currentWorkspace = nextWorkspace;
        notificationState = nextNotifications;
      });
    } finally {
      _shellStateRefreshInFlight = false;
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
    setState(() {
      final next = !startOpen;
      _closeTransientPanels();
      startOpen = next;
    });
  }

  void _toggleSpotlight() {
    setState(() {
      final next = !spotlightOpen;
      _closeTransientPanels();
      spotlightOpen = next;
    });
  }

  void _toggleQuickSettings() {
    setState(() {
      final next = !quickSettingsOpen;
      _closeTransientPanels();
      quickSettingsOpen = next;
    });
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
            appIds: const <String>{'files', 'cloudos:files'},
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
      ];

  void _toggleMaximizeWindow(String id, BoxConstraints constraints) {
    setState(() {
      final maxAvailableHeight = constraints.maxHeight - 56.0;
      final maxAvailableWidth = constraints.maxWidth;

      if (id == 'files') {
        if (filesMaximized) {
          filesOffset = filesPreMaxOffset ?? const Offset(120, 50);
          filesSize = filesPreMaxSize ?? const Size(960, 600);
          filesMaximized = false;
        } else {
          filesPreMaxOffset = filesOffset;
          filesPreMaxSize = filesSize;
          filesOffset = Offset.zero;
          filesSize = Size(maxAvailableWidth, maxAvailableHeight);
          filesMaximized = true;
        }
      } else if (id == 'terminal') {
        if (terminalMaximized) {
          terminalOffset = terminalPreMaxOffset ?? const Offset(180, 80);
          terminalSize = terminalPreMaxSize ?? const Size(780, 480);
          terminalMaximized = false;
        } else {
          terminalPreMaxOffset = terminalOffset;
          terminalPreMaxSize = terminalSize;
          terminalOffset = Offset.zero;
          terminalSize = Size(maxAvailableWidth, maxAvailableHeight);
          terminalMaximized = true;
        }
      } else if (id == 'browser') {
        if (browserMaximized) {
          browserOffset = browserPreMaxOffset ?? const Offset(150, 70);
          browserSize = browserPreMaxSize ?? const Size(880, 540);
          browserMaximized = false;
        } else {
          browserPreMaxOffset = browserOffset;
          browserPreMaxSize = browserSize;
          browserOffset = Offset.zero;
          browserSize = Size(maxAvailableWidth, maxAvailableHeight);
          browserMaximized = true;
        }
      } else if (id == 'settings') {
        if (settingsMaximized) {
          settingsOffset = settingsPreMaxOffset ?? const Offset(210, 90);
          settingsSize = settingsPreMaxSize ?? const Size(760, 500);
          settingsMaximized = false;
        } else {
          settingsPreMaxOffset = settingsOffset;
          settingsPreMaxSize = settingsSize;
          settingsOffset = Offset.zero;
          settingsSize = Size(maxAvailableWidth, maxAvailableHeight);
          settingsMaximized = true;
        }
      } else if (id == 'notes') {
        if (notesMaximized) {
          notesOffset = notesPreMaxOffset ?? const Offset(240, 110);
          notesSize = notesPreMaxSize ?? const Size(780, 520);
          notesMaximized = false;
        } else {
          notesPreMaxOffset = notesOffset;
          notesPreMaxSize = notesSize;
          notesOffset = Offset.zero;
          notesSize = Size(maxAvailableWidth, maxAvailableHeight);
          notesMaximized = true;
        }
      } else if (id == 'calculator') {
        if (calculatorMaximized) {
          calculatorOffset = calculatorPreMaxOffset ?? const Offset(280, 130);
          calculatorSize = calculatorPreMaxSize ?? const Size(540, 480);
          calculatorMaximized = false;
        } else {
          calculatorPreMaxOffset = calculatorOffset;
          calculatorPreMaxSize = calculatorSize;
          calculatorOffset = Offset.zero;
          calculatorSize = Size(maxAvailableWidth, maxAvailableHeight);
          calculatorMaximized = true;
        }
      } else if (id == 'task_manager') {
        if (taskManagerMaximized) {
          taskManagerOffset = taskManagerPreMaxOffset ?? const Offset(200, 100);
          taskManagerSize = taskManagerPreMaxSize ?? const Size(720, 480);
          taskManagerMaximized = false;
        } else {
          taskManagerPreMaxOffset = taskManagerOffset;
          taskManagerPreMaxSize = taskManagerSize;
          taskManagerOffset = Offset.zero;
          taskManagerSize = Size(maxAvailableWidth, maxAvailableHeight);
          taskManagerMaximized = true;
        }
      }
      _focusWindow(id);
    });
  }

  void _snapWindowLeft(String id, BoxConstraints constraints) {
    setState(() {
      final availableHeight = constraints.maxHeight - 56.0;
      final halfWidth = constraints.maxWidth / 2.0;

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
    final openList = <String>[];
    if (filesOpen) openList.add('files');
    if (terminalOpen) openList.add('terminal');
    if (browserOpen) openList.add('browser');
    if (settingsOpen) openList.add('settings');
    if (notesOpen) openList.add('notes');
    if (calculatorOpen) openList.add('calculator');
    if (taskManagerOpen) openList.add('task_manager');

    if (openList.isEmpty) return;

    setState(() {
      altTabOpen = true;
      altTabSelectedIndex = (altTabSelectedIndex + 1) % openList.length;
    });
  }

  void _confirmAltTab() {
    final openList = <String>[];
    if (filesOpen) openList.add('files');
    if (terminalOpen) openList.add('terminal');
    if (browserOpen) openList.add('browser');
    if (settingsOpen) openList.add('settings');
    if (notesOpen) openList.add('notes');
    if (calculatorOpen) openList.add('calculator');
    if (taskManagerOpen) openList.add('task_manager');

    if (openList.isNotEmpty && altTabSelectedIndex < openList.length) {
      _focusWindow(openList[altTabSelectedIndex]);
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

  Future<void> _openQuickSettingsRoute(QuickSettingsRoute route) async {
    final launched = await widget.bridge.launchApp(quickSettingsLaunchId(route));
    if (!mounted || !launched) return;
    setState(_closeTransientPanels);
  }

  Future<void> _launchApp(CloudApp app) async {
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

    if (app.id == 'settings' || app.id == 'cloudos:settings') {
      _toggleOrFocusWindow('settings');
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

    // External Windows Application (VS Code, Notepad, etc.)
    await widget.bridge.launchApp(app.id);
    if (!mounted) return;
    setState(_closeTransientPanels);
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
              return GestureDetector(
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
                    Positioned(
                      left: 20,
                      top: 20,
                      child: RepaintBoundary(
                        child: DesktopIcons(
                          selectedId: selectedDesktopIcon,
                          onSelect: (id) =>
                              setState(() => selectedDesktopIcon = id),
                          onFiles: () => _toggleOrFocusWindow('files'),
                          onStart: _toggleStart,
                          onTerminal: () => _toggleOrFocusWindow('terminal'),
                          onOpenSettings: () => _toggleOrFocusWindow('settings'),
                        ),
                      ),
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
                    ..._buildInternalWindows(constraints),
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
                      onQuickSettings: _toggleQuickSettings,
                      onNotifications: _toggleNotifications,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
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
          value: 'terminal',
          child: Row(
            children: <Widget>[
              Icon(Icons.terminal_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Text('Abrir Terminal', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'notes',
          child: Row(
            children: <Widget>[
              Icon(Icons.description_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Text('Nova Anotação', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'calculator',
          child: Row(
            children: <Widget>[
              Icon(Icons.calculate_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Text('Calculadora', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'task_manager',
          child: Row(
            children: <Widget>[
              Icon(Icons.monitor_heart_rounded, size: 16, color: CloudOSColors.accent),
              SizedBox(width: 10),
              Text('Monitor de Sistema', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
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
              Text('Central de Comando (Alt+Espaço)', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: <Widget>[
              Icon(Icons.settings_rounded, size: 16, color: CloudOSColors.text),
              SizedBox(width: 10),
              Text('Configurações', style: TextStyle(color: CloudOSColors.text, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((choice) {
      if (choice == 'terminal') _toggleOrFocusWindow('terminal');
      if (choice == 'notes') _toggleOrFocusWindow('notes');
      if (choice == 'calculator') _toggleOrFocusWindow('calculator');
      if (choice == 'task_manager') _toggleOrFocusWindow('task_manager');
      if (choice == 'spotlight') _toggleSpotlight();
      if (choice == 'settings') _toggleOrFocusWindow('settings');
    });
  }

  List<Widget> _buildInternalWindows(BoxConstraints constraints) {
    final entries = <_WindowRenderEntry>[];

    if (filesOpen && !filesMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: filesZIndex,
          widget: Positioned(
            left: filesMaximized ? 0 : filesOffset.dx,
            top: filesMaximized ? 0 : filesOffset.dy,
            width: filesMaximized ? constraints.maxWidth : filesSize.width,
            height: filesMaximized ? constraints.maxHeight - 56.0 : filesSize.height,
            child: Listener(
              onPointerDown: (_) => _focusWindow('files'),
              child: FilesWindow(
                bridge: widget.bridge,
                onClose: () => _closeWindow('files'),
                onMinimize: () => setState(() => filesMinimized = true),
                onDrag: (delta) => _moveWindow('files', delta, constraints),
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
            width: terminalMaximized ? constraints.maxWidth : terminalSize.width,
            height: terminalMaximized ? constraints.maxHeight - 56.0 : terminalSize.height,
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
            width: browserMaximized ? constraints.maxWidth : browserSize.width,
            height: browserMaximized ? constraints.maxHeight - 56.0 : browserSize.height,
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
            width: settingsMaximized ? constraints.maxWidth : settingsSize.width,
            height: settingsMaximized ? constraints.maxHeight - 56.0 : settingsSize.height,
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
            width: notesMaximized ? constraints.maxWidth : notesSize.width,
            height: notesMaximized ? constraints.maxHeight - 56.0 : notesSize.height,
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
            width: calculatorMaximized ? constraints.maxWidth : calculatorSize.width,
            height: calculatorMaximized ? constraints.maxHeight - 56.0 : calculatorSize.height,
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
            width: taskManagerMaximized ? constraints.maxWidth : taskManagerSize.width,
            height: taskManagerMaximized ? constraints.maxHeight - 56.0 : taskManagerSize.height,
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
        ),
      );
    }
    if (notesOpen) {
      list.add(
        CloudWindow(
          id: 'notes',
          title: 'CloudOS Notes',
          icon: Icons.description_rounded,
          type: CloudWindowType.notes,
          position: notesOffset,
          size: notesSize,
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
        ),
      );
    }
    if (taskManagerOpen) {
      list.add(
        CloudWindow(
          id: 'task_manager',
          title: 'Monitor de Sistema',
          icon: Icons.monitor_heart_rounded,
          type: CloudWindowType.taskManager,
          position: taskManagerOffset,
          size: taskManagerSize,
        ),
      );
    }

    return AltTabSwitcher(
      windows: list,
      selectedIndex: altTabSelectedIndex.clamp(0, list.isEmpty ? 0 : list.length - 1),
      onSelect: (index) {
        if (index < list.length) {
          _focusWindow(list[index].id);
        }
        setState(() => altTabOpen = false);
      },
    );
  }

  Widget _panelSwitcher() {
    Widget child = const SizedBox.shrink(key: ValueKey<String>('none'));
    if (startOpen) {
      child = StartPanel(
        key: const ValueKey<String>('start'),
        apps: apps,
        onLaunch: _launchApp,
        runningApps: _startRunningApps,
        onActivateWindow: _focusWindow,
        onCloseWindow: _closeWindow,
        onClose: () => setState(() => startOpen = false),
      );
    } else if (quickSettingsOpen) {
      child = QuickSettingsPanel(
        key: const ValueKey<String>('quick-settings'),
        snapshot: snapshot,
        onSetVolume: widget.bridge.setVolume,
        onSetBrightness: widget.bridge.setBrightness,
        onOpenSettings: () => _toggleOrFocusWindow('settings'),
        onOpenNetworkSettings: () => unawaited(
          _openQuickSettingsRoute(QuickSettingsRoute.wifi),
        ),
        onOpenBluetoothSettings: () => unawaited(
          _openQuickSettingsRoute(QuickSettingsRoute.bluetooth),
        ),
        onOpenNightLightSettings: () => unawaited(
          _openQuickSettingsRoute(QuickSettingsRoute.nightLight),
        ),
        onOpenFocusSettings: () => unawaited(
          _openQuickSettingsRoute(QuickSettingsRoute.focus),
        ),
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
