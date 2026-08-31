import 'package:flutter/material.dart';

import '../models/file_models.dart';
import 'cloudos_bridge.dart';

class FilesTabState {
  FilesTabState({
    required this.id,
    required this.title,
    required this.currentPath,
  }) {
    history.add(currentPath);
  }

  final String id;
  String title;
  String currentPath;
  List<String> history = <String>[];
  int historyIndex = 0;
  List<CloudFileItem> items = <CloudFileItem>[];
  bool isLoading = false;
  String? errorMessage;
  String searchQuery = '';
  FileSortField sortField = FileSortField.name;
  bool sortAscending = true;
  bool isGridView = true;
  Set<String> selectedPaths = <String>{};
  int loadGeneration = 0;

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward => historyIndex < history.length - 1;
  LocationKind get locationKind =>
      currentPath.startsWith(r'\\wsl.localhost\') ||
          currentPath.startsWith(r'\\wsl$\')
      ? LocationKind.wsl
      : LocationKind.windows;
}

class FilesController extends ChangeNotifier {
  FilesController({CloudOSBridge? bridge})
    : _bridge = bridge ?? const CloudOSBridge() {
    _init();
  }

  final CloudOSBridge _bridge;

  final List<FilesTabState> _tabs = <FilesTabState>[];
  int _activeTabIndex = 0;

  List<KnownFolderModel> _knownFolders = <KnownFolderModel>[];
  List<DriveInfoModel> _drives = <DriveInfoModel>[];

  // Clipboard for copy/cut/paste
  List<String> _clipboardPaths = <String>[];
  bool _isCutOperation = false;

  // Active Job Progress
  String? _activeJobId;
  double _activeJobProgress = 0.0;
  String _activeJobStatus = '';
  bool _disposed = false;
  String? _initializationError;

  List<FilesTabState> get tabs => List<FilesTabState>.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  FilesTabState? get activeTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
      ? _tabs[_activeTabIndex]
      : null;

  List<KnownFolderModel> get knownFolders => _knownFolders;
  List<DriveInfoModel> get drives => _drives;
  List<String> get clipboardPaths => _clipboardPaths;
  bool get isCutOperation => _isCutOperation;
  bool get hasActiveJob => _activeJobId != null;
  double get activeJobProgress => _activeJobProgress;
  String get activeJobStatus => _activeJobStatus;
  String? get initializationError => _initializationError;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final tab in _tabs) {
      tab.loadGeneration++;
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _knownFolders = await _bridge.getKnownFolders();
      _drives = await _bridge.getDrives();
    } catch (error) {
      _knownFolders = const <KnownFolderModel>[];
      _drives = const <DriveInfoModel>[];
      _initializationError = 'System Broker indisponível: $error';
    }

    // Create default tab
    if (_disposed) return;
    addTab(title: 'Início', initialPath: 'home');
    notifyListeners();
  }

  void addTab({String title = 'Início', String initialPath = 'home'}) {
    final tab = FilesTabState(
      id: 'tab-${DateTime.now().millisecondsSinceEpoch}-${_tabs.length}',
      title: title,
      currentPath: initialPath,
    );
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    loadTabFiles(tab);
    notifyListeners();
  }

  void closeTab(int index) {
    if (_tabs.length <= 1) return; // Keep at least 1 tab
    _tabs[index].loadGeneration++;
    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void selectTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      _activeTabIndex = index;
      notifyListeners();
    }
  }

  Future<void> navigateTo(String path, {String? title}) async {
    final tab = activeTab;
    if (tab == null) return;

    if (tab.historyIndex < tab.history.length - 1) {
      tab.history = tab.history.sublist(0, tab.historyIndex + 1);
    }
    tab.history.add(path);
    tab.historyIndex = tab.history.length - 1;
    tab.currentPath = path;
    if (title != null) tab.title = title;
    tab.selectedPaths.clear();

    await loadTabFiles(tab);
    notifyListeners();
  }

  Future<void> goBack() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoBack) return;
    tab.historyIndex--;
    tab.currentPath = tab.history[tab.historyIndex];
    tab.selectedPaths.clear();
    await loadTabFiles(tab);
    notifyListeners();
  }

  Future<void> goForward() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoForward) return;
    tab.historyIndex++;
    tab.currentPath = tab.history[tab.historyIndex];
    tab.selectedPaths.clear();
    await loadTabFiles(tab);
    notifyListeners();
  }

  Future<void> goToParent() async {
    final tab = activeTab;
    if (tab == null) return;
    final current = tab.currentPath;
    if (current == 'home' || current.isEmpty) return;

    final lastSlash = current.lastIndexOf(RegExp(r'[\\/]'));
    if (lastSlash > 0) {
      final parent = current.substring(0, lastSlash);
      await navigateTo(parent.endsWith(':') ? '$parent\\' : parent);
    }
  }

  Future<void> refresh() async {
    final tab = activeTab;
    if (tab != null) {
      await loadTabFiles(tab);
      notifyListeners();
    }
  }

  Future<void> loadTabFiles(FilesTabState tab) async {
    final generation = ++tab.loadGeneration;
    tab.isLoading = true;
    tab.errorMessage = null;
    notifyListeners();

    try {
      final items = await _bridge.listFiles(
        tab.currentPath,
        sortField: tab.sortField,
        ascending: tab.sortAscending,
        searchText: tab.searchQuery,
      );
      if (_disposed || !_tabs.contains(tab) || generation != tab.loadGeneration)
        return;
      tab.items = items;
      tab.isLoading = false;
    } catch (e) {
      if (_disposed || !_tabs.contains(tab) || generation != tab.loadGeneration)
        return;
      tab.isLoading = false;
      tab.errorMessage = 'Não foi possível carregar a pasta: $e';
    }
    notifyListeners();
  }

  void toggleViewMode() {
    final tab = activeTab;
    if (tab != null) {
      tab.isGridView = !tab.isGridView;
      notifyListeners();
    }
  }

  void setSortField(FileSortField field) {
    final tab = activeTab;
    if (tab != null) {
      if (tab.sortField == field) {
        tab.sortAscending = !tab.sortAscending;
      } else {
        tab.sortField = field;
        tab.sortAscending = true;
      }
      loadTabFiles(tab);
    }
  }

  void setSearchQuery(String query) {
    final tab = activeTab;
    if (tab != null) {
      tab.searchQuery = query;
      loadTabFiles(tab);
    }
  }

  void selectItem(String path, {bool isMulti = false, bool isToggle = false}) {
    final tab = activeTab;
    if (tab == null) return;

    if (!isMulti && !isToggle) {
      tab.selectedPaths.clear();
      tab.selectedPaths.add(path);
    } else if (isToggle) {
      if (tab.selectedPaths.contains(path)) {
        tab.selectedPaths.remove(path);
      } else {
        tab.selectedPaths.add(path);
      }
    } else {
      tab.selectedPaths.add(path);
    }
    notifyListeners();
  }

  void clearSelection() {
    final tab = activeTab;
    if (tab != null) {
      tab.selectedPaths.clear();
      notifyListeners();
    }
  }

  void selectAll() {
    final tab = activeTab;
    if (tab != null) {
      tab.selectedPaths = tab.items.map((i) => i.path).toSet();
      notifyListeners();
    }
  }

  // File Actions
  Future<bool> createFolder(String name) async {
    final tab = activeTab;
    if (tab == null) return false;
    final ok = await _bridge.createFolder(tab.currentPath, name);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> renameItem(String path, String newName) async {
    final ok = await _bridge.renameItem(path, newName);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> deleteSelected({bool permanent = false}) async {
    final tab = activeTab;
    if (tab == null || tab.selectedPaths.isEmpty) return false;
    final ok = await _bridge.deleteItems(
      tab.selectedPaths.toList(),
      permanent: permanent,
    );
    if (ok) {
      tab.selectedPaths.clear();
      await refresh();
    }
    return ok;
  }

  void copySelected() {
    final tab = activeTab;
    if (tab == null || tab.selectedPaths.isEmpty) return;
    _clipboardPaths = tab.selectedPaths.toList();
    _isCutOperation = false;
    notifyListeners();
  }

  void cutSelected() {
    final tab = activeTab;
    if (tab == null || tab.selectedPaths.isEmpty) return;
    _clipboardPaths = tab.selectedPaths.toList();
    _isCutOperation = true;
    notifyListeners();
  }

  Future<void> paste() async {
    final tab = activeTab;
    if (tab == null || _clipboardPaths.isEmpty) return;

    final cut = _isCutOperation;
    try {
      final jobId = cut
          ? await _bridge.moveItems(
              _clipboardPaths,
              tab.currentPath,
              overwritePolicy: 'replace',
            )
          : await _bridge.copyItems(
              _clipboardPaths,
              tab.currentPath,
              overwritePolicy: 'replace',
            );
      if (jobId == null) {
        throw const CloudOSBridgeException(
          'job_not_started',
          'A operação de arquivo não foi iniciada.',
        );
      }
      _activeJobId = jobId;
      _activeJobProgress = 0;
      _activeJobStatus = 'queued';
      notifyListeners();

      await _waitForJob(jobId);
      if (cut) {
        _clipboardPaths.clear();
        _isCutOperation = false;
      }
      await refresh();
    } catch (error) {
      _activeJobStatus = 'failed: $error';
      notifyListeners();
    } finally {
      _activeJobId = null;
      notifyListeners();
    }
  }

  Future<void> _waitForJob(String jobId) async {
    const maxPolls = 600;
    for (var poll = 0; poll < maxPolls; poll++) {
      if (_disposed) return;
      final status = await _bridge.getJobStatus(jobId);
      _activeJobProgress = ((status['progress'] as num?)?.toDouble() ?? 0)
          .clamp(0, 100)
          .toDouble();
      _activeJobStatus = status['state'] as String? ?? 'unknown';
      notifyListeners();
      switch (_activeJobStatus) {
        case 'completed':
          return;
        case 'failed':
          throw CloudOSBridgeException(
            'job_failed',
            status['error'] as String? ?? 'A operação de arquivo falhou.',
          );
        case 'cancelled':
          throw const CloudOSBridgeException(
            'job_cancelled',
            'A operação foi cancelada.',
          );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const CloudOSBridgeException(
      'job_timeout',
      'A operação de arquivo excedeu o tempo limite.',
    );
  }

  Future<void> openItem(CloudFileItem item) async {
    if (item.isDirectory) {
      await navigateTo(item.path, title: item.name);
    } else {
      await _bridge.openDefault(item.path);
    }
  }

  Future<List<OpenWithAppModel>> getOpenWith(String path) async {
    return _bridge.getOpenWithList(path);
  }

  Future<bool> launchOpenWith(String path, OpenWithAppModel app) async {
    return _bridge.launchOpenWith(
      path,
      app.appId,
      app.platform,
      distro: app.distro,
    );
  }
}
