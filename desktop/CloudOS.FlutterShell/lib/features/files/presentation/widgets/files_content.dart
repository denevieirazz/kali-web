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
    required this.onSelect,
    required this.onOpen,
    this.selectedPath,
    this.selectedPaths = const <String>{},
    this.cutPaths = const <String>{},
    super.key,
  });

  final List<CloudFileItem> files;
  final String query;
  final bool isGridView;
  final String? selectedPath;
  final Set<String> selectedPaths;
  final Set<String> cutPaths;
  final void Function(CloudFileItem item, {bool isCtrl, bool isShift}) onSelect;
  final ValueChanged<CloudFileItem> onOpen;

  Set<String> get _effectiveSelectedPaths {
    if (selectedPaths.isNotEmpty) return selectedPaths;
    if (selectedPath != null && selectedPath!.isNotEmpty) {
      return <String>{selectedPath!};
    }
    return const <String>{};
  }

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return FilesEmptyState(query: query);
    }
    if (isGridView) {
      return FilesGrid(
        files: files,
        selectedPaths: _effectiveSelectedPaths,
        cutPaths: cutPaths,
        onSelect: onSelect,
        onOpen: onOpen,
      );
    }
    return FilesList(
      files: files,
      selectedPaths: _effectiveSelectedPaths,
      cutPaths: cutPaths,
      onSelect: onSelect,
      onOpen: onOpen,
    );
  }
}
