import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/files_content.dart';
import 'widgets/files_loading_state.dart';
import 'widgets/files_sidebar.dart';
import 'widgets/files_status_bar.dart';
import 'widgets/files_title_bar.dart';

class FilesWindow extends StatefulWidget {
  const FilesWindow({
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
    CloudOSBridge? bridge,
    super.key,
  }) : bridge = bridge ?? const CloudOSBridge();

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;
  final CloudOSBridge bridge;

  @override
  State<FilesWindow> createState() => _FilesWindowState();
}

class _FilesWindowState extends State<FilesWindow> {
  _FilesLocation _current = const _FilesLocation.root('home', 'Início');
  String query = '';
  bool isGridView = true;
  String? selectedItemPath;
  List<CloudFileItem> _files = const <CloudFileItem>[];
  bool _isLoading = true;
  int _loadGeneration = 0;
  final List<_FilesLocation> _backStack = <_FilesLocation>[];
  final List<_FilesLocation> _forwardStack = <_FilesLocation>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocation(_current));
  }

  List<CloudFileItem> get _currentFiles {
    if (query.trim().isEmpty) return _files;
    final normalizedQuery = query.trim().toLowerCase();
    return _files
        .where((file) => file.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }

  Future<void> _loadLocation(_FilesLocation location) async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _isLoading = true);

    final files = location.entryId != null
        ? await widget.bridge.loadFilesEntry(location.entryId!)
        : await widget.bridge.loadFiles(location.rootId!);
    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      _files = files;
      _isLoading = false;
      selectedItemPath = null;
    });
  }

  void _applyLocation(_FilesLocation next) {
    setState(() {
      _current = next;
      query = '';
      selectedItemPath = null;
    });
    unawaited(_loadLocation(next));
  }

  void _navigateTo(String id, String label) {
    if (_current.rootId == id && _current.entryId == null) {
      unawaited(_loadLocation(_current));
      return;
    }
    _backStack.add(_current);
    _forwardStack.clear();
    _applyLocation(_FilesLocation.root(id, label));
  }

  Future<void> _openItem(CloudFileItem item) async {
    final entryId = item.entryId;
    if (entryId == null || entryId.isEmpty) return;

    if (item.isFolder) {
      _backStack.add(_current);
      _forwardStack.clear();
      _applyLocation(
        _FilesLocation.entry(
          entryId: entryId,
          label: item.name,
          sidebarId: _current.sidebarId,
          parent: _current,
        ),
      );
      return;
    }

    final opened = await widget.bridge.openFileEntry(entryId);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir ${item.name}.')),
      );
    }
  }

  void _goBack() {
    if (_backStack.isEmpty) return;
    final previous = _backStack.removeLast();
    _forwardStack.add(_current);
    _applyLocation(previous);
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    final next = _forwardStack.removeLast();
    _backStack.add(_current);
    _applyLocation(next);
  }

  void _goUp() {
    final parent = _current.parent;
    if (parent != null) {
      _backStack.add(_current);
      _forwardStack.clear();
      _applyLocation(parent);
      return;
    }
    if (_current.rootId == 'home') return;
    _backStack.add(_current);
    _forwardStack.clear();
    _applyLocation(const _FilesLocation.root('home', 'Início'));
  }

  void _refresh() {
    unawaited(_loadLocation(_current));
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
              title: _current.label,
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
                      selectedId: _current.sidebarId,
                      onSelect: _navigateTo,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _ConnectedFilesToolbar(
                          currentTitle: _current.label,
                          isGridView: isGridView,
                          canGoBack: _backStack.isNotEmpty,
                          canGoForward: _forwardStack.isNotEmpty,
                          canGoUp: _current.parent != null ||
                              _current.rootId != 'home',
                          isLoading: _isLoading,
                          onBack: _goBack,
                          onForward: _goForward,
                          onUp: _goUp,
                          onRefresh: _refresh,
                          onQueryChanged: (value) =>
                              setState(() => query = value),
                          onToggleView: () =>
                              setState(() => isGridView = !isGridView),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _isLoading
                              ? const FilesLoadingState()
                              : FilesContent(
                                  files: files,
                                  query: query,
                                  isGridView: isGridView,
                                  selectedPath: selectedItemPath,
                                  onSelect: (path) =>
                                      setState(() => selectedItemPath = path),
                                  onOpen: (item) => unawaited(_openItem(item)),
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

class _FilesLocation {
  const _FilesLocation.root(this.rootId, this.label)
      : entryId = null,
        sidebarId = rootId,
        parent = null;

  const _FilesLocation.entry({
    required this.entryId,
    required this.label,
    required this.sidebarId,
    required this.parent,
  }) : rootId = null;

  final String? rootId;
  final String? entryId;
  final String label;
  final String sidebarId;
  final _FilesLocation? parent;
}

class _ConnectedFilesToolbar extends StatelessWidget {
  const _ConnectedFilesToolbar({
    required this.currentTitle,
    required this.isGridView,
    required this.canGoBack,
    required this.canGoForward,
    required this.canGoUp,
    required this.isLoading,
    required this.onBack,
    required this.onForward,
    required this.onUp,
    required this.onRefresh,
    required this.onQueryChanged,
    required this.onToggleView,
  });

  final String currentTitle;
  final bool isGridView;
  final bool canGoBack;
  final bool canGoForward;
  final bool canGoUp;
  final bool isLoading;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onUp;
  final VoidCallback onRefresh;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          _NavButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Voltar',
            enabled: canGoBack,
            onPressed: onBack,
          ),
          _NavButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Avançar',
            enabled: canGoForward,
            onPressed: onForward,
          ),
          _NavButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Subir Pasta',
            enabled: canGoUp,
            onPressed: onUp,
          ),
          _NavButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Atualizar',
            enabled: !isLoading,
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: CloudOSColors.elevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CloudOSColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 15,
                    color: CloudOSColors.accent,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CloudOS',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: CloudOSColors.caption,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: CloudOSColors.caption,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currentTitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CloudOSColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            height: 32,
            child: TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 16),
                hintText: 'Filtrar pasta...',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: isGridView
                ? 'Mudar para exibição em lista'
                : 'Mudar para exibição em grade',
            child: IconButton(
              onPressed: onToggleView,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 16,
          color: enabled ? CloudOSColors.secondary : CloudOSColors.caption,
        ),
      ),
    );
  }
}
