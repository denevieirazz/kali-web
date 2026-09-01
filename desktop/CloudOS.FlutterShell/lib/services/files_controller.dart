import 'dart:async';

import 'package:flutter/material.dart';

import '../models/file_models.dart';
import 'broker_events.dart';
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
    : _bridge = bridge ?? const CloudOSBridge(),
      _eventStartFuture = CloudOSBrokerEvents.instance.start() {
    _eventSubscription = CloudOSBrokerEvents.instance.stream.listen(
      _onBrokerEvent,
    );
    _init();
  }

  final CloudOSBridge _bridge;
  final Future<bool> _eventStartFuture;
  StreamSubscription<CloudOSBrokerEvent>? _eventSubscription;
  Timer? _filesRefreshDebounce;
  Completer<Map<String, Object?>>? _activeJobCompleter;

  final List<FilesTabState> _tabs = <FilesTabState>[];
  int _activeTabIndex = 0;

  List<KnownFolderModel> _knownFolders = <KnownFolderModel>[];
  List<DriveInfoModel> _drives = <DriveInfoModel>[];

  List<String> _clipboardPaths = <String>[];
  bool _isCutOperation = false;

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
  List<String> get clipboardPaths => List<String>.unmodifiable(_clipboardPaths);
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
    _filesRefreshDebounce?.cancel();
    _eventSubscription?.cancel();
    final completer = _activeJobCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(<String, Object?>{'state': 'disposed'});
    }
    _activeJobCompleter = null;
    for (final tab in _tabs) {
      tab.loadGeneration++;
    }
    super.dispose();
  }

  void _onBrokerEvent(CloudOSBrokerEvent event) {
    if (_disposed) return;

    if (event.name == 'files.changed') {
      _filesRefreshDebounce?.cancel();
      _filesRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!_disposed) refresh();
      });
      return;
    }

    if (!event.name.startsWith('job.')) return;
    final jobId = event.payload['jobId'];
    if (jobId is! String || jobId != _activeJobId) return;

    if (event.name == 'job.progress') {
      _activeJobProgress = ((event.payload['progress'] as num?)?.toDouble() ?? 0)
          .clamp(0, 100)
          .toDouble();
      _activeJobStatus = event.payload['state'] as String? ?? 'running';
      notifyListeners();
      return;
    }

    final terminalState = switch (event.name) {
      'job.completed' => 'completed',
      'job.failed' => 'failed',
      'job.cancelled' => 'cancelled',
      _ => null,
    };
    if (terminalState == null) return;

    _activeJobStatus = terminalState;
    if (terminalState == 'completed') _activeJobProgress = 100;
    notifyListeners();

    final completer = _activeJobCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(<String, Object?>{
        ...event.payload,
        'state': terminalState,
      });
    }
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
    addTab(title: 'Início', initialPath: 'home');
    notifyListeners();
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
    loadTabFiles(tab);
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length || _tabs.length <= 1) return;
    _tabs[index].loadGeneration++;
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
    if (tab == null || path.trim().isEmpty) return;

    if (tab.historyIndex < tab.history.length - 1) {
      tab.history = tab.history.sublist(0, tab.historyIndex + 1);
    }
    tab.history.add(path);
    tab.historyIndex = tab.history.length - 1;
    tab.currentPath = path;
    if (title != null) tab.title = title;
    tab.selectedPaths.clear();

    await loadTabFiles(tab);
  }

  Future<void> goBack() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoBack) return;
    tab.historyIndex--;
    tab.currentPath = tab.history[tab.historyIndex];
    tab.selectedPaths.clear();
    await loadTabFiles(tab);
  }

  Future<void> goForward() async {
    final tab = activeTab;
    if (tab == null || !tab.canGoForward) return;
    tab.historyIndex++;
    tab.currentPath = tab.history[tab.historyIndex];
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
    } catch (e) {
      if (_disposed || !_tabs.contains(tab) || generation != tab.loadGeneration) {
        return;
      }
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
    if (tab == null) return;
    if (tab.sortField == field) {
      tab.sortAscending = !tab.sortAscending;
    } else {
      tab.sortField = field;
      tab.sortAscending = true;
    }
    loadTabFiles(tab);
  }

  void setSearchQuery(String query) {
    final tab = activeTab;
    if (tab == null || tab.searchQuery == query) return;
    tab.searchQuery = query;
    loadTabFiles(tab);
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
      tab.selectedPaths = tab.items.map((i) => i.path).toSet();
      notifyListeners();
    }
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
      _activeJobCompleter = null;
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
    final reactive = await _eventStartFuture;
    if (_disposed || _activeJobId != jobId) return;
    if (reactive) {
      await _waitForJobReactive(jobId);
      return;
    }
    await _waitForJobPollingFallback(jobId);
  }

  Future<void> _waitForJobReactive(String jobId) async {
    final completer = Completer<Map<String, Object?>>();
    _activeJobCompleter = completer;

    // A tiny file job can finish before files.copy/move returns its jobId. One
    // immediate status read closes that race; after this point production waits
    // for Broker EventBus completion instead of polling every 100 ms.
    final initial = await _bridge.getJobStatus(jobId);
    if (_disposed || _activeJobId != jobId) return;
    _applyJobStatus(initial);
    if (_isTerminalJobState(_activeJobStatus)) {
      _throwIfJobFailedOrCancelled(initial);
      return;
    }

    Map<String, Object?> terminal;
    try {
      terminal = await completer.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      // One final read distinguishes a genuinely stuck/missed stream from an
      // event that raced with the timeout boundary. This is not a poll loop.
      terminal = await _bridge.getJobStatus(jobId);
    }

    if (_disposed || _activeJobId != jobId) return;
    _applyJobStatus(terminal);
    if (!_isTerminalJobState(_activeJobStatus)) {
      throw const CloudOSBridgeException(
        'job_timeout',
        'A operação de arquivo excedeu o tempo limite.',
      );
    }
    _throwIfJobFailedOrCancelled(terminal);
  }

  Future<void> _waitForJobPollingFallback(String jobId) async {
    // Preview/widget-test/legacy bridge fallback only. Native V23 production
    // reaches _waitForJobReactive after startBrokerEvents succeeds.
    const maxPolls = 240;
    for (var poll = 0; poll < maxPolls; poll++) {
      if (_disposed || _activeJobId != jobId) return;
      final status = await _bridge.getJobStatus(jobId);
      if (_disposed || _activeJobId != jobId) return;
      _applyJobStatus(status);
      if (_isTerminalJobState(_activeJobStatus)) {
        _throwIfJobFailedOrCancelled(status);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const CloudOSBridgeException(
      'job_timeout',
      'A operação de arquivo excedeu o tempo limite.',
    );
  }

  void _applyJobStatus(Map<String, Object?> status) {
    _activeJobProgress = ((status['progress'] as num?)?.toDouble() ??
            (_activeJobStatus == 'completed' ? 100 : _activeJobProgress))
        .clamp(0, 100)
        .toDouble();
    _activeJobStatus = status['state'] as String? ?? _activeJobStatus;
    if (_activeJobStatus == 'completed') _activeJobProgress = 100;
    notifyListeners();
  }

  bool _isTerminalJobState(String state) =>
      state == 'completed' || state == 'failed' || state == 'cancelled';

  void _throwIfJobFailedOrCancelled(Map<String, Object?> status) {
    switch (_activeJobStatus) {
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
