import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Central versioned user preferences for CloudOS.
/// Handles desktop layout, pinning, recent apps, first run state,
/// appearance and performance profile with atomic save, schema migration,
/// bounded backup rotation, and corrupt file quarantine.
class CloudOSPreferences {
  CloudOSPreferences({
    this.schemaVersion = currentSchemaVersion,
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

  static const int currentSchemaVersion = 2;
  static const int maxRecentApps = 10;
  static const int maxBackups = 5;

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
    desktopIconPositions[id] = <double>[
      x.clamp(0.0, 10000.0),
      y.clamp(0.0, 10000.0),
    ];
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
    final rawSchema = (map['schemaVersion'] as num?)?.toInt() ?? 1;
    final positions = <String, List<double>>{};
    final rawPositions = map['desktopIconPositions'];
    if (rawPositions is Map) {
      for (final entry in rawPositions.entries) {
        if (entry.value is List) {
          final list = (entry.value as List)
              .whereType<num>()
              .map((n) => n.toDouble().clamp(0.0, 10000.0))
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
          if (pinned.length < 50) {
            pinned.add(item);
          }
        }
      }
    }

    final recent = <String>[];
    if (map['recentAppIds'] is List) {
      for (final item in map['recentAppIds'] as List) {
        if (item is String && item.isNotEmpty && !recent.contains(item)) {
          if (recent.length < 20) {
            recent.add(item);
          }
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

    var theme = map['appearanceTheme'] as String? ?? 'auto';
    if (!const <String>{'dark', 'light', 'auto'}.contains(theme)) {
      theme = 'auto';
    }

    var profile = map['performanceProfile'] as String? ?? 'auto';
    if (!const <String>{'auto', 'economy', 'balanced', 'performance'}.contains(profile)) {
      profile = 'auto';
    }

    var viewMode = map['filesViewMode'] as String? ?? 'details';
    if (!const <String>{'details', 'grid', 'list'}.contains(viewMode)) {
      viewMode = 'details';
    }

    return CloudOSPreferences(
      schemaVersion: rawSchema < currentSchemaVersion ? currentSchemaVersion : rawSchema,
      firstRunCompleted: map['firstRunCompleted'] as bool? ?? false,
      appearanceTheme: theme,
      accentColorValue: (map['accentColorValue'] as num?)?.toInt() ?? 0xFF0078D4,
      performanceProfile: profile,
      hardwareSummary: map['hardwareSummary'] as String? ?? '',
      desktopIconPositions: positions,
      pinnedAppIds: pinned.isEmpty ? null : pinned,
      recentAppIds: recent,
      favoriteFolderPaths: favorites,
      filesViewMode: viewMode,
      startupEnabled: map['startupEnabled'] as bool? ?? true,
    );
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static CloudOSPreferences importJson(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) throw const FormatException('Formato de preferências inválido');
    return CloudOSPreferences.fromJson(Map<String, dynamic>.from(decoded));
  }

  // --- File Storage with Atomic Write, Quarantine, and Backup Rotation ---
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
    final candidates = <File>[file, File('${file.path}.bak')];
    for (var i = 1; i <= maxBackups; i++) {
      candidates.add(File('${file.path}.backup.$i.json'));
    }

    for (final candidate in candidates) {
      try {
        if (await candidate.exists()) {
          final content = await candidate.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            final rawMap = Map<String, dynamic>.from(decoded);
            final oldSchema = (rawMap['schemaVersion'] as num?)?.toInt() ?? 1;
            final prefs = CloudOSPreferences.fromJson(rawMap);
            // If migrated from older schema, auto-save to current schema
            if (oldSchema < currentSchemaVersion && candidate == file) {
              unawaited(prefs.save(explicitPath));
            }
            return prefs;
          }
        }
      } on Object {
        // Quarantine corrupt candidate safely
        try {
          if (await candidate.exists() && candidate == file) {
            final quarantinePath = '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
            await candidate.rename(quarantinePath);
          }
        } on Object {}
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

      // Rotate bounded backups: backup.4 -> backup.5, ..., backup.1 -> backup.2
      if (await file.exists()) {
        for (var i = maxBackups - 1; i >= 1; i--) {
          final src = File('${file.path}.backup.$i.json');
          final dst = File('${file.path}.backup.${i + 1}.json');
          if (await src.exists()) {
            try {
              await src.copy(dst.path);
            } on Object {}
          }
        }
        // Copy current valid file to backup.1 and .bak
        try {
          await file.copy('${file.path}.backup.1.json');
          await file.copy('${file.path}.bak');
        } on Object {}
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
