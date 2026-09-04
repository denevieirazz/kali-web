import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/features/spotlight/domain/spotlight_item.dart';
import 'package:cloudos_flutter_shell/features/spotlight/presentation/spotlight_palette.dart';

void main() {
  group('SpotlightPalette Widget Tests', () {
    testWidgets('renders search bar and list of items', (tester) async {
      final items = <SpotlightItem>[
        SpotlightItem(
          id: 'terminal',
          title: 'Terminal CloudOS',
          subtitle: 'Linha de comando WSL/PowerShell',
          icon: Icons.terminal_rounded,
          kind: SpotlightItemKind.app,
          onSelect: () {},
        ),
        SpotlightItem(
          id: 'calc',
          title: 'Calculadora',
          subtitle: 'Cálculos matemáticos rápidos',
          icon: Icons.calculate_rounded,
          kind: SpotlightItemKind.app,
          onSelect: () {},
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightPalette(
              items: items,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Terminal CloudOS'), findsOneWidget);
      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.text('Central de Comando CloudOS'), findsOneWidget);
    });

    testWidgets('filters items when typing in search bar', (tester) async {
      final items = <SpotlightItem>[
        SpotlightItem(
          id: 'terminal',
          title: 'Terminal CloudOS',
          subtitle: 'Linha de comando WSL/PowerShell',
          icon: Icons.terminal_rounded,
          kind: SpotlightItemKind.app,
          onSelect: () {},
        ),
        SpotlightItem(
          id: 'notes',
          title: 'CloudOS Notes',
          subtitle: 'Bloco de anotações rápido',
          icon: Icons.description_rounded,
          kind: SpotlightItemKind.app,
          onSelect: () {},
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightPalette(
              items: items,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Notes');
      await tester.pumpAndSettle();

      expect(find.text('CloudOS Notes'), findsOneWidget);
      expect(find.text('Terminal CloudOS'), findsNothing);
    });

    testWidgets('evaluates math in real-time when typing expression', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightPalette(
              items: const <SpotlightItem>[],
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '128 * 4');
      await tester.pumpAndSettle();

      expect(find.text('= 512'), findsOneWidget);
      expect(find.text('Cálculo'), findsOneWidget);
    });

    testWidgets('triggers onSelect when tapping item', (tester) async {
      var selected = false;
      final items = <SpotlightItem>[
        SpotlightItem(
          id: 'notes',
          title: 'CloudOS Notes',
          subtitle: 'Bloco de notas',
          icon: Icons.description_rounded,
          kind: SpotlightItemKind.app,
          onSelect: () => selected = true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotlightPalette(
              items: items,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('CloudOS Notes'));
      await tester.pumpAndSettle();

      expect(selected, isTrue);
    });
  });
}
