import 'dart:convert';
import 'dart:io';

import '../models/session_models.dart';
import '../models/window_model.dart';
import 'cloudos_logger.dart';

/// Crash-tolerant, serialized desktop session persistence.
///
/// V2 allowed fire-and-forget writes to race. V3 snapshots mutable window
/// state at enqueue time, serializes every disk mutation, keeps a known-good
/// `.bak`, and can recover primary/backup independently.
class SessionService {
  SessionService._({Directory? stateDirectoryOverride})
      : _stateDirectoryOverride = stateDirectoryOverride;

  /// Isolated persistence authority for deterministic tests. Production uses
  /// [instance], which resolves the per-user CloudOS directory normally.
  SessionService.forTesting(Directory stateDirectory)
      : _stateDirectoryOverride = stateDirectory;

  static final SessionService instance = SessionService._();

  static const int schemaVersion = 3;

  final Directory? _stateDirectoryOverride;
  Future<void> _writeTail = Future<void>.value();
  int _sequence = 0;
  String? _lastSerializedPayload;
  Object? _lastWriteError;
  StackTrace? _lastWriteStackTrace;

  Directory get _stateDirectory {
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

  File get _sessionFile => File('${_stateDirectory.path}\\desktop_session.json');
  File get _backupFile => File('${_sessionFile.path}.bak');
  File get _temporaryFile => File('${_sessionFile.path}.tmp');

  bool get hasWriteFailure => _lastWriteError != null;

  Future<void> saveSession({
    required List<CloudWindow> windows,
    required int activeWorkspace,
    List<String> mruWindowIds = const <String>[],
  }) {
    final records = windows
        .map(
          (window) => SessionWindowRecord.fromWindow(
            window,
            sanitizeSessionParams(window.customParams),
          ),
        )
        .toList(growable: false);
    final knownIds = records.map((record) => record.id).toSet();
    final safeMru = <String>[];
    final seen = <String>{};
    for (final id in mruWindowIds) {
      if (knownIds.contains(id) && seen.add(id)) safeMru.add(id);
    }
    for (final record in records.reversed) {
      if (seen.add(record.id)) safeMru.add(record.id);
    }

    final snapshot = SessionSnapshot(
      schemaVersion: schemaVersion,
      savedAt: DateTime.now(),
      activeWorkspace: activeWorkspace.clamp(1, 4).toInt(),
      windows: List<SessionWindowRecord>.unmodifiable(records),
      mruWindowIds: List<String>.unmodifiable(safeMru),
      sequence: ++_sequence,
    );

    final task = _writeTail.then((_) => _saveSnapshot(snapshot));
    final guarded = task.catchError((Object error, StackTrace stackTrace) {
      _lastWriteError = error;
      _lastWriteStackTrace = stackTrace;
      CloudOSLogger.error('SessionService', 'saveSession', error, stackTrace);
    });
    _writeTail = guarded;
    return guarded;
  }

  Future<void> _saveSnapshot(SessionSnapshot snapshot) async {
    final payload = jsonEncode(snapshot.toJson());
    final stableProjection = _stableProjection(snapshot);
    if (_lastSerializedPayload == stableProjection && await _sessionFile.exists()) {
      _clearWriteFailure();
      return;
    }

    final directory = _stateDirectory;
    if (!await directory.exists()) await directory.create(recursive: true);

    final temporary = _temporaryFile;
    try {
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsString(payload, flush: true);

      final target = _sessionFile;
      final backup = _backupFile;
      if (await target.exists()) {
        // Keep a readable primary while the last-known-good backup is copied.
        await target.copy(backup.path);
      }

      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      _lastSerializedPayload = stableProjection;
      _clearWriteFailure();
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SessionService',
        'saveSnapshot',
        error,
        stackTrace,
      );
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      try {
        if (!await _sessionFile.exists() && await _backupFile.exists()) {
          await _backupFile.copy(_sessionFile.path);
        }
      } catch (restoreError, restoreStack) {
        CloudOSLogger.error(
          'SessionService',
          'saveSnapshot.restoreBackup',
          restoreError,
          restoreStack,
        );
      }
      rethrow;
    }
  }

  Future<SessionSnapshot?> loadSnapshot() async {
    await flush();

    SessionSnapshot? primary;
    try {
      primary = await _readSnapshot(_sessionFile);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SessionService',
        'loadSnapshot.primary',
        error,
        stackTrace,
      );
    }
    if (primary != null) {
      _sequence = _max(_sequence, primary.sequence);
      _lastSerializedPayload = _stableProjection(primary);
      return primary;
    }

    SessionSnapshot? backup;
    try {
      backup = await _readSnapshot(_backupFile);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SessionService',
        'loadSnapshot.backup',
        error,
        stackTrace,
      );
    }
    if (backup == null) return null;

    CloudOSLogger.warn(
      'SessionService',
      'loadSnapshot.recovery',
      'Recovered desktop session from last-known-good backup.',
    );
    _sequence = _max(_sequence, backup.sequence);
    _lastSerializedPayload = _stableProjection(backup);
    try {
      final directory = _stateDirectory;
      if (!await directory.exists()) await directory.create(recursive: true);
      await _backupFile.copy(_sessionFile.path);
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SessionService',
        'loadSnapshot.restorePrimary',
        error,
        stackTrace,
      );
    }
    return backup;
  }

  /// Compatibility surface while shell callers migrate to typed snapshots.
  Future<Map<String, dynamic>?> loadSession() async {
    final snapshot = await loadSnapshot();
    return snapshot?.toLegacyMap();
  }

  Future<SessionSnapshot?> _readSnapshot(File file) async {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      final rawSchema = decoded['schemaVersion'];
      final storedSchema = rawSchema is num ? rawSchema.toInt() : 1;
      if (storedSchema > schemaVersion) {
        CloudOSLogger.warn(
          'SessionService',
          'readSnapshot',
          'Ignoring newer desktop session schema $storedSchema; supported=$schemaVersion',
        );
        return null;
      }
    }
    return SessionSnapshot.fromJson(decoded, supportedSchema: schemaVersion);
  }

  /// Drains every queued write. When [requireSuccessfulWrite] is true, a
  /// previously logged persistence failure becomes a hard error so orderly
  /// shutdown can be cancelled instead of pretending the session is durable.
  Future<void> flush({bool requireSuccessfulWrite = false}) async {
    await _writeTail;
    if (!requireSuccessfulWrite || _lastWriteError == null) return;
    final error = _lastWriteError!;
    final stackTrace = _lastWriteStackTrace ?? StackTrace.current;
    Error.throwWithStackTrace(error, stackTrace);
  }

  Future<void> resetForTests() async {
    await flush();
    _sequence = 0;
    _lastSerializedPayload = null;
    _clearWriteFailure();
  }

  void _clearWriteFailure() {
    _lastWriteError = null;
    _lastWriteStackTrace = null;
  }

  String _stableProjection(SessionSnapshot snapshot) {
    return jsonEncode(<String, Object?>{
      'activeWorkspace': snapshot.activeWorkspace,
      'windows': snapshot.windows.map((item) => item.toJson()).toList(),
      'mruWindowIds': snapshot.mruWindowIds,
    });
  }

  int _max(int a, int b) => a > b ? a : b;
}
