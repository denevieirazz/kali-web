import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../models/window_model.dart';
import '../services/app_registry.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/desktop_broker_service.dart';
import '../services/session_service.dart';
import '../services/window_manager.dart';
import '../widgets/alt_tab_overlay.dart';
import '../widgets/browser_window.dart';
import '../widgets/cloud_taskbar.dart';
import '../widgets/cloudos_drive_window.dart';
import '../widgets/context_menu.dart';
import '../widgets/desktop_surface.dart';
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

class _CloudOSShellState extends State<CloudOSShell>
    with WidgetsBindingObserver {
  final WindowManager windowManager = WindowManager();
  late DesktopBrokerService _desktopService;

  List<CloudApp> apps = const <CloudApp>[];
  CloudSystemSnapshot snapshot = CloudOSBridge.unavailableSnapshot;
  bool startOpen = false;
  bool quickSettingsOpen = false;
  bool notificationsOpen = false;
  bool isAltTabOpen = false;
  int altTabIndex = 0;
  String? altTabWindowId;
  bool isGlobalSearchOpen = false;
  int currentWorkspace = 1;
  String? selectedDesktopIcon;
  Offset? contextMenuPosition;

  @override
  void initState() {
    super.initState();
    _desktopService = DesktopBrokerService(widget.bridge);
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(_onWindowManagerUpdate);
    unawaited(_loadBridgeData());
    unawaited(_restoreDesktopSession());
  }

  @override
  void didUpdateWidget(covariant CloudOSShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bridge, widget.bridge)) {
      _desktopService = DesktopBrokerService(widget.bridge);
      unawaited(_loadBridgeData());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(windowManager.flushSession());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(_onWindowManagerUpdate);
    unawaited(windowManager.flushSession());
    windowManager.dispose();
    super.dispose();
  }

  void _onWindowManagerUpdate() {
    if (!mounted) return;
    setState(() {
      currentWorkspace = windowManager.activeWorkspace;
      if (isAltTabOpen) {
        final wins = windowManager.altTabWindows;
        final index = wins.indexWhere((window) => window.id == altTabWindowId);
        if (wins.isEmpty) {
          isAltTabOpen = false;
          altTabWindowId = null;
          altTabIndex = 0;
        } else {
          altTabIndex = index >= 0 ? index : 0;
          altTabWindowId = wins[altTabIndex].id;
        }
      }
    });
  }

  Future<void> _restoreDesktopSession() async {
    try {
      final session = await SessionService.instance.loadSession();
      if (session == null || !mounted) return;

      final rawWindows = session['windows'];
      final savedList = rawWindows is List
          ? rawWindows
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final rawWorkspace = session['activeWorkspace'];
      final savedWorkspace = rawWorkspace is num
          ? rawWorkspace.toInt().clamp(1, 4).toInt()
          : 1;
      final rawMru = session['mruWindowIds'];
      final savedMru = rawMru is List
          ? rawMru.whereType<String>().toList(growable: false)
          : const <String>[];

      windowManager.restoreSavedWindows(
        savedList,
        savedWorkspace,
        savedMru,
      );
      if (mounted) {
        setState(() => currentWorkspace = windowManager.activeWorkspace);
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'CloudOSShell',
        'restoreSession',
        error,
        stackTrace,
      );
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
    altTabWindowId = null;
    isGlobalSearchOpen = false;
    contextMenuPosition = null;
  }

  void _closePanelsExceptAltTab() {
    startOpen = false;
    quickSettingsOpen = false;
    notificationsOpen = false;
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

  void _toggleAltTab({bool forward = true}) {
    final wins = windowManager.altTabWindows;
    if (wins.isEmpty) return;

    setState(() {
      if (!isAltTabOpen) {
        isAltTabOpen = true;
        _closePanelsExceptAltTab();
        altTabWindowId = windowManager.cycleAltTab(
              currentId: windowManager.focusedWindow?.id,
              forward: forward,
            ) ??
            wins.first.id;
      } else {
        altTabWindowId = windowManager.cycleAltTab(
              currentId: altTabWindowId,
              forward: forward,
            ) ??
            wins.first.id;
      }
      final refreshed = windowManager.altTabWindows;
      final index = refreshed.indexWhere(
        (window) => window.id == altTabWindowId,
      );
      altTabIndex = index >= 0 ? index : 0;
    });
  }

  void _confirmAltTab(int index) {
    final wins = windowManager.altTabWindows;
    if (index >= 0 && index < wins.length) {
      windowManager.focusWindow(wins[index].id);
    }
    if (!mounted) return;
    setState(() {
      isAltTabOpen = false;
      altTabWindowId = null;
    });
  }

  void _cancelAltTab() {
    if (!isAltTabOpen) return;
    setState(() {
      isAltTabOpen = false;
      altTabWindowId = null;
    });
  }

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (isAltTabOpen && event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight) {
        _confirmAltTab(altTabIndex);
        return KeyEventResult.handled;
      }
    }
    if (isAltTabOpen &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelAltTab();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _switchWorkspace(int index) {
    windowManager.setWorkspace(index);
    setState(() {
      currentWorkspace = windowManager.activeWorkspace;
      _closeTransientPanels();
    });
  }

  Future<void> _createDesktopFolder() async {
    final createdPath = await _desktopService.createUniqueFolder();
    if (!mounted) return;
    if (createdPath == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível criar a pasta no Desktop pelo Files Broker.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Pasta criada: $createdPath')),
    );
  }

  Future<void> _openTerminalAtDesktop() async {
    final desktop = await _desktopService.desktopPath();
    if (!mounted) return;
    if (desktop == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('O Desktop não foi retornado pelo Files Broker.'),
        ),
      );
      return;
    }
    windowManager.openWindow(
      'cloudos:terminal',
      params: <String, dynamic>{'initialWorkingDirectory': desktop},
    );
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
    final normalized = app.id.toLowerCase();
    if (normalized.startsWith('wsl:')) {
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

    final definition = AppRegistry.findById(app.id);
    if (definition != null && definition.isInternal) {
      windowManager.openWindow(definition.id);
      if (mounted) setState(_closeTransientPanels);
      return;
    }

    final launched = await widget.bridge.launchApp(app.id);
    if (!mounted) return;
    setState(_closeTransientPanels);
    if (!launched) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Não foi possível abrir ${app.name}.')),
      );
    }
  }

  String? _initialWorkingDirectory(CloudWindow window) {
    final value = window.customParams['initialWorkingDirectory'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
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
        initialWorkingDirectory: _initialWorkingDirectory(window),
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
        initialWorkingDirectory: _initialWorkingDirectory(window),
      );
    }

    if (appId == 'cloudos:browser' || appId == 'browser') {
      return BrowserWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        isVisible: window.workspaceIndex == windowManager.activeWorkspace &&
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
      final initialPage = window.customParams['initialSettingsPage'];
      return SettingsWindow(
        key: ValueKey<String>(window.id),
        bridge: widget.bridge,
        initialPageId: initialPage is String ? initialPage : null,
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aplicação ID: ${window.appId}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white60,
              fontFamily: 'Consolas',
            ),
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
        onTap: () => unawaited(_createDesktopFolder()),
      ),
      ContextMenuItemData(
        title: 'Novo Documento de Texto',
        icon: Icons.note_add_outlined,
        onTap: () => windowManager.openWindow('cloudos:notepad'),
      ),
      const ContextMenuItemData(
        isDivider: true,
        title: '',
        icon: Icons.circle,
      ),
      ContextMenuItemData(
        title: 'Abrir Terminal Aqui',
        icon: Icons.terminal_rounded,
        shortcut: 'Ctrl+Alt+T',
        onTap: () => unawaited(_openTerminalAtDesktop()),
      ),
      ContextMenuItemData(
        title: 'Abrir Explorador de Arquivos',
        icon: Icons.folder_open_rounded,
        shortcut: 'Ctrl+Alt+E',
        onTap: () => windowManager.openWindow('cloudos:files'),
      ),
      ContextMenuItemData(
        title: 'Mostrar Área de Trabalho',
        icon: Icons.desktop_windows_rounded,
        shortcut: 'Ctrl+Alt+D',
        onTap: windowManager.toggleShowDesktop,
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
        onTap: () => unawaited(_loadBridgeData()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
          alt: true,
        ): () => windowManager.toggleWindow('cloudos:files'),
        const SingleActivator(
          LogicalKeyboardKey.keyT,
          control: true,
          alt: true,
        ): () => windowManager.toggleWindow('cloudos:terminal'),
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          alt: true,
        ): () => windowManager.toggleWindow('cloudos:browser'),
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
          alt: true,
        ): windowManager.toggleShowDesktop,
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
          LogicalKeyboardKey.space,
          control: true,
        ): _toggleGlobalSearch,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          alt: true,
          shift: true,
        ): () => _toggleAltTab(forward: false),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          alt: true,
        ): () => _toggleAltTab(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (isAltTabOpen) {
            _cancelAltTab();
          } else {
            setState(_closeTransientPanels);
          }
        },
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
        onKeyEvent: _handleRootKeyEvent,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
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
                    const RepaintBoundary(child: CloudOSWallpaper()),
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
                        child: DesktopIconGrid(
                          selectedId: selectedDesktopIcon,
                          onSelect: (id) =>
                              setState(() => selectedDesktopIcon = id),
                          onFiles: () =>
                              windowManager.openWindow('cloudos:files'),
                          onStart: _toggleStart,
                          onTerminal: () =>
                              windowManager.openWindow('cloudos:terminal'),
                          onOpenSettings: () =>
                              windowManager.openWindow('cloudos:settings'),
                          onBrowser: () =>
                              windowManager.openWindow('cloudos:browser'),
                          onDrive: () =>
                              windowManager.openWindow('cloudos:drive'),
                          onProjects: () =>
                              windowManager.openWindow('cloudos:projects'),
                          onSystemMonitor: () =>
                              windowManager.openWindow('cloudos:system-monitor'),
                          onWsl: snapshot.wslAvailable &&
                                  snapshot.distros.isNotEmpty
                              ? () {
                                  final distro = snapshot.defaultDistro.isNotEmpty
                                      ? snapshot.defaultDistro
                                      : snapshot.distros.first;
                                  windowManager.openWindow(
                                    'wsl:terminal',
                                    params: <String, dynamic>{
                                      'initialDistro': distro,
                                    },
                                  );
                                }
                              : null,
                          onNotepad: () =>
                              windowManager.openWindow('cloudos:notepad'),
                        ),
                      ),
                    ),
                    if (windowManager.activeSnapPreview != SnapRegion.none)
                      _buildSnapGhost(
                        windowManager.activeSnapPreview,
                        viewportSize,
                      ),
                    for (final window in windowManager.windows)
                      Positioned.fill(
                        key: ValueKey<String>('window-holder-${window.id}'),
                        child: Offstage(
                          offstage: window.workspaceIndex !=
                                  windowManager.activeWorkspace ||
                              window.minimized,
                          child: Stack(
                            children: <Widget>[
                              WindowFrame(
                                key: ValueKey<String>(window.id),
                                window: window,
                                windowManager: windowManager,
                                viewportSize: viewportSize,
                                child: _buildWindowContent(window),
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
                      onFiles: () =>
                          windowManager.toggleWindow('cloudos:files'),
                      onBrowser: () =>
                          windowManager.toggleWindow('cloudos:browser'),
                      onTerminal: () =>
                          windowManager.toggleWindow('cloudos:terminal'),
                      onQuickSettings: _toggleQuickSettings,
                      onNotifications: _toggleNotifications,
                      windowManager: windowManager,
                    ),
                    if (isAltTabOpen)
                      AltTabOverlay(
                        windows: windowManager.altTabWindows,
                        selectedIndex: altTabIndex,
                        onSelect: _confirmAltTab,
                        onClose: _cancelAltTab,
                      ),
                    if (isGlobalSearchOpen)
                      GlobalSearchOverlay(
                        apps: apps,
                        bridge: widget.bridge,
                        onSelectApp: (id, {params}) =>
                            windowManager.openWindow(id, params: params),
                        onClose: () =>
                            setState(() => isGlobalSearchOpen = false),
                      ),
                    if (contextMenuPosition != null)
                      ContextMenuOverlay(
                        position: contextMenuPosition!,
                        items: _getDesktopContextMenuItems(),
                        onDismiss: () =>
                            setState(() => contextMenuPosition = null),
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
    var left = 0.0;
    var top = 0.0;
    var width = viewportSize.width;
    var height = (viewportSize.height - 48.0)
        .clamp(0.0, double.infinity)
        .toDouble();
    final halfWidth = viewportSize.width / 2.0;
    final halfHeight = height / 2.0;

    switch (region) {
      case SnapRegion.left:
        width = halfWidth;
        break;
      case SnapRegion.right:
        left = halfWidth;
        width = halfWidth;
        break;
      case SnapRegion.topLeft:
        width = halfWidth;
        height = halfHeight;
        break;
      case SnapRegion.topRight:
        left = halfWidth;
        width = halfWidth;
        height = halfHeight;
        break;
      case SnapRegion.bottomLeft:
        top = halfHeight;
        width = halfWidth;
        height = halfHeight;
        break;
      case SnapRegion.bottomRight:
        left = halfWidth;
        top = halfHeight;
        width = halfWidth;
        height = halfHeight;
        break;
      case SnapRegion.top:
      case SnapRegion.none:
        break;
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
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
      ),
    );
  }

  Widget _panelSwitcher() {
    Widget child = const SizedBox.shrink(key: ValueKey<String>('none'));
    if (startOpen) {
      child = StartPanel(
        key: const ValueKey<String>('start'),
        apps: apps,
        bridge: widget.bridge,
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
          setState(() => quickSettingsOpen = false);
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
