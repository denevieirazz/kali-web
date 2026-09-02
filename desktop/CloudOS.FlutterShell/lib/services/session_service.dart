import 'dart:convert';
import 'dart:io';

import '../models/window_model.dart';
import 'cloudos_logger.dart';

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const int schemaVersion = 2;

  Directory get _stateDirectory {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return Directory('$localAppData\\CloudOS');
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return Directory('$userProfile\\AppData\\Local\\CloudOS');
    }

    return Directory('${Directory.current.path}\\.cloudos');
  }

  File get _sessionFile => File('${_stateDirectory.path}\\desktop_session.json');

  Map<String, Object?> _jsonSafeParams(Map<String, dynamic> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value == null || value is String || value is num || value is bool) {
        result[entry.key] = value;
      } else if (value is List) {
        final safe = value.where((item) =>
            item == null || item is String || item is num || item is bool).toList();
        if (safe.length == value.length) result[entry.key] = safe;
      } else if (value is Map) {
        final mapped = <String, Object?>{};
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
            mapped[nested.key as String] = nestedValue;
          } else {
            valid = false;
            break;
          }
        }
        if (valid) result[entry.key] = mapped;
      }
    }
    return result;
  }

  Future<void> saveSession({
    required List<CloudWindow> windows,
    required int activeWorkspace,
  }) async {
    try {
      final data = <String, Object?>{
        'schemaVersion': schemaVersion,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'activeWorkspace': activeWorkspace.clamp(1, 4),
        'windows': windows
            .map(
              (w) => <String, Object?>{
                'id': w.id,
                'appId': w.appId,
                'title': w.title,
                'x': w.x,
                'y': w.y,
                'width': w.width,
                'height': w.height,
                'minimized': w.minimized,
                'maximized': w.maximized,
                'focused': w.focused,
                'workspaceIndex': w.workspaceIndex,
                'previousX': w.previousX,
                'previousY': w.previousY,
                'previousWidth': w.previousWidth,
                'previousHeight': w.previousHeight,
                'customParams': _jsonSafeParams(w.customParams),
              },
            )
            .toList(growable: false),
      };

      final dir = _stateDirectory;
      if (!await dir.exists()) await dir.create(recursive: true);

      final target = _sessionFile;
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);

      if (await target.exists()) {
        final backup = File('${target.path}.bak');
        try {
          if (await backup.exists()) await backup.delete();
          await target.rename(backup.path);
          await temp.rename(target.path);
          if (await backup.exists()) await backup.delete();
        } catch (_) {
          if (!await target.exists() && await backup.exists()) {
            await backup.rename(target.path);
          }
          rethrow;
        }
      } else {
        await temp.rename(target.path);
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error('SessionService', 'saveSession', error, stackTrace);
    }
  }

  Future<Map<String, dynamic>?> loadSession() async {
    try {
      final file = _sessionFile;
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;

      final workspace = decoded['activeWorkspace'];
      if (workspace is! int || workspace < 1 || workspace > 4) {
        decoded['activeWorkspace'] = 1;
      }

      final rawWindows = decoded['windows'];
      if (rawWindows is! List) {
        decoded['windows'] = <Map<String, dynamic>>[];
      } else {
        decoded['windows'] = rawWindows
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((item) {
              final appId = item['appId'];
              return appId is String && appId.trim().isNotEmpty;
            })
            .toList(growable: false);
      }

      return decoded;
    } catch (error, stackTrace) {
      CloudOSLogger.error('SessionService', 'loadSession', error, stackTrace);
      return null;
    }
  }
}
