import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class FilesList extends StatelessWidget {
  const FilesList({
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
    return ListView.builder(
      itemExtent: 36.0,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final isSelected = selectedPaths.contains(item.path);
        final isCut = cutPaths.contains(item.path);

        return Opacity(
          opacity: isCut ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: InkWell(
              onTap: () => onSelect(item),
              onDoubleTap: () => onOpen(item),
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
                              : _iconForExtension(item.name)),
                      size: 17,
                      color: item.isFolder
                          ? CloudOSColors.accent
                          : _colorForExtension(item.name),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : CloudOSColors.text,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        item.modifiedFormatted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        item.isFolder ? '--' : item.sizeFormatted,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconForExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return Icons.insert_drive_file_rounded;
    final ext = name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'txt' || 'md' || 'log' || 'json' || 'yaml' || 'yml' || 'xml' => Icons.description_rounded,
      'dart' || 'cpp' || 'c' || 'h' || 'hpp' || 'py' || 'js' || 'ts' || 'html' || 'css' || 'sh' || 'ps1' || 'bat' => Icons.code_rounded,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' || 'bmp' || 'ico' => Icons.image_rounded,
      'mp3' || 'wav' || 'ogg' || 'flac' || 'm4a' => Icons.audiotrack_rounded,
      'mp4' || 'mkv' || 'mov' || 'webm' || 'avi' => Icons.movie_rounded,
      'zip' || 'tar' || 'gz' || '7z' || 'rar' || 'bz2' => Icons.archive_rounded,
      'exe' || 'msi' || 'dll' => Icons.terminal_rounded,
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
