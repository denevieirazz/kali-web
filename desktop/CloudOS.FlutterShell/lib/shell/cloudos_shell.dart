import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/broker_events.dart';
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

  StreamSubscription<CloudOSBrokerEvent>? _brokerEventSubscription;
  bool _snapshotRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _brokerEventSubscription = CloudOSBrokerEvents.instance.stream.listen(
      _onBrokerEvent,
    );
    unawaited(CloudOSBrokerEvents.instance.start());
    _loadBridgeData();
  }

  @override
  void dispose() {
    _brokerEventSubscription?.cancel();
    super.dispose();
  }

  void _onBrokerEvent(CloudOSBrokerEvent event) {
    if (!mounted) return;

    if (event.name == 'system.volumeChanged') {
      final value = (event.payload['volume'] as num?)?.toDouble();
      if (value != null && value.isFinite && value >= 0 && value <= 1) {
        setState(() {
          snapshot = snapshot.copyWith(volume: value, volumeAvailable: true);
        });
      }
      return;
    }

    if (event.name.startsWith('system.')) {
      unawaited(_refreshSystemSnapshotFromEvent());
    }
  }

  Future<void> _refreshSystemSnapshotFromEvent() async {
    if (_snapshotRefreshInFlight) return;
    _snapshotRefreshInFlight = true;
    try {
      final loadedSnapshot = await widget.bridge.loadSystemSnapshot();
      if (!mounted) return;
      setState(() => snapshot = loadedSnapshot);
    } finally {
      _snapshotRefreshInFlight = false;
    }
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
    switch (app.id) {
      case 'files':
      case 'cloudos:files':
      case 'drive':
      case 'cloudos:drive':
        if (!mounted) return;
        setState(() {
          filesOpen = true;
          _closeTransientPanels();
        });
        return;
      case 'settings':
      case 'cloudos:settings':
        if (!mounted) return;
        setState(() {
          _closeTransientPanels();
          quickSettingsOpen = true;
        });
        return;
      case 'browser':
        // Legacy preview ID only. Typed cloudos:browser is launched through the
        // broker until a real Flutter Browser surface is wired.
        _toggleBrowser();
        return;
      case 'terminal':
      case 'ubuntu-terminal':
        // Legacy preview IDs only. Real typed Windows/WSL IDs go to the broker.
        _toggleTerminal();
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
        ): () => _switchWorkspace(1),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): () => _switchWorkspace(2),
        const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ): () => _switchWorkspace(3),
        const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
          alt: true,
        ): () => _switchWorkspace(4),
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
        key: const ValueKey<String>('quick'),
        snapshot: snapshot,
        bridge: widget.bridge,
        onClose: () => setState(() => quickSettingsOpen = false),
      );
    } else if (notificationsOpen) {
      child = NotificationCenter(
        key: const ValueKey<String>('notifications'),
        onClose: () => setState(() => notificationsOpen = false),
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: child is SizedBox,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          reverseDuration: const Duration(milliseconds: 130),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: child,
        ),
      ),
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.45, -0.55),
          radius: 1.5,
          colors: <Color>[
            Color(0xFF162331),
            Color(0xFF0B111A),
            Color(0xFF070B10),
          ],
          stops: <double>[0, 0.48, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0x1022B4F2),
              Color(0x00070B10),
              Color(0x1419D3AE),
            ],
            stops: <double>[0, 0.55, 1],
          ),
        ),
      ),
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

  static const items = <({String id, String title, IconData icon, Color color})>[
    (
      id: 'files',
      title: 'Arquivos',
      icon: Icons.folder_rounded,
      color: CloudOSColors.accent,
    ),
    (
      id: 'apps',
      title: 'Aplicativos',
      icon: Icons.grid_view_rounded,
      color: CloudOSColors.success,
    ),
    (
      id: 'ubuntu',
      title: 'Ubuntu WSL2',
      icon: Icons.terminal_rounded,
      color: CloudOSColors.linux,
    ),
    (
      id: 'drive',
      title: 'CloudOS Drive',
      icon: Icons.cloud_outlined,
      color: Color(0xFF8AA8FF),
    ),
    (
      id: 'settings',
      title: 'Configurações',
      icon: Icons.settings_outlined,
      color: CloudOSColors.caption,
    ),
    (
      id: 'trash',
      title: 'Lixeira',
      icon: Icons.delete_outline_rounded,
      color: CloudOSColors.caption,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _DesktopIconTile(
              title: item.title,
              icon: item.icon,
              color: item.color,
              selected: selectedId == item.id,
              onTap: () => onSelect(item.id),
              onOpen: () {
                onSelect(item.id);
                switch (item.id) {
                  case 'files':
                  case 'drive':
                    onFiles();
                  case 'apps':
                    onStart();
                  case 'ubuntu':
                    onTerminal();
                  case 'settings':
                    onOpenSettings();
                  case 'trash':
                    // Reserved for the native Recycle Bin surface.
                    break;
                }
              },
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _DesktopIconTile extends StatefulWidget {
  const _DesktopIconTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  final String title;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  State<_DesktopIconTile> createState() => _DesktopIconTileState();
}

class _DesktopIconTileState extends State<_DesktopIconTile> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 104,
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 7),
            decoration: BoxDecoration(
              color: selected
                  ? CloudOSColors.accent.withValues(alpha: 0.13)
                  : hover
                  ? CloudOSColors.text.withValues(alpha: 0.055)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? CloudOSColors.accent.withValues(alpha: 0.48)
                    : hover
                    ? CloudOSColors.borderStrong
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 24),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CloudOSColors.text,
                    fontSize: 10.5,
                    height: 1.12,
                    fontWeight: FontWeight.w500,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 5, color: Colors.black87),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CloudOSColors.surface.withValues(alpha: 0.76),
        border: Border.all(color: CloudOSColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.cloud_done_outlined,
            color: CloudOSColors.success,
            size: 15,
          ),
          const SizedBox(width: 7),
          Text(
            snapshot.networkAvailable
                ? (snapshot.networkName.isEmpty
                      ? 'Rede conectada'
                      : snapshot.networkName)
                : 'Rede indisponível',
            style: const TextStyle(color: CloudOSColors.secondary, fontSize: 11),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: CloudOSColors.border),
          const SizedBox(width: 12),
          Text(
            'Área $currentWorkspace',
            style: const TextStyle(
              color: CloudOSColors.caption,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
