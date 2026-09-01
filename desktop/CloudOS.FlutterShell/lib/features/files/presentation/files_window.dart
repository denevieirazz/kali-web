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
  final List<_RootLocation> _backStack = <_RootLocation>[];
  final List<_RootLocation> _forwardStack = <_RootLocation>[];

  _RootLocation get _currentRoot =>
      _RootLocation(currentLocation, currentTitle);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocation('home'));
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

  void _applyRoot(_RootLocation next) {
    setState(() {
      currentLocation = next.id;
      currentTitle = next.label;
      query = '';
      selectedItemPath = null;
    });
    unawaited(_loadLocation(next.id));
  }

  void _navigateTo(String id, String label) {
    if (id == currentLocation) {
      unawaited(_loadLocation(id));
      return;
    }
    _backStack.add(_currentRoot);
    _forwardStack.clear();
    _applyRoot(_RootLocation(id, label));
  }

  void _goBack() {
    if (_backStack.isEmpty) return;
    final previous = _backStack.removeLast();
    _forwardStack.add(_currentRoot);
    _applyRoot(previous);
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    final next = _forwardStack.removeLast();
    _backStack.add(_currentRoot);
    _applyRoot(next);
  }

  void _goUp() {
    if (currentLocation == 'home') return;
    _backStack.add(_currentRoot);
    _forwardStack.clear();
    _applyRoot(const _RootLocation('home', 'Início'));
  }

  void _refresh() {
    unawaited(_loadLocation(currentLocation));
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
                        _ConnectedFilesToolbar(
                          currentTitle: currentTitle,
                          isGridView: isGridView,
                          canGoBack: _backStack.isNotEmpty,
                          canGoForward: _forwardStack.isNotEmpty,
                          canGoUp: currentLocation != 'home',
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

class _RootLocation {
  const _RootLocation(this.id, this.label);

  final String id;
  final String label;
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
