import 'package:flutter/material.dart';

import '../../core/cloudos_theme.dart';

class DesktopItemData {
  const DesktopItemData({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.position,
    this.badge,
    this.isCustomFolder = false,
    this.isCustomFile = false,
    this.customPath,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final Offset position;
  final String? badge;
  final bool isCustomFolder;
  final bool isCustomFile;
  final String? customPath;

  DesktopItemData copyWith({
    String? id,
    String? label,
    IconData? icon,
    Color? color,
    Offset? position,
    String? badge,
    bool? isCustomFolder,
    bool? isCustomFile,
    String? customPath,
  }) {
    return DesktopItemData(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      position: position ?? this.position,
      badge: badge ?? this.badge,
      isCustomFolder: isCustomFolder ?? this.isCustomFolder,
      isCustomFile: isCustomFile ?? this.isCustomFile,
      customPath: customPath ?? this.customPath,
    );
  }
}

List<DesktopItemData> getDefaultDesktopItems() {
  return <DesktopItemData>[
    const DesktopItemData(
      id: 'files',
      label: 'Arquivos',
      icon: Icons.folder_rounded,
      color: CloudOSColors.accent,
      position: Offset(20, 20),
    ),
    const DesktopItemData(
      id: 'apps',
      label: 'Aplicativos',
      icon: Icons.apps_rounded,
      color: CloudOSColors.success,
      position: Offset(20, 114),
    ),
    const DesktopItemData(
      id: 'ubuntu',
      label: 'Ubuntu WSL',
      icon: Icons.terminal_rounded,
      color: CloudOSColors.linux,
      badge: 'WSL2',
      position: Offset(20, 208),
    ),
    const DesktopItemData(
      id: 'drive',
      label: 'CloudOS Drive',
      icon: Icons.cloud_circle_rounded,
      color: CloudOSColors.accent,
      position: Offset(20, 302),
    ),
    const DesktopItemData(
      id: 'settings',
      label: 'Configurações',
      icon: Icons.settings_rounded,
      color: CloudOSColors.secondary,
      position: Offset(20, 396),
    ),
    const DesktopItemData(
      id: 'trash',
      label: 'Lixeira',
      icon: Icons.delete_outline_rounded,
      color: CloudOSColors.caption,
      position: Offset(20, 490),
    ),
  ];
}

class DesktopIcons extends StatelessWidget {
  const DesktopIcons({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.items,
    this.onItemMoved,
    this.onItemDoubleTap,
    this.onItemSecondaryTap,
    this.onFiles,
    this.onStart,
    this.onTerminal,
    this.onOpenSettings,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final List<DesktopItemData>? items;
  final void Function(String id, Offset newPosition)? onItemMoved;
  final void Function(DesktopItemData item)? onItemDoubleTap;
  final void Function(DesktopItemData item, Offset globalPosition)? onItemSecondaryTap;
  final VoidCallback? onFiles;
  final VoidCallback? onStart;
  final VoidCallback? onTerminal;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (items == null) {
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

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final item in items!)
          Positioned(
            left: item.position.dx,
            top: item.position.dy,
            child: Draggable<DesktopItemData>(
              data: item,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.85,
                  child: _DesktopIcon(
                    id: item.id,
                    label: item.label,
                    icon: item.icon,
                    color: item.color,
                    badge: item.badge,
                    isSelected: true,
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _DesktopIcon(
                  id: item.id,
                  label: item.label,
                  icon: item.icon,
                  color: item.color,
                  badge: item.badge,
                  isSelected: selectedId == item.id,
                ),
              ),
              onDragEnd: (details) {
                onItemMoved?.call(item.id, details.offset);
              },
              child: _DesktopIcon(
                id: item.id,
                label: item.label,
                icon: item.icon,
                color: item.color,
                badge: item.badge,
                isSelected: selectedId == item.id,
                onTap: () => onSelect(item.id),
                onDoubleTap: () => onItemDoubleTap?.call(item),
                onSecondaryTapUp: (pos) => onItemSecondaryTap?.call(item, pos),
              ),
            ),
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
    this.onSecondaryTapUp,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String? badge;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('desktop-icon-$id'),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapUp: onSecondaryTapUp != null
            ? (details) => onSecondaryTapUp!(details.globalPosition)
            : null,
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
            mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}
