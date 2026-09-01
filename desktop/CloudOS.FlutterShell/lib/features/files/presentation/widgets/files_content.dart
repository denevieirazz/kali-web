import 'package:flutter/material.dart';

import '../../../../models/shell_models.dart';
import 'files_empty_state.dart';
import 'files_grid.dart';
import 'files_list.dart';

class FilesContent extends StatelessWidget {
  const FilesContent({
    required this.files,
    required this.query,
    required this.isGridView,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpen,
    super.key,
  });

  final List<CloudFileItem> files;
  final String query;
  final bool isGridView;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<CloudFileItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return FilesEmptyState(query: query);
    }
    if (isGridView) {
      return FilesGrid(
        files: files,
        selectedPath: selectedPath,
        onSelect: onSelect,
        onOpen: onOpen,
      );
    }
    return FilesList(
      files: files,
      selectedPath: selectedPath,
      onSelect: onSelect,
      onOpen: onOpen,
    );
  }
}
