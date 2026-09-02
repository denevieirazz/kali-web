import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../models/window_model.dart';
import '../services/app_registry.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/session_service.dart';
import '../services/window_manager.dart';
import '../widgets/alt_tab_overlay.dart';
import '../widgets/browser_window.dart';
import '../widgets/cloud_taskbar.dart';
import '../widgets/cloudos_drive_window.dart';
import '../widgets/context_menu.dart';
import '../widgets/desktop_widgets.dart';
import '../widgets/files_window.dart';
import '../widgets/global_search_overlay.dart';
import '../widgets/notepad_window.dart';
import '../widgets/notification_center.dart';
import '../widgets/projects_window.dart';
import '../widgets/quick_settings_panel.dart';
import '../widgets/settings_window.dart';
import '../widgets/start_panel.dart';
import '../widgets/system_monitor_window.dart';
import '../widgets/terminal_window.dart';
import '../widgets/window_frame.dart';

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
  final WindowManager windowManager = WindowManager();
  List<CloudApp> apps = const <CloudApp>[];
  CloudSystemSnapshot snapshot = CloudOSBridge.unavailableSnapshot;
  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool isAltTabOpen = false;
  int altTabIndex = 0;
  bool isGlobalSearchOpen = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  Offset? contextMenuPosition;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(_onWindowManagerUpdate);
    _loadBridgeData();
    _restoreDesktopSession();
  }

  @override
  void dispose() {
    windowManager.removeListener(_onWindowManagerUpdate);
    windowManager.dispose();
    super.dispose();
  }

  void _onWindowManagerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreDesktopSession() async {
    try {
      final session = await SessionService.instance.loadSession();
      if (session != null && mounted) {
        final rawWindows = session['windows'] as List<dynamic>? ?? <dynamic>[];
        final savedList = rawWindows.cast<Map<String, dynamic>>();
        final savedWs = session['activeWorkspace'] as int? ?? 1;
        if (savedList.isNotEmpty) {
          windowManager.restoreSavedWindows(savedList, savedWs);
          setState(() => currentWorkspace = savedWs);
        }
      }
    } catch (e, st) {
      CloudOSLogger.error('CloudOSShell', 'restoreSession', e, st);
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
    isAltTabOpen = false;
    isGlobalSearchOpen = false;
    contextMenuPosition = null;
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

  void _toggleGlobalSearch() {
    setState(() {
      final next = !isGlobalSearchOpen;
      _closeTransientPanels();
      isGlobalSearchOpen = next;
    });
  }

  void _toggleAltTab() {
    final wins = windowManager.currentWorkspaceWindows;
    if (wins.isEmpty) return;

    setState(() {
      if (!isAltTabOpen) {
        isAltTabOpen = true;
        altTabIndex = wins.length > 1 ? 1 : 0;
      } else {
        altTabIndex = (altTabIndex + 1) % wins.length;
      }
    });
  }

  void _confirmAltTab(int index) {
    final wins = windowManager.currentWorkspaceWindows;
    if (index >= 0 && index < wins.length) {
      windowManager.focusWindow(wins[index].id);
    }
    setState(() => isAltTabOpen = false);
  }

  void _switchWorkspace(int index) {
    windowManager.setWorkspace(index);
    setState(() {
      currentWorkspace = index;
      _closeTransientPanels();
    });
  }

  String _resolveWslDistro(CloudApp app) {
    final direct = app.distro?.trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final parts = app.id.split(':');
    if (parts.length >= 3 &&
        parts.first.toLowerCase() == 'wsl' &&
        parts.last.toLowerCase() == 'terminal') {
      return parts.sublist(1, parts.length - 1).join(':').trim();
    }
    return '';
  }

  Future<void> _launchApp(CloudApp app) async {
    final norm = app.id.toLowerCase();
    if (norm.startsWith('wsl:')) {
      final distro = _resolveWslDistro(app);
      windowManager.openWindow(
        'wsl:terminal',
        params: distro.isEmpty
            ? null
            : <String, dynamic>{'initialDistro': distro},
      );
      if (mounted) setState(_closeTransientPanels);
      return;
    }

    final def = AppRegistry.findById(app.id);
    if (def != null && def.isInternal) {
      windowManager.openWindow(app.id);
      if (mounted) setState(_closeTransientPanels);
      return;
    }

    if (norm == 'files' || norm == 'cloudos:files') {
      windowManager.openWindow('cloudos:files');
      if (mounted) setState(_closeTransientPanels);
      return;
    }
    if (norm == 'terminal' || norm == 'cloudos:terminal') {
      windowManager.openWindow('cloudos:terminal');
      if (mounted) setState(_closeTransientPanels);
      return;
    }
    if (norm == 'browser' || norm == 'cloudos:browser') {
      windowManager.openWindow('cloudos:browser');
      if (mounted) setState(_closeTransientPanels);
      return;
    }
    if (norm == 'settings' || norm == 'cloudos:settings') {
      windowManager.openWindow('cloudos:settings');
      if (mounted) setState(_closeTransientPanels);
      return;
    }
    if (norm == 'notepad' || norm == 'cloudos:notepad' || norm == 'windows:notepad') {
      windowManager.openWindow('cloudos:notepad');
      if (mounted) setState(_closeTransientPanels);
      return;
    }

    await widget.bridge.launchApp(app.id);
    if (!mounted) return;
    setState(_closeTransientPanels);
  }

  Widget _buildWindowContent(CloudWindow window) {
    final appId = window.appId.toLowerCase();

    if (appId == 'cloudos:files' || appId == 'files') {
      return FilesWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        windowManager: windowManager,
      );
    }

    if (appId == 'cloudos:terminal' || appId == 'terminal') {
      return TerminalWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
      );
    }

    if (appId.startsWith('wsl:')) {
      final initialDistro = window.customParams['initialDistro'];
      return TerminalWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        initialShell: TerminalShellKind.wsl,
        initialDistro: initialDistro is String && initialDistro.trim().isNotEmpty
            ? initialDistro.trim()
            : null,
      );
    }

    if (appId == 'cloudos:browser' || appId == 'browser') {
      return BrowserWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        isVisible:
            window.workspaceIndex == windowManager.activeWorkspace &&
            !window.minimized,
      );
    }

    if (appId == 'cloudos:notepad' || appId == 'notepad') {
      final initialPath = window.customParams['initialFilePath'] as String?;
      return NotepadWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        initialFilePath: initialPath,
      );
    }

    if (appId == 'cloudos:settings' || appId == 'settings') {
      return SettingsWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
      );
    }

    if (appId == 'cloudos:system-monitor' || appId == 'system-monitor') {
      return SystemMonitorWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
      );
    }

    if (appId == 'cloudos:projects' || appId == 'projects') {
      return ProjectsWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        windowManager: windowManager,
      );
    }

    if (appId == 'cloudos:drive' || appId == 'drive') {
      return CloudOSDriveWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        windowManager: windowManager,
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(window.icon, size: 48, color: CloudOSColors.accent),
          const SizedBox(height: 16),
          Text(
            window.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Aplicação ID: ${window.appId}',
            style: const TextStyle(fontSize: 12, color: Colors.white60, fontFamily: 'Consolas'),
          ),
        ],
      ),
    );
  }

  List<ContextMenuItemData> _getDesktopContextMenuItems() {
    return <ContextMenuItemData>[
      ContextMenuItemData(
        title: 'Nova Pasta',
        icon: Icons.create_new_folder_outlined,
        onTap: () {
          try {
            final desktopDir = Directory('${Platform.environment['USERPROFILE'] ?? r"C:\"}\\Desktop');
            int count = 1;
            Directory target = Directory('${desktopDir.path}\\Nova Pasta');
            while (target.existsSync()) {
              count++;
              target = Directory('${desktopDir.path}\\Nova Pasta ($count)');
            }
            target.createSync(recursive: true);
            _loadBridgeData();
          } catch (e, st) {
            CloudOSLogger.error('CloudOSShell', 'createDesktopFolder', e, st);
          }
        },
      ),
      ContextMenuItemData(
        title: 'Novo Documento de Texto',
        icon: Icons.note_add_outlined,
        onTap: () {
          windowManager.openWindow('cloudos:notepad');
        },
      ),
      const ContextMenuItemData(isDivider: true, title: '', icon: Icons.circle),
      ContextMenuItemData(
        title: 'Abrir Terminal Aqui',
        icon: Icons.terminal_rounded,
        shortcut: 'Ctrl+Alt+T',
        onTap: () => windowManager.openWindow('cloudos:terminal'),
      ),
      ContextMenuItemData(
        title: 'Abrir Explorador de Arquivos',
        icon: Icons.folder_open_rounded,
        shortcut: 'Ctrl+Alt+E',
        onTap: () => windowManager.openWindow('cloudos:files'),
      ),
      ContextMenuItemData(
        title: 'Configurações do Sistema',
        icon: Icons.settings_rounded,
        onTap: () => windowManager.openWindow('cloudos:settings'),
      ),
      ContextMenuItemData(
        title: 'Atualizar Área de Trabalho',
        icon: Icons.refresh_rounded,
        shortcut: 'F5',
        onTap: () => _loadBridgeData(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, alt: true): () => windowManager.toggleWindow('cloudos:files'),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true, alt: true): () => windowManager.toggleWindow('cloudos:terminal'),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true, alt: true): () => windowManager.toggleWindow('cloudos:browser'),
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true, alt: true): _toggleQuickSettings,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, alt: true): _toggleNotifications,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true): _toggleStart,
        const SingleActivator(LogicalKeyboardKey.space, control: true): _toggleGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.tab, alt: true): _toggleAltTab,
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
              final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
              windowManager.ensureWithinBounds(viewportSize);

              return GestureDetector(
                onTap: () {
                  if (startOpen ||
                      quickSettingsOpen ||
                      notificationsOpen ||
                      isAltTabOpen ||
                      isGlobalSearchOpen ||
                      selectedDesktopIcon != null ||
                      contextMenuPosition != null) {
                    setState(() {
                      _closeTransientPanels();
                      selectedDesktopIcon = null;
                    });
                  }
                },
                onSecondaryTapDown: (details) {
                  setState(() {
                    _closeTransientPanels();
                    contextMenuPosition = details.globalPosition;
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const RepaintBoundary(child: _Wallpaper()),
                    Positioned(
                      right: 24,
                      top: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          const DesktopClockWidget(),
                          const SizedBox(height: 12),
                          DesktopMetricsWidget(bridge: widget.bridge),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 16,
                      bottom: 56,
                      child: RepaintBoundary(
                        child: _DesktopIcons(
                          selectedId: selectedDesktopIcon,
                          onSelect: (id) => setState(() => selectedDesktopIcon = id),
                          onFiles: () => windowManager.openWindow('cloudos:files'),
                          onStart: _toggleStart,
                          onTerminal: () => windowManager.openWindow('cloudos:terminal'),
                          onOpenSettings: () => windowManager.openWindow('cloudos:settings'),
                          onBrowser: () => windowManager.openWindow('cloudos:browser'),
                          onDrive: () => windowManager.openWindow('cloudos:drive'),
                          onProjects: () => windowManager.openWindow('cloudos:projects'),
                          onSystemMonitor: () => windowManager.openWindow('cloudos:system-monitor'),
                          onWsl: () => windowManager.openWindow('wsl:terminal'),
                          onNotepad: () => windowManager.openWindow('cloudos:notepad'),
                        ),
                      ),
                    ),
                    if (windowManager.activeSnapPreview != SnapRegion.none)
                      _buildSnapGhost(windowManager.activeSnapPreview, viewportSize),
                    for (final win in windowManager.windows)
                      Positioned.fill(
                        key: ValueKey<String>('window-holder-${win.id}'),
                        child: Offstage(
                          offstage:
                              win.workspaceIndex !=
                                  windowManager.activeWorkspace ||
                              win.minimized,
                          child: Stack(
                            children: <Widget>[
                              WindowFrame(
                                key: ValueKey<String>(win.id),
                                window: win,
                                windowManager: windowManager,
                                viewportSize: viewportSize,
                                child: _buildWindowContent(win),
                              ),
                            ],
                          ),
                        ),
                      ),
                    _panelSwitcher(),
                    CloudTaskbar(
                      startOpen: startOpen,
                      quickSettingsOpen: quickSettingsOpen,
                      notificationsOpen: notificationsOpen,
                      currentWorkspace: currentWorkspace,
                      onWorkspaceChanged: _switchWorkspace,
                      onStart: _toggleStart,
                      onFiles: () => windowManager.toggleWindow('cloudos:files'),
                      onBrowser: () => windowManager.toggleWindow('cloudos:browser'),
                      onTerminal: () => windowManager.toggleWindow('cloudos:terminal'),
                      onQuickSettings: _toggleQuickSettings,
                      onNotifications: _toggleNotifications,
                      windowManager: windowManager,
                    ),
                    if (isAltTabOpen)
                      AltTabOverlay(
                        windows: windowManager.currentWorkspaceWindows,
                        selectedIndex: altTabIndex,
                        onSelect: _confirmAltTab,
                        onClose: () => setState(() => isAltTabOpen = false),
                      ),
                    if (isGlobalSearchOpen)
                      GlobalSearchOverlay(
                        apps: apps,
                        bridge: widget.bridge,
                        onSelectApp: (id, {params}) =>
                            windowManager.openWindow(id, params: params),
                        onClose: () => setState(() => isGlobalSearchOpen = false),
                      ),
                    if (contextMenuPosition != null)
                      ContextMenuOverlay(
                        position: contextMenuPosition!,
                        items: _getDesktopContextMenuItems(),
                        onDismiss: () => setState(() => contextMenuPosition = null),
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

  Widget _buildSnapGhost(SnapRegion region, Size viewportSize) {
    double left = 0;
    double top = 0;
    double width = viewportSize.width;
    double height = viewportSize.height - 48.0;

    if (region == SnapRegion.left) {
      width = viewportSize.width / 2.0;
    } else if (region == SnapRegion.right) {
      left = viewportSize.width / 2.0;
      width = viewportSize.width / 2.0;
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: CloudOSColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CloudOSColors.accent.withValues(alpha: 0.6),
            width: 2,
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
          });
          windowManager.openWindow('cloudos:settings');
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
        Image.asset(
          'assets/wallpapers/cloudos_dark_bg.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.1, 0.0),
                  radius: 0.85,
                  colors: <Color>[
                    Color(0xFF1E1035),
                    Color(0xFF0C0718),
                    Color(0xFF05070B),
                  ],
                ),
              ),
            );
          },
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
    required this.onBrowser,
    required this.onDrive,
    required this.onProjects,
    required this.onSystemMonitor,
    required this.onWsl,
    required this.onNotepad,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onFiles;
  final VoidCallback onStart;
  final VoidCallback onTerminal;
  final VoidCallback onOpenSettings;
  final VoidCallback onBrowser;
  final VoidCallback onDrive;
  final VoidCallback onProjects;
  final VoidCallback onSystemMonitor;
  final VoidCallback onWsl;
  final VoidCallback onNotepad;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DesktopIcon(
              id: 'files',
              label: 'Arquivos',
              icon: Icons.folder_rounded,
              iconColor: const Color(0xFF38BDF8),
              isSelected: selectedId == 'files',
              onTap: () => onSelect('files'),
              onDoubleTap: onFiles,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'terminal',
              label: 'Terminal',
              icon: Icons.terminal_rounded,
              iconColor: const Color(0xFF10B981),
              isSelected: selectedId == 'terminal',
              onTap: () => onSelect('terminal'),
              onDoubleTap: onTerminal,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'browser',
              label: 'Navegador',
              icon: Icons.public_rounded,
              iconColor: const Color(0xFF06B6D4),
              isSelected: selectedId == 'browser',
              onTap: () => onSelect('browser'),
              onDoubleTap: onBrowser,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'notepad',
              label: 'Bloco de Notas',
              icon: Icons.edit_note_rounded,
              iconColor: const Color(0xFFF59E0B),
              isSelected: selectedId == 'notepad',
              onTap: () => onSelect('notepad'),
              onDoubleTap: onNotepad,
            ),
          ],
        ),
        const SizedBox(width: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DesktopIcon(
              id: 'drive',
              label: 'CloudOS Drive',
              icon: Icons.cloud_queue_rounded,
              iconColor: const Color(0xFF818CF8),
              isSelected: selectedId == 'drive',
              onTap: () => onSelect('drive'),
              onDoubleTap: onDrive,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'projects',
              label: 'Projetos',
              icon: Icons.account_tree_rounded,
              iconColor: const Color(0xFFA78BFA),
              isSelected: selectedId == 'projects',
              onTap: () => onSelect('projects'),
              onDoubleTap: onProjects,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'monitor',
              label: 'Monitor',
              icon: Icons.speed_rounded,
              iconColor: const Color(0xFFEC4899),
              isSelected: selectedId == 'monitor',
              onTap: () => onSelect('monitor'),
              onDoubleTap: onSystemMonitor,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'wsl',
              label: 'WSL Linux',
              icon: Icons.auto_awesome_mosaic_rounded,
              iconColor: const Color(0xFFEAB308),
              isSelected: selectedId == 'wsl',
              onTap: () => onSelect('wsl'),
              onDoubleTap: onWsl,
            ),
            const SizedBox(height: 14),
            _DesktopIcon(
              id: 'settings',
              label: 'Configurações',
              icon: Icons.settings_rounded,
              iconColor: const Color(0xFFE2E8F0),
              isSelected: selectedId == 'settings',
              onTap: () => onSelect('settings'),
              onDoubleTap: onOpenSettings,
            ),
          ],
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
    required this.iconColor,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x3338BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0x6638BDF8) : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              color: iconColor,
              size: 28,
              shadows: const <Shadow>[
                Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.15,
                shadows: <Shadow>[
                  Shadow(color: Colors.black, blurRadius: 6),
                  Shadow(color: Colors.black87, blurRadius: 3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
