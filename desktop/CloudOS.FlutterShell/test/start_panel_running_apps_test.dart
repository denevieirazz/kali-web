import 'package:cloudos_flutter_shell/core/cloudos_theme.dart';
import 'package:cloudos_flutter_shell/features/start/domain/start_running_app.dart';
import 'package:cloudos_flutter_shell/features/start/presentation/start_panel.dart';
import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filesApp = CloudApp(
    id: 'files',
    name: 'Arquivos',
    icon: Icons.folder_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
  );

  const runningFiles = StartRunningApp(
    id: 'files',
    title: 'Explorador de Arquivos',
    icon: Icons.folder_rounded,
    appIds: <String>{'files', 'cloudos:files'},
    isActive: true,
  );

  Widget buildPanel({
    required ValueChanged<String> onActivate,
    required ValueChanged<String> onCloseWindow,
  }) {
    return MaterialApp(
      theme: buildCloudOSTheme(),
      home: Scaffold(
        body: StartPanel(
          apps: const <CloudApp>[filesApp],
          runningApps: const <StartRunningApp>[runningFiles],
          onLaunch: (_) {},
          onActivateWindow: onActivate,
          onCloseWindow: onCloseWindow,
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets('shows running count and closes a window from Abertos', (
    tester,
  ) async {
    String? closedWindow;

    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildPanel(onActivate: (_) {}, onCloseWindow: (id) => closedWindow = id),
    );

    expect(
      find.byKey(const ValueKey<String>('start-running-count')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Abertos'));
    await tester.pumpAndSettle();

    expect(find.text('Aplicativos abertos'), findsOneWidget);
    expect(find.text('Explorador de Arquivos'), findsOneWidget);
    expect(find.text('Ativo agora'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('close-running-files')));
    await tester.pump();

    expect(closedWindow, 'files');
  });

  testWidgets('restores or focuses a running window from Abertos', (
    tester,
  ) async {
    String? activatedWindow;

    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildPanel(
        onActivate: (id) => activatedWindow = id,
        onCloseWindow: (_) {},
      ),
    );

    await tester.tap(find.text('Abertos'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('activate-running-files')),
    );

    expect(activatedWindow, 'files');
  });

  testWidgets(
    'marks a pinned app as active and focuses it instead of relaunching',
    (tester) async {
      String? activatedWindow;
      var launchCount = 0;

      await tester.binding.setSurfaceSize(const Size(1000, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildCloudOSTheme(),
          home: Scaffold(
            body: StartPanel(
              apps: const <CloudApp>[filesApp],
              runningApps: const <StartRunningApp>[runningFiles],
              onLaunch: (_) => launchCount++,
              onActivateWindow: (id) => activatedWindow = id,
              onCloseWindow: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('Ativo'), findsOneWidget);
      expect(find.byTooltip('Fechar Arquivos'), findsOneWidget);

      await tester.tap(find.text('Arquivos'));
      await tester.pump();

      expect(activatedWindow, 'files');
      expect(launchCount, 0);
    },
  );
}
