import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/features/notes/presentation/notes_window.dart';

void main() {
  group('NotesWindow Widget Tests', () {
    testWidgets('renders initial notes and sidebar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NotesWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bem-vindo ao CloudOS Notes'), findsWidgets);
      expect(find.text('Comandos WSL & Kali'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Title and content
    });

    testWidgets('can create a new note', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NotesWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addNoteButton = find.byTooltip('Nova Nota');
      expect(addNoteButton, findsOneWidget);
      await tester.tap(addNoteButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Nova Nota'), findsWidgets);
    });

    testWidgets('can switch between notes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NotesWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the second note in sidebar
      final secondNoteFinder = find.text('Comandos WSL & Kali');
      await tester.tap(secondNoteFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('nmap -sV'), findsOneWidget);
    });
  });
}
