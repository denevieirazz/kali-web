import 'package:cloudos_flutter_shell/core/cloudos_theme.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/shell/cloudos_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop renders default items and allows dragging icons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCloudOSTheme(),
        home: const CloudOSShell(bridge: CloudOSBridge()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey<String>('desktop-icon-files')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('desktop-icon-apps')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('desktop-icon-ubuntu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('desktop-icon-drive')), findsOneWidget);

    // Initial position of files icon
    final initialRect = tester.getRect(find.byKey(const ValueKey<String>('desktop-icon-files')));
    expect(initialRect.left, 20.0);
    expect(initialRect.top, 20.0);

    // Drag the files icon across the desktop
    await tester.drag(
      find.byKey(const ValueKey<String>('desktop-icon-files')),
      const Offset(150, 100),
    );
    await tester.pumpAndSettle();

    final movedRect = tester.getRect(find.byKey(const ValueKey<String>('desktop-icon-files')));
    expect(movedRect.left, greaterThan(initialRect.left));
    expect(movedRect.top, greaterThan(initialRect.top));
  });

  testWidgets('desktop right click menu creates a new folder and allows renaming and organizing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCloudOSTheme(),
        home: const CloudOSShell(bridge: CloudOSBridge()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Right-click on empty desktop area
    await tester.tapAt(const Offset(500, 300), buttons: 2); // secondary button
    await tester.pumpAndSettle();

    expect(find.text('Nova Pasta'), findsOneWidget);
    expect(find.text('Novo Arquivo de Texto'), findsOneWidget);
    expect(find.text('Organizar Ícones'), findsOneWidget);
    expect(find.text('Abrir Terminal'), findsOneWidget);

    // Tap Nova Pasta to open naming dialog
    await tester.tap(find.text('Nova Pasta'));
    await tester.pumpAndSettle();

    expect(find.text('Criar Nova Pasta'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('new-folder-name-input')), findsOneWidget);

    // Confirm folder creation
    await tester.tap(find.byKey(const ValueKey<String>('new-folder-submit-btn')));
    await tester.pumpAndSettle();

    // New folder icon appears on the desktop
    expect(find.text('Nova Pasta'), findsOneWidget);

    // Organize icons aligns everything
    await tester.tapAt(const Offset(500, 300), buttons: 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organizar Ícones'));
    await tester.pumpAndSettle();

    // Files icon is back to x=20
    final organizedRect = tester.getRect(find.byKey(const ValueKey<String>('desktop-icon-files')));
    expect(organizedRect.left, 20.0);
  });

  testWidgets('taskbar running app pill has title, active underline, and close button that closes the window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCloudOSTheme(),
        home: const CloudOSShell(bridge: CloudOSBridge()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Taskbar has the running pill for Arquivos with close button
    expect(find.byTooltip('Fechar Arquivos'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('taskbar-close-Arquivos')), findsOneWidget);

    // Clicking the direct close button closes Arquivos
    await tester.tap(find.byTooltip('Fechar Arquivos'));
    await tester.pumpAndSettle();

    // After closing, the running close button is gone
    expect(find.byTooltip('Fechar Arquivos'), findsNothing);
    expect(find.byKey(const ValueKey<String>('taskbar-close-Arquivos')), findsNothing);
  });
}
