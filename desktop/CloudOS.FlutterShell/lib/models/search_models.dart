import 'package:flutter/material.dart';

import 'file_models.dart';

/// Search V23 is intentionally typed. Search results never carry executable
/// shell strings. They describe a destination/action that the presentation
/// layer routes through existing CloudOS APIs.
enum SearchCategory {
  apps,
  files,
  settings,
  projects,
  wsl,
  recent,
}

enum SearchActionKind {
  openInternalApp,
  launchRuntimeApp,
  openFile,
  openFolder,
  openSettingsPage,
  openProject,
  openWslTerminal,
  none,
}

enum SearchMatchKind {
  exact,
  prefix,
  wordPrefix,
  contains,
  keyword,
  fuzzy,
  fallback,
}

enum SearchScope {
  all,
  apps,
  files,
  settings,
  projects,
  wsl,
}

class SearchQuery {
  const SearchQuery({
    required this.raw,
    required this.normalized,
    required this.terms,
    required this.scope,
    required this.fileExtensions,
    required this.excludedTerms,
    required this.includeHidden,
    required this.explicitScope,
  });

  final String raw;
  final String normalized;
  final List<String> terms;
  final SearchScope scope;
  final Set<String> fileExtensions;
  final Set<String> excludedTerms;
  final bool includeHidden;
  final bool explicitScope;

  bool get isEmpty => terms.isEmpty && fileExtensions.isEmpty;
  bool get wantsFiles => scope == SearchScope.all || scope == SearchScope.files;
  bool get wantsApps => scope == SearchScope.all || scope == SearchScope.apps;
  bool get wantsSettings =>
      scope == SearchScope.all || scope == SearchScope.settings;
  bool get wantsProjects =>
      scope == SearchScope.all || scope == SearchScope.projects;
  bool get wantsWsl => scope == SearchScope.all || scope == SearchScope.wsl;

  String get plainText => terms.join(' ');

  SearchQuery copyWith({
    String? raw,
    String? normalized,
    List<String>? terms,
    SearchScope? scope,
    Set<String>? fileExtensions,
    Set<String>? excludedTerms,
    bool? includeHidden,
    bool? explicitScope,
  }) {
    return SearchQuery(
      raw: raw ?? this.raw,
      normalized: normalized ?? this.normalized,
      terms: terms ?? this.terms,
      scope: scope ?? this.scope,
      fileExtensions: fileExtensions ?? this.fileExtensions,
      excludedTerms: excludedTerms ?? this.excludedTerms,
      includeHidden: includeHidden ?? this.includeHidden,
      explicitScope: explicitScope ?? this.explicitScope,
    );
  }

  @override
  String toString() {
    return 'SearchQuery(scope: $scope, terms: $terms, extensions: '
        '$fileExtensions, excluded: $excludedTerms, hidden: $includeHidden)';
  }
}

class SearchAction {
  const SearchAction({
    required this.kind,
    this.appId,
    this.path,
    this.distro,
    this.settingsPageId,
    this.projectId,
    this.runtimeAppId,
    this.params = const <String, dynamic>{},
  });

  const SearchAction.none()
      : kind = SearchActionKind.none,
        appId = null,
        path = null,
        distro = null,
        settingsPageId = null,
        projectId = null,
        runtimeAppId = null,
        params = const <String, dynamic>{};

  final SearchActionKind kind;
  final String? appId;
  final String? path;
  final String? distro;
  final String? settingsPageId;
  final String? projectId;
  final String? runtimeAppId;
  final Map<String, dynamic> params;

  bool get isExecutable => kind != SearchActionKind.none;
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.score,
    required this.matchKind,
    required this.action,
    this.keywords = const <String>[],
    this.badges = const <String>[],
    this.file,
    this.source = 'CloudOS',
    this.isAvailable = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final SearchCategory category;
  final IconData icon;
  final Color iconColor;
  final double score;
  final SearchMatchKind matchKind;
  final SearchAction action;
  final List<String> keywords;
  final List<String> badges;
  final CloudFileItem? file;
  final String source;
  final bool isAvailable;

  String get categoryLabel => switch (category) {
        SearchCategory.apps => 'APLICATIVOS',
        SearchCategory.files => 'ARQUIVOS',
        SearchCategory.settings => 'CONFIGURAÇÕES',
        SearchCategory.projects => 'PROJETOS',
        SearchCategory.wsl => 'WSL',
        SearchCategory.recent => 'RECENTES',
      };

  Color get categoryColor => switch (category) {
        SearchCategory.apps => const Color(0xFF58A6FF),
        SearchCategory.files => const Color(0xFF79C0FF),
        SearchCategory.settings => const Color(0xFFBC8CFF),
        SearchCategory.projects => const Color(0xFF39D353),
        SearchCategory.wsl => const Color(0xFFFFA657),
        SearchCategory.recent => const Color(0xFFE3B341),
      };

  SearchResult copyWith({
    String? title,
    String? subtitle,
    double? score,
    SearchMatchKind? matchKind,
    SearchAction? action,
    List<String>? badges,
    bool? isAvailable,
  }) {
    return SearchResult(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      category: category,
      icon: icon,
      iconColor: iconColor,
      score: score ?? this.score,
      matchKind: matchKind ?? this.matchKind,
      action: action ?? this.action,
      keywords: keywords,
      badges: badges ?? this.badges,
      file: file,
      source: source,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }
}

class SearchSettingsDescriptor {
  const SearchSettingsDescriptor({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.keywords,
    this.requiresWsl = false,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<String> keywords;
  final bool requiresWsl;
}

class SearchFileBudget {
  const SearchFileBudget({
    this.maxRoots = 5,
    this.maxDirectories = 64,
    this.maxDepth = 2,
    this.maxItemsPerDirectory = 160,
    this.maxResults = 30,
    this.maxDuration = const Duration(milliseconds: 900),
  });

  final int maxRoots;
  final int maxDirectories;
  final int maxDepth;
  final int maxItemsPerDirectory;
  final int maxResults;
  final Duration maxDuration;

  SearchFileBudget sanitized() {
    return SearchFileBudget(
      maxRoots: maxRoots.clamp(1, 8).toInt(),
      maxDirectories: maxDirectories.clamp(1, 256).toInt(),
      maxDepth: maxDepth.clamp(0, 4).toInt(),
      maxItemsPerDirectory: maxItemsPerDirectory.clamp(20, 300).toInt(),
      maxResults: maxResults.clamp(1, 80).toInt(),
      maxDuration: Duration(
        milliseconds: maxDuration.inMilliseconds.clamp(100, 2500).toInt(),
      ),
    );
  }
}

class SearchDiagnostics {
  const SearchDiagnostics({
    required this.generation,
    required this.elapsed,
    required this.totalResults,
    required this.fileDirectoriesVisited,
    required this.fileItemsExamined,
    required this.fileSearchTruncated,
    required this.sourcesCompleted,
    required this.sourcesFailed,
  });

  const SearchDiagnostics.empty()
      : generation = 0,
        elapsed = Duration.zero,
        totalResults = 0,
        fileDirectoriesVisited = 0,
        fileItemsExamined = 0,
        fileSearchTruncated = false,
        sourcesCompleted = const <String>{},
        sourcesFailed = const <String>{};

  final int generation;
  final Duration elapsed;
  final int totalResults;
  final int fileDirectoriesVisited;
  final int fileItemsExamined;
  final bool fileSearchTruncated;
  final Set<String> sourcesCompleted;
  final Set<String> sourcesFailed;
}

class SearchBatch {
  const SearchBatch({
    required this.query,
    required this.results,
    required this.diagnostics,
    required this.isFinal,
  });

  final SearchQuery query;
  final List<SearchResult> results;
  final SearchDiagnostics diagnostics;
  final bool isFinal;

  SearchBatch copyWith({
    List<SearchResult>? results,
    SearchDiagnostics? diagnostics,
    bool? isFinal,
  }) {
    return SearchBatch(
      query: query,
      results: results ?? this.results,
      diagnostics: diagnostics ?? this.diagnostics,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}

class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.resultId,
    required this.title,
    required this.category,
    required this.lastUsedAt,
    required this.useCount,
  });

  final String resultId;
  final String title;
  final SearchCategory category;
  final DateTime lastUsedAt;
  final int useCount;

  SearchHistoryEntry touch(DateTime now) {
    return SearchHistoryEntry(
      resultId: resultId,
      title: title,
      category: category,
      lastUsedAt: now,
      useCount: useCount + 1,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'resultId': resultId,
        'title': title,
        'category': category.name,
        'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
        'useCount': useCount,
      };

  static SearchHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final resultId = value['resultId'];
    final title = value['title'];
    final categoryName = value['category'];
    final lastUsed = value['lastUsedAt'];
    final count = value['useCount'];
    if (resultId is! String || resultId.isEmpty || title is! String) {
      return null;
    }
    SearchCategory category = SearchCategory.recent;
    if (categoryName is String) {
      for (final candidate in SearchCategory.values) {
        if (candidate.name == categoryName) {
          category = candidate;
          break;
        }
      }
    }
    final parsed = lastUsed is String ? DateTime.tryParse(lastUsed) : null;
    return SearchHistoryEntry(
      resultId: resultId,
      title: title,
      category: category,
      lastUsedAt: parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      useCount: count is num
          ? count.toInt().clamp(1, 1 << 20).toInt()
          : 1,
    );
  }
}

class SearchSourceProgress {
  const SearchSourceProgress({
    required this.source,
    required this.running,
    required this.completed,
    required this.failed,
    required this.resultCount,
  });

  final String source;
  final bool running;
  final bool completed;
  final bool failed;
  final int resultCount;
}
