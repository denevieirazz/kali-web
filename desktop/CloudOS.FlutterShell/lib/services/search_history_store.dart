import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/search_models.dart';
import 'cloudos_logger.dart';

/// Small local usage-history store used only for ranking Search V23 results.
///
/// It never stores query text, document contents, terminal input, credentials,
/// URLs, tokens, or file paths. File results are deliberately not persisted by
/// GlobalSearchService. Only a typed result ID/title/category and counters are
/// kept for app/settings/WSL/project ranking.
class SearchHistoryStore {
  SearchHistoryStore({
    Directory? stateDirectory,
    this.maxEntries = 64,
  }) : _overrideDirectory = stateDirectory;

  final Directory? _overrideDirectory;
  final int maxEntries;
  Future<void> _writeTail = Future<void>.value();

  int get _boundedMaxEntries => maxEntries.clamp(8, 256).toInt();

  Directory get _stateDirectory {
    final overrideDirectory = _overrideDirectory;
    if (overrideDirectory != null) return overrideDirectory;
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.trim().isNotEmpty) {
      return Directory('$local\\CloudOS');
    }
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.trim().isNotEmpty) {
      return Directory('$profile\\AppData\\Local\\CloudOS');
    }
    return Directory('${Directory.current.path}\\.cloudos');
  }

  File get _file => File('${_stateDirectory.path}\\search_history_v23.json');

  Future<List<SearchHistoryEntry>> load() async {
    try {
      final primary = await _read(_file);
      if (primary != null) return primary;
      final backup = File('${_file.path}.bak');
      final recovered = await _read(backup);
      if (recovered != null) {
        _unawaitedSafe(_restoreBackup(backup));
        return recovered;
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error('SearchHistoryStore', 'load', error, stackTrace);
    }
    return const <SearchHistoryEntry>[];
  }

  Future<List<SearchHistoryEntry>?> _read(File file) async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return null;
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['schema'] != 23) return null;
    final raw = decoded['entries'];
    if (raw is! List) return const <SearchHistoryEntry>[];

    final result = <SearchHistoryEntry>[];
    final seen = <String>{};
    for (final value in raw) {
      final entry = SearchHistoryEntry.fromJson(value);
      if (entry == null || !seen.add(entry.resultId)) continue;
      result.add(entry);
      if (result.length >= _boundedMaxEntries) break;
    }
    result.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return List<SearchHistoryEntry>.unmodifiable(result);
  }

  Future<void> record(SearchResult result) {
    final task = _writeTail.then((_) => _recordNow(result));
    final guarded = task.catchError((Object error, StackTrace stackTrace) {
      CloudOSLogger.error('SearchHistoryStore', 'record', error, stackTrace);
    });
    _writeTail = guarded;
    return guarded;
  }

  Future<void> _recordNow(SearchResult result) async {
    if (result.id.trim().isEmpty || result.title.trim().isEmpty) return;
    final existing = (await load()).toList(growable: true);
    final now = DateTime.now();
    final index = existing.indexWhere((entry) => entry.resultId == result.id);
    if (index >= 0) {
      existing[index] = existing[index].touch(now);
    } else {
      existing.add(
        SearchHistoryEntry(
          resultId: result.id,
          title: result.title,
          category: result.category,
          lastUsedAt: now,
          useCount: 1,
        ),
      );
    }

    existing.sort((a, b) {
      final time = b.lastUsedAt.compareTo(a.lastUsedAt);
      if (time != 0) return time;
      return b.useCount.compareTo(a.useCount);
    });
    await _write(existing.take(_boundedMaxEntries).toList(growable: false));
  }

  Future<void> remove(String resultId) async {
    final id = resultId.trim();
    if (id.isEmpty) return;
    final task = _writeTail.then((_) async {
      final entries = (await load())
          .where((entry) => entry.resultId != id)
          .toList(growable: false);
      await _write(entries);
    });
    final guarded = task.catchError((Object error, StackTrace stackTrace) {
      CloudOSLogger.error('SearchHistoryStore', 'remove', error, stackTrace);
    });
    _writeTail = guarded;
    await guarded;
  }

  Future<void> clear() async {
    final task = _writeTail.then((_) async {
      for (final path in <String>[
        _file.path,
        '${_file.path}.bak',
        '${_file.path}.tmp',
      ]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    });
    final guarded = task.catchError((Object error, StackTrace stackTrace) {
      CloudOSLogger.error('SearchHistoryStore', 'clear', error, stackTrace);
    });
    _writeTail = guarded;
    await guarded;
  }

  Future<void> flush() => _writeTail;

  Future<void> _write(List<SearchHistoryEntry> entries) async {
    final directory = _stateDirectory;
    if (!await directory.exists()) await directory.create(recursive: true);

    final target = _file;
    final backup = File('${target.path}.bak');
    final temporary = File('${target.path}.tmp');
    final payload = <String, Object?>{
      'schema': 23,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };

    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    if (await target.exists()) {
      try {
        await target.copy(backup.path);
      } catch (error, stackTrace) {
        CloudOSLogger.error('SearchHistoryStore', 'backup', error, stackTrace);
      }
    }

    try {
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      if (!await target.exists() && await backup.exists()) {
        try {
          await backup.copy(target.path);
        } catch (error, stackTrace) {
          CloudOSLogger.error(
            'SearchHistoryStore',
            'commit.restoreBackup',
            error,
            stackTrace,
          );
        }
      }
      rethrow;
    }
  }

  Future<void> _restoreBackup(File backup) async {
    try {
      final directory = _stateDirectory;
      if (!await directory.exists()) await directory.create(recursive: true);
      await backup.copy(_file.path);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SearchHistoryStore',
        'restoreBackup',
        error,
        stackTrace,
      );
    }
  }

  static void _unawaitedSafe(Future<void> future) {
    unawaited(
      future.catchError((Object error, StackTrace stackTrace) {
        CloudOSLogger.error('SearchHistoryStore', 'unawaited', error, stackTrace);
      }),
    );
  }
}
