import 'package:cloudos_flutter_shell/features/browser/presentation/browser_window.dart';
import 'package:cloudos_flutter_shell/features/settings/presentation/settings_window.dart';
import 'package:cloudos_flutter_shell/features/terminal/presentation/terminal_window.dart';
import 'package:cloudos_flutter_shell/shell/window_manager/cloud_window.dart';
import 'package:cloudos_flutter_shell/shell/window_manager/cloud_window_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudOS Window Manager Suite', () {
    test('CloudWindow model supports copyWith and state transitions', () {
      final win = CloudWindow(
        id: 'test-1',
        title: 'Janela de Teste',
        icon: Icons.apps,
        type: CloudWindowType.terminal,
        position: const Offset(100, 100),
        size: const Size(600, 400),
      );

      expect(win.isMinimized, false);
      expect(win.isMaximized, false);

      final minimized = win.copyWith(isMinimized: true);
      expect(minimized.isMinimized, true);

      final maximized = win.copyWith(
        isMaximized: true,
        preMaximizedPosition: win.position,
        preMaximizedSize: win.size,
      );
      expect(maximized.isMaximized, true);
      expect(maximized.preMaximizedPosition, const Offset(100, 100));
      expect(maximized.preMaximizedSize, const Size(600, 400));
    });

    testWidgets('CloudWindowFrame renders header controls and content', (tester) async {
      bool closed = false;
      bool minimized = false;
      bool toggledMax = false;
      bool focused = false;

      final win = CloudWindow(
        id: 'frame-test',
        title: 'Terminal ConPTY',
        icon: Icons.terminal_rounded,
        type: CloudWindowType.terminal,
        position: const Offset(50, 50),
        size: const Size(500, 350),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudWindowFrame(
              window: win,
              onFocus: () => focused = true,
              onClose: () => closed = true,
              onMinimize: () => minimized = true,
              onToggleMaximize: () => toggledMax = true,
              onMove: (_) {},
              onResize: (_, __, ___, ____, _____) {},
              child: const Text('Terminal Content Active'),
            ),
          ),
        ),
      );

      expect(find.text('Terminal ConPTY'), findsOneWidget);
      expect(find.text('Terminal Content Active'), findsOneWidget);

      await tester.tap(find.byTooltip('Minimizar'));
      await tester.pump();
      expect(minimized, true);

      await tester.tap(find.byTooltip('Maximizar'));
      await tester.pump();
      expect(toggledMax, true);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pump();
      expect(closed, true);

      await tester.tap(find.text('Terminal Content Active'));
      await tester.pump();
      expect(focused, true);
    });

    testWidgets('Internal Terminal window renders tabs and responds to help', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TerminalWindow(),
          ),
        ),
      );

      expect(find.text('PowerShell 7'), findsOneWidget);
      expect(find.text('Prompt de Comando'), findsOneWidget);
      expect(find.text('Ubuntu WSL2'), findsOneWidget);
      expect(find.textContaining('CloudOS Terminal'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'help');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('Comandos suportados'), findsOneWidget);
    });

    testWidgets('Internal Browser window renders navigation bar and quick links', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrowserWindow(),
          ),
        ),
      );

      expect(find.text('CloudOS Web Navigation'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
    });

    testWidgets('Internal Settings window renders category navigation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsWindow(),
          ),
        ),
      );

      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Áudio e Vídeo'), findsOneWidget);
      expect(find.text('Rede e Internet'), findsOneWidget);
      expect(find.text('WSL e Linux'), findsOneWidget);
      expect(find.text('Sobre o CloudOS'), findsOneWidget);
    });
  });
}
