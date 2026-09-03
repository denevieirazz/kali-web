import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/browser/presentation/browser_window.dart';
import '../features/files/presentation/files_window.dart';
import '../features/notifications/presentation/notification_center_panel.dart';
import '../features/quick_settings/domain/quick_settings_route.dart';
import '../features/quick_settings/presentation/quick_settings_panel.dart';
import '../features/settings/presentation/settings_window.dart';
import '../features/start/presentation/start_panel.dart';
import '../features/taskbar/presentation/cloud_taskbar.dart';
import '../features/terminal/presentation/terminal_window.dart';
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

  bool terminalOpen = false;
  bool terminalMinimized = false;
  bool terminalMaximized = false;
  Offset terminalOffset = const Offset(180, 80);
  Size terminalSize = const Size(780, 480);
  Offset? terminalPreMaxOffset;
  Size? terminalPreMaxSize;
  int terminalZIndex = 2;

  bool browserOpen = false;
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

  int topZIndex = 5;
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
  }

  void _toggleStart() {
    setState(() {
      final next = !startOpen;
      _closeTransientPanels();
      startOpen = next;
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
      }
      _closeTransientPanels();
    });
  }

  void _closeWindow(String id) {
    setState(() {
      if (id == 'files') filesOpen = false;
      if (id == 'terminal') terminalOpen = false;
      if (id == 'browser') browserOpen = false;
      if (id == 'settings') settingsOpen = false;
      if (activeInternalWindowId == id) {
        activeInternalWindowId = null;
      }
    });
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
      }
    });
  }

  void _cycleAltTab() {
    final openList = <String>[];
    if (filesOpen) openList.add('files');
    if (terminalOpen) openList.add('terminal');
    if (browserOpen) openList.add('browser');
    if (settingsOpen) openList.add('settings');

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

    // External Windows Application (VS Code, Notepad, etc.)
    await widget.bridge.launchApp(app.id);
    if (!mounted) return;
    setState(_closeTransientPanels);
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
                      selectedDesktopIcon != null) {
                    setState(() {
                      _closeTransientPanels();
                      selectedDesktopIcon = null;
                    });
                  }
                },
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
                    CloudTaskbar(
                      startOpen: startOpen,
                      quickSettingsOpen: quickSettingsOpen,
                      notificationsOpen: notificationsOpen,
                      filesRunning: filesOpen && !filesMinimized,
                      browserRunning: browserOpen && !browserMinimized,
                      terminalRunning: terminalOpen && !terminalMinimized,
                      currentWorkspace: currentWorkspace,
                      notificationCount: notificationState.unreadCount,
                      onWorkspaceChanged: (index) =>
                          unawaited(_switchWorkspace(index)),
                      onStart: _toggleStart,
                      onFiles: () => _toggleOrFocusWindow('files'),
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

    if (terminalOpen && !terminalMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: terminalZIndex,
          widget: Positioned(
            left: terminalMaximized ? 0 : terminalOffset.dx,
            top: terminalMaximized ? 0 : terminalOffset.dy,
            width: terminalMaximized ? constraints.maxWidth : terminalSize.width,
            height: terminalMaximized ? constraints.maxHeight - 56.0 : terminalSize.height,
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
                snapshot: snapshot,
                bridge: widget.bridge,
              ),
            ),
          ),
        ),
      );
    }

    if (browserOpen && !browserMinimized) {
      entries.add(
        _WindowRenderEntry(
          zIndex: browserZIndex,
          widget: Positioned(
            left: browserMaximized ? 0 : browserOffset.dx,
            top: browserMaximized ? 0 : browserOffset.dy,
            width: browserMaximized ? constraints.maxWidth : browserSize.width,
            height: browserMaximized ? constraints.maxHeight - 56.0 : browserSize.height,
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
