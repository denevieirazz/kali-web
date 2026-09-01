import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import '../widgets/cloud_taskbar.dart';
import '../widgets/files_window.dart';
import '../widgets/notification_center.dart';
import '../widgets/quick_settings_panel.dart';
import '../widgets/start_panel.dart';

part '../widgets/desktop_surface.dart';

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
  bool browserOpen = false;
  bool terminalOpen = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  Offset filesOffset = const Offset(200, 70);

  @override
  void initState() {
    super.initState();
    _loadBridgeData();
  }

  Future<void> _loadBridgeData() async {
    final loadedApps = await widget.bridge.loadApps();
    final loadedSnapshot = await widget.bridge.loadSystemSnapshot();
    if (!mounted) return;
    setState(() {
      apps = loadedApps;
      snapshot = loadedSnapshot;
    });
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

  void _toggleBrowser() {
    setState(() {
      browserOpen = !browserOpen;
      _closeTransientPanels();
    });
  }

  void _toggleTerminal() {
    setState(() {
      terminalOpen = !terminalOpen;
      _closeTransientPanels();
    });
  }

  void _switchWorkspace(int index) {
    setState(() {
      currentWorkspace = index;
      _closeTransientPanels();
    });
  }

  Future<void> _launchApp(CloudApp app) async {
    if (app.id == 'files') {
      setState(() {
        filesOpen = true;
        _closeTransientPanels();
      });
      return;
    }
    if (app.id == 'browser') {
      setState(() {
        browserOpen = true;
        _closeTransientPanels();
      });
      return;
    }
    if (app.id == 'terminal' || app.id == 'ubuntu-terminal') {
      setState(() {
        terminalOpen = true;
        _closeTransientPanels();
      });
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
                    const RepaintBoundary(child: _Wallpaper()),
                    Positioned(
                      left: 20,
                      top: 20,
                      child: RepaintBoundary(
                        child: _DesktopIcons(
                          selectedId: selectedDesktopIcon,
                          onSelect: (id) => setState(() => selectedDesktopIcon = id),
                          onFiles: _toggleFiles,
                          onStart: _toggleStart,
                          onTerminal: _toggleTerminal,
                          onOpenSettings: _toggleQuickSettings,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      right: 18,
                      child: RepaintBoundary(
                        child: _DesktopStatus(
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
                      browserRunning: browserOpen,
                      terminalRunning: terminalOpen,
                      currentWorkspace: currentWorkspace,
                      onWorkspaceChanged: _switchWorkspace,
                      onStart: _toggleStart,
                      onFiles: _toggleFiles,
                      onBrowser: _toggleBrowser,
                      onTerminal: _toggleTerminal,
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
