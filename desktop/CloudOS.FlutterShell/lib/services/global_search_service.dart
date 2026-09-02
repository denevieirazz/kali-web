import 'package:flutter/material.dart';

import '../models/file_models.dart';
import '../models/search_models.dart';
import '../models/shell_models.dart';
import 'app_registry.dart';
import 'cloudos_bridge.dart';
import 'cloudos_logger.dart';
import 'project_store.dart';
import 'search_history_store.dart';
import 'search_query_parser.dart';
import 'search_ranker.dart';
import 'search_settings_catalog.dart';

class _DirectoryQueueEntry {
  const _DirectoryQueueEntry(this.path, this.depth);
  final String path;
  final int depth;
}

class _FileSearchOutcome {
  const _FileSearchOutcome({
    required this.results,
    required this.directoriesVisited,
    required this.itemsExamined,
    required this.truncated,
    required this.failed,
  });

  final List<SearchResult> results;
  final int directoriesVisited;
  final int itemsExamined;
  final bool truncated;
  final bool failed;
}

/// Search V23 coordinator. Files are discovered exclusively through typed
/// Files V22 APIs and a strict traversal budget.
class GlobalSearchService {
  GlobalSearchService({
    required CloudOSBridge bridge,
    SearchQueryParser parser = const SearchQueryParser(),
    SearchRanker? ranker,
    SearchHistoryStore? historyStore,
    SearchFileBudget fileBudget = const SearchFileBudget(),
  })  : _bridge = bridge,
        _parser = parser,
        _ranker = ranker ?? SearchRanker(parser: parser),
        _historyStore = historyStore ?? SearchHistoryStore(),
        _fileBudget = fileBudget.sanitized();

  final CloudOSBridge _bridge;
  final SearchQueryParser _parser;
  final SearchRanker _ranker;
  final SearchHistoryStore _historyStore;
  final SearchFileBudget _fileBudget;

  int _generation = 0;
  List<SearchHistoryEntry>? _historyCache;
  List<KnownFolderModel>? _knownFoldersCache;
  DateTime? _knownFoldersLoadedAt;

  int get generation => _generation;

  void cancel() {
    _generation++;
  }

  Future<void> recordActivation(SearchResult result) async {
    // File result IDs contain paths. Never persist those IDs cross-session.
    if (result.category == SearchCategory.files) return;
    try {
      await _historyStore.record(result);
      _historyCache = null;
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'GlobalSearchService',
        'recordActivation',
        error,
        stackTrace,
      );
    }
  }

  Future<SearchBatch> search({
    required String rawQuery,
    required List<CloudApp> runtimeApps,
  }) async {
    final myGeneration = ++_generation;
    final stopwatch = Stopwatch()..start();
    final query = _parser.parse(rawQuery);
    final results = <SearchResult>[];
    final completed = <String>{};
    final failed = <String>{};
    var fileDirectoriesVisited = 0;
    var fileItemsExamined = 0;
    var fileSearchTruncated = false;

    final history = await _loadHistory();
    if (myGeneration != _generation) {
      return _cancelledBatch(query, myGeneration, stopwatch.elapsed);
    }
    final historyBoosts = _buildHistoryBoosts(history);

    if (query.wantsApps) {
      try {
        results.addAll(_searchApps(query, runtimeApps, historyBoosts));
        completed.add('apps');
      } catch (error, stackTrace) {
        failed.add('apps');
        CloudOSLogger.error('GlobalSearchService', 'apps', error, stackTrace);
      }
    }

    if (query.wantsSettings) {
      try {
        results.addAll(
          _searchSettings(
            query,
            runtimeApps: runtimeApps,
            historyBoosts: historyBoosts,
          ),
        );
        completed.add('settings');
      } catch (error, stackTrace) {
        failed.add('settings');
        CloudOSLogger.error('GlobalSearchService', 'settings', error, stackTrace);
      }
    }

    if (query.wantsProjects) {
      try {
        final projects = await ProjectStore.load();
        if (myGeneration != _generation) {
          return _cancelledBatch(query, myGeneration, stopwatch.elapsed);
        }
        results.addAll(_searchProjects(query, projects, historyBoosts));
        completed.add('projects');
      } catch (error, stackTrace) {
        failed.add('projects');
        CloudOSLogger.error('GlobalSearchService', 'projects', error, stackTrace);
      }
    }

    if (query.wantsWsl) {
      try {
        results.addAll(_searchWsl(query, runtimeApps, historyBoosts));
        completed.add('wsl');
      } catch (error, stackTrace) {
        failed.add('wsl');
        CloudOSLogger.error('GlobalSearchService', 'wsl', error, stackTrace);
      }
    }

    // Ctrl+Space with no query stays cheap. One-character input also avoids a
    // filesystem traversal to prevent churn while the user is still typing.
    if (query.wantsFiles && !query.isEmpty && query.plainText.length >= 2) {
      try {
        final outcome = await _searchFiles(
          query,
          generation: myGeneration,
          historyBoosts: historyBoosts,
        );
        if (myGeneration != _generation) {
          return _cancelledBatch(query, myGeneration, stopwatch.elapsed);
        }
        results.addAll(outcome.results);
        fileDirectoriesVisited = outcome.directoriesVisited;
        fileItemsExamined = outcome.itemsExamined;
        fileSearchTruncated = outcome.truncated;
        if (outcome.failed) {
          failed.add('files');
        } else {
          completed.add('files');
        }
      } catch (error, stackTrace) {
        failed.add('files');
        CloudOSLogger.error('GlobalSearchService', 'files', error, stackTrace);
      }
    }

    if (query.isEmpty) {
      results.addAll(_buildRecentResults(history, runtimeApps));
      completed.add('recent');
    }

    final deduped = _dedupeAndSort(results);
    stopwatch.stop();
    return SearchBatch(
      query: query,
      results: List<SearchResult>.unmodifiable(deduped.take(60)),
      diagnostics: SearchDiagnostics(
        generation: myGeneration,
        elapsed: stopwatch.elapsed,
        totalResults: deduped.length,
        fileDirectoriesVisited: fileDirectoriesVisited,
        fileItemsExamined: fileItemsExamined,
        fileSearchTruncated: fileSearchTruncated,
        sourcesCompleted: Set<String>.unmodifiable(completed),
        sourcesFailed: Set<String>.unmodifiable(failed),
      ),
      isFinal: true,
    );
  }

  SearchBatch _cancelledBatch(
    SearchQuery query,
    int generation,
    Duration elapsed,
  ) {
    return SearchBatch(
      query: query,
      results: const <SearchResult>[],
      diagnostics: SearchDiagnostics(
        generation: generation,
        elapsed: elapsed,
        totalResults: 0,
        fileDirectoriesVisited: 0,
        fileItemsExamined: 0,
        fileSearchTruncated: true,
        sourcesCompleted: const <String>{},
        sourcesFailed: const <String>{'cancelled'},
      ),
      isFinal: true,
    );
  }

  Future<List<SearchHistoryEntry>> _loadHistory() async {
    final cached = _historyCache;
    if (cached != null) return cached;
    final loaded = await _historyStore.load();
    _historyCache = loaded;
    return loaded;
  }

  Map<String, double> _buildHistoryBoosts(List<SearchHistoryEntry> history) {
    final now = DateTime.now();
    final result = <String, double>{};
    for (final entry in history) {
      final age = now.difference(entry.lastUsedAt);
      final recency = age.inMinutes < 15
          ? 24.0
          : age.inHours < 6
              ? 18.0
              : age.inDays < 2
                  ? 12.0
                  : age.inDays < 14
                      ? 6.0
                      : 2.0;
      final frequency = entry.useCount.clamp(1, 20).toDouble() * 1.5;
      result[entry.resultId] = recency + frequency;
    }
    return result;
  }

  List<SearchResult> _searchApps(
    SearchQuery query,
    List<CloudApp> runtimeApps,
    Map<String, double> historyBoosts,
  ) {
    final results = <SearchResult>[];
    final seen = <String>{};

    for (final definition in AppRegistry.definedApps) {
      if (!definition.isInternal) continue;
      final lowerId = definition.id.toLowerCase();
      if (lowerId.startsWith('wsl:')) continue;
      final id = 'app:${definition.id}';
      final scored = _ranker.score(
        query: query,
        title: definition.name,
        subtitle: definition.subtitle,
        keywords: <String>[definition.id, definition.category.name, 'cloudos'],
        sourceBoost: 16,
        historyBoost: historyBoosts[id] ?? 0,
      );
      if (!scored.matched) continue;
      seen.add(lowerId);
      results.add(
        SearchResult(
          id: id,
          title: definition.name,
          subtitle: definition.subtitle,
          category: SearchCategory.apps,
          icon: definition.icon,
          iconColor: const Color(0xFF58A6FF),
          score: scored.score,
          matchKind: scored.kind,
          action: SearchAction(
            kind: SearchActionKind.openInternalApp,
            appId: definition.id,
          ),
          keywords: <String>[definition.id, definition.category.name, 'cloudos'],
          source: 'AppRegistry',
        ),
      );
    }

    for (final app in runtimeApps) {
      final lowerId = app.id.toLowerCase();
      final isLinux = app.platform == CloudAppPlatform.linux ||
          lowerId.startsWith('wsl:');
      if (isLinux || !seen.add(lowerId)) continue;
      final id = 'runtime:${app.id}';
      final scored = _ranker.score(
        query: query,
        title: app.name,
        subtitle: app.subtitle ?? '',
        keywords: <String>[app.id, app.category],
        sourceBoost: app.isPinned ? 10 : 4,
        historyBoost: historyBoosts[id] ?? 0,
      );
      if (!scored.matched) continue;
      final internal = AppRegistry.findById(app.id);
      results.add(
        SearchResult(
          id: id,
          title: app.name,
          subtitle: app.subtitle ?? 'Aplicativo detectado pelo System Broker',
          category: SearchCategory.apps,
          icon: app.icon,
          iconColor: const Color(0xFF58A6FF),
          score: scored.score,
          matchKind: scored.kind,
          action: internal?.isInternal == true ||
                  app.platform == CloudAppPlatform.cloudos
              ? SearchAction(
                  kind: SearchActionKind.openInternalApp,
                  appId: internal?.id ?? app.id,
                )
              : SearchAction(
                  kind: SearchActionKind.launchRuntimeApp,
                  runtimeAppId: app.id,
                ),
          keywords: <String>[app.id, app.category],
          badges: <String>[app.platform.name.toUpperCase()],
          source: 'System Broker',
        ),
      );
    }

    return results;
  }

  List<SearchResult> _searchSettings(
    SearchQuery query, {
    required List<CloudApp> runtimeApps,
    required Map<String, double> historyBoosts,
  }) {
    final hasWsl = _hasWslRuntime(runtimeApps);
    final results = <SearchResult>[];
    for (final page in SearchSettingsCatalog.pages) {
      if (page.requiresWsl && !hasWsl) continue;
      final id = 'settings:${page.id}';
      final scored = _ranker.score(
        query: query,
        title: page.title,
        subtitle: page.description,
        keywords: page.keywords,
        sourceBoost: 8,
        historyBoost: historyBoosts[id] ?? 0,
      );
      if (!scored.matched) continue;
      results.add(
        SearchResult(
          id: id,
          title: page.title,
          subtitle: page.description,
          category: SearchCategory.settings,
          icon: page.icon,
          iconColor: const Color(0xFFBC8CFF),
          score: scored.score,
          matchKind: scored.kind,
          action: SearchAction(
            kind: SearchActionKind.openSettingsPage,
            appId: 'cloudos:settings',
            settingsPageId: page.id,
            params: <String, dynamic>{'initialSettingsPage': page.id},
          ),
          keywords: page.keywords,
          source: 'Settings Catalog',
        ),
      );
    }
    return results;
  }

  List<SearchResult> _searchProjects(
    SearchQuery query,
    List<ProjectRecord> projects,
    Map<String, double> historyBoosts,
  ) {
    final results = <SearchResult>[];
    for (final project in projects) {
      final id = 'project:${project.id}';
      final type = ProjectStore.detectType(project.path);
      final scored = _ranker.score(
        query: query,
        title: project.name,
        subtitle: project.path,
        keywords: <String>[type, project.id],
        sourceBoost: 12,
        historyBoost: historyBoosts[id] ?? 0,
      );
      if (!scored.matched) continue;
      results.add(
        SearchResult(
          id: id,
          title: project.name,
          subtitle: '${project.path} · $type',
          category: SearchCategory.projects,
          icon: Icons.workspaces_rounded,
          iconColor: const Color(0xFF39D353),
          score: scored.score,
          matchKind: scored.kind,
          action: SearchAction(
            kind: SearchActionKind.openProject,
            appId: 'cloudos:files',
            projectId: project.id,
            path: project.path,
            params: <String, dynamic>{
              'initialPath': project.path,
              'initialTitle': project.name,
            },
          ),
          keywords: <String>[type, project.id],
          badges: <String>[type],
          source: 'ProjectStore',
        ),
      );
    }
    return results;
  }

  List<SearchResult> _searchWsl(
    SearchQuery query,
    List<CloudApp> runtimeApps,
    Map<String, double> historyBoosts,
  ) {
    final results = <SearchResult>[];
    final seenDistros = <String>{};
    for (final app in runtimeApps) {
      final lowerId = app.id.toLowerCase();
      final linux = app.platform == CloudAppPlatform.linux ||
          lowerId.startsWith('wsl:');
      if (!linux) continue;
      final distro = (app.distro ?? _distroFromId(app.id)).trim();
      if (distro.isEmpty || !seenDistros.add(distro.toLowerCase())) continue;
      final id = 'wsl:${distro.toLowerCase()}';
      final scored = _ranker.score(
        query: query,
        title: distro,
        subtitle: 'Terminal WSL integrado',
        keywords: <String>['wsl', 'linux', app.name, app.id],
        sourceBoost: 14,
        historyBoost: historyBoosts[id] ?? 0,
      );
      if (!scored.matched) continue;
      results.add(
        SearchResult(
          id: id,
          title: distro,
          subtitle: 'Abrir Terminal integrado nesta distribuição WSL',
          category: SearchCategory.wsl,
          icon: Icons.terminal_rounded,
          iconColor: const Color(0xFFFFA657),
          score: scored.score,
          matchKind: scored.kind,
          action: SearchAction(
            kind: SearchActionKind.openWslTerminal,
            appId: 'wsl:terminal',
            distro: distro,
            params: <String, dynamic>{'initialDistro': distro},
          ),
          keywords: <String>['wsl', 'linux', app.name],
          badges: const <String>['WSL'],
          source: 'System Broker',
        ),
      );
    }
    return results;
  }

  Future<_FileSearchOutcome> _searchFiles(
    SearchQuery query, {
    required int generation,
    required Map<String, double> historyBoosts,
  }) async {
    final stopwatch = Stopwatch()..start();
    var directoriesVisited = 0;
    var itemsExamined = 0;
    var truncated = false;
    var failed = false;
    final results = <SearchResult>[];
    final visited = <String>{};
    final queue = <_DirectoryQueueEntry>[];

    final roots = await _loadSearchRoots();
    for (final root in roots.take(_fileBudget.maxRoots)) {
      final path = root.path.trim();
      if (path.isEmpty || _isWslUnc(path)) continue;
      final normalized = _normalizeWindowsPathKey(path);
      if (normalized.isNotEmpty && visited.add(normalized)) {
        queue.add(_DirectoryQueueEntry(path, 0));
      }
    }

    var cursor = 0;
    while (cursor < queue.length) {
      if (generation != _generation) {
        truncated = true;
        break;
      }
      if (directoriesVisited >= _fileBudget.maxDirectories ||
          results.length >= _fileBudget.maxResults ||
          stopwatch.elapsed >= _fileBudget.maxDuration) {
        truncated = true;
        break;
      }

      final entry = queue[cursor++];
      directoriesVisited++;
      List<CloudFileItem> items;
      try {
        items = await _bridge.listFiles(
          entry.path,
          pageSize: _fileBudget.maxItemsPerDirectory,
          showHidden: query.includeHidden,
        );
      } catch (error, stackTrace) {
        failed = true;
        CloudOSLogger.error(
          'GlobalSearchService',
          'fileDirectory:${entry.path}',
          error,
          stackTrace,
        );
        continue;
      }

      if (generation != _generation) {
        truncated = true;
        break;
      }

      for (final item in items) {
        itemsExamined++;
        if (!query.includeHidden && item.isHidden) continue;
        if (_excludedByQuery(query, item)) continue;

        if (item.isDirectory &&
            !item.isSymlink &&
            entry.depth < _fileBudget.maxDepth &&
            queue.length < _fileBudget.maxDirectories * 2) {
          final normalized = _normalizeWindowsPathKey(item.path);
          if (normalized.isNotEmpty && visited.add(normalized)) {
            queue.add(_DirectoryQueueEntry(item.path, entry.depth + 1));
          }
        }

        if (!_extensionMatches(query, item)) continue;
        final stablePath = item.canonicalPath.isNotEmpty
            ? item.canonicalPath
            : item.path;
        final id = 'file:$stablePath';
        final scored = _ranker.score(
          query: query,
          title: item.displayName.isNotEmpty ? item.displayName : item.name,
          subtitle: item.path,
          keywords: <String>[
            item.extension,
            item.fileKind.name,
            item.locationKind.name,
          ],
          sourceBoost: item.isDirectory ? 8 : 4,
          historyBoost: historyBoosts[id] ?? 0,
        );
        if (!scored.matched) continue;

        results.add(_fileResult(item, id, scored));
        if (results.length >= _fileBudget.maxResults) {
          truncated = true;
          break;
        }
      }
    }

    stopwatch.stop();
    return _FileSearchOutcome(
      results: results,
      directoriesVisited: directoriesVisited,
      itemsExamined: itemsExamined,
      truncated: truncated,
      failed: failed,
    );
  }

  SearchResult _fileResult(CloudFileItem item, String id, SearchScore scored) {
    final name = item.displayName.isNotEmpty ? item.displayName : item.name;
    if (item.isDirectory) {
      return SearchResult(
        id: id,
        title: name,
        subtitle: item.path,
        category: SearchCategory.files,
        icon: item.icon,
        iconColor: item.iconColor,
        score: scored.score,
        matchKind: scored.kind,
        action: SearchAction(
          kind: SearchActionKind.openFolder,
          appId: 'cloudos:files',
          path: item.path,
          params: <String, dynamic>{
            'initialPath': item.path,
            'initialTitle': name,
          },
        ),
        file: item,
        badges: <String>[item.locationKind.name.toUpperCase()],
        source: 'Files V22',
      );
    }

    final internalText = item.fileKind == FileKind.text ||
        item.fileKind == FileKind.code ||
        <String>{'.json', '.md', '.yaml', '.yml', '.xml', '.ini', '.log'}
            .contains(item.extension.toLowerCase());
    return SearchResult(
      id: id,
      title: name,
      subtitle: item.path,
      category: SearchCategory.files,
      icon: item.icon,
      iconColor: item.iconColor,
      score: scored.score,
      matchKind: scored.kind,
      action: internalText
          ? SearchAction(
              kind: SearchActionKind.openFile,
              appId: 'cloudos:notepad',
              path: item.path,
              params: <String, dynamic>{'initialFilePath': item.path},
            )
          : SearchAction(
              kind: SearchActionKind.openFile,
              path: item.path,
            ),
      file: item,
      badges: <String>[
        if (item.extension.isNotEmpty)
          item.extension.replaceFirst('.', '').toUpperCase(),
      ],
      source: 'Files V22',
    );
  }

  Future<List<KnownFolderModel>> _loadSearchRoots() async {
    final loadedAt = _knownFoldersLoadedAt;
    final cached = _knownFoldersCache;
    if (cached != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 2)) {
      return cached;
    }
    final folders = await _bridge.getKnownFolders();
    const preferred = <String>{
      'home',
      'desktop',
      'documents',
      'downloads',
      'pictures',
    };
    final selected = folders
        .where((folder) => preferred.contains(folder.id.toLowerCase()))
        .toList(growable: false);
    _knownFoldersCache = selected;
    _knownFoldersLoadedAt = DateTime.now();
    return selected;
  }

  bool _excludedByQuery(SearchQuery query, CloudFileItem item) {
    if (query.excludedTerms.isEmpty) return false;
    final haystack = _parser.normalize(
      '${item.name} ${item.path} ${item.extension}',
    );
    return query.excludedTerms.any(haystack.contains);
  }

  bool _extensionMatches(SearchQuery query, CloudFileItem item) {
    if (query.fileExtensions.isEmpty) return true;
    if (item.isDirectory) return false;
    final extension = item.extension.toLowerCase().replaceFirst('.', '');
    return query.fileExtensions.contains(extension);
  }

  bool _isWslUnc(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith(r'\\wsl.localhost\') ||
        lower.startsWith(r'\\wsl$\');
  }

  String _normalizeWindowsPathKey(String path) {
    var normalized = path.trim().replaceAll('/', r'\').toLowerCase();
    while (normalized.length > 3 && normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _hasWslRuntime(List<CloudApp> runtimeApps) {
    return runtimeApps.any(
      (app) => app.platform == CloudAppPlatform.linux ||
          app.id.toLowerCase().startsWith('wsl:'),
    );
  }

  String _distroFromId(String id) {
    final parts = id.split(':');
    if (parts.length >= 3 &&
        parts.first.toLowerCase() == 'wsl' &&
        parts.last.toLowerCase() == 'terminal') {
      return parts.sublist(1, parts.length - 1).join(':');
    }
    return '';
  }

  List<SearchResult> _buildRecentResults(
    List<SearchHistoryEntry> history,
    List<CloudApp> runtimeApps,
  ) {
    if (history.isEmpty) return const <SearchResult>[];
    final results = <SearchResult>[];
    final appById = <String, CloudApp>{
      for (final app in runtimeApps) app.id.toLowerCase(): app,
    };

    for (final entry in history.take(8)) {
      SearchAction action = const SearchAction.none();
      IconData icon = Icons.history_rounded;
      Color color = const Color(0xFFE3B341);

      if (entry.resultId.startsWith('app:')) {
        final appId = entry.resultId.substring(4);
        final definition = AppRegistry.findById(appId);
        if (definition != null && definition.isInternal) {
          action = SearchAction(
            kind: SearchActionKind.openInternalApp,
            appId: appId,
          );
          icon = definition.icon;
        }
      } else if (entry.resultId.startsWith('runtime:')) {
        final appId = entry.resultId.substring(8);
        final runtime = appById[appId.toLowerCase()];
        if (runtime != null) {
          action = SearchAction(
            kind: SearchActionKind.launchRuntimeApp,
            runtimeAppId: runtime.id,
          );
          icon = runtime.icon;
        }
      } else if (entry.resultId.startsWith('settings:')) {
        final pageId = entry.resultId.substring(9);
        final page = SearchSettingsCatalog.findById(pageId);
        if (page != null) {
          action = SearchAction(
            kind: SearchActionKind.openSettingsPage,
            appId: 'cloudos:settings',
            settingsPageId: pageId,
            params: <String, dynamic>{'initialSettingsPage': pageId},
          );
          icon = page.icon;
          color = const Color(0xFFBC8CFF);
        }
      } else if (entry.resultId.startsWith('wsl:')) {
        final distro = entry.resultId.substring(4);
        if (distro.isNotEmpty) {
          action = SearchAction(
            kind: SearchActionKind.openWslTerminal,
            appId: 'wsl:terminal',
            distro: distro,
            params: <String, dynamic>{'initialDistro': distro},
          );
          icon = Icons.terminal_rounded;
          color = const Color(0xFFFFA657);
        }
      }

      if (!action.isExecutable) continue;
      results.add(
        SearchResult(
          id: 'recent:${entry.resultId}',
          title: entry.title,
          subtitle: 'Usado recentemente · ${entry.category.name}',
          category: SearchCategory.recent,
          icon: icon,
          iconColor: color,
          score: 25.0 + entry.useCount.clamp(1, 20).toDouble(),
          matchKind: SearchMatchKind.fallback,
          action: action,
          source: 'Search History',
        ),
      );
    }
    return results;
  }

  List<SearchResult> _dedupeAndSort(List<SearchResult> input) {
    final byId = <String, SearchResult>{};
    for (final result in input) {
      final previous = byId[result.id];
      if (previous == null || result.score > previous.score) {
        byId[result.id] = result;
      }
    }
    final values = byId.values.toList(growable: false);
    values.sort((a, b) {
      final availability =
          (b.isAvailable ? 1 : 0).compareTo(a.isAvailable ? 1 : 0);
      if (availability != 0) return availability;
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final category = a.category.index.compareTo(b.category.index);
      if (category != 0) return category;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return values;
  }
}
