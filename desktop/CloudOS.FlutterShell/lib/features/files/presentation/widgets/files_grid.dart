import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class FilesGrid extends StatelessWidget {
  const FilesGrid({
    required this.files,
    required this.selectedPath,
    required this.onSelect,
    super.key,
  });

  final List<CloudFileItem> files;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 116,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        return _FileGridCard(
          item: item,
          isSelected: item.path == selectedPath,
          onTap: () => onSelect(item.path),
        );
      },
    );
  }
}

class _FileGridCard extends StatelessWidget {
  const _FileGridCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final CloudFileItem item;
  final bool isSelected;
  final VoidCallback onTap;

  Color get sourceColor => switch (item.source) {
        CloudFileSource.windows => CloudOSColors.windows,
        CloudFileSource.linux => CloudOSColors.linux,
        CloudFileSource.cloudDrive => CloudOSColors.accent,
        CloudFileSource.trash => CloudOSColors.danger,
      };

  String get sourceLabel => switch (item.source) {
        CloudFileSource.windows => 'Win',
        CloudFileSource.linux => 'WSL',
        CloudFileSource.cloudDrive => 'Cloud',
        CloudFileSource.trash => 'Lixeira',
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? CloudOSColors.accentSoft
              : CloudOSColors.elevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  item.icon ??
                      (item.isFolder
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded),
                  color: item.isFolder
                      ? CloudOSColors.accent
                      : CloudOSColors.secondary,
                  size: 28,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sourceLabel,
                    style: TextStyle(
                      color: sourceColor,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${item.sizeFormatted} • ${item.modifiedFormatted}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}
