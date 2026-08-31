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
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onFiles;
  final VoidCallback onQuickSettings;
  final VoidCallback onNotifications;
  final bool startOpen;
  final bool quickSettingsOpen;
  final bool notificationsOpen;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: GlassSurface(
          borderRadius: 18,
          blur: 28,
          color: const Color(0xE616222D),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              _TaskButton(
                tooltip: 'Iniciar',
                icon: Icons.cloud_rounded,
                active: startOpen,
                onPressed: onStart,
                accent: true,
              ),
              const SizedBox(width: 4),
              _TaskButton(
                tooltip: 'Pesquisar',
                icon: Icons.search_rounded,
                onPressed: onStart,
              ),
              const SizedBox(width: 4),
              _TaskButton(
                tooltip: 'Arquivos',
                icon: Icons.folder_rounded,
                onPressed: onFiles,
              ),
              const SizedBox(width: 4),
              const _TaskButton(
                tooltip: 'Browser',
                icon: Icons.public_rounded,
              ),
              const SizedBox(width: 4),
              const _TaskButton(
                tooltip: 'Terminal',
                icon: Icons.terminal_rounded,
              ),
              const SizedBox(width: 14),
              Container(width: 1, height: 28, color: CloudOSColors.border),
              const SizedBox(width: 12),
              const _WorkspacePill(index: 1, selected: true),
              const SizedBox(width: 5),
              const _WorkspacePill(index: 2),
              const SizedBox(width: 5),
              const _WorkspacePill(index: 3),
              const Spacer(),
              _TrayButton(
                icon: Icons.expand_less_rounded,
                tooltip: 'Ícones ocultos',
                onPressed: onQuickSettings,
              ),
              const _TrayStatus(icon: Icons.wifi_rounded),
              const _TrayStatus(icon: Icons.volume_up_rounded),
              const _TrayStatus(icon: Icons.battery_5_bar_rounded),
              const SizedBox(width: 6),
              _ClockButton(onPressed: onNotifications),
              const SizedBox(width: 4),
              _TrayButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notificações',
                active: notificationsOpen,
                onPressed: onNotifications,
              ),
              const SizedBox(width: 4),
              _TrayButton(
                icon: Icons.tune_rounded,
                tooltip: 'Configurações rápidas',
                active: quickSettingsOpen,
                onPressed: onQuickSettings,
              ),
            ],
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool accent;

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
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active ? CloudOSColors.borderStrong : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 21,
            color: accent ? CloudOSColors.accent : CloudOSColors.text,
          ),
        ),
      ),
    );
  }
}

class _TrayStatus extends StatelessWidget {
  const _TrayStatus({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(icon, size: 16, color: CloudOSColors.secondary),
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: active ? CloudOSColors.accentSoft : Colors.transparent,
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _WorkspacePill extends StatelessWidget {
  const _WorkspacePill({required this.index, this.selected = false});

  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: selected ? 34 : 26,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? CloudOSColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? CloudOSColors.accent : CloudOSColors.border,
        ),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          color: selected ? CloudOSColors.text : CloudOSColors.caption,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(9),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text('16:40', style: TextStyle(fontSize: 11, color: CloudOSColors.text)),
            Text('31/08/2026', style: TextStyle(fontSize: 10, color: CloudOSColors.caption)),
          ],
        ),
      ),
    );
  }
}
