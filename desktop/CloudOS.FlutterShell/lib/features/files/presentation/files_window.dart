import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/files_content.dart';
import 'widgets/files_sidebar.dart';
import 'widgets/files_status_bar.dart';
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
  static const _bridge = CloudOSBridge();

  String currentLocation = 'home';
  String currentTitle = 'Início';
  String query = '';
  bool isGridView = true;
  String? selectedItemPath;
  List<CloudFileItem> _files = const <CloudFileItem>[];
  bool _isLoading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadLocation('home');
  }

  List<CloudFileItem> get _currentFiles {
    if (query.trim().isEmpty) return _files;
    final normalizedQuery = query.trim().toLowerCase();
    return _files
        .where((file) => file.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }

  Future<void> _loadLocation(String location) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final files = await _bridge.loadFiles(location);
    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      _files = files;
      _isLoading = false;
      selectedItemPath = null;
    });
  }

  void _navigateTo(String id, String label) {
    setState(() {
      currentLocation = id;
      currentTitle = label;
      query = '';
      selectedItemPath = null;
    });
    _loadLocation(id);
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
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : FilesContent(
                                  files: files,
                                  query: query,
                                  isGridView: isGridView,
                                  selectedPath: selectedItemPath,
                                  onSelect: (path) =>
                                      setState(() => selectedItemPath = path),
                                ),
                        ),
                        FilesStatusBar(
                          itemCount: _isLoading ? 0 : files.length,
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
