import 'package:cloudos_flutter_shell/core/cloudos_theme.dart';
import 'package:cloudos_flutter_shell/features/start/domain/start_running_app.dart';
import 'package:cloudos_flutter_shell/features/start/presentation/start_panel.dart';
import 'package:cloudos_flutter_shell/features/start/presentation/widgets/start_filter_bar.dart';
import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cloudApp = CloudApp(
    id: 'cloudos:files',
    name: 'Arquivos CloudOS',
    icon: Icons.folder_rounded,
    platform: CloudAppPlatform.cloudos,
    category: 'Sistema',
    isPinned: true,
  );

  const winApp = CloudApp(
    id: 'windows:notepad',
    name: 'Bloco de Notas',
    icon: Icons.edit_note_rounded,
    platform: CloudAppPlatform.windows,
    category: 'Produtividade',
    isPinned: true,
  );

  const linuxApp = CloudApp(
    id: 'wsl:ubuntu:terminal',
    name: 'Ubuntu Terminal',
    icon: Icons.terminal_rounded,
    platform: CloudAppPlatform.linux,
    distro: 'Ubuntu',
    category: 'Linux / WSL',
    isPinned: false,
  );

  final allApps = <CloudApp>[cloudApp, winApp, linuxApp];

  Widget buildPanel({
    required ValueChanged<CloudApp> onLaunch,
    VoidCallback? onLockSession,
    VoidCallback? onPowerOptions,
  }) {
    return MaterialApp(
      theme: buildCloudOSTheme(),
      home: Scaffold(
        body: StartPanel(
          apps: allApps,
          runningApps: const <StartRunningApp>[],
          onLaunch: onLaunch,
          onActivateWindow: (_) {},
          onCloseWindow: (_) {},
          onClose: () {},
          onLockSession: onLockSession,
          onPowerOptions: onPowerOptions,
        ),
      ),
    );
  }

  testWidgets('Start Menu renders unified catalog apps across CloudOS, Windows and Linux', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('CloudOS Start'), findsOneWidget);
    expect(find.text('Arquivos CloudOS'), findsWidgets);
    expect(find.text('Bloco de Notas'), findsWidgets);
    expect(find.text('Ubuntu Terminal'), findsWidgets);
  });

  testWidgets('Tapping CloudOS app triggers onLaunch callback', (tester) async {
    CloudApp? launched;
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (app) => launched = app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('start-app-cloudos:files')).first);
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.id, 'cloudos:files');
    expect(launched!.platform, CloudAppPlatform.cloudos);
  });

  testWidgets('Tapping Windows app triggers onLaunch callback', (tester) async {
    CloudApp? launched;
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (app) => launched = app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('start-app-windows:notepad')).first);
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.id, 'windows:notepad');
    expect(launched!.platform, CloudAppPlatform.windows);
  });

  testWidgets('Tapping Linux WSL app triggers onLaunch callback', (tester) async {
    CloudApp? launched;
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (app) => launched = app));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('start-app-wsl:ubuntu:terminal')).first);
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.id, 'wsl:ubuntu:terminal');
    expect(launched!.platform, CloudAppPlatform.linux);
  });

  testWidgets('Category filters isolate apps per platform cleanly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (_) {}));
    await tester.pumpAndSettle();

    Finder filterChip(String label) => find.descendant(
          of: find.byType(StartFilterBar),
          matching: find.text(label),
        );

    // Tap Windows filter chip
    await tester.ensureVisible(filterChip('Windows'));
    await tester.tap(filterChip('Windows'));
    await tester.pumpAndSettle();

    expect(find.text('Bloco de Notas'), findsOneWidget);
    expect(find.text('Arquivos CloudOS'), findsNothing);
    expect(find.text('Ubuntu Terminal'), findsNothing);

    // Tap Linux filter chip
    await tester.ensureVisible(filterChip('Linux / WSL'));
    await tester.tap(filterChip('Linux / WSL'));
    await tester.pumpAndSettle();

    expect(find.text('Ubuntu Terminal'), findsOneWidget);
    expect(find.text('Bloco de Notas'), findsNothing);
    expect(find.text('Arquivos CloudOS'), findsNothing);

    // Tap CloudOS filter chip
    await tester.ensureVisible(filterChip('CloudOS'));
    await tester.tap(filterChip('CloudOS'));
    await tester.pumpAndSettle();

    expect(find.text('Arquivos CloudOS'), findsOneWidget);
    expect(find.text('Bloco de Notas'), findsNothing);
    expect(find.text('Ubuntu Terminal'), findsNothing);
  });

  testWidgets('Search query filters apps accurately', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(onLaunch: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ubuntu');
    await tester.pumpAndSettle();

    expect(find.text('Ubuntu Terminal'), findsOneWidget);
    expect(find.text('Bloco de Notas'), findsNothing);
    expect(find.text('Arquivos CloudOS'), findsNothing);
  });

  testWidgets('Footer lock and power buttons fire assigned callbacks', (tester) async {
    bool locked = false;
    bool powerOpened = false;

    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPanel(
      onLaunch: (_) {},
      onLockSession: () => locked = true,
      onPowerOptions: () => powerOpened = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('start-footer-lock')));
    await tester.pump();
    expect(locked, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('start-footer-power')));
    await tester.pump();
    expect(powerOpened, isTrue);
  });
}
