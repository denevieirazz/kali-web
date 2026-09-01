import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/files_content.dart';
import 'widgets/files_sidebar.dart';
import 'widgets/files_title_bar.dart';
import 'widgets/files_toolbar.dart';

class FilesWindow extends StatefulWidget {
  const FilesWindow({
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  State<FilesWindow> createState() => _FilesWindowState();
}

class _FilesWindowState extends State<FilesWindow> {
  String currentLocation = 'home';
  String currentTitle = 'Início';
  String query = '';
  bool isGridView = true;
  String? selectedItemPath;

  List<CloudFileItem> get _currentFiles {
    final allFiles = CloudOSBridge.previewFiles['home'] ?? <CloudFileItem>[];
    if (query.trim().isEmpty) return allFiles;
    final normalizedQuery = query.trim().toLowerCase();
    return allFiles
        .where((file) => file.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }

  void _navigateTo(String id, String label) {
    setState(() {
      currentLocation = id;
      currentTitle = label;
      selectedItemPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = _currentFiles;

    return SizedBox(
      width: 960,
      height: 600,
      child: GlassSurface(
        borderRadius: 14,
        blur: 24,
        color: const Color(0xF4101822),
        borderColor: CloudOSColors.borderStrong,
        child: Column(
          children: <Widget>[
            FilesTitleBar(
              title: currentTitle,
              onClose: widget.onClose,
              onMinimize: widget.onMinimize,
              onDrag: widget.onDrag,
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 210,
                    child: FilesSidebar(
                      sections: defaultFilesSidebarSections,
                      selectedId: currentLocation,
                      onSelect: _navigateTo,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        FilesToolbar(
                          currentTitle: currentTitle,
                          isGridView: isGridView,
                          onQueryChanged: (value) => setState(() => query = value),
                          onToggleView: () => setState(() => isGridView = !isGridView),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: FilesContent(
                            files: files,
                            query: query,
                            isGridView: isGridView,
                            selectedPath: selectedItemPath,
                            onSelect: (path) => setState(() => selectedItemPath = path),
                          ),
                        ),
                        FilesStatusBar(
                          itemCount: files.length,
                          selectedPath: selectedItemPath,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
