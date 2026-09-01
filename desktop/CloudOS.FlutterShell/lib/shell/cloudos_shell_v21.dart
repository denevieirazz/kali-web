import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import '../widgets/cloud_taskbar.dart';
import '../widgets/files_window_v21.dart';
import '../widgets/notification_center.dart';
import '../widgets/quick_settings_panel.dart';
import '../widgets/start_panel_v21.dart';

class CloudOSShellV21 extends StatefulWidget {
  const CloudOSShellV21({super.key, CloudOSBridge? bridge})
      : bridge = bridge ?? const CloudOSBridge();

  final CloudOSBridge bridge;

  @override
  State<CloudOSShellV21> createState() => _CloudOSShellV21State();
}

class _CloudOSShellV21State extends State<CloudOSShellV21> {
  List<CloudApp> apps = CloudOSBridge.previewApps;
  CloudSystemSnapshot snapshot = CloudOSBridge.previewSnapshot;

  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool filesOpen = true;
  bool loadingBridge = true;
  int currentWorkspace = 1;
  Offset filesOffset = const Offset(210, 70);
  String? selectedDesktopIcon;

  @override
  void initState() {
    super.initState();
    _reloadBridge();
  }

  Future<void> _reloadBridge() async {
    final loadedApps = await widget.bridge.loadApps();
    final loadedSnapshot = await widget.bridge.loadSystemSnapshot();
    if (!mounted) return;
    setState(() {
      apps = loadedApps;
      snapshot = loadedSnapshot;
      currentWorkspace = loadedSnapshot.currentWorkspace.clamp(1, 4);
      loadingBridge = false;
    });
  }

  void _closePanels() {
    startOpen = false;
    quickSettingsOpen = false;
    notificationsOpen = false;
  }

  void _toggleStart() {
    setState(() {
      final next = !startOpen;
      _closePanels();
      startOpen = next;
    });
  }

  void _toggleQuickSettings() {
    setState(() {
      final next = !quickSettingsOpen;
      _closePanels();
      quickSettingsOpen = next;
    });
  }

  void _toggleNotifications() {
    setState(() {
      final next = !notificationsOpen;
      _closePanels();
      notificationsOpen = next;
    });
  }

  void _showFiles() {
    setState(() {
      filesOpen = true;
      _closePanels();
    });
  }

  void _toggleFiles() {
    setState(() {
      filesOpen = !filesOpen;
      _closePanels();
    });
  }

  void _switchWorkspace(int index) {
    setState(() {
      currentWorkspace = index.clamp(1, 4);
      _closePanels();
    });
  }

  CloudApp? _findApp(String id) {
    for (final app in apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  Future<void> _launchById(String id) async {
    final app = _findApp(id);
    if (app != null) {
      await _launchApp(app);
      return;
    }

    final ok = await widget.bridge.launchApp(id);
    if (!mounted || ok) return;
    _showError('Não foi possível iniciar $id.');
  }

  Future<void> _launchApp(CloudApp app) async {
    if (app.id == 'files' || app.id == 'cloudos:files') {
      _showFiles();
      return;
    }

    setState(_closePanels);
    final ok = await widget.bridge.launchApp(app.id);
    if (!mounted || ok) return;
    _showError('Falha ao abrir ${app.name}.');
  }

  Future<void> _launchFirstLinuxApp() async {
    CloudApp? candidate;
    for (final app in apps) {
      if (app.platform == CloudAppPlatform.linux && app.id.contains('terminal')) {
        candidate = app;
        break;
      }
    }
    candidate ??= apps.cast<CloudApp?>().firstWhere(
          (app) => app?.platform == CloudAppPlatform.linux,
          orElse: () => null,
        );

    if (candidate == null) {
      _showError('Nenhuma distribuição WSL com app disponível foi detectada.');
      return;
    }
    await _launchApp(candidate);
  }

  Future<void> _setVolume(double value) async {
    final ok = await widget.bridge.setVolume(value);
    if (!mounted) return;
    if (!ok) {
      _showError('O Windows não disponibilizou controle de volume para o Broker.');
      return;
    }
    await _reloadSnapshotOnly();
  }

  Future<void> _setBrightness(double value) async {
    final ok = await widget.bridge.setBrightness(value);
    if (!mounted) return;
    if (!ok) {
      _showError('Este monitor não expõe controle de brilho compatível.');
      return;
    }
    await _reloadSnapshotOnly();
  }

  Future<void> _reloadSnapshotOnly() async {
    final updated = await widget.bridge.loadSystemSnapshot();
    if (!mounted) return;
    setState(() => snapshot = updated);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyA, control: true, alt: true): _toggleStart,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true): _toggleStart,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, alt: true): _toggleFiles,
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true, alt: true): _toggleQuickSettings,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, alt: true): _toggleNotifications,
        const SingleActivator(LogicalKeyboardKey.enter, control: true, alt: true): () {
          _launchById('cloudos:terminal');
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          setState(_closePanels);
        },
        for (int i = 1; i <= 4; i++)
          SingleActivator(LogicalKeyboardKey.values.firstWhere((key) => key.keyLabel == '$i'), control: true, alt: true): () {
            _switchWorkspace(i);
          },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final maxLeft = (constraints.maxWidth - 1000).clamp(20.0, double.infinity);
              final maxTop = (constraints.maxHeight - 675).clamp(20.0, double.infinity);
              final safeLeft = filesOffset.dx.clamp(20.0, maxLeft).toDouble();
              final safeTop = filesOffset.dy.clamp(20.0, maxTop).toDouble();

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (startOpen || quickSettingsOpen || notificationsOpen || selectedDesktopIcon != null) {
                    setState(() {
                      _closePanels();
                      selectedDesktopIcon = null;
                    });
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const _V21Wallpaper(),
                    Positioned(
                      left: 18,
                      top: 18,
                      child: _DesktopShortcuts(
                        snapshot: snapshot,
                        selectedId: selectedDesktopIcon,
                        onSelected: (id) => setState(() => selectedDesktopIcon = id),
                        onFiles: _showFiles,
                        onApps: _toggleStart,
                        onLinux: _launchFirstLinuxApp,
                        onSettings: () => _launchById('cloudos:settings'),
                        onTrash: () => _launchById('cloudos:trash'),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      right: 18,
                      child: _SystemStatusCard(
                        snapshot: snapshot,
                        currentWorkspace: currentWorkspace,
                        loading: loadingBridge,
                        onRefresh: _reloadBridge,
                      ),
                    ),
                    if (filesOpen)
                      Positioned(
                        left: safeLeft,
                        top: safeTop,
                        child: FilesWindowV21(
                          snapshot: snapshot,
                          onClose: () => setState(() => filesOpen = false),
                          onMinimize: () => setState(() => filesOpen = false),
                          onDrag: (delta) => setState(() => filesOffset += delta),
                        ),
                      ),
                    _panel(),
                    CloudTaskbar(
                      startOpen: startOpen,
                      quickSettingsOpen: quickSettingsOpen,
                      notificationsOpen: notificationsOpen,
                      filesRunning: filesOpen,
                      browserRunning: false,
                      terminalRunning: false,
                      currentWorkspace: currentWorkspace,
                      notificationCount: CloudOSBridge.previewNotifications.length,
                      onWorkspaceChanged: _switchWorkspace,
                      onStart: _toggleStart,
                      onFiles: _toggleFiles,
                      onBrowser: () => _launchById('cloudos:browser'),
                      onTerminal: () => _launchById('cloudos:terminal'),
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

  Widget _panel() {
    Widget child = const SizedBox.shrink(key: ValueKey<String>('none'));

    if (startOpen) {
      child = StartPanelV21(
        key: const ValueKey<String>('start-v21'),
        apps: apps,
        snapshot: snapshot,
        onLaunch: _launchApp,
        onClose: () => setState(() => startOpen = false),
      );
    } else if (quickSettingsOpen) {
      child = QuickSettingsPanel(
        key: const ValueKey<String>('quick-v21'),
        snapshot: snapshot,
        onOpenSettings: () => _launchById('cloudos:settings'),
        onVolumeChanged: _setVolume,
        onBrightnessChanged: _setBrightness,
      );
    } else if (notificationsOpen) {
      child = const NotificationCenterPanel(key: ValueKey<String>('notifications-v21'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 170),
      reverseDuration: const Duration(milliseconds: 120),
      child: child,
    );
  }
}

class _V21Wallpaper extends StatelessWidget {
  const _V21Wallpaper();

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
                Color(0xFF060A10),
                Color(0xFF0B1420),
                Color(0xFF080D15),
              ],
            ),
          ),
        ),
        Positioned(
          right: -120,
          top: -140,
          child: Container(
            width: 560,
            height: 560,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Color(0x204C9AFF), Color(0x004C9AFF)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 100,
          bottom: -180,
          child: Container(
            width: 600,
            height: 600,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Color(0x1643C780), Color(0x0043C780)],
              ),
            ),
          ),
        ),
        const Center(
          child: Opacity(
            opacity: 0.035,
            child: Icon(Icons.cloud_rounded, size: 420, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _DesktopShortcuts extends StatelessWidget {
  const _DesktopShortcuts({
    required this.snapshot,
    required this.selectedId,
    required this.onSelected,
    required this.onFiles,
    required this.onApps,
    required this.onLinux,
    required this.onSettings,
    required this.onTrash,
  });

  final CloudSystemSnapshot snapshot;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onFiles;
  final VoidCallback onApps;
  final VoidCallback onLinux;
  final VoidCallback onSettings;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final linuxLabel = snapshot.distros.isNotEmpty ? snapshot.distros.first : 'WSL';
    return Column(
      children: <Widget>[
        _DesktopShortcut(
          id: 'files',
          label: 'Arquivos',
          icon: Icons.folder_rounded,
          color: CloudOSColors.accent,
          selected: selectedId == 'files',
          onSelect: onSelected,
          onOpen: onFiles,
        ),
        _DesktopShortcut(
          id: 'apps',
          label: 'Aplicativos',
          icon: Icons.apps_rounded,
          color: CloudOSColors.success,
          selected: selectedId == 'apps',
          onSelect: onSelected,
          onOpen: onApps,
        ),
        if (snapshot.wslAvailable)
          _DesktopShortcut(
            id: 'wsl',
            label: linuxLabel,
            icon: Icons.terminal_rounded,
            color: CloudOSColors.linux,
            selected: selectedId == 'wsl',
            onSelect: onSelected,
            onOpen: onLinux,
          ),
        _DesktopShortcut(
          id: 'settings',
          label: 'Configurações',
          icon: Icons.settings_rounded,
          color: CloudOSColors.secondary,
          selected: selectedId == 'settings',
          onSelect: onSelected,
          onOpen: onSettings,
        ),
        _DesktopShortcut(
          id: 'trash',
          label: 'Lixeira',
          icon: Icons.delete_outline_rounded,
          color: CloudOSColors.caption,
          selected: selectedId == 'trash',
          onSelect: onSelected,
          onOpen: onTrash,
        ),
      ],
    );
  }
}

class _DesktopShortcut extends StatelessWidget {
  const _DesktopShortcut({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onSelect(id),
        onDoubleTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 82,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? CloudOSColors.accent : Colors.transparent),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CloudOSColors.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({
    required this.snapshot,
    required this.currentWorkspace,
    required this.loading,
    required this.onRefresh,
  });

  final CloudSystemSnapshot snapshot;
  final int currentWorkspace;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final wslText = snapshot.wslAvailable
        ? snapshot.distros.isEmpty
            ? 'WSL instalado'
            : 'WSL • ${snapshot.distros.join(', ')}'
        : 'WSL indisponível';

    return Container(
      width: 285,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xB5121A25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CloudOSColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: loading
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_done_rounded, color: CloudOSColors.accent, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${snapshot.deviceName} • Workspace $currentWorkspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CloudOSColors.text, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${snapshot.networkName} • $wslText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar estado',
            visualDensity: VisualDensity.compact,
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}
