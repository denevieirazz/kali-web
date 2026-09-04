import 'dart:io';

import 'package:cloudos_flutter_shell/features/notes/data/notes_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileNotesStore', () {
    test('round-trips notes and selected note', () async {
      final directory = await Directory.systemTemp.createTemp('cloudos-notes-store-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final path = '${directory.path}${Platform.pathSeparator}notes.json';
      final store = FileNotesStore(pathOverride: path);
      final snapshot = NotesSnapshot(
        notes: <StoredNote>[
          StoredNote(
            id: 'one',
            title: 'Primeira',
            content: 'Conteúdo 1',
            updatedAt: DateTime.utc(2026, 9, 4, 5),
          ),
          StoredNote(
            id: 'two',
            title: 'Segunda',
            content: 'Conteúdo 2',
            updatedAt: DateTime.utc(2026, 9, 4, 6),
          ),
        ],
        selectedNoteId: 'two',
      );

      await store.save(snapshot);
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.selectedNoteId, 'two');
      expect(loaded.notes, hasLength(2));
      expect(loaded.notes.first.title, 'Primeira');
      expect(loaded.notes.last.content, 'Conteúdo 2');
    });

    test('serializes overlapping saves and keeps the latest snapshot', () async {
      final directory = await Directory.systemTemp.createTemp('cloudos-notes-race-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final path = '${directory.path}${Platform.pathSeparator}notes.json';
      final store = FileNotesStore(pathOverride: path);
      final writes = <Future<void>>[];

      for (var index = 0; index < 20; index++) {
        writes.add(
          store.save(
            NotesSnapshot(
              notes: <StoredNote>[
                StoredNote(
                  id: 'note',
                  title: 'Versão $index',
                  content: 'conteúdo-$index',
                  updatedAt: DateTime.utc(2026, 9, 4, 7, 0, index),
                ),
              ],
              selectedNoteId: 'note',
            ),
          ),
        );
      }

      await Future.wait(writes);
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.notes.single.title, 'Versão 19');
      expect(loaded.notes.single.content, 'conteúdo-19');
      expect(await File('$path.tmp').exists(), isFalse);
    });

    test('falls back to backup when primary storage is malformed', () async {
      final directory = await Directory.systemTemp.createTemp('cloudos-notes-backup-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final path = '${directory.path}${Platform.pathSeparator}notes.json';
      final store = FileNotesStore(pathOverride: path);
      final first = NotesSnapshot(
        notes: <StoredNote>[
          StoredNote(
            id: 'safe',
            title: 'Versão segura',
            content: 'backup',
            updatedAt: DateTime.utc(2026, 9, 4, 5),
          ),
        ],
        selectedNoteId: 'safe',
      );
      final second = NotesSnapshot(
        notes: <StoredNote>[
          StoredNote(
            id: 'new',
            title: 'Versão nova',
            content: 'primary',
            updatedAt: DateTime.utc(2026, 9, 4, 6),
          ),
        ],
        selectedNoteId: 'new',
      );

      await store.save(first);
      await store.save(second);
      await File(path).writeAsString('{malformed', flush: true);

      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.selectedNoteId, 'safe');
      expect(loaded.notes.single.title, 'Versão segura');
    });

    test('returns null instead of throwing for malformed storage', () async {
      final directory = await Directory.systemTemp.createTemp('cloudos-notes-malformed-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final path = '${directory.path}${Platform.pathSeparator}notes.json';
      await File(path).writeAsString('not-json', flush: true);
      await File('$path.bak').writeAsString('also-not-json', flush: true);

      final loaded = await FileNotesStore(pathOverride: path).load();

      expect(loaded, isNull);
    });
  });
}
