import 'dart:async';

import 'package:flutter/material.dart';

import '../models/file_models.dart';
import 'cloudos_bridge.dart';
import 'runtime_event_service.dart';

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
  FilesController({
    CloudOSBridge? bridge,
    RuntimeEventService? runtimeEventService,
    String initialPath = 'home',
    String? initialTitle,
  }) : _bridge = bridge ?? const CloudOSBridge(),
       _runtimeEvents = runtimeEventService ?? RuntimeEventService.instance,
       _initialPath = initialPath.trim().isEmpty ? 'home' : initialPath.trim(),
       _initialTitle = initialTitle {
    _eventSubscription = _runtimeEvents.events.listen(_onRuntimeEvent);
    _init();
  }

  final CloudOSBridge _bridge;
  final RuntimeEventService _runtimeEvents;
  final String _initialPath;
  final String? _initialTitle;
  late final StreamSubscription<BrokerRuntimeEvent> _eventSubscription;

  final List<FilesTabState> _tabs = <FilesTabState>[];
  int _activeTabIndex = 0;

  List<KnownFolderModel> _knownFolders = <KnownFolderModel>[];
  List<DriveInfoModel> _drives = <DriveInfoModel>[];

  List<String> _clipboardPaths = <String>[];
  bool _isCutOperation = false;

  String? _activeJobId;
  double _activeJobProgress = 0.0;
  String _activeJobStatus = '';
  final Map<String, Completer<void>> _jobWaiters = <String, Completer<void>>{};
  final Set<String> _pendingRefreshTabIds = <String>{};
  Timer? _eventRefreshDebounce;
  bool _disposed = false;
  String? _initializationError;

  static const Duration _eventRefreshDelay = Duration(milliseconds: 120);
  static const Duration _jobFallbackInterval = Duration(seconds: 1);
  static const int _maxFallbackPolls = 60;

  List<FilesTabState> get tabs => List<FilesTabState>.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  FilesTabState? get activeTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
      ? _tabs[_activeTabIndex]
      : null;

  List<KnownFolderModel> get knownFolders => _knownFolders;
  List<DriveInfoModel> get drives => _drives;
  List<String> get clipboardPaths => List<String>.unmodifiable(_clipboardPaths);
  bool get isCutOperation => _isCutOperation;
  bool get hasActiveJob => _activeJobId != null;
  double get activeJobProgress => _activeJobProgress;
  String get activeJobStatus => _activeJobStatus;
  String? get initializationError => _initializationError;

  String? resolveFilesystemPath(String rawPath) {
    final path = rawPath.trim();
    if (path.isEmpty) return null;
    final lower = path.toLowerCase();

    for (final folder in _knownFolders) {
      if (folder.id.toLowerCase() == lower ||
          folder.path.toLowerCase() == lower) {
        return folder.path.trim().isEmpty ? null : folder.path;
      }
    }
    for (final drive in _drives) {
      if (drive.letter.toLowerCase() == lower ||
          drive.path.toLowerCase() == lower) {
        return drive.path.trim().isEmpty ? null : drive.path;
      }
    }

    if (lower == 'home' || lower.startsWith('wsl:')) return null;
    return path;
  }

  String? get activeResolvedPath {
    final path = activeTab?.currentPath;
    return path == null ? null : resolveFilesystemPath(path);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventRefreshDebounce?.cancel();
    _eventRefreshDebounce = null;
    _pendingRefreshTabIds.clear();
    unawaited(_eventSubscription.cancel());
    _jobWaiters.clear();
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

    if (_disposed) return;
    addTab(
      title: _initialTitle ?? _titleForInitialPath(_initialPath),
      initialPath: _initialPath,
    );
    notifyListeners();
  }

  String _titleForInitialPath(String path) {
    if (path == 'home') return 'Início';
    for (final folder in _knownFolders) {
      if (folder.path.toLowerCase() == path.toLowerCase() ||
          folder.id.toLowerCase() == path.toLowerCase()) {
        return folder.name;
      }
    }
    for (final drive in _drives) {
      if (drive.path.toLowerCase() == path.toLowerCase() ||
          drive.letter.toLowerCase() == path.toLowerCase()) {
        return drive.letter;
      }
    }
    final normalized = path.replaceAll('/', r'\');
    final parts = normalized
        .split(r'\')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.last : path;
  }

  void addTab({String title = 'Início', String initialPath = 'home'}) {
    if (_disposed) return;
    final tab = FilesTabState(
      id: 'tab-${DateTime.now().microsecondsSinceEpoch}-${_tabs.length}',
      title: title,
      currentPath: initialPath,
    );
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    unawaited(loadTabFiles(tab));
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length || _tabs.length <= 1) return;
    _tabs[index].loadGeneration++;
    _pendingRefreshTabIds.remove(_tabs[index].id);
    _tabs.removeAt(index);
    if (_activeTabIndex > index) {
      _activeTabIndex--;
    } else if (_activeTabIndex >= _tabs.length) {
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
    final target = path.trim();
    if (tab == null || target.isEmpty) return;

    if (tab.historyIndex < tab.history.length - 1) {
      tab.history = tab.history.sublist(0, tab.historyIndex + 1);
    }
    tab.history.add(target);
    tab.historyIndex = tab.history.length - 1;
    tab.currentPath = target;
    tab.title = title ?? _titleForInitialPath(target);
    tab.selectedPaths.clear();

    await loadTabFiles(tab);
  }

  Future<void> goBack() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoBack) return;
    tab.historyIndex--;
    tab.currentPath = tab.history[tab.historyIndex];
    tab.title = _titleForInitialPath(tab.currentPath);
    tab.selectedPaths.clear();
    await loadTabFiles(tab);
  }

  Future<void> goForward() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoForward) return;
    tab.historyIndex++;
    tab.currentPath = tab.history[tab.historyIndex];
    tab.title = _titleForInitialPath(tab.currentPath);
    tab.selectedPaths.clear();
    await loadTabFiles(tab);
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
    if (tab != null) await loadTabFiles(tab);
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
      if (_disposed || !_tabs.contains(tab) || generation != tab.loadGeneration) {
        return;
      }
      tab.items = items;
      tab.isLoading = false;
    } catch (error) {
      if (_disposed || !_tabs.contains(tab) || generation != tab.loadGeneration) {
        return;
      }
      tab.isLoading = false;
      tab.errorMessage = 'Não foi possível carregar a pasta: $error';
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
    if (tab == null) return;
    if (tab.sortField == field) {
      tab.sortAscending = !tab.sortAscending;
    } else {
      tab.sortField = field;
      tab.sortAscending = true;
    }
    unawaited(loadTabFiles(tab));
  }

  void setSearchQuery(String query) {
    final tab = activeTab;
    if (tab == null || tab.searchQuery == query) return;
    tab.searchQuery = query;
    unawaited(loadTabFiles(tab));
  }

  void selectItem(String path, {bool isMulti = false, bool isToggle = false}) {
    final tab = activeTab;
    if (tab == null) return;

    if (!isMulti && !isToggle) {
      tab.selectedPaths
        ..clear()
        ..add(path);
    } else if (isToggle) {
      if (!tab.selectedPaths.remove(path)) tab.selectedPaths.add(path);
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
      tab.selectedPaths = tab.items.map((item) => item.path).toSet();
      notifyListeners();
    }
  }

  CloudFileItem? selectedSingleItem() {
    final tab = activeTab;
    if (tab == null || tab.selectedPaths.length != 1) return null;
    final path = tab.selectedPaths.first;
    for (final item in tab.items) {
      if (item.path == path) return item;
    }
    return null;
  }

  Future<bool> createFolder(String name) async {
    final tab = activeTab;
    if (tab == null || name.trim().isEmpty) return false;
    final ok = await _bridge.createFolder(tab.currentPath, name);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> renameItem(String path, String newName) async {
    if (path.isEmpty || newName.trim().isEmpty) return false;
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
    if (tab == null || _clipboardPaths.isEmpty || _activeJobId != null) return;

    final cut = _isCutOperation;
    try {
      // Never overwrite user data silently. The broker returns
      // destination_exists and the UI can ask for an explicit replace action.
      final jobId = cut
          ? await _bridge.moveItems(
              _clipboardPaths,
              tab.currentPath,
              overwritePolicy: 'ask',
            )
          : await _bridge.copyItems(
              _clipboardPaths,
              tab.currentPath,
              overwritePolicy: 'ask',
            );
      if (jobId == null || jobId.isEmpty) {
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
      _jobWaiters.remove(_activeJobId);
      _activeJobId = null;
      notifyListeners();
    }
  }

  Future<bool> cancelActiveJob() async {
    final jobId = _activeJobId;
    if (jobId == null) return false;
    return _bridge.cancelJob(jobId);
  }

  Future<void> _waitForJob(String jobId) async {
    final waiter = Completer<void>();
    _jobWaiters[jobId] = waiter;
    try {
      for (var poll = 0; poll < _maxFallbackPolls; poll++) {
        if (_disposed || _activeJobId != jobId) return;
        try {
          await waiter.future.timeout(_jobFallbackInterval);
          return;
        } on TimeoutException {
          // EventBus is the fast path. A low-frequency status call is only a
          // recovery path for a dropped event or disconnected event channel.
        }

        if (_disposed || _activeJobId != jobId) return;
        final status = await _bridge.getJobStatus(jobId);
        if (_disposed || _activeJobId != jobId) return;
        _applyPolledJobStatus(jobId, status);
        if (waiter.isCompleted) {
          await waiter.future;
          return;
        }
      }
    } finally {
      _jobWaiters.remove(jobId);
    }
    throw const CloudOSBridgeException(
      'job_timeout',
      'A operação de arquivo excedeu o tempo limite.',
    );
  }

  void _applyPolledJobStatus(String jobId, Map<String, Object?> status) {
    if (_disposed || _activeJobId != jobId) return;
    _activeJobProgress = ((status['progress'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100)
        .toDouble();
    final state = status['state'] as String? ?? 'unknown';
    _activeJobStatus = state;
    notifyListeners();
    _completeJobFromState(
      jobId,
      state,
      error: status['error'] as String?,
    );
  }

  void _onRuntimeEvent(BrokerRuntimeEvent event) {
    if (_disposed) return;
    if (event.name.startsWith('job.')) {
      _handleJobEvent(event);
    }
    if (event.name == 'files.changed') {
      _scheduleRefreshForFileChange(event.payload);
    }
  }

  void _handleJobEvent(BrokerRuntimeEvent event) {
    final rawJobId = event.payload['jobId'];
    if (rawJobId is! String || rawJobId.isEmpty || rawJobId != _activeJobId) {
      return;
    }

    switch (event.name) {
      case 'job.started':
        _activeJobStatus = 'queued';
        break;
      case 'job.progress':
        _activeJobStatus = 'running';
        _activeJobProgress =
            ((event.payload['progress'] as num?)?.toDouble() ??
                    _activeJobProgress)
                .clamp(0, 100)
                .toDouble();
        break;
      case 'job.completed':
        _activeJobStatus = 'completed';
        _activeJobProgress = 100;
        _completeJobFromState(rawJobId, 'completed');
        break;
      case 'job.failed':
        _activeJobStatus = 'failed';
        _completeJobFromState(
          rawJobId,
          'failed',
          error: event.payload['error'] as String?,
        );
        break;
      case 'job.cancelled':
        _activeJobStatus = 'cancelled';
        _completeJobFromState(rawJobId, 'cancelled');
        break;
    }
    notifyListeners();
  }

  void _completeJobFromState(
    String jobId,
    String state, {
    String? error,
  }) {
    final waiter = _jobWaiters[jobId];
    if (waiter == null || waiter.isCompleted) return;
    switch (state) {
      case 'completed':
        waiter.complete();
        break;
      case 'failed':
        waiter.completeError(
          CloudOSBridgeException(
            'job_failed',
            error?.trim().isNotEmpty == true
                ? error!.trim()
                : 'A operação de arquivo falhou.',
          ),
        );
        break;
      case 'cancelled':
        waiter.completeError(
          const CloudOSBridgeException(
            'job_cancelled',
            'A operação foi cancelada.',
          ),
        );
        break;
    }
  }

  void _scheduleRefreshForFileChange(Map<String, Object?> payload) {
    if (_tabs.isEmpty) return;
    final affectedDirectories = <String>{};
    final changedPaths = <String>{};

    void addDirectory(Object? value) {
      if (value is! String) return;
      final normalized = _normalizeFilesystemPath(value);
      if (normalized.isNotEmpty) affectedDirectories.add(normalized);
    }

    void addChangedPath(Object? value) {
      if (value is! String) return;
      final normalized = _normalizeFilesystemPath(value);
      if (normalized.isEmpty) return;
      changedPaths.add(normalized);
      final parent = _parentDirectory(normalized);
      if (parent != null) affectedDirectories.add(parent);
    }

    addDirectory(payload['parentPath']);
    addDirectory(payload['destination']);
    addChangedPath(payload['path']);
    addChangedPath(payload['oldPath']);
    addChangedPath(payload['newPath']);
    final paths = payload['paths'];
    if (paths is List) {
      for (final path in paths) {
        addChangedPath(path);
      }
    }

    if (affectedDirectories.isEmpty && changedPaths.isEmpty) return;
    for (final tab in _tabs) {
      final resolved = resolveFilesystemPath(tab.currentPath) ?? tab.currentPath;
      final tabPath = _normalizeFilesystemPath(resolved);
      if (tabPath.isEmpty) continue;
      if (affectedDirectories.contains(tabPath) || changedPaths.contains(tabPath)) {
        _pendingRefreshTabIds.add(tab.id);
      }
    }
    if (_pendingRefreshTabIds.isEmpty) return;

    _eventRefreshDebounce?.cancel();
    _eventRefreshDebounce = Timer(_eventRefreshDelay, () {
      _eventRefreshDebounce = null;
      unawaited(_flushEventRefreshes());
    });
  }

  Future<void> _flushEventRefreshes() async {
    if (_disposed || _pendingRefreshTabIds.isEmpty) return;
    final ids = Set<String>.from(_pendingRefreshTabIds);
    _pendingRefreshTabIds.clear();
    final targets = _tabs
        .where((tab) => ids.contains(tab.id))
        .toList(growable: false);
    await Future.wait(targets.map(loadTabFiles));
  }

  String _normalizeFilesystemPath(String input) {
    var path = input.trim().replaceAll('/', r'\');
    while (path.length > 3 && path.endsWith(r'\')) {
      path = path.substring(0, path.length - 1);
    }
    return path.toLowerCase();
  }

  String? _parentDirectory(String normalizedPath) {
    if (normalizedPath.isEmpty) return null;
    final index = normalizedPath.lastIndexOf(r'\');
    if (index <= 0) return null;
    if (index == 2 && normalizedPath.length >= 2 && normalizedPath[1] == ':') {
      return normalizedPath.substring(0, 3);
    }
    return normalizedPath.substring(0, index);
  }

  Future<void> openItem(CloudFileItem item) async {
    if (item.isDirectory) {
      await navigateTo(item.path, title: item.name);
    } else {
      await _bridge.openDefault(item.path);
    }
  }

  Future<List<OpenWithAppModel>> getOpenWith(String path) {
    return _bridge.getOpenWithList(path);
  }

  Future<bool> launchOpenWith(String path, OpenWithAppModel app) {
    return _bridge.launchOpenWith(
      path,
      app.appId,
      app.platform,
      distro: app.distro,
    );
  }
}
