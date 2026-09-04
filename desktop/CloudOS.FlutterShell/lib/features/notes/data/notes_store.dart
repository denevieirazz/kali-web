import 'dart:convert';
import 'dart:io';

class StoredNote {
  StoredNote({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  String title;
  String content;
  DateTime updatedAt;

  StoredNote copy() {
    return StoredNote(
      id: id,
      title: title,
      content: content,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static StoredNote? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final id = map['id'];
    final title = map['title'];
    final content = map['content'];
    final updatedAt = map['updated_at'];
    if (id is! String || id.trim().isEmpty) return null;
    if (title is! String || content is! String || updatedAt is! String) {
      return null;
    }
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedUpdatedAt == null) return null;
    return StoredNote(
      id: id,
      title: title,
      content: content,
      updatedAt: parsedUpdatedAt.toLocal(),
    );
  }
}

class NotesSnapshot {
  NotesSnapshot({
    required this.notes,
    required this.selectedNoteId,
  });

  final List<StoredNote> notes;
  final String? selectedNoteId;

  NotesSnapshot copy() {
    return NotesSnapshot(
      notes: notes.map((note) => note.copy()).toList(growable: false),
      selectedNoteId: selectedNoteId,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 1,
      'selected_note_id': selectedNoteId,
      'notes': notes.map((note) => note.toJson()).toList(growable: false),
    };
  }

  static NotesSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    if (map['schema'] != 1) return null;
    final rawNotes = map['notes'];
    if (rawNotes is! List) return null;

    final notes = rawNotes
        .map(StoredNote.fromJson)
        .whereType<StoredNote>()
        .toList(growable: false);
    if (notes.isEmpty) return null;

    final selected = map['selected_note_id'];
    final selectedNoteId = selected is String &&
            notes.any((note) => note.id == selected)
        ? selected
        : notes.first.id;

    return NotesSnapshot(
      notes: notes,
      selectedNoteId: selectedNoteId,
    );
  }
}

abstract class NotesStore {
  Future<NotesSnapshot?> load();

  Future<void> save(NotesSnapshot snapshot);
}

class FileNotesStore implements NotesStore {
  const FileNotesStore({this.pathOverride});

  final String? pathOverride;

  // FileNotesStore is intentionally const so it can remain the default widget
  // dependency. Writes are therefore serialized per resolved path in a shared
  // queue. This prevents overlapping debounce/dispose saves from racing over
  // the same .tmp/.bak files while keeping independent test/user paths isolated.
  static final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};

  File _primaryFile() {
    final explicit = pathOverride?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return File(explicit);
    }

    final base = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    final separator = Platform.pathSeparator;
    return File('$base${separator}CloudOS${separator}notes-v1.json');
  }

  @override
  Future<NotesSnapshot?> load() async {
    final primary = _primaryFile();
    final pending = _pendingWrites[primary.path];
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // Loading still attempts primary/backup recovery after a failed write.
      }
    }

    final backup = File('${primary.path}.bak');
    for (final candidate in <File>[primary, backup]) {
      try {
        if (!await candidate.exists()) continue;
        final raw = await candidate.readAsString();
        final decoded = jsonDecode(raw);
        final snapshot = NotesSnapshot.fromJson(decoded);
        if (snapshot != null) return snapshot;
      } on Object {
        // A malformed or partially-written file must never crash the shell.
      }
    }
    return null;
  }

  @override
  Future<void> save(NotesSnapshot snapshot) {
    final primary = _primaryFile();
    final frozenSnapshot = snapshot.copy();
    final previous = _pendingWrites[primary.path] ?? Future<void>.value();

    late final Future<void> queued;
    queued = previous
        .catchError((Object _) {
          // A previous failed save must not permanently poison the per-path queue.
        })
        .then((_) => _writeSnapshot(primary, frozenSnapshot));
    _pendingWrites[primary.path] = queued;

    return queued.whenComplete(() {
      if (identical(_pendingWrites[primary.path], queued)) {
        _pendingWrites.remove(primary.path);
      }
    });
  }

  Future<void> _writeSnapshot(File primary, NotesSnapshot snapshot) async {
    final backup = File('${primary.path}.bak');
    final temporary = File('${primary.path}.tmp');
    await primary.parent.create(recursive: true);

    if (await temporary.exists()) {
      await temporary.delete();
    }

    final payload = const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    await temporary.writeAsString(payload, flush: true);

    if (await primary.exists()) {
      await primary.copy(backup.path);
    }

    try {
      if (await primary.exists()) {
        await primary.delete();
      }
      await temporary.rename(primary.path);
    } on Object {
      if (!await primary.exists() && await backup.exists()) {
        await backup.copy(primary.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
