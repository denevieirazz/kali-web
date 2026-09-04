import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/features/calculator/presentation/calculator_window.dart';

void main() {
  group('CalculatorWindow Widget Tests', () {
    testWidgets('renders calculator display and keypads', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: CalculatorWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsWidgets);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
    });

    testWidgets('performs addition calculation (7 + 5 = 12)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: CalculatorWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('7'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsWidgets);
      expect(find.textContaining('7+5 = 12'), findsOneWidget);
    });

    testWidgets('clear button resets calculation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 500,
              child: CalculatorWindow(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsWidgets);
    });
  });
}
