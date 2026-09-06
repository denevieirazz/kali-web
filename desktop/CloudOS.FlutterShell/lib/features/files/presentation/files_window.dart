import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../services/cloudos_bridge.dart';
import 'widgets/cloudos_open_with_dialog.dart';
import 'widgets/files_content.dart';
import 'widgets/files_loading_state.dart';
import 'widgets/files_sidebar.dart';
import 'widgets/files_status_bar.dart';
import 'widgets/files_title_bar.dart';
import 'widgets/recycle_bin_view.dart';

enum FileSortField { name, size, type, date }

class FilesWindow extends StatefulWidget {
  const FilesWindow({
    this.onClose,
    this.onMinimize,
    this.onDrag,
    this.onOpenFile,
    this.showTitleBar = false,
    this.initialRootId = 'home',
    CloudOSBridge? bridge,
    super.key,
  }) : bridge = bridge ?? const CloudOSBridge();

  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final ValueChanged<Offset>? onDrag;
  final ValueChanged<CloudFileItem>? onOpenFile;
  final bool showTitleBar;
  final String initialRootId;
  final CloudOSBridge bridge;

  @override
  State<FilesWindow> createState() => _FilesWindowState();
}

class _FilesWindowState extends State<FilesWindow> {
  late _FilesLocation _current;
  String query = '';
  bool isGridView = false; // Default to clean table list view
  List<CloudFileItem> _files = const <CloudFileItem>[];
  List<CloudDriveInfo> _drives = const <CloudDriveInfo>[];
  bool _isLoading = true;
  int _loadGeneration = 0;

  // Navigation History (up to 50 locations)
  final List<_FilesLocation> _backStack = <_FilesLocation>[];
  final List<_FilesLocation> _forwardStack = <_FilesLocation>[];
  static const int _maxHistory = 50;

  // Multi-selection & Clipboard
  final Set<String> _selectedPaths = <String>{};
  int? _anchorIndex;
  final List<CloudFileItem> _clipboardItems = <CloudFileItem>[];
  bool _clipboardIsCut = false;

  // Sorting
  FileSortField _sortField = FileSortField.name;
  bool _sortAscending = true;

  // Address Bar Editing
  bool _isEditingAddress = false;
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  final TextEditingController _filterController = TextEditingController();

  // Async file operation state
  String? _activeOperationTitle;
  double? _activeOperationProgress;
  String? _activeJobId;
  StreamSubscription<FileOperationProgressEvent>? _progressSub;

  @override
  void initState() {
    super.initState();
    _current = _allowlistedRoot(widget.initialRootId);
    unawaited(_loadLocation(_current));
    unawaited(_loadDrives());

    _progressSub = widget.bridge.onFileOperationProgress.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.status == 'completed' ||
            event.status == 'canceled' ||
            event.status == 'failed' ||
            event.errorMessage != null) {
          _activeOperationTitle = null;
          _activeOperationProgress = null;
          _activeJobId = null;
          _refresh();
        } else {
          _activeJobId = event.jobId;
          _activeOperationTitle = event.currentItem.isNotEmpty
              ? 'Processando: ${event.currentItem}'
              : 'Operação em andamento...';
          _activeOperationProgress =
              event.filesTotal > 0 ? (event.filesCompleted / event.filesTotal) : null;
        }
      });
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _addressController.dispose();
    _filterController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FilesWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRootId == widget.initialRootId) return;

    final next = _allowlistedRoot(widget.initialRootId);
    _backStack.clear();
    _forwardStack.clear();
    _applyLocation(next);
  }

  Future<void> _loadDrives() async {
    try {
      final drives = await widget.bridge.listDrives();
      if (mounted) {
        setState(() => _drives = drives);
      }
    } catch (_) {}
  }

  static _FilesLocation _allowlistedRoot(String id) {
    return switch (id) {
      'desktop' => const _FilesLocation.root('desktop', 'Área de Trabalho', r'C:\Users\Área de Trabalho'),
      'documents' => const _FilesLocation.root('documents', 'Documentos', r'C:\Users\Documentos'),
      'downloads' => const _FilesLocation.root('downloads', 'Downloads', r'C:\Users\Downloads'),
      'cloud-drive' => const _FilesLocation.root('cloud-drive', 'CloudOS Drive', r'CloudOS:\Drive'),
      'windows-c' => const _FilesLocation.root('windows-c', 'Disco Local (C:)', r'C:\'),
      'ubuntu-wsl' => const _FilesLocation.root('ubuntu-wsl', 'Ubuntu (WSL2)', r'\\wsl.localhost\Ubuntu'),
      'trash' => const _FilesLocation.root('trash', 'Lixeira', 'Lixeira'),
      _ => const _FilesLocation.root('home', 'Início', 'Início'),
    };
  }

  List<CloudFileItem> get _currentFiles {
    var list = _files;
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      list = list.where((file) => file.name.toLowerCase().contains(q)).toList();
    }

    final sorted = List<CloudFileItem>.from(list);
    sorted.sort((a, b) {
      // Folders always grouped first
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;

      int cmp;
      switch (_sortField) {
        case FileSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case FileSortField.size:
          cmp = a.sizeFormatted.compareTo(b.sizeFormatted);
          break;
        case FileSortField.type:
          final extA = a.extension ?? (a.name.contains('.') ? a.name.split('.').last : '');
          final extB = b.extension ?? (b.name.contains('.') ? b.name.split('.').last : '');
          cmp = extA.toLowerCase().compareTo(extB.toLowerCase());
          break;
        case FileSortField.date:
          cmp = a.modifiedFormatted.compareTo(b.modifiedFormatted);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  List<CloudFileItem> get _selectedFiles {
    return _files.where((f) => _selectedPaths.contains(f.path)).toList(growable: false);
  }

  Future<void> _loadLocation(_FilesLocation location) async {
    final generation = ++_loadGeneration;
    if (location.rootId == 'trash' || location.sidebarId == 'trash') {
      if (mounted) {
        setState(() {
          _files = const <CloudFileItem>[];
          _isLoading = false;
          _selectedPaths.clear();
          _anchorIndex = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    final files = location.entryId != null
        ? await widget.bridge.loadFilesEntry(location.entryId!)
        : await widget.bridge.loadFiles(location.rootId!);
    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      _files = files;
      _isLoading = false;
      _selectedPaths.clear();
      _anchorIndex = null;
    });
  }

  void _applyLocation(_FilesLocation next) {
    setState(() {
      _current = next;
      query = '';
      _filterController.clear();
      _selectedPaths.clear();
      _anchorIndex = null;
      _isEditingAddress = false;
    });
    unawaited(_loadLocation(next));
  }

  void _navigateTo(String id, String label, {String? entryId}) {
    if (entryId != null && entryId.isNotEmpty) {
      _pushHistory(_current);
      _applyLocation(
        _FilesLocation.entry(
          entryId: entryId,
          label: label,
          displayPath: id.startsWith('drive:') ? id.substring(6) : label,
          sidebarId: id,
          parent: null,
        ),
      );
      return;
    }

    if (_current.rootId == id && _current.entryId == null) {
      unawaited(_loadLocation(_current));
      return;
    }

    _pushHistory(_current);
    _applyLocation(_allowlistedRoot(id));
  }

  Future<void> _openItem(CloudFileItem item) async {
    final entryId = item.entryId;
    if (entryId == null || entryId.isEmpty) return;

    if (item.isFolder) {
      _pushHistory(_current);
      final childPath = _current.displayPath.endsWith(r'\') || _current.displayPath.endsWith('/')
          ? '${_current.displayPath}${item.name}'
          : '${_current.displayPath}\\${item.name}';

      _applyLocation(
        _FilesLocation.entry(
          entryId: entryId,
          label: item.name,
          displayPath: childPath,
          sidebarId: _current.sidebarId,
          parent: _current,
        ),
      );
      return;
    }

    if (widget.onOpenFile != null) {
      widget.onOpenFile!(item);
      return;
    }

    final opened = await widget.bridge.openFileEntry(entryId);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir ${item.name}.')),
      );
    }
  }

  void _pushHistory(_FilesLocation loc) {
    _backStack.add(loc);
    if (_backStack.length > _maxHistory) {
      _backStack.removeAt(0);
    }
    _forwardStack.clear();
  }

  void _goBack() {
    if (_backStack.isEmpty) return;
    final previous = _backStack.removeLast();
    _forwardStack.add(_current);
    if (_forwardStack.length > _maxHistory) {
      _forwardStack.removeAt(0);
    }
    _applyLocation(previous);
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    final next = _forwardStack.removeLast();
    _backStack.add(_current);
    if (_backStack.length > _maxHistory) {
      _backStack.removeAt(0);
    }
    _applyLocation(next);
  }

  void _goUp() {
    final parent = _current.parent;
    if (parent != null) {
      _pushHistory(_current);
      _applyLocation(parent);
      return;
    }
    if (_current.rootId == 'home') return;
    _pushHistory(_current);
    _applyLocation(const _FilesLocation.root('home', 'Início', 'Início'));
  }

  void _refresh() {
    unawaited(_loadLocation(_current));
    unawaited(_loadDrives());
  }

  void _handleItemSelect(CloudFileItem item, {bool isCtrl = false, bool isShift = false}) {
    final files = _currentFiles;
    final clickedIdx = files.indexWhere((f) => f.path == item.path);

    setState(() {
      if (isCtrl) {
        if (_selectedPaths.contains(item.path)) {
          _selectedPaths.remove(item.path);
        } else {
          _selectedPaths.add(item.path);
        }
        _anchorIndex = clickedIdx;
      } else if (isShift && _anchorIndex != null && clickedIdx != -1) {
        final start = min(_anchorIndex!, clickedIdx);
        final end = max(_anchorIndex!, clickedIdx);
        _selectedPaths.clear();
        for (var i = start; i <= end; i++) {
          _selectedPaths.add(files[i].path);
        }
      } else {
        _selectedPaths.clear();
        _selectedPaths.add(item.path);
        _anchorIndex = clickedIdx;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths.clear();
      for (final f in _currentFiles) {
        _selectedPaths.add(f.path);
      }
    });
  }

  void _clearSelection() {
    if (_selectedPaths.isNotEmpty) {
      setState(() {
        _selectedPaths.clear();
        _anchorIndex = null;
      });
    }
  }

  List<_FilesLocation> get _breadcrumbs {
    final list = <_FilesLocation>[];
    _FilesLocation? loc = _current;
    while (loc != null) {
      list.add(loc);
      loc = loc.parent;
    }
    return list.reversed.toList();
  }

  void _startEditingAddress() {
    _addressController.text = _current.displayPath;
    _addressController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _addressController.text.length,
    );
    setState(() => _isEditingAddress = true);
    _addressFocusNode.requestFocus();
  }

  void _submitAddress(String rawPath) {
    final target = rawPath.trim();
    if (target.isEmpty) {
      setState(() => _isEditingAddress = false);
      return;
    }

    final lower = target.toLowerCase();
    if (lower == 'home' || lower == 'início' || lower == 'inicio') {
      _navigateTo('home', 'Início');
      return;
    } else if (lower == 'desktop' || lower == 'área de trabalho') {
      _navigateTo('desktop', 'Área de Trabalho');
      return;
    } else if (lower == 'documents' || lower == 'documentos') {
      _navigateTo('documents', 'Documentos');
      return;
    } else if (lower == 'downloads') {
      _navigateTo('downloads', 'Downloads');
      return;
    }

    for (final drive in _drives) {
      if (drive.mountPath.toLowerCase() == lower ||
          drive.mountPath.toLowerCase() == '$lower\\' ||
          drive.label.toLowerCase() == lower) {
        _navigateTo('drive:${drive.mountPath}', drive.label, entryId: drive.entryId);
        return;
      }
    }

    // Direct path entry navigation
    _pushHistory(_current);
    _applyLocation(
      _FilesLocation.entry(
        entryId: target,
        label: target.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? target,
        displayPath: target,
        sidebarId: '',
        parent: _current,
      ),
    );
  }

  static const _reservedNames = <String>{
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  static String? _validateFileName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'O nome não pode ser vazio.';
    if (trimmed.endsWith('.') || trimmed.endsWith(' ')) {
      return 'Nomes de arquivo no Windows não podem terminar com ponto ou espaço.';
    }
    final baseName = trimmed.split('.').first.toUpperCase();
    if (_reservedNames.contains(baseName)) {
      return 'O nome "$baseName" é uma palavra reservada do sistema Windows.';
    }
    if (RegExp(r'[<>:"/\\|?*]').hasMatch(trimmed)) {
      return 'Caracteres não permitidos: < > : " / \\ | ? *';
    }
    return null;
  }

  // --- Actions ---

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController(text: 'Nova Pasta');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141C2B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Text('Nova Pasta', style: TextStyle(color: CloudOSColors.text, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: CloudOSColors.text),
          decoration: const InputDecoration(
            labelText: 'Nome da pasta',
            hintText: 'Digite o nome da pasta',
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final valErr = _validateFileName(name);
      if (valErr != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: CloudOSColors.danger,
              content: Text(valErr),
            ),
          );
        }
        return;
      }
      final currentEntryId = _current.entryId ?? _current.rootId ?? 'home';
      final created = await widget.bridge.createFolder(currentEntryId, name);
      if (created != null) {
        _refresh();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao criar pasta. Verifique permissões.')),
        );
      }
    }
  }

  void _cutSelected() {
    final selected = _selectedFiles;
    if (selected.isEmpty) return;
    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(selected);
      _clipboardIsCut = true;
    });
  }

  void _copySelected() {
    final selected = _selectedFiles;
    if (selected.isEmpty) return;
    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(selected);
      _clipboardIsCut = false;
    });
  }

  Future<void> _pasteClipboard() async {
    if (_clipboardItems.isEmpty) return;
    final targetEntryId = _current.entryId ?? _current.rootId ?? 'home';
    final entryIds = _clipboardItems.map((f) => f.entryId ?? f.path).toList();

    // Check conflicts
    final conflicting = _clipboardItems.where((c) => _files.any((f) => f.name == c.name)).toList();
    if (conflicting.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141C2B),
          title: const Text('Conflito de Arquivos', style: TextStyle(color: CloudOSColors.text, fontSize: 15)),
          content: Text(
            '${conflicting.length} item(ns) com o mesmo nome já existem nesta pasta.\nDeseja substituir ou ignorar?',
            style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: const Text('Substituir'),
            ),
          ],
        ),
      );
      if (choice != 'overwrite') return;
    }

    if (_clipboardIsCut) {
      await widget.bridge.moveFiles(entryIds, targetEntryId);
      setState(() {
        _clipboardItems.clear();
        _clipboardIsCut = false;
      });
    } else {
      await widget.bridge.copyFiles(entryIds, targetEntryId);
    }
    _refresh();
  }

  Future<void> _renameSelected() async {
    final selected = _selectedFiles;
    if (selected.length != 1) return;
    final item = selected.first;
    final controller = TextEditingController(text: item.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141C2B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Text('Renomear', style: TextStyle(color: CloudOSColors.text, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: CloudOSColors.text),
          decoration: const InputDecoration(labelText: 'Novo nome'),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Renomear'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.name) {
      final valErr = _validateFileName(newName);
      if (valErr != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: CloudOSColors.danger,
              content: Text(valErr),
            ),
          );
        }
        return;
      }
      final renamed = await widget.bridge.renameFile(item.entryId ?? item.path, newName);
      if (renamed != null) {
        _refresh();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao renomear arquivo.')),
        );
      }
    }
  }

  Future<void> _openWithSelected() async {
    final selected = _selectedFiles;
    if (selected.length != 1) return;
    final item = selected.first;
    if (item.isFolder) return;
    await CloudOSOpenWithDialog.show(
      context: context,
      filePath: item.path,
      bridge: widget.bridge,
    );
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedFiles;
    if (selected.isEmpty) return;

    // Safety guard: protect root system directories
    final protected = selected.any((item) {
      final p = item.path.toLowerCase().replaceAll('/', '\\');
      return p.startsWith(r'c:\windows') ||
          p.startsWith(r'c:\program files') ||
          p == r'c:\' ||
          p == 'c:';
    });

    if (protected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: CloudOSColors.danger,
            content: Text('Operação cancelada: diretórios de sistema do Windows são protegidos contra exclusão.'),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141C2B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: CloudOSColors.border),
        ),
        title: const Text('Mover para a Lixeira', style: TextStyle(color: CloudOSColors.text, fontSize: 15)),
        content: Text(
          'Deseja mover ${selected.length} item(ns) para a Lixeira do Windows?',
          style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final entryIds = selected.map((s) => s.entryId ?? s.path).toList();
      await widget.bridge.deleteFiles(entryIds, permanent: false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = _currentFiles;
    final selectedFiles = _selectedFiles;
    final cutPaths = _clipboardIsCut ? _clipboardItems.map((f) => f.path).toSet() : const <String>{};

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelected,
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): _cutSelected,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteClipboard,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.f2): _renameSelected,
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): _createFolderDialog,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): _startEditingAddress,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _goBack,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _goForward,
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _goUp,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isEditingAddress) {
            setState(() => _isEditingAddress = false);
          } else {
            _clearSelection();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: const Color(0xF4101822),
          child: Column(
            children: <Widget>[
              if (widget.showTitleBar) ...<Widget>[
                FilesTitleBar(
                  title: _current.label,
                  onClose: widget.onClose ?? () {},
                  onMinimize: widget.onMinimize ?? () {},
                  onDrag: widget.onDrag ?? (_) {},
                ),
                const Divider(height: 1),
              ],
              _buildModernToolbar(),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 220,
                      child: FilesSidebar(
                        drives: _drives,
                        selectedId: _current.sidebarId,
                        onSelect: _navigateTo,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Expanded(
                            child: _current.sidebarId == 'trash'
                                ? RecycleBinView(
                                    bridge: widget.bridge,
                                    onBack: _backStack.isNotEmpty ? _goBack : null,
                                  )
                                : _isLoading
                                    ? const FilesLoadingState()
                                    : FilesContent(
                                        files: files,
                                        query: query,
                                        isGridView: isGridView,
                                        selectedPaths: _selectedPaths,
                                        cutPaths: cutPaths,
                                        onSelect: (item, {bool isCtrl = false, bool isShift = false}) {
                                          final keys = HardwareKeyboard.instance;
                                          final ctrlPressed = isCtrl || keys.isControlPressed;
                                          final shiftPressed = isShift || keys.isShiftPressed;
                                          _handleItemSelect(item, isCtrl: ctrlPressed, isShift: shiftPressed);
                                        },
                                        onOpen: (item) => unawaited(_openItem(item)),
                                      ),
                          ),
                          if (_current.sidebarId != 'trash')
                            FilesStatusBar(
                              itemCount: _isLoading ? 0 : files.length,
                              selectedCount: selectedFiles.length,
                              selectedSizeFormatted: selectedFiles.length == 1
                                  ? selectedFiles.first.sizeFormatted
                                  : null,
                              activeOperationTitle: _activeOperationTitle,
                              operationProgress: _activeOperationProgress,
                              onCancelOperation: _activeJobId != null
                                  ? () => widget.bridge.cancelFileOperation(_activeJobId!)
                                  : null,
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
      ),
    );
  }

  Widget _buildModernToolbar() {
    final hasSelection = _selectedPaths.isNotEmpty;
    final hasSingleSelection = _selectedPaths.length == 1;
    final hasClipboard = _clipboardItems.isNotEmpty;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          // Navigation
          _NavButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Voltar (Alt+Seta Esquerda)',
            enabled: _backStack.isNotEmpty,
            onPressed: _goBack,
          ),
          _NavButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Avançar (Alt+Seta Direita)',
            enabled: _forwardStack.isNotEmpty,
            onPressed: _goForward,
          ),
          _NavButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Subir Pasta (Alt+Seta Acima)',
            enabled: _current.parent != null || _current.rootId != 'home',
            onPressed: _goUp,
          ),
          _NavButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Atualizar (F5)',
            enabled: !_isLoading,
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),

          // Breadcrumb / Address Bar
          Expanded(
            child: _isEditingAddress
                ? Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: CloudOSColors.elevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: CloudOSColors.accent),
                    ),
                    child: TextField(
                      controller: _addressController,
                      focusNode: _addressFocusNode,
                      style: const TextStyle(color: CloudOSColors.text, fontSize: 12),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: _submitAddress,
                    ),
                  )
                : InkWell(
                    onTap: _startEditingAddress,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: CloudOSColors.elevated.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: CloudOSColors.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.folder_open_rounded, size: 15, color: CloudOSColors.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: <Widget>[
                                  for (int i = 0; i < _breadcrumbs.length; i++) ...<Widget>[
                                    if (i > 0)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(Icons.chevron_right_rounded, size: 14, color: CloudOSColors.caption),
                                      ),
                                    InkWell(
                                      onTap: () {
                                        final target = _breadcrumbs[i];
                                        if (target != _current) {
                                          _pushHistory(_current);
                                          _applyLocation(target);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Text(
                                          _breadcrumbs[i].label,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: i == _breadcrumbs.length - 1 ? FontWeight.w600 : FontWeight.normal,
                                            color: i == _breadcrumbs.length - 1 ? CloudOSColors.text : CloudOSColors.caption,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Digitar caminho (Ctrl+L)',
                            child: Icon(Icons.edit_rounded, size: 13, color: CloudOSColors.caption.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),

          // Action Toolbar
          _ActionButton(
            icon: Icons.create_new_folder_rounded,
            tooltip: 'Nova Pasta (Ctrl+Shift+N)',
            enabled: !_isLoading,
            onPressed: _createFolderDialog,
          ),
          _ActionButton(
            icon: Icons.content_cut_rounded,
            tooltip: 'Recortar (Ctrl+X)',
            enabled: hasSelection,
            onPressed: _cutSelected,
          ),
          _ActionButton(
            icon: Icons.content_copy_rounded,
            tooltip: 'Copiar (Ctrl+C)',
            enabled: hasSelection,
            onPressed: _copySelected,
          ),
          _ActionButton(
            icon: Icons.content_paste_rounded,
            tooltip: 'Colar (Ctrl+V)',
            enabled: hasClipboard,
            onPressed: _pasteClipboard,
          ),
          _ActionButton(
            icon: Icons.edit_rounded,
            tooltip: 'Renomear (F2)',
            enabled: hasSingleSelection,
            onPressed: _renameSelected,
          ),
          _ActionButton(
            icon: Icons.open_in_new_rounded,
            tooltip: 'Abrir com o CloudOS...',
            enabled: hasSingleSelection && !_selectedFiles.first.isFolder,
            onPressed: _openWithSelected,
          ),
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Mover para a Lixeira (Delete)',
            enabled: hasSelection,
            isDanger: true,
            onPressed: _deleteSelected,
          ),

          const SizedBox(width: 6),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 6),

          // Sorting Menu
          PopupMenuButton<FileSortField>(
            tooltip: 'Ordenar arquivos',
            icon: Icon(
              _sortAscending ? Icons.sort_rounded : Icons.swap_vert_rounded,
              size: 18,
              color: CloudOSColors.secondary,
            ),
            color: const Color(0xFF141C2B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: CloudOSColors.border),
            ),
            onSelected: (field) {
              setState(() {
                if (_sortField == field) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortField = field;
                  _sortAscending = true;
                }
              });
            },
            itemBuilder: (ctx) => <PopupMenuEntry<FileSortField>>[
              _buildSortMenuItem(FileSortField.name, 'Nome', Icons.sort_by_alpha_rounded),
              _buildSortMenuItem(FileSortField.size, 'Tamanho', Icons.format_size_rounded),
              _buildSortMenuItem(FileSortField.type, 'Tipo', Icons.category_rounded),
              _buildSortMenuItem(FileSortField.date, 'Data de Modificação', Icons.calendar_today_rounded),
            ],
          ),

          // View Mode Toggle
          Tooltip(
            message: isGridView ? 'Visualização em Lista' : 'Visualização em Grade',
            child: IconButton(
              onPressed: () => setState(() => isGridView = !isGridView),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                size: 18,
                color: CloudOSColors.secondary,
              ),
            ),
          ),

          const SizedBox(width: 6),
          // Search Filter
          SizedBox(
            width: 160,
            height: 30,
            child: TextField(
              controller: _filterController,
              onChanged: (val) => setState(() => query = val),
              style: const TextStyle(color: CloudOSColors.text, fontSize: 12),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 15),
                hintText: 'Filtrar...',
                contentPadding: EdgeInsets.zero,
                isDense: true,
                suffixIcon: query.isNotEmpty
                    ? InkWell(
                        onTap: () {
                          _filterController.clear();
                          setState(() => query = '');
                        },
                        child: const Icon(Icons.close_rounded, size: 14),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<FileSortField> _buildSortMenuItem(FileSortField field, String title, IconData icon) {
    final isCurrent = _sortField == field;
    return PopupMenuItem<FileSortField>(
      value: field,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: isCurrent ? CloudOSColors.accent : CloudOSColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isCurrent ? CloudOSColors.accent : CloudOSColors.text,
                fontSize: 12,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isCurrent)
            Icon(
              _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14,
              color: CloudOSColors.accent,
            ),
        ],
      ),
    );
  }
}

class _FilesLocation {
  const _FilesLocation.root(String rootId, this.label, this.displayPath)
      : rootId = rootId,
        entryId = null,
        sidebarId = rootId,
        parent = null;

  const _FilesLocation.entry({
    required this.entryId,
    required this.label,
    required this.displayPath,
    required this.sidebarId,
    required this.parent,
  }) : rootId = null;

  final String? rootId;
  final String? entryId;
  final String label;
  final String displayPath;
  final String sidebarId;
  final _FilesLocation? parent;
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 17,
          color: enabled
              ? (isDanger ? CloudOSColors.danger : CloudOSColors.secondary)
              : CloudOSColors.caption.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
