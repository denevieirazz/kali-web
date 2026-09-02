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
class ProjectStore {
  ProjectStore._();

  static Directory get _cloudOsStateDirectory {
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

  static File get storageFile =>
      File('${_cloudOsStateDirectory.path}\\projects.json');

  static Future<List<ProjectRecord>> load() async {
    final file = storageFile;
    try {
      if (!await file.exists()) return <ProjectRecord>[];
      final rawText = await file.readAsString();
      if (rawText.trim().isEmpty) return <ProjectRecord>[];

      final decoded = jsonDecode(rawText);
      if (decoded is! List) return <ProjectRecord>[];

      final records = <ProjectRecord>[];
      final seenIds = <String>{};
      final seenPaths = <String>{};
      for (final item in decoded) {
        final record = ProjectRecord.fromJson(item);
        if (record == null) continue;
        final normalizedPath = record.path.trim().toLowerCase();
        if (!seenIds.add(record.id) || !seenPaths.add(normalizedPath)) continue;
        records.add(record);
      }
      return records;
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectStore', 'load', error, stackTrace);
      return <ProjectRecord>[];
    }
  }

  static Future<void> save(List<ProjectRecord> records) async {
    try {
      final dir = _cloudOsStateDirectory;
      if (!await dir.exists()) await dir.create(recursive: true);

      final target = storageFile;
      final temp = File('${target.path}.tmp');
      final payload = const JsonEncoder.withIndent('  ').convert(
        records.map((record) => record.toJson()).toList(growable: false),
      );
      await temp.writeAsString(payload, flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectStore', 'save', error, stackTrace);
      rethrow;
    }
  }

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
