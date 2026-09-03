import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/shell/cloudos_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('taskbar shows an open window with a direct close button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: CloudOSShell(bridge: CloudOSBridge())),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Fechar Arquivos'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('taskbar-close-Arquivos')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Fechar Arquivos'));
    await tester.pump();

    expect(find.byTooltip('Fechar Arquivos'), findsNothing);
    expect(find.text('Arquivos • Início'), findsNothing);
    expect(find.byTooltip('Arquivos (Ctrl+Alt+E)'), findsOneWidget);
  });
}
