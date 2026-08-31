import 'package:cloudos_flutter_shell/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudOS V19 Desktop Presentation Suite', () {
    testWidgets('CloudOS presentation renders core desktop surfaces on 1920x1080', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
      expect(find.text('Windows + Linux (WSL2)'), findsOneWidget);
      expect(find.text('ACESSO RÁPIDO'), findsOneWidget);
      expect(find.text('ARMAZENAMENTO'), findsOneWidget);
      expect(find.text('CloudOS Drive'), findsWidgets);
      expect(find.text('Ubuntu WSL'), findsWidgets);

      // Open Start Panel
      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      expect(find.text('CloudOS Start'), findsOneWidget);
      expect(find.text('Aplicativos Fixados'), findsOneWidget);
      expect(find.text('Visual Studio Code'), findsOneWidget);
      expect(find.text('Ubuntu Terminal'), findsOneWidget);

      // Test Search
      await tester.enterText(find.byType(TextField).first, 'Code');
      await tester.pumpAndSettle();
      expect(find.text('Visual Studio Code'), findsOneWidget);

      // Close Start
      await tester.tap(find.byTooltip('Fechar (Esc)').first);
      await tester.pumpAndSettle();
      expect(find.text('CloudOS Start'), findsNothing);

      // Open Quick Settings
      await tester.tap(find.byTooltip('Configurações Rápidas (Ctrl+Alt+Q)'));
      await tester.pumpAndSettle();
      expect(find.text('Configurações Rápidas'), findsOneWidget);
      expect(find.text('Wi‑Fi 6'), findsOneWidget);
      expect(find.text('Luz Noturna'), findsOneWidget);

      // Open Notifications
      await tester.tap(find.byTooltip('Notificações'));
      await tester.pumpAndSettle();
      expect(find.text('Centro de Notificações'), findsOneWidget);
      expect(find.text('Limpar Tudo'), findsOneWidget);

      // Clear all notifications
      await tester.tap(find.text('Limpar Tudo'));
      await tester.pumpAndSettle();
      expect(find.text('Sem novas notificações'), findsOneWidget);
    });

    testWidgets('CloudOS presentation renders cleanly on notebook viewport (1366x768)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
    });

    testWidgets('CloudOS presentation renders cleanly on 2K / 1440p (2560x1440)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(2560, 1440));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
    });
  });
}
