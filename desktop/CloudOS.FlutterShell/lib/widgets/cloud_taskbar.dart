import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/app_registry.dart';
import '../services/cloudos_bridge.dart';
import '../services/desktop_clock_service.dart';
import '../services/runtime_event_service.dart';
import '../services/system_tray_state_service.dart';
import '../services/window_manager.dart';

class CloudTaskbar extends StatefulWidget {
  const CloudTaskbar({
    required this.onStart,
    required this.onFiles,
    required this.onQuickSettings,
    required this.onNotifications,
    required this.startOpen,
    required this.quickSettingsOpen,
    required this.notificationsOpen,
    this.onBrowser,
    this.onTerminal,
    this.onSettings,
    this.filesRunning = true,
    this.browserRunning = false,
    this.terminalRunning = false,
    this.currentWorkspace = 1,
    this.onWorkspaceChanged,
    this.notificationCount,
    this.windowManager,
    this.systemSnapshot,
    this.systemStateService,
    this.runtimeEventService,
    this.clockService,
    this.bridge = const CloudOSBridge(),
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onFiles;
  final VoidCallback onQuickSettings;
  final VoidCallback onNotifications;
  final VoidCallback? onBrowser;
  final VoidCallback? onTerminal;
  final VoidCallback? onSettings;
  final bool startOpen;
  final bool quickSettingsOpen;
  final bool notificationsOpen;
  final bool filesRunning;
  final bool browserRunning;
  final bool terminalRunning;
  final int currentWorkspace;
  final ValueChanged<int>? onWorkspaceChanged;

  /// Explicit compatibility/test override. Production normally leaves this
  /// null and displays RuntimeEventService.unreadCount.
  final int? notificationCount;
  final WindowManager? windowManager;

  /// Optional deterministic snapshot for tests/embedded surfaces. If null,
  /// production normally injects the Shell-owned SystemTrayStateService.
  final CloudSystemSnapshot? systemSnapshot;
  final SystemTrayStateService? systemStateService;
  final RuntimeEventService? runtimeEventService;
  final DesktopClockService? clockService;
  final CloudOSBridge bridge;

  @override
  State<CloudTaskbar> createState() => _CloudTaskbarState();
}

class _CloudTaskbarState extends State<CloudTaskbar> {
  late RuntimeEventService _runtimeEvents;
  late SystemTrayStateService _systemState;
  late DesktopClockService _clock;
  bool _ownsSystemState = false;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    widget.windowManager?.addListener(_onWindowManagerUpdate);
    _bindClock();
    _bindRuntimeSources();
  }

  void _bindClock() {
    _clock = widget.clockService ?? DesktopClockService.instance;
    _now = _clock.now;
    _clock.addListener(_onClockUpdate);
  }

  void _unbindClock() {
    _clock.removeListener(_onClockUpdate);
  }

  void _bindRuntimeSources() {
    _runtimeEvents = widget.runtimeEventService ?? RuntimeEventService.instance;
    _runtimeEvents.addListener(_onRuntimeUpdate);

    _ownsSystemState = widget.systemStateService == null;
    _systemState = widget.systemStateService ??
        SystemTrayStateService(
          bridge: widget.bridge,
          runtime: _runtimeEvents,
          pollInterval: null,
        );
    _systemState.addListener(_onSystemStateUpdate);

    // Runtime ownership belongs to main()/CloudOSShell. An isolated taskbar
    // never starts native channels or background polling merely because it was
    // mounted. This makes tests and embedded surfaces deterministic.
  }

  void _unbindRuntimeSources() {
    _runtimeEvents.removeListener(_onRuntimeUpdate);
    _systemState.removeListener(_onSystemStateUpdate);
    if (_ownsSystemState) _systemState.dispose();
  }

  @override
  void didUpdateWidget(covariant CloudTaskbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowManager != widget.windowManager) {
      oldWidget.windowManager?.removeListener(_onWindowManagerUpdate);
      widget.windowManager?.addListener(_onWindowManagerUpdate);
    }

    if (!identical(oldWidget.clockService, widget.clockService)) {
      _unbindClock();
      _bindClock();
    }

    if (!identical(oldWidget.runtimeEventService, widget.runtimeEventService) ||
        !identical(oldWidget.systemStateService, widget.systemStateService) ||
        !identical(oldWidget.bridge, widget.bridge)) {
      _unbindRuntimeSources();
      _bindRuntimeSources();
    }
  }

  @override
  void dispose() {
    widget.windowManager?.removeListener(_onWindowManagerUpdate);
    _unbindClock();
    _unbindRuntimeSources();
    super.dispose();
  }

  void _onWindowManagerUpdate() {
    if (mounted) setState(() {});
  }

  void _onRuntimeUpdate() {
    if (mounted && widget.notificationCount == null) setState(() {});
  }

  void _onSystemStateUpdate() {
    if (mounted && widget.systemSnapshot == null) setState(() {});
  }

  void _onClockUpdate() {
    if (!mounted) return;
    final next = _clock.now;
    if (next == _now) return;
    setState(() => _now = next);
  }

  String get _timeString {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get _dateString {
    final day = _now.day.toString().padLeft(2, '0');
    final month = _now.month.toString().padLeft(2, '0');
    return '$day/$month/${_now.year}';
  }

  CloudSystemSnapshot get _visibleSystemSnapshot =>
      (widget.systemSnapshot ?? _systemState.snapshot).normalized();

  int get _visibleNotificationCount {
    final explicit = widget.notificationCount;
    if (explicit != null) return explicit < 0 ? 0 : explicit;
    return _runtimeEvents.unreadCount;
  }

  @override
  Widget build(BuildContext context) {
    final wm = widget.windowManager;
    final systemSnapshot = _visibleSystemSnapshot;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xF6090B12),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 1; i <= 4; i++) ...<Widget>[
                  _WorkspacePill(
                    index: i,
                    selected: widget.currentWorkspace == i,
                    onTap: () => widget.onWorkspaceChanged?.call(i),
                  ),
                  if (i < 4) const SizedBox(width: 4),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StartButton(
                  active: widget.startOpen,
                  onPressed: widget.onStart,
                ),
                const SizedBox(width: 6),
                if (wm != null)
                  ..._buildWindowManagerTaskItems(wm)
                else ...<Widget>[
                  _TaskButton(
                    tooltip: 'Arquivos (Ctrl+Alt+E)',
                    icon: Icons.folder_rounded,
                    active: false,
                    isRunning: widget.filesRunning,
                    onPressed: widget.onFiles,
                  ),
                  const SizedBox(width: 4),
                  _TaskButton(
                    tooltip: 'Navegador Web',
                    icon: Icons.language_rounded,
                    active: false,
                    isRunning: widget.browserRunning,
                    onPressed: widget.onBrowser,
                  ),
                  const SizedBox(width: 4),
                  _TaskButton(
                    tooltip: 'Terminal ConPTY (Ctrl+Alt+Enter)',
                    icon: Icons.terminal_rounded,
                    active: false,
                    isRunning: widget.terminalRunning,
                    onPressed: widget.onTerminal,
                  ),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _TrayQuickGroup(
                  onPressed: widget.onQuickSettings,
                  active: widget.quickSettingsOpen,
                  snapshot: systemSnapshot,
                  brokerConnected: _systemState.brokerConnected,
                ),
                const SizedBox(width: 8),
                _ClockButton(
                  timeString: _timeString,
                  dateString: _dateString,
                  onPressed: widget.onNotifications,
                ),
                const SizedBox(width: 4),
                _NotificationTrayButton(
                  active: widget.notificationsOpen,
                  count: _visibleNotificationCount,
                  onPressed: widget.onNotifications,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildWindowManagerTaskItems(WindowManager wm) {
    final items = <Widget>[];
    final pinnedApps = AppRegistry.definedApps.where((app) => app.pinned).toList();

    for (final app in pinnedApps) {
      final isOpen = wm.isAppOpen(app.id);
      final isFocused = wm.isAppFocused(app.id);
      items.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _TaskButton(
            tooltip: app.name,
            icon: app.icon,
            active: isFocused,
            isRunning: isOpen,
            onPressed: () => wm.toggleWindow(app.id),
          ),
        ),
      );
    }

    final openExtraWindows = wm.windows
        .where((window) => !pinnedApps.any((app) => app.id == window.appId))
        .toList(growable: false);
    for (final window in openExtraWindows) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _TaskButton(
            tooltip: window.title,
            icon: window.icon,
            active: window.focused && !window.minimized,
            isRunning: true,
            onPressed: () {
              if (window.focused && !window.minimized) {
                wm.minimizeWindow(window.id);
              } else {
                wm.focusWindow(window.id);
              }
            },
          ),
        ),
      );
    }
    return items;
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Iniciar (Ctrl+Alt+A)',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 38,
          decoration: BoxDecoration(
            color: active ? CloudOSColors.active : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 18,
            height: 18,
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 2.5,
              mainAxisSpacing: 2.5,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(
                4,
                (_) => Container(
                  decoration: BoxDecoration(
                    color: active
                        ? CloudOSColors.neonCyan
                        : const Color(0xFF38BDF8),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskButton extends StatelessWidget {
  const _TaskButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.active = false,
    this.isRunning = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 38,
          decoration: BoxDecoration(
            color: active ? CloudOSColors.active : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: active ? Colors.white : const Color(0xFFCBD5E1),
              ),
              if (isRunning)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: active ? 16 : 6,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: active
                          ? CloudOSColors.neonCyan
                          : CloudOSColors.secondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayQuickGroup extends StatelessWidget {
  const _TrayQuickGroup({
    required this.onPressed,
    required this.active,
    required this.snapshot,
    required this.brokerConnected,
  });

  final VoidCallback onPressed;
  final bool active;
  final CloudSystemSnapshot snapshot;
  final bool brokerConnected;

  IconData get _networkIcon => snapshot.networkAvailable
      ? Icons.wifi_rounded
      : Icons.signal_wifi_off_rounded;

  IconData get _volumeIcon {
    if (!snapshot.volumeAvailable) return Icons.volume_off_outlined;
    if (snapshot.volume <= 0.001) return Icons.volume_off_rounded;
    if (snapshot.volume < 0.34) return Icons.volume_mute_rounded;
    if (snapshot.volume < 0.67) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  IconData _batteryIcon(int percent) {
    if (percent <= 10) return Icons.battery_0_bar_rounded;
    if (percent <= 25) return Icons.battery_1_bar_rounded;
    if (percent <= 40) return Icons.battery_2_bar_rounded;
    if (percent <= 55) return Icons.battery_3_bar_rounded;
    if (percent <= 70) return Icons.battery_4_bar_rounded;
    if (percent <= 85) return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  String get _networkTooltip {
    if (!snapshot.networkAvailable) return 'Rede indisponível';
    final name = snapshot.networkName.trim();
    return name.isEmpty ? 'Rede conectada' : 'Rede: $name';
  }

  String get _volumeTooltip {
    if (!snapshot.volumeAvailable) return 'Volume indisponível';
    return 'Volume: ${(snapshot.volume * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: brokerConnected
          ? 'Configurações Rápidas (Ctrl+Alt+Q)'
          : 'Configurações Rápidas · EventBus reconectando',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Tooltip(
                message: _networkTooltip,
                child: Icon(
                  _networkIcon,
                  size: 15,
                  color: snapshot.networkAvailable
                      ? const Color(0xFF94A3B8)
                      : Colors.white38,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: _volumeTooltip,
                child: Icon(
                  _volumeIcon,
                  size: 15,
                  color: snapshot.volumeAvailable
                      ? const Color(0xFF94A3B8)
                      : Colors.white38,
                ),
              ),
              if (snapshot.batteryAvailable) ...<Widget>[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Bateria: ${snapshot.batteryPercent}%',
                  child: Icon(
                    _batteryIcon(snapshot.batteryPercent),
                    size: 15,
                    color: snapshot.batteryPercent <= 15
                        ? Colors.orangeAccent
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
              if (!brokerConnected) ...<Widget>[
                const SizedBox(width: 7),
                const Tooltip(
                  message: 'Canal de eventos do System Broker desconectado',
                  child: Icon(
                    Icons.link_off_rounded,
                    size: 13,
                    color: Colors.orangeAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockButton extends StatelessWidget {
  const _ClockButton({
    required this.onPressed,
    required this.timeString,
    required this.dateString,
  });

  final VoidCallback onPressed;
  final String timeString;
  final String dateString;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Data e Notificações',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                timeString,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF1F5F9),
                  height: 1.1,
                ),
              ),
              Text(
                dateString,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF94A3B8),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTrayButton extends StatelessWidget {
  const _NotificationTrayButton({
    required this.active,
    required this.count,
    required this.onPressed,
  });

  final bool active;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final displayCount = count > 99 ? '99+' : '$count';
    return Tooltip(
      message: count > 0
          ? '$count notificação(ões) não lida(s)'
          : 'Notificações',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.notifications_outlined,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: CloudOSColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    displayCount,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF05070B),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspacePill extends StatelessWidget {
  const _WorkspacePill({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Área $index (Ctrl+Alt+$index)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: selected
                ? CloudOSColors.accent
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: selected
                  ? const Color(0xFF05070B)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}
