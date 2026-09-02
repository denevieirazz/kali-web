import '../models/window_model.dart';

class SessionWindowRecord {
  const SessionWindowRecord({
    required this.id,
    required this.appId,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.minimized,
    required this.maximized,
    required this.focused,
    required this.workspaceIndex,
    required this.previousX,
    required this.previousY,
    required this.previousWidth,
    required this.previousHeight,
    required this.customParams,
  });

  final String id;
  final String appId;
  final String title;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool minimized;
  final bool maximized;
  final bool focused;
  final int workspaceIndex;
  final double previousX;
  final double previousY;
  final double previousWidth;
  final double previousHeight;
  final Map<String, Object?> customParams;

  factory SessionWindowRecord.fromWindow(
    CloudWindow window,
    Map<String, Object?> safeParams,
  ) {
    return SessionWindowRecord(
      id: window.id,
      appId: window.appId,
      title: window.title,
      x: window.x,
      y: window.y,
      width: window.width,
      height: window.height,
      minimized: window.minimized,
      maximized: window.maximized,
      focused: window.focused,
      workspaceIndex: window.workspaceIndex,
      previousX: window.previousX,
      previousY: window.previousY,
      previousWidth: window.previousWidth,
      previousHeight: window.previousHeight,
      customParams: safeParams,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'appId': appId,
        'title': title,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'minimized': minimized,
        'maximized': maximized,
        'focused': focused,
        'workspaceIndex': workspaceIndex,
        'previousX': previousX,
        'previousY': previousY,
        'previousWidth': previousWidth,
        'previousHeight': previousHeight,
        'customParams': customParams,
      };

  static SessionWindowRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final appId = raw['appId'];
    if (appId is! String || appId.trim().isEmpty) return null;
    final idValue = raw['id'];
    final id = idValue is String && idValue.trim().isNotEmpty
        ? idValue.trim()
        : 'restored-${appId.hashCode.abs()}';
    final rawParams = raw['customParams'];
    final params = <String, Object?>{};
    if (rawParams is Map) {
      for (final entry in rawParams.entries) {
        if (entry.key is! String) continue;
        final value = entry.value;
        if (value == null || value is String || value is num || value is bool) {
          params[entry.key as String] = value;
        } else if (value is List) {
          final safe = value
              .where((item) =>
                  item == null ||
                  item is String ||
                  item is num ||
                  item is bool)
              .toList(growable: false);
          if (safe.length == value.length) params[entry.key as String] = safe;
        } else if (value is Map) {
          final nested = <String, Object?>{};
          var valid = true;
          for (final nestedEntry in value.entries) {
            if (nestedEntry.key is! String) {
              valid = false;
              break;
            }
            final nestedValue = nestedEntry.value;
            if (nestedValue == null ||
                nestedValue is String ||
                nestedValue is num ||
                nestedValue is bool) {
              nested[nestedEntry.key as String] = nestedValue;
            } else {
              valid = false;
              break;
            }
          }
          if (valid) params[entry.key as String] = nested;
        }
      }
    }

    double number(String key, double fallback) {
      final value = raw[key];
      if (value is! num) return fallback;
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : fallback;
    }

    bool boolean(String key, bool fallback) {
      final value = raw[key];
      return value is bool ? value : fallback;
    }

    int workspace() {
      final value = raw['workspaceIndex'];
      if (value is num) return value.toInt().clamp(1, 4).toInt();
      return 1;
    }

    return SessionWindowRecord(
      id: id,
      appId: appId.trim(),
      title: raw['title'] is String && (raw['title'] as String).trim().isNotEmpty
          ? (raw['title'] as String).trim()
          : appId.trim(),
      x: number('x', 100),
      y: number('y', 60),
      width: number('width', 800),
      height: number('height', 560),
      minimized: boolean('minimized', false),
      maximized: boolean('maximized', false),
      focused: boolean('focused', false),
      workspaceIndex: workspace(),
      previousX: number('previousX', 100),
      previousY: number('previousY', 60),
      previousWidth: number('previousWidth', 800),
      previousHeight: number('previousHeight', 560),
      customParams: Map<String, Object?>.unmodifiable(params),
    );
  }
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.schemaVersion,
    required this.savedAt,
    required this.activeWorkspace,
    required this.windows,
    required this.mruWindowIds,
    required this.sequence,
  });

  final int schemaVersion;
  final DateTime savedAt;
  final int activeWorkspace;
  final List<SessionWindowRecord> windows;
  final List<String> mruWindowIds;
  final int sequence;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'timestamp': savedAt.toUtc().toIso8601String(),
        'activeWorkspace': activeWorkspace.clamp(1, 4).toInt(),
        'sequence': sequence,
        'mruWindowIds': mruWindowIds,
        'windows': windows.map((window) => window.toJson()).toList(growable: false),
      };

  Map<String, dynamic> toLegacyMap() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'timestamp': savedAt.toUtc().toIso8601String(),
        'activeWorkspace': activeWorkspace.clamp(1, 4).toInt(),
        'sequence': sequence,
        'mruWindowIds': List<String>.from(mruWindowIds),
        'windows': windows
            .map((window) => Map<String, dynamic>.from(window.toJson()))
            .toList(growable: false),
      };

  static SessionSnapshot? fromJson(
    Object? raw, {
    required int supportedSchema,
  }) {
    if (raw is! Map) return null;
    final schemaRaw = raw['schemaVersion'];
    final schema = schemaRaw is num ? schemaRaw.toInt() : 1;
    if (schema > supportedSchema || schema < 1) return null;

    final timestampRaw = raw['timestamp'];
    final timestamp = timestampRaw is String
        ? DateTime.tryParse(timestampRaw)?.toLocal()
        : null;
    final workspaceRaw = raw['activeWorkspace'];
    final activeWorkspace = workspaceRaw is num
        ? workspaceRaw.toInt().clamp(1, 4).toInt()
        : 1;
    final sequenceRaw = raw['sequence'];
    final sequence = sequenceRaw is num
        ? sequenceRaw.toInt().clamp(0, 1 << 62).toInt()
        : 0;

    final windows = <SessionWindowRecord>[];
    final seenIds = <String>{};
    final rawWindows = raw['windows'];
    if (rawWindows is List) {
      for (final value in rawWindows) {
        final record = SessionWindowRecord.fromJson(value);
        if (record == null || !seenIds.add(record.id)) continue;
        windows.add(record);
        if (windows.length >= 256) break;
      }
    }

    final mru = <String>[];
    final rawMru = raw['mruWindowIds'];
    if (rawMru is List) {
      final validIds = windows.map((window) => window.id).toSet();
      final seenMru = <String>{};
      for (final value in rawMru) {
        if (value is! String ||
            !validIds.contains(value) ||
            !seenMru.add(value)) {
          continue;
        }
        mru.add(value);
      }
    }
    for (final window in windows.reversed) {
      if (!mru.contains(window.id)) mru.add(window.id);
    }

    return SessionSnapshot(
      schemaVersion: schema,
      savedAt: timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
      activeWorkspace: activeWorkspace,
      windows: List<SessionWindowRecord>.unmodifiable(windows),
      mruWindowIds: List<String>.unmodifiable(mru),
      sequence: sequence,
    );
  }
}

Map<String, Object?> sanitizeSessionParams(Map<String, dynamic> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    final value = entry.value;
    if (value == null || value is String || value is num || value is bool) {
      result[entry.key] = value;
      continue;
    }
    if (value is List) {
      final safe = value
          .where((item) =>
              item == null ||
              item is String ||
              item is num ||
              item is bool)
          .toList(growable: false);
      if (safe.length == value.length) result[entry.key] = safe;
      continue;
    }
    if (value is Map) {
      final safe = <String, Object?>{};
      var valid = true;
      for (final nested in value.entries) {
        if (nested.key is! String) {
          valid = false;
          break;
        }
        final nestedValue = nested.value;
        if (nestedValue == null ||
            nestedValue is String ||
            nestedValue is num ||
            nestedValue is bool) {
          safe[nested.key as String] = nestedValue;
        } else {
          valid = false;
          break;
        }
      }
      if (valid) result[entry.key] = safe;
    }
  }
  return result;
}
