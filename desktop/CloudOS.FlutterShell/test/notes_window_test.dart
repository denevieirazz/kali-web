import 'package:cloudos_flutter_shell/features/notes/data/notes_store.dart';
import 'package:cloudos_flutter_shell/features/notes/presentation/notes_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryNotesStore implements NotesStore {
  NotesSnapshot? snapshot;

  @override
  Future<NotesSnapshot?> load() async => snapshot?.copy();

  @override
  Future<void> save(NotesSnapshot value) async {
    snapshot = value.copy();
  }
}

Widget _buildNotes(_MemoryNotesStore store) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: NotesWindow(store: store),
      ),
    ),
  );
}

void main() {
  group('NotesWindow Widget Tests', () {
    testWidgets('renders initial notes and sidebar', (tester) async {
      final store = _MemoryNotesStore();
      await tester.pumpWidget(_buildNotes(store));
      await tester.pumpAndSettle();

      expect(find.text('Bem-vindo ao CloudOS Notes'), findsWidgets);
      expect(find.text('Comandos WSL & Kali'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('can create a new note', (tester) async {
      final store = _MemoryNotesStore();
      await tester.pumpWidget(_buildNotes(store));
      await tester.pumpAndSettle();

      final addNoteButton = find.byTooltip('Nova Nota');
      expect(addNoteButton, findsOneWidget);
      await tester.tap(addNoteButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Nova Nota'), findsWidgets);
    });

    testWidgets('can switch between notes', (tester) async {
      final store = _MemoryNotesStore();
      await tester.pumpWidget(_buildNotes(store));
      await tester.pumpAndSettle();

      final secondNoteFinder = find.text('Comandos WSL & Kali');
      await tester.tap(secondNoteFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('nmap -sV'), findsOneWidget);
    });

    testWidgets('persists edits and reloads them through the store', (tester) async {
      final store = _MemoryNotesStore();
      await tester.pumpWidget(_buildNotes(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Nova Nota'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'Título persistente');
      await tester.enterText(fields.last, 'Conteúdo persistente');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(store.snapshot, isNotNull);
      expect(store.snapshot!.notes.first.title, 'Título persistente');
      expect(store.snapshot!.notes.first.content, 'Conteúdo persistente');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_buildNotes(store));
      await tester.pumpAndSettle();

      expect(find.text('Título persistente'), findsWidgets);
      expect(find.textContaining('Conteúdo persistente'), findsWidgets);
    });
  });
}
