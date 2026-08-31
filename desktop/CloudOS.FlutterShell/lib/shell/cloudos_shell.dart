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
  CloudSystemSnapshot snapshot = CloudOSBridge.unavailableSnapshot;
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
        ): () =>
            _switchWorkspace(1),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): () =>
            _switchWorkspace(2),
        const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ): () =>
            _switchWorkspace(3),
        const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
          alt: true,
        ): () =>
            _switchWorkspace(4),
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
                    const RepaintBoundary(child: _Wallpaper()),
                    Positioned(
                      left: 20,
                      top: 20,
                      child: RepaintBoundary(
                        child: _DesktopIcons(
                          selectedId: selectedDesktopIcon,
                          onSelect: (id) =>
                              setState(() => selectedDesktopIcon = id),
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
                          onDrag: (delta) =>
                              setState(() => filesOffset += delta),
                          bridge: widget.bridge,
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
        onVolumeChanged: widget.bridge.setVolume,
        onBrightnessChanged: widget.bridge.setBrightness,
        onOpenSettings: () {
          setState(() {
            quickSettingsOpen = false;
            startOpen = true;
          });
        },
      );
    } else if (notificationsOpen) {
      child = const NotificationCenterPanel(
        key: ValueKey<String>('notifications'),
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
                Color(0xFF070B10),
                Color(0xFF0D141E),
                Color(0xFF090E16),
              ],
            ),
          ),
        ),
        Positioned(
          right: -100,
          top: -120,
          child: Container(
            width: 500,
            height: 500,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Color(0x184C9AFF), Color(0x004C9AFF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 120,
          bottom: -150,
          child: Container(
            width: 540,
            height: 540,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Color(0x1443C780), Color(0x0043C780)],
              ),
            ),
          ),
        ),
        const Center(
          child: Opacity(
            opacity: 0.035,
            child: Icon(Icons.cloud_rounded, size: 400, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _DesktopIcons extends StatelessWidget {
  const _DesktopIcons({
    required this.selectedId,
    required this.onSelect,
    required this.onFiles,
    required this.onStart,
    required this.onTerminal,
    required this.onOpenSettings,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onFiles;
  final VoidCallback onStart;
  final VoidCallback onTerminal;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DesktopIcon(
          id: 'files',
          label: 'Arquivos',
          icon: Icons.folder_rounded,
          color: CloudOSColors.accent,
          isSelected: selectedId == 'files',
          onTap: () => onSelect('files'),
          onDoubleTap: onFiles,
        ),
        const SizedBox(height: 10),
        _DesktopIcon(
          id: 'apps',
          label: 'Aplicativos',
          icon: Icons.apps_rounded,
          color: CloudOSColors.success,
          isSelected: selectedId == 'apps',
          onTap: () => onSelect('apps'),
          onDoubleTap: onStart,
        ),
        const SizedBox(height: 10),
        _DesktopIcon(
          id: 'ubuntu',
          label: 'Ubuntu WSL',
          icon: Icons.terminal_rounded,
          color: CloudOSColors.linux,
          badge: 'WSL2',
          isSelected: selectedId == 'ubuntu',
          onTap: () => onSelect('ubuntu'),
          onDoubleTap: onTerminal,
        ),
        const SizedBox(height: 10),
        _DesktopIcon(
          id: 'drive',
          label: 'CloudOS Drive',
          icon: Icons.cloud_circle_rounded,
          color: CloudOSColors.accent,
          isSelected: selectedId == 'drive',
          onTap: () => onSelect('drive'),
          onDoubleTap: onFiles,
        ),
        const SizedBox(height: 10),
        _DesktopIcon(
          id: 'settings',
          label: 'Configurações',
          icon: Icons.settings_rounded,
          color: CloudOSColors.secondary,
          isSelected: selectedId == 'settings',
          onTap: () => onSelect('settings'),
          onDoubleTap: onOpenSettings,
        ),
        const SizedBox(height: 10),
        _DesktopIcon(
          id: 'trash',
          label: 'Lixeira',
          icon: Icons.delete_outline_rounded,
          color: CloudOSColors.caption,
          isSelected: selectedId == 'trash',
          onTap: () => onSelect('trash'),
          onDoubleTap: onFiles,
        ),
      ],
    );
  }
}

class _DesktopIcon extends StatelessWidget {
  const _DesktopIcon({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.badge,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String? badge;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? CloudOSColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? CloudOSColors.accent : Colors.transparent,
          ),
        ),
        child: Column(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.28)),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                if (badge != null)
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: CloudOSColors.elevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: CloudOSColors.border),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: CloudOSColors.linux,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopStatus extends StatelessWidget {
  const _DesktopStatus({
    required this.snapshot,
    required this.currentWorkspace,
  });

  final CloudSystemSnapshot snapshot;
  final int currentWorkspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.cloud_done_rounded,
            size: 15,
            color: CloudOSColors.success,
          ),
          const SizedBox(width: 6),
          const Text(
            'CloudOS V22.1',
            style: TextStyle(
              color: CloudOSColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 12, color: CloudOSColors.border),
          const SizedBox(width: 8),
          Text(
            'Área $currentWorkspace',
            style: const TextStyle(
              color: CloudOSColors.secondary,
              fontSize: 11,
            ),
          ),
          if (snapshot.wslAvailable) ...<Widget>[
            const SizedBox(width: 8),
            Container(width: 1, height: 12, color: CloudOSColors.border),
            const SizedBox(width: 8),
            const Icon(
              Icons.terminal_rounded,
              size: 14,
              color: CloudOSColors.linux,
            ),
            const SizedBox(width: 4),
            Text(
              snapshot.distros.isEmpty ? 'WSL2' : snapshot.distros.first,
              style: const TextStyle(
                color: CloudOSColors.caption,
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
