import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class FilesGrid extends StatelessWidget {
  const FilesGrid({
    required this.files,
    required this.selectedPaths,
    required this.onSelect,
    required this.onOpen,
    this.cutPaths = const <String>{},
    super.key,
  });

  final List<CloudFileItem> files;
  final Set<String> selectedPaths;
  final Set<String> cutPaths;
  final void Function(CloudFileItem item, {bool isCtrl, bool isShift}) onSelect;
  final ValueChanged<CloudFileItem> onOpen;

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
        final isSelected = selectedPaths.contains(item.path);
        final isCut = cutPaths.contains(item.path);

        return Opacity(
          opacity: isCut ? 0.5 : 1.0,
          child: _FileGridCard(
            item: item,
            isSelected: isSelected,
            onTap: () => onSelect(item),
            onDoubleTap: () => onOpen(item),
          ),
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
    required this.onDoubleTap,
  });

  final CloudFileItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

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
      onDoubleTap: onDoubleTap,
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
            width: isSelected ? 1.5 : 1.0,
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
                          : _iconForExtension(item.name)),
                  color: item.isFolder
                      ? CloudOSColors.accent
                      : _colorForExtension(item.name),
                  size: 26,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: sourceColor.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    sourceLabel,
                    style: TextStyle(
                      color: sourceColor,
                      fontSize: 9,
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
              style: TextStyle(
                color: isSelected ? Colors.white : CloudOSColors.text,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.isFolder ? 'Pasta' : item.sizeFormatted,
                    style: const TextStyle(
                      color: CloudOSColors.caption,
                      fontSize: 10,
                    ),
                  ),
                ),
                Text(
                  item.modifiedFormatted,
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return Icons.insert_drive_file_rounded;
    final ext = name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'txt' || 'md' || 'log' || 'json' || 'yaml' || 'yml' || 'xml' => Icons.description_rounded,
      'dart' || 'cpp' || 'c' || 'h' || 'hpp' || 'py' || 'js' || 'ts' || 'html' || 'css' => Icons.code_rounded,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => Icons.image_rounded,
      'mp3' || 'wav' || 'ogg' || 'flac' => Icons.audiotrack_rounded,
      'mp4' || 'mkv' || 'mov' || 'webm' => Icons.movie_rounded,
      'zip' || 'tar' || 'gz' || '7z' => Icons.archive_rounded,
      'exe' || 'msi' => Icons.terminal_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  static Color _colorForExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return CloudOSColors.secondary;
    final ext = name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'dart' || 'cpp' || 'h' || 'py' || 'js' || 'ts' => CloudOSColors.accent,
      'html' || 'css' || 'json' => Colors.amberAccent,
      'png' || 'jpg' || 'jpeg' || 'svg' => Colors.purpleAccent,
      'mp4' || 'mkv' => Colors.deepOrangeAccent,
      'zip' || 'tar' || 'gz' || '7z' => Colors.tealAccent,
      'exe' || 'msi' => Colors.redAccent,
      'pdf' => Colors.redAccent,
      _ => CloudOSColors.secondary,
    };
  }
}
