import 'package:flutter/material.dart';

class CloudOSWallpaper extends StatelessWidget {
  const CloudOSWallpaper({super.key});

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

class DesktopIconGrid extends StatelessWidget {
  const DesktopIconGrid({
    super.key,
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
    this.onWsl,
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
  final VoidCallback? onWsl;
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
            if (onWsl != null) ...<Widget>[
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
            ],
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
      key: ValueKey<String>('desktop-icon-$id'),
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
            color: isSelected
                ? const Color(0x6638BDF8)
                : Colors.transparent,
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
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
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
