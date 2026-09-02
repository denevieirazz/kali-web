import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cloudos_logger.dart';

class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    this.lastOpenedAt,
  });

  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime? lastOpenedAt;

  ProjectRecord copyWith({
    String? name,
    String? path,
    DateTime? lastOpenedAt,
  }) {
    return ProjectRecord(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'path': path,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toUtc().toIso8601String(),
      };

  static ProjectRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final path = raw['path'];
    final createdAtRaw = raw['createdAt'];
    final lastOpenedAtRaw = raw['lastOpenedAt'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        path is! String ||
        path.isEmpty) {
      return null;
    }

    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)?.toLocal()
        : null;
    final lastOpenedAt = lastOpenedAtRaw is String
        ? DateTime.tryParse(lastOpenedAtRaw)?.toLocal()
        : null;
    return ProjectRecord(
      id: id,
      name: name,
      path: path,
      createdAt: createdAt ?? DateTime.now(),
      lastOpenedAt: lastOpenedAt,
    );
  }
}

/// Persistent CloudOS-owned project metadata.
///
/// dart:io is intentionally limited to this private state file. User workspace
/// inspection/mutation belongs to ProjectFilesystemService -> Files V22 Broker.
/// Writes are serialized and transactional: `.tmp` is flushed first, the
/// previous primary becomes `.bak`, and a corrupt/missing primary can recover
/// from that last-known-good backup.
class ProjectStore {
  ProjectStore._({Directory? stateDirectoryOverride})
      : _stateDirectoryOverride = stateDirectoryOverride;

  ProjectStore.forTesting(Directory stateDirectory)
      : _stateDirectoryOverride = stateDirectory;

  static final ProjectStore _instance = ProjectStore._();

  final Directory? _stateDirectoryOverride;
  Future<void> _writeTail = Future<void>.value();

  Directory get _cloudOsStateDirectory {
    final override = _stateDirectoryOverride;
    if (override != null) return override;

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

  File get _storageFile =>
      File('${_cloudOsStateDirectory.path}\\projects.json');
  File get _backupFile => File('${_storageFile.path}.bak');
  File get _temporaryFile => File('${_storageFile.path}.tmp');

  static File get storageFile => _instance._storageFile;

  static Future<List<ProjectRecord>> load() => _instance.loadRecords();

  static Future<void> save(List<ProjectRecord> records) =>
      _instance.saveRecords(records);

  Future<List<ProjectRecord>> loadRecords() async {
    await _writeTail;
    final primary = await _tryRead(_storageFile, source: 'primary');
    if (primary != null) return primary;

    final backup = await _tryRead(_backupFile, source: 'backup');
    if (backup == null) return const <ProjectRecord>[];

    CloudOSLogger.warn(
      'ProjectStore',
      'load.recovery',
      'Recovered CloudOS project metadata from last-known-good backup.',
    );
    try {
      final directory = _cloudOsStateDirectory;
      if (!await directory.exists()) await directory.create(recursive: true);
      await _backupFile.copy(_storageFile.path);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'ProjectStore',
        'load.restorePrimary',
        error,
        stackTrace,
      );
    }
    return backup;
  }

  Future<List<ProjectRecord>?> _tryRead(
    File file, {
    required String source,
  }) async {
    try {
      if (!await file.exists()) return null;
      final rawText = await file.readAsString();
      if (rawText.trim().isEmpty) return null;

      final decoded = jsonDecode(rawText);
      if (decoded is! List) return null;

      final records = <ProjectRecord>[];
      final seenIds = <String>{};
      final seenPaths = <String>{};
      for (final item in decoded) {
        final record = ProjectRecord.fromJson(item);
        if (record == null) continue;
        final normalizedPath = record.path.trim().toLowerCase();
        if (!seenIds.add(record.id) || !seenPaths.add(normalizedPath)) continue;
        records.add(record);
        if (records.length >= 512) break;
      }
      return List<ProjectRecord>.unmodifiable(records);
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectStore', 'read.$source', error, stackTrace);
      return null;
    }
  }

  Future<void> saveRecords(List<ProjectRecord> records) {
    final snapshot = List<ProjectRecord>.unmodifiable(records);
    final task = _writeTail.then((_) => _saveNow(snapshot));

    // Keep the serialization queue alive after a failed caller-visible write.
    _writeTail = task.catchError((Object error, StackTrace stackTrace) {
      CloudOSLogger.error('ProjectStore', 'save.queue', error, stackTrace);
    });
    return task;
  }

  Future<void> _saveNow(List<ProjectRecord> records) async {
    final dir = _cloudOsStateDirectory;
    if (!await dir.exists()) await dir.create(recursive: true);

    final payload = const JsonEncoder.withIndent('  ').convert(
      records.map((record) => record.toJson()).toList(growable: false),
    );
    final target = _storageFile;
    final backup = _backupFile;
    final temporary = _temporaryFile;

    try {
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(payload, flush: true);

      if (await target.exists()) {
        await target.copy(backup.path);
      }

      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectStore', 'save.commit', error, stackTrace);
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      try {
        if (!await target.exists() && await backup.exists()) {
          await backup.copy(target.path);
        }
      } catch (restoreError, restoreStack) {
        CloudOSLogger.error(
          'ProjectStore',
          'save.restoreBackup',
          restoreError,
          restoreStack,
        );
      }
      rethrow;
    }
  }

  Future<void> flush() => _writeTail;

  static String makeId(String path) {
    final normalized = path.trim().toLowerCase();
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'project-${hash.toRadixString(16)}';
  }

  /// Compatibility fallback for call sites that only have persisted metadata.
  /// Real type detection is Broker-backed in ProjectFilesystemService.
  static String detectType(String path) => 'Workspace';

  /// Compatibility fallback. Real modification time is Broker-backed.
  static DateTime? lastModified(String path) => null;
}
