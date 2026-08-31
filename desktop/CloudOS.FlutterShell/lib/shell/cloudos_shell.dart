import 'dart:ui';

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
  Offset filesOffset = const Offset(250, 94);

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

  Future<void> _launchApp(CloudApp app) async {
    if (app.id == 'files') {
      setState(() {
        filesOpen = true;
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
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_closeTransientPanels),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const _Wallpaper(),
                  _DesktopIcons(onFiles: _toggleFiles, onStart: _toggleStart),
                  _DesktopStatus(snapshot: snapshot),
                  if (filesOpen)
                    Positioned(
                      left: filesOffset.dx.clamp(20, constraints.maxWidth - 520),
                      top: filesOffset.dy.clamp(20, constraints.maxHeight - 260),
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
                    onStart: _toggleStart,
                    onFiles: _toggleFiles,
                    onQuickSettings: _toggleQuickSettings,
                    onNotifications: _toggleNotifications,
                  ),
                ],
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
      );
    } else if (notificationsOpen) {
      child = const NotificationCenterPanel(key: ValueKey<String>('notifications'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 130),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.025),
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

class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF071018),
                Color(0xFF0B1722),
                Color(0xFF07121B),
              ],
            ),
          ),
        ),
        Positioned(
          right: -180,
          top: -220,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(
              width: 620,
              height: 620,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x285DA9FF),
              ),
            ),
          ),
        ),
        Positioned(
          left: 180,
          bottom: -280,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
            child: Container(
              width: 680,
              height: 680,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1F62D99A),
              ),
            ),
          ),
        ),
        const Center(
          child: Opacity(
            opacity: 0.055,
            child: Icon(Icons.cloud_rounded, size: 480, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _DesktopIcons extends StatelessWidget {
  const _DesktopIcons({required this.onFiles, required this.onStart});

  final VoidCallback onFiles;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 22,
      top: 22,
      child: Column(
        children: <Widget>[
          _DesktopIcon(
            label: 'Arquivos',
            icon: Icons.folder_rounded,
            color: CloudOSColors.accent,
            onTap: onFiles,
          ),
          const SizedBox(height: 12),
          _DesktopIcon(
            label: 'Apps',
            icon: Icons.apps_rounded,
            color: CloudOSColors.success,
            onTap: onStart,
          ),
          const SizedBox(height: 12),
          const _DesktopIcon(
            label: 'Ubuntu',
            icon: Icons.terminal_rounded,
            color: CloudOSColors.linux,
          ),
          const SizedBox(height: 12),
          const _DesktopIcon(
            label: 'Lixeira',
            icon: Icons.delete_outline_rounded,
            color: CloudOSColors.secondary,
          ),
        ],
      ),
    );
  }
}

class _DesktopIcon extends StatelessWidget {
  const _DesktopIcon({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 76,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CloudOSColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopStatus extends StatelessWidget {
  const _DesktopStatus({required this.snapshot});

  final CloudSystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x5515222E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CloudOSColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_done_rounded, size: 16, color: CloudOSColors.success),
            const SizedBox(width: 7),
            Text(
              snapshot.deviceName,
              style: const TextStyle(color: CloudOSColors.secondary, fontSize: 11),
            ),
            if (snapshot.wslAvailable) ...<Widget>[
              const SizedBox(width: 10),
              Container(width: 1, height: 14, color: CloudOSColors.border),
              const SizedBox(width: 10),
              const Icon(Icons.terminal_rounded, size: 15, color: CloudOSColors.linux),
              const SizedBox(width: 5),
              Text(
                snapshot.distros.isEmpty ? 'WSL' : snapshot.distros.first,
                style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
