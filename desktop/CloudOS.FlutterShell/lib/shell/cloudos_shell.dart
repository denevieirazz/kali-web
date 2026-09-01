import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/files/presentation/files_window.dart';
import '../features/notifications/presentation/notification_center_panel.dart';
import '../features/quick_settings/presentation/quick_settings_panel.dart';
import '../features/start/presentation/start_panel.dart';
import '../features/taskbar/presentation/cloud_taskbar.dart';
import '../models/cloud_app.dart';
import '../models/cloud_system_snapshot.dart';
import '../services/cloudos_bridge.dart';
import 'shell_app_route.dart';
import 'widgets/desktop_icons.dart';
import 'widgets/desktop_status.dart';
import 'widgets/desktop_wallpaper.dart';

class CloudOSShell extends StatefulWidget {
  const CloudOSShell({super.key, CloudOSBridge? bridge}) : bridge = bridge ?? const _DefaultBridge();

  final CloudOSBridge bridge;

  @override
  State<CloudOSShell> createState() => _CloudOSShellState();
}

class _DefaultBridge extends CloudOSBridge {
  const _DefaultBridge();
}

class _CloudOSShellState extends State<CloudOSShell> {
  List<CloudApp> apps = CloudOSBridge.previewApps;
  CloudSystemSnapshot snapshot = CloudOSBridge.previewSnapshot;
  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool filesOpen = true;
  bool browserRunning = false;
  bool terminalRunning = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  Offset filesOffset = const Offset(200, 70);

  Timer? _surfaceStateTimer;
  bool _surfaceRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadBridgeData();
    _surfaceStateTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshShellSurfaceStates(),
    );
  }

  @override
  void dispose() {
    _surfaceStateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBridgeData() async {
    final loadedApps = await widget.bridge.loadApps();
    final loadedSnapshot = await widget.bridge.loadSystemSnapshot();
    final surfaceStates = await widget.bridge.loadShellSurfaceStates();
    if (!mounted) return;
    setState(() {
      apps = loadedApps;
      snapshot = loadedSnapshot;
      browserRunning = surfaceStates['browser'] ?? false;
      terminalRunning = surfaceStates['terminal'] ?? false;
    });
  }

  Future<void> _refreshShellSurfaceStates() async {
    if (_surfaceRefreshInFlight) return;
    _surfaceRefreshInFlight = true;
    try {
      final states = await widget.bridge.loadShellSurfaceStates();
      if (!mounted) return;
      final nextBrowser = states['browser'] ?? false;
      final nextTerminal = states['terminal'] ?? false;
      if (nextBrowser == browserRunning && nextTerminal == terminalRunning) return;
      setState(() {
        browserRunning = nextBrowser;
        terminalRunning = nextTerminal;
      });
    } finally {
      _surfaceRefreshInFlight = false;
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
    setState(() {
      final next = !notificationsOpen;
      _closeTransientPanels();
      notificationsOpen = next;
    });
  }

  void _toggleFiles() {
    setState(() {
      filesOpen = !filesOpen;
      _closeTransientPanels();
    });
  }

  Future<void> _launchBridgeSurface(String appId, ShellAppRoute route) async {
    final launched = await widget.bridge.launchApp(appId);
    if (!mounted) return;
    setState(() {
      _closeTransientPanels();
      if (route == ShellAppRoute.browser) browserRunning = launched;
      if (route == ShellAppRoute.terminal) terminalRunning = launched;
    });
    if (launched) {
      await _refreshShellSurfaceStates();
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

  void _switchWorkspace(int index) {
    setState(() {
      currentWorkspace = index;
      _closeTransientPanels();
    });
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
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, alt: true): _toggleFiles,
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true, alt: true): _toggleQuickSettings,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, alt: true): _toggleNotifications,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true): _toggleStart,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true, alt: true): _toggleStart,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_closeTransientPanels),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true, alt: true): () => _switchWorkspace(1),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true, alt: true): () => _switchWorkspace(2),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true, alt: true): () => _switchWorkspace(3),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true, alt: true): () => _switchWorkspace(4),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final maxLeft = constraints.maxWidth > 1000 ? constraints.maxWidth - 980 : 20.0;
              final maxTop = constraints.maxHeight > 700 ? constraints.maxHeight - 660 : 20.0;
              final safeLeft = filesOffset.dx.clamp(20.0, maxLeft).toDouble();
              final safeTop = filesOffset.dy.clamp(20.0, maxTop).toDouble();

              return GestureDetector(
                onTap: () {
                  if (startOpen || quickSettingsOpen || notificationsOpen || selectedDesktopIcon != null) {
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
                          onSelect: (id) => setState(() => selectedDesktopIcon = id),
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
                          onDrag: (delta) => setState(() => filesOffset += delta),
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
                      onWorkspaceChanged: _switchWorkspace,
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
        onOpenSettings: () {
          setState(() {
            quickSettingsOpen = false;
            startOpen = true;
          });
        },
      );
    } else if (notificationsOpen) {
      child = const NotificationCenterPanel(key: ValueKey<String>('notifications'));
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