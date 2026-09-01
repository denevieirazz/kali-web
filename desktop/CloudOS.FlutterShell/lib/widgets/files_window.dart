import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import 'glass_surface.dart';

part 'files_window_parts.dart';

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

  static const sidebarSections = <_SidebarSection>[
    _SidebarSection(
      title: 'Acesso Rápido',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'home', label: 'Início', icon: Icons.home_rounded, color: CloudOSColors.accent),
        _SidebarEntry(id: 'desktop', label: 'Área de Trabalho', icon: Icons.desktop_windows_rounded, color: CloudOSColors.secondary),
        _SidebarEntry(id: 'documents', label: 'Documentos', icon: Icons.description_rounded, color: CloudOSColors.secondary),
        _SidebarEntry(id: 'downloads', label: 'Downloads', icon: Icons.download_rounded, color: CloudOSColors.secondary),
      ],
    ),
    _SidebarSection(
      title: 'Armazenamento',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'cloud-drive', label: 'CloudOS Drive', icon: Icons.cloud_circle_rounded, color: CloudOSColors.accent, badge: '10 GB'),
        _SidebarEntry(id: 'windows-c', label: 'Disco Local (C:)', icon: Icons.storage_rounded, color: CloudOSColors.windows),
        _SidebarEntry(id: 'ubuntu-wsl', label: 'Ubuntu (WSL2)', icon: Icons.terminal_rounded, color: CloudOSColors.linux, badge: 'WSLg'),
      ],
    ),
    _SidebarSection(
      title: 'Sistema',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'trash', label: 'Lixeira CloudOS', icon: Icons.delete_outline_rounded, color: CloudOSColors.secondary),
      ],
    ),
  ];

  List<CloudFileItem> get _currentFiles {
    final allFiles = CloudOSBridge.previewFiles['home'] ?? <CloudFileItem>[];
    if (query.trim().isEmpty) return allFiles;
    final q = query.trim().toLowerCase();
    return allFiles.where((f) => f.name.toLowerCase().contains(q)).toList(growable: false);
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
            _TitleBar(
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
                    child: _Sidebar(
                      sections: sidebarSections,
                      selectedId: currentLocation,
                      onSelect: _navigateTo,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _Toolbar(
                          currentTitle: currentTitle,
                          query: query,
                          isGridView: isGridView,
                          onQueryChanged: (val) => setState(() => query = val),
                          onToggleView: () => setState(() => isGridView = !isGridView),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: files.isEmpty
                              ? _EmptyFilesState(query: query)
                              : isGridView
                                  ? _FilesGrid(
                                      files: files,
                                      selectedPath: selectedItemPath,
                                      onSelect: (path) => setState(() => selectedItemPath = path),
                                    )
                                  : _FilesList(
                                      files: files,
                                      selectedPath: selectedItemPath,
                                      onSelect: (path) => setState(() => selectedItemPath = path),
                                    ),
                        ),
                        _StatusBar(
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
