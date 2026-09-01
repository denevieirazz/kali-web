import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../services/app_registry.dart';
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
    this.notificationCount = 3,
    this.windowManager,
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
  final int notificationCount;
  final WindowManager? windowManager;

  @override
  State<CloudTaskbar> createState() => _CloudTaskbarState();
}

class _CloudTaskbarState extends State<CloudTaskbar> {
  Timer? _clockTimer;
  String _timeString = '';
  String _dateString = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    }
    widget.windowManager?.addListener(_onWindowManagerUpdate);
  }

  @override
  void didUpdateWidget(CloudTaskbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowManager != widget.windowManager) {
      oldWidget.windowManager?.removeListener(_onWindowManagerUpdate);
      widget.windowManager?.addListener(_onWindowManagerUpdate);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    widget.windowManager?.removeListener(_onWindowManagerUpdate);
    super.dispose();
  }

  void _onWindowManagerUpdate() {
    if (mounted) setState(() {});
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();

    if (mounted) {
      setState(() {
        _timeString = '$h:$m';
        _dateString = '$day/$month/$year';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wm = widget.windowManager;

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
            // Lado Esquerdo: Workspaces e Status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 1; i <= 4; i++) ...<Widget>[
                  _WorkspacePill(
                    index: i,
                    selected: widget.currentWorkspace == i,
                    onTap: () => widget.onWorkspaceChanged?.call(i),
                  ),
                  if (i < 4) const SizedBox(width: 4),
                ],
              ],
            ),

            // Centro: Botão Iniciar + Ícones de Aplicativos
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Botão Iniciar Central (4 Quadrados Estilo Windows 11 / CloudOS)
                _StartButton(
                  active: widget.startOpen,
                  onPressed: widget.onStart,
                ),
                const SizedBox(width: 6),

                // Lista de Apps Centralizados
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

            // Lado Direito: Bandeja do Sistema (Tray) e Relógio
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Quick Settings Tray Group
                _TrayQuickGroup(
                  onPressed: widget.onQuickSettings,
                  active: widget.quickSettingsOpen,
                ),
                const SizedBox(width: 8),

                // Relógio em Duas Linhas (Hora e Data)
                _ClockButton(
                  timeString: _timeString,
                  dateString: _dateString,
                  onPressed: widget.onNotifications,
                ),
                const SizedBox(width: 4),

                // Notificações
                _NotificationTrayButton(
                  active: widget.notificationsOpen,
                  count: widget.notificationCount,
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
    final pinnedApps = AppRegistry.definedApps.where((a) => a.pinned).toList();

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
            onPressed: () {
              wm.toggleWindow(app.id);
            },
          ),
        ),
      );
    }

    final openExtraWindows = wm.windows.where(
      (w) => !pinnedApps.any((a) => a.id == w.appId),
    ).toList();

    for (final win in openExtraWindows) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _TaskButton(
            tooltip: win.title,
            icon: win.icon,
            active: win.focused && !win.minimized,
            isRunning: true,
            onPressed: () {
              if (win.focused && !win.minimized) {
                wm.minimizeWindow(win.id);
              } else {
                wm.focusWindow(win.id);
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
  const _StartButton({
    required this.active,
    required this.onPressed,
  });

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
                (index) => Container(
                  decoration: BoxDecoration(
                    color: active ? CloudOSColors.neonCyan : const Color(0xFF38BDF8),
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
    final background = active
        ? CloudOSColors.active
        : Colors.transparent;

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
            color: background,
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
                color: active
                    ? Colors.white
                    : const Color(0xFFCBD5E1),
              ),
              if (isRunning)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: active ? 16 : 6,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: active ? CloudOSColors.neonCyan : CloudOSColors.secondary,
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
  const _TrayQuickGroup({required this.onPressed, required this.active});

  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Configurações Rápidas (Ctrl+Alt+Q)',
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.wifi_rounded,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.volume_up_rounded,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.battery_5_bar_rounded,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
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
    this.timeString = '',
    this.dateString = '',
  });

  final VoidCallback onPressed;
  final String timeString;
  final String dateString;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeDisplay = timeString.isNotEmpty
        ? timeString
        : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateDisplay = dateString.isNotEmpty
        ? dateString
        : '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

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
                timeDisplay,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF1F5F9),
                  height: 1.1,
                ),
              ),
              Text(
                dateDisplay,
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
    return Tooltip(
      message: 'Notificações',
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
                    '$count',
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
            color: selected ? CloudOSColors.accent : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: selected ? const Color(0xFF05070B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}
