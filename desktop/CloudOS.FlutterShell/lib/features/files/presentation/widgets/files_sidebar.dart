import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../services/cloudos_bridge.dart';

class FilesSidebarSection {
  const FilesSidebarSection({required this.title, required this.items});

  final String title;
  final List<FilesSidebarEntry> items;
}

class FilesSidebarEntry {
  const FilesSidebarEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.badge,
    this.entryId,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String? badge;
  final String? entryId;
}

const defaultFilesSidebarSections = <FilesSidebarSection>[
  FilesSidebarSection(
    title: 'Acesso Rápido',
    items: <FilesSidebarEntry>[
      FilesSidebarEntry(
        id: 'home',
        label: 'Início',
        icon: Icons.home_rounded,
        color: CloudOSColors.accent,
      ),
      FilesSidebarEntry(
        id: 'desktop',
        label: 'Área de Trabalho',
        icon: Icons.desktop_windows_rounded,
        color: CloudOSColors.secondary,
      ),
      FilesSidebarEntry(
        id: 'documents',
        label: 'Documentos',
        icon: Icons.description_rounded,
        color: CloudOSColors.secondary,
      ),
      FilesSidebarEntry(
        id: 'downloads',
        label: 'Downloads',
        icon: Icons.download_rounded,
        color: CloudOSColors.secondary,
      ),
    ],
  ),
  FilesSidebarSection(
    title: 'Armazenamento',
    items: <FilesSidebarEntry>[
      FilesSidebarEntry(
        id: 'cloud-drive',
        label: 'CloudOS Drive',
        icon: Icons.cloud_circle_rounded,
        color: CloudOSColors.accent,
        badge: '10 GB',
      ),
      FilesSidebarEntry(
        id: 'windows-c',
        label: 'Disco Local (C:)',
        icon: Icons.storage_rounded,
        color: CloudOSColors.windows,
      ),
      FilesSidebarEntry(
        id: 'ubuntu-wsl',
        label: 'Ubuntu (WSL2)',
        icon: Icons.terminal_rounded,
        color: CloudOSColors.linux,
        badge: 'WSLg',
      ),
    ],
  ),
  FilesSidebarSection(
    title: 'Sistema',
    items: <FilesSidebarEntry>[
      FilesSidebarEntry(
        id: 'trash',
        label: 'Lixeira CloudOS',
        icon: Icons.delete_outline_rounded,
        color: CloudOSColors.secondary,
      ),
    ],
  ),
];

class FilesSidebar extends StatelessWidget {
  const FilesSidebar({
    super.key,
    required this.onSelect,
    required this.selectedId,
    this.sections,
    this.drives = const <CloudDriveInfo>[],
  });

  final List<FilesSidebarSection>? sections;
  final List<CloudDriveInfo> drives;
  final String selectedId;
  final void Function(String id, String label, {String? entryId}) onSelect;

  List<FilesSidebarSection> get _effectiveSections {
    if (sections != null && drives.isEmpty) {
      return sections!;
    }

    final result = <FilesSidebarSection>[];

    // 1. Quick Access
    result.add(
      const FilesSidebarSection(
        title: 'Acesso Rápido',
        items: <FilesSidebarEntry>[
          FilesSidebarEntry(
            id: 'home',
            label: 'Início',
            icon: Icons.home_rounded,
            color: CloudOSColors.accent,
          ),
          FilesSidebarEntry(
            id: 'desktop',
            label: 'Área de Trabalho',
            icon: Icons.desktop_windows_rounded,
            color: CloudOSColors.secondary,
          ),
          FilesSidebarEntry(
            id: 'documents',
            label: 'Documentos',
            icon: Icons.description_rounded,
            color: CloudOSColors.secondary,
          ),
          FilesSidebarEntry(
            id: 'downloads',
            label: 'Downloads',
            icon: Icons.download_rounded,
            color: CloudOSColors.secondary,
          ),
        ],
      ),
    );

    // 2. Storage / Drives
    if (drives.isNotEmpty) {
      final driveEntries = <FilesSidebarEntry>[
        const FilesSidebarEntry(
          id: 'cloud-drive',
          label: 'CloudOS Drive',
          icon: Icons.cloud_circle_rounded,
          color: CloudOSColors.accent,
          badge: '10 GB',
        ),
      ];

      for (final drive in drives) {
        final isWsl = drive.driveType == 'wsl' || drive.mountPath.contains('wsl');
        final isRemovable = drive.driveType == 'removable';
        final icon = isWsl
            ? Icons.terminal_rounded
            : (isRemovable ? Icons.usb_rounded : Icons.storage_rounded);
        final color = isWsl
            ? CloudOSColors.linux
            : (isRemovable ? Colors.orangeAccent : CloudOSColors.windows);
        final badge = isWsl
            ? 'WSL'
            : (isRemovable ? 'USB' : (drive.freeFormatted.isNotEmpty ? '${drive.freeFormatted} livre' : null));

        driveEntries.add(
          FilesSidebarEntry(
            id: 'drive:${drive.mountPath}',
            label: drive.label.isNotEmpty ? drive.label : drive.mountPath,
            icon: icon,
            color: color,
            badge: badge,
            entryId: drive.entryId,
          ),
        );
      }

      result.add(
        FilesSidebarSection(
          title: 'Armazenamento',
          items: driveEntries,
        ),
      );
    } else {
      // Default fallback
      result.add(
        const FilesSidebarSection(
          title: 'Armazenamento',
          items: <FilesSidebarEntry>[
            FilesSidebarEntry(
              id: 'cloud-drive',
              label: 'CloudOS Drive',
              icon: Icons.cloud_circle_rounded,
              color: CloudOSColors.accent,
              badge: '10 GB',
            ),
            FilesSidebarEntry(
              id: 'windows-c',
              label: 'Disco Local (C:)',
              icon: Icons.storage_rounded,
              color: CloudOSColors.windows,
            ),
            FilesSidebarEntry(
              id: 'ubuntu-wsl',
              label: 'Ubuntu (WSL2)',
              icon: Icons.terminal_rounded,
              color: CloudOSColors.linux,
              badge: 'WSLg',
            ),
          ],
        ),
      );
    }

    // 3. System
    result.add(
      const FilesSidebarSection(
        title: 'Sistema',
        items: <FilesSidebarEntry>[
          FilesSidebarEntry(
            id: 'trash',
            label: 'Lixeira CloudOS',
            icon: Icons.delete_outline_rounded,
            color: CloudOSColors.secondary,
          ),
        ],
      ),
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sectionsList = _effectiveSections;

    return Container(
      color: const Color(0x350D151E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: ListView.separated(
        itemCount: sectionsList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, sectionIndex) {
          final section = sectionsList[sectionIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  section.title.toUpperCase(),
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              for (final item in section.items) ...<Widget>[
                _SidebarItemTile(
                  entry: item,
                  selected: item.id == selectedId || (item.entryId != null && item.entryId == selectedId),
                  onTap: () => onSelect(item.id, item.label, entryId: item.entryId),
                ),
                const SizedBox(height: 2),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SidebarItemTile extends StatelessWidget {
  const _SidebarItemTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final FilesSidebarEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? CloudOSColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? CloudOSColors.accent.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              entry.icon,
              size: 16,
              color: selected ? CloudOSColors.accent : entry.color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? CloudOSColors.text
                      : CloudOSColors.secondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (entry.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: CloudOSColors.elevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.badge!,
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
