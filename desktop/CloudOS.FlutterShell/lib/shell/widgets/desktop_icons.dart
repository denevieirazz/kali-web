import 'package:flutter/material.dart';

import '../../core/cloudos_theme.dart';

class DesktopIcons extends StatelessWidget {
  const DesktopIcons({
    super.key,
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
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                shadows: <Shadow>[
                  Shadow(color: Colors.black, blurRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
