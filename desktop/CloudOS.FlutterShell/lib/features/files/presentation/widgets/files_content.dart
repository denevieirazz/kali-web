import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class FilesContent extends StatelessWidget {
  const FilesContent({
    super.key,
    required this.files,
    required this.query,
    required this.isGridView,
    required this.selectedPath,
    required this.onSelect,
  });

  final List<CloudFileItem> files;
  final String query;
  final bool isGridView;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return _EmptyFilesState(query: query);
    if (isGridView) {
      return _FilesGrid(
        files: files,
        selectedPath: selectedPath,
        onSelect: onSelect,
      );
    }
    return _FilesList(
      files: files,
      selectedPath: selectedPath,
      onSelect: onSelect,
    );
  }
}

class FilesStatusBar extends StatelessWidget {
  const FilesStatusBar({
    super.key,
    required this.itemCount,
    required this.selectedPath,
  });

  final int itemCount;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0x350D151E),
        border: Border(top: BorderSide(color: CloudOSColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$itemCount itens',
            style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
          if (selectedPath != null) ...<Widget>[
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: CloudOSColors.caption)),
            const SizedBox(width: 8),
            const Text(
              '1 item selecionado',
              style: TextStyle(
                color: CloudOSColors.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          const Icon(Icons.cloud_done_rounded, size: 13, color: CloudOSColors.success),
          const SizedBox(width: 5),
          const Text(
            'Sistema de arquivos unificado e sincronizado',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _FilesGrid extends StatelessWidget {
  const _FilesGrid({
    required this.files,
    required this.selectedPath,
    required this.onSelect,
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

class _FilesList extends StatelessWidget {
  const _FilesList({
    required this.files,
    required this.selectedPath,
    required this.onSelect,
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

class _EmptyFilesState extends StatelessWidget {
  const _EmptyFilesState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.folder_open_rounded, size: 44, color: CloudOSColors.caption),
          const SizedBox(height: 10),
          Text(
            query.isNotEmpty
                ? 'Nenhum arquivo correspondente a "$query"'
                : 'Pasta vazia',
            style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
