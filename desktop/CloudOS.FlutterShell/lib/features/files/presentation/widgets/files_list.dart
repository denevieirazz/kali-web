import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class FilesList extends StatelessWidget {
  const FilesList({
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final item = files[index];
        final isSelected = item.path == selectedPath;
        return InkWell(
          onTap: () => onSelect(item.path),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? CloudOSColors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? CloudOSColors.accent.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon ??
                      (item.isFolder
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded),
                  size: 17,
                  color: item.isFolder
                      ? CloudOSColors.accent
                      : CloudOSColors.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.text, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.modifiedFormatted,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    item.sizeFormatted,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
