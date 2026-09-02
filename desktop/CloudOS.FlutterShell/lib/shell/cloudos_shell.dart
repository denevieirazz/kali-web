import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/files/presentation/files_window.dart';
import '../features/notifications/presentation/notification_center_panel.dart';
import '../features/quick_settings/domain/quick_settings_route.dart';
import '../features/quick_settings/presentation/quick_settings_panel.dart';
import '../features/start/presentation/start_panel.dart';
import '../features/taskbar/presentation/cloud_taskbar.dart';
import '../models/cloud_app.dart';
import '../models/cloud_notification.dart';
import '../models/cloud_system_snapshot.dart';
import '../services/cloudos_bridge.dart';
import 'shell_app_route.dart';
import 'widgets/desktop_icons.dart';
import 'widgets/desktop_status.dart';
import 'widgets/desktop_wallpaper.dart';

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
  bool filesOpen = true;
  bool browserRunning = false;
  bool terminalRunning = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  Offset filesOffset = const Offset(200, 70);

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
        browserRunning = surfaceStates['browser'] ?? browserRunning;
        terminalRunning = surfaceStates['terminal'] ?? terminalRunning;
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
      final nativeSnapshot = await widget.bridge.tryLoadSystemSnapshot();
      final states = await widget.bridge.tryLoadShellSurfaceStates();
      final nativeWorkspace = await widget.bridge.getCurrentWorkspace();
      final nativeNotifications = await widget.bridge.tryLoadNotificationState();
      if (!mounted) return;

      final nextSnapshot = nativeSnapshot ?? snapshot;
      final nextBrowser = states?['browser'] ?? browserRunning;
      final nextTerminal = states?['terminal'] ?? terminalRunning;
      final nextWorkspace = nativeWorkspace ??
          nativeSnapshot?.currentWorkspace.clamp(1, 4).toInt() ??
          currentWorkspace;
      final nextNotifications = nativeNotifications != null &&
              nativeNotifications.revision >= notificationState.revision
          ? nativeNotifications
          : notificationState;

      if (_sameSystemSnapshot(nextSnapshot, snapshot) &&
          nextBrowser == browserRunning &&
          nextTerminal == terminalRunning &&
          nextWorkspace == currentWorkspace &&
          _sameNotificationState(nextNotifications, notificationState)) {
        return;
      }

      setState(() {
        snapshot = nextSnapshot;
        browserRunning = nextBrowser;
        terminalRunning = nextTerminal;
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

  void _toggleFiles() {
    setState(() {
      filesOpen = !filesOpen;
      _closeTransientPanels();
    });
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
        if (route == ShellAppRoute.browser) browserRunning = true;
        if (route == ShellAppRoute.terminal) terminalRunning = true;
      });
      return;
    }

    final launched = await widget.bridge.launchApp(appId);
    if (!mounted) return;
    setState(() {
      _closeTransientPanels();
      if (route == ShellAppRoute.browser) browserRunning = launched;
      if (route == ShellAppRoute.terminal) terminalRunning = launched;
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
    if (route == ShellAppRoute.files) {
      setState(() {
        filesOpen = true;
        _closeTransientPanels();
      });
      return;
    }

    if (route == ShellAppRoute.browser) {
      final id = app.id == 'browser' ? canonicalLaunchId(route) : app.id;
      await _launchBridgeSurface(id, route);
      return;
    }

    if (route == ShellAppRoute.terminal) {
      await _launchBridgeSurface(app.id, route);
      return;
    }

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
        ): _toggleFiles,
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
              final maxLeft = constraints.maxWidth > 1000
                  ? constraints.maxWidth - 980
                  : 20.0;
              final maxTop = constraints.maxHeight > 700
                  ? constraints.maxHeight - 660
                  : 20.0;
              final safeLeft = filesOffset.dx.clamp(20.0, maxLeft).toDouble();
              final safeTop = filesOffset.dy.clamp(20.0, maxTop).toDouble();

              return GestureDetector(
                onTap: () {
                  if (startOpen ||
                      quickSettingsOpen ||
                      notificationsOpen ||
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
                          onFiles: _toggleFiles,
                          onStart: _toggleStart,
                          onTerminal: _launchTerminal,
                          onOpenSettings: _toggleQuickSettings,
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
                    if (filesOpen)
                      Positioned(
                        left: safeLeft,
                        top: safeTop,
                        child: FilesWindow(
                          onClose: () => setState(() => filesOpen = false),
                          onMinimize: () => setState(() => filesOpen = false),
                          onDrag: (delta) =>
                              setState(() => filesOffset += delta),
                        ),
                      ),
                    _panelSwitcher(),
                    CloudTaskbar(
                      startOpen: startOpen,
                      quickSettingsOpen: quickSettingsOpen,
                      notificationsOpen: notificationsOpen,
                      filesRunning: filesOpen,
                      browserRunning: browserRunning,
                      terminalRunning: terminalRunning,
                      currentWorkspace: currentWorkspace,
                      notificationCount: notificationState.unreadCount,
                      onWorkspaceChanged: (index) =>
                          unawaited(_switchWorkspace(index)),
                      onStart: _toggleStart,
                      onFiles: _toggleFiles,
                      onBrowser: _launchBrowser,
                      onTerminal: _launchTerminal,
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
        onOpenSettings: () => unawaited(
          _openQuickSettingsRoute(QuickSettingsRoute.root),
        ),
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
        onDismiss: (id) => unawaited(_dismissNotification(id)),
        onClearAll: () => unawaited(_clearNotifications()),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 170),
      reverseDuration: const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
    );
  }
}

bool _sameSystemSnapshot(
  CloudSystemSnapshot left,
  CloudSystemSnapshot right,
) {
  return left.deviceName == right.deviceName &&
      left.networkAvailable == right.networkAvailable &&
      left.networkName == right.networkName &&
      left.volumeAvailable == right.volumeAvailable &&
      left.volume == right.volume &&
      left.brightnessAvailable == right.brightnessAvailable &&
      left.brightness == right.brightness &&
      left.batteryAvailable == right.batteryAvailable &&
      left.batteryPercent == right.batteryPercent &&
      left.wslAvailable == right.wslAvailable &&
      _sameStrings(left.distros, right.distros) &&
      left.currentWorkspace == right.currentWorkspace;
}

bool _sameNotificationState(
  CloudNotificationState left,
  CloudNotificationState right,
) {
  if (left.revision != right.revision ||
      left.unreadCount != right.unreadCount ||
      left.items.length != right.items.length) {
    return false;
  }
  for (var index = 0; index < left.items.length; index++) {
    final a = left.items[index];
    final b = right.items[index];
    if (a.id != b.id || a.read != b.read) return false;
  }
  return true;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
