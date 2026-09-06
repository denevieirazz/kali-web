import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Central versioned user preferences for CloudOS.
/// Handles desktop layout, pinning, recent apps, first run state,
/// appearance and performance profile with atomic save and corruption recovery.
class CloudOSPreferences {
  CloudOSPreferences({
    this.schemaVersion = 1,
    this.firstRunCompleted = false,
    this.appearanceTheme = 'auto',
    this.accentColorValue = 0xFF0078D4,
    this.performanceProfile = 'auto',
    this.hardwareSummary = '',
    Map<String, List<double>>? desktopIconPositions,
    List<String>? pinnedAppIds,
    List<String>? recentAppIds,
    List<String>? favoriteFolderPaths,
    this.filesViewMode = 'details',
    this.startupEnabled = true,
  })  : desktopIconPositions = desktopIconPositions ?? <String, List<double>>{},
        pinnedAppIds = pinnedAppIds ?? <String>[
          'files',
          'terminal',
          'browser',
          'settings',
          'task_manager',
        ],
        recentAppIds = recentAppIds ?? <String>[],
        favoriteFolderPaths = favoriteFolderPaths ?? <String>[];

  static const int currentSchemaVersion = 1;
  static const int maxRecentApps = 10;

  final int schemaVersion;
  bool firstRunCompleted;
  String appearanceTheme; // 'dark', 'light', 'auto'
  int accentColorValue;
  String performanceProfile; // 'auto', 'economy', 'balanced', 'performance'
  String hardwareSummary;
  final Map<String, List<double>> desktopIconPositions;
  final List<String> pinnedAppIds;
  final List<String> recentAppIds;
  final List<String> favoriteFolderPaths;
  String filesViewMode; // 'details', 'grid', 'list'
  bool startupEnabled;

  void recordAppLaunch(String appId) {
    recentAppIds.remove(appId);
    recentAppIds.insert(0, appId);
    if (recentAppIds.length > maxRecentApps) {
      recentAppIds.removeRange(maxRecentApps, recentAppIds.length);
    }
  }

  void togglePin(String appId) {
    if (pinnedAppIds.contains(appId)) {
      pinnedAppIds.remove(appId);
    } else {
      pinnedAppIds.add(appId);
    }
  }

  bool isPinned(String appId) => pinnedAppIds.contains(appId);
  bool isAppPinned(String appId) => isPinned(appId);
  bool isAppRecent(String appId) => recentAppIds.contains(appId);

  Offset? getIconPosition(String id) {
    final pos = desktopIconPositions[id];
    if (pos != null && pos.length >= 2) {
      return Offset(pos[0], pos[1]);
    }
    return null;
  }

  void removeDesktopItem(String id) {
    desktopIconPositions.remove(id);
  }

  void setIconPosition(String id, double x, double y) {
    desktopIconPositions[id] = <double>[x, y];
  }

  void toggleFavoriteFolder(String path) {
    if (favoriteFolderPaths.contains(path)) {
      favoriteFolderPaths.remove(path);
    } else {
      favoriteFolderPaths.add(path);
    }
  }

  bool isFavoriteFolder(String path) => favoriteFolderPaths.contains(path);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'firstRunCompleted': firstRunCompleted,
      'appearanceTheme': appearanceTheme,
      'accentColorValue': accentColorValue,
      'performanceProfile': performanceProfile,
      'hardwareSummary': hardwareSummary,
      'desktopIconPositions': desktopIconPositions,
      'pinnedAppIds': pinnedAppIds,
      'recentAppIds': recentAppIds,
      'favoriteFolderPaths': favoriteFolderPaths,
      'filesViewMode': filesViewMode,
      'startupEnabled': startupEnabled,
    };
  }

  static CloudOSPreferences fromJson(Map<String, dynamic> map) {
    final positions = <String, List<double>>{};
    final rawPositions = map['desktopIconPositions'];
    if (rawPositions is Map) {
      for (final entry in rawPositions.entries) {
        if (entry.value is List) {
          final list = (entry.value as List)
              .whereType<num>()
              .map((n) => n.toDouble())
              .toList(growable: false);
          if (list.length >= 2) {
            positions[entry.key.toString()] = list;
          }
        }
      }
    }

    final pinned = <String>[];
    if (map['pinnedAppIds'] is List) {
      for (final item in map['pinnedAppIds'] as List) {
        if (item is String && item.isNotEmpty && !pinned.contains(item)) {
          pinned.add(item);
        }
      }
    }

    final recent = <String>[];
    if (map['recentAppIds'] is List) {
      for (final item in map['recentAppIds'] as List) {
        if (item is String && item.isNotEmpty && !recent.contains(item)) {
          recent.add(item);
        }
      }
    }

    final favorites = <String>[];
    if (map['favoriteFolderPaths'] is List) {
      for (final item in map['favoriteFolderPaths'] as List) {
        if (item is String && item.isNotEmpty && !favorites.contains(item)) {
          favorites.add(item);
        }
      }
    }

    return CloudOSPreferences(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      firstRunCompleted: map['firstRunCompleted'] as bool? ?? false,
      appearanceTheme: map['appearanceTheme'] as String? ?? 'auto',
      accentColorValue: (map['accentColorValue'] as num?)?.toInt() ?? 0xFF0078D4,
      performanceProfile: map['performanceProfile'] as String? ?? 'auto',
      hardwareSummary: map['hardwareSummary'] as String? ?? '',
      desktopIconPositions: positions,
      pinnedAppIds: pinned.isEmpty ? null : pinned,
      recentAppIds: recent,
      favoriteFolderPaths: favorites,
      filesViewMode: map['filesViewMode'] as String? ?? 'details',
      startupEnabled: map['startupEnabled'] as bool? ?? true,
    );
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static CloudOSPreferences importJson(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) throw const FormatException('Formato de preferências inválido');
    return CloudOSPreferences.fromJson(Map<String, dynamic>.from(decoded));
  }

  // --- File Storage with Atomic Write and Backup Recovery ---
  static File _getFile([String? explicitPath]) {
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    final sep = Platform.pathSeparator;
    return File('$base${sep}CloudOS${sep}preferences-v1.json');
  }

  static Future<CloudOSPreferences> load([String? explicitPath]) async {
    final file = _getFile(explicitPath);
    final backup = File('${file.path}.bak');

    for (final candidate in <File>[file, backup]) {
      try {
        if (await candidate.exists()) {
          final content = await candidate.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            return CloudOSPreferences.fromJson(Map<String, dynamic>.from(decoded));
          }
        }
      } on Object {
        // Quarantine or skip corrupt file safely
      }
    }
    return CloudOSPreferences();
  }

  Future<void> save([String? explicitPath]) async {
    final file = _getFile(explicitPath);
    try {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final jsonText = exportJson();
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(jsonText, flush: true);

      // Create backup of current valid file before overwrite
      if (await file.exists()) {
        final backupFile = File('${file.path}.bak');
        await file.copy(backupFile.path);
      }
      await tmpFile.rename(file.path);
    } on Object {
      // Writing preferences must never crash caller
    }
  }

  Future<void> resetToDefaults([String? explicitPath]) async {
    firstRunCompleted = false;
    appearanceTheme = 'auto';
    accentColorValue = 0xFF0078D4;
    performanceProfile = 'auto';
    hardwareSummary = '';
    desktopIconPositions.clear();
    pinnedAppIds.clear();
    pinnedAppIds.addAll(<String>[
      'files',
      'terminal',
      'browser',
      'settings',
      'task_manager',
    ]);
    recentAppIds.clear();
    favoriteFolderPaths.clear();
    filesViewMode = 'details';
    startupEnabled = true;
    await save(explicitPath);
  }
}
