import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import 'glass_surface.dart';

class CloudTaskbar extends StatelessWidget {
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
    this.notificationCount = 0,
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

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassSurface(
          borderRadius: 14,
          blur: 24,
          color: const Color(0xF2131C27),
          borderColor: CloudOSColors.border,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                _TaskButton(
                  tooltip: 'Iniciar (Ctrl+Alt+A)',
                  icon: Icons.cloud_rounded,
                  active: startOpen,
                  onPressed: onStart,
                  accent: true,
                ),
                const SizedBox(width: 4),
                _TaskButton(
                  tooltip: 'Pesquisa Global (Ctrl+Alt+S)',
                  icon: Icons.search_rounded,
                  active: startOpen,
                  onPressed: onStart,
                ),
                const SizedBox(width: 4),
                _TaskButton(
                  tooltip: 'Arquivos (Ctrl+Alt+E)',
                  icon: Icons.folder_rounded,
                  active: false,
                  isRunning: filesRunning,
                  onPressed: onFiles,
                ),
                const SizedBox(width: 4),
                _TaskButton(
                  tooltip: 'Navegador Web',
                  icon: Icons.language_rounded,
                  active: false,
                  isRunning: browserRunning,
                  onPressed: onBrowser,
                ),
                const SizedBox(width: 4),
                _TaskButton(
                  tooltip: 'Terminal ConPTY (Ctrl+Alt+Enter)',
                  icon: Icons.terminal_rounded,
                  active: false,
                  isRunning: terminalRunning,
                  onPressed: onTerminal,
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 22, color: CloudOSColors.border),
                const SizedBox(width: 10),
                for (int i = 1; i <= 4; i++) ...<Widget>[
                  _WorkspacePill(
                    index: i,
                    selected: currentWorkspace == i,
                    onTap: () => onWorkspaceChanged?.call(i),
                  ),
                  if (i < 4) const SizedBox(width: 4),
                ],
                const Spacer(),
                _TrayQuickGroup(
                  onPressed: onQuickSettings,
                  active: quickSettingsOpen,
                ),
                const SizedBox(width: 6),
                _ClockButton(onPressed: onNotifications),
                const SizedBox(width: 4),
                _NotificationTrayButton(
                  active: notificationsOpen,
                  count: notificationCount,
                  onPressed: onNotifications,
                ),
              ],
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
    this.accent = false,
    this.isRunning = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool accent;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? CloudOSColors.active
        : accent
        ? CloudOSColors.accentSoft
        : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
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
                color: accent
                    ? CloudOSColors.accent
                    : active
                    ? CloudOSColors.text
                    : CloudOSColors.secondary,
              ),
              if (isRunning && !active)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 14,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: CloudOSColors.accent,
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
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
                color: CloudOSColors.secondary,
              ),
              SizedBox(width: 6),
              Icon(
                Icons.volume_up_rounded,
                size: 15,
                color: CloudOSColors.secondary,
              ),
              SizedBox(width: 6),
              Icon(
                Icons.battery_5_bar_rounded,
                size: 15,
                color: CloudOSColors.secondary,
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                size: 16,
                color: count > 0
                    ? CloudOSColors.accent
                    : CloudOSColors.secondary,
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: CloudOSColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
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
    this.selected = false,
    this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Área de Trabalho $index (Ctrl+Alt+$index)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 28 : 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? CloudOSColors.accent : CloudOSColors.border,
            ),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: selected ? CloudOSColors.text : CloudOSColors.caption,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockButton extends StatelessWidget {
  const _ClockButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();

    return Tooltip(
      message: 'Calendário e Notificações',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$hour:$minute',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: CloudOSColors.text,
                ),
              ),
              Text(
                '$day/$month/$year',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: CloudOSColors.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
