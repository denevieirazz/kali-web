import 'package:cloudos_flutter_shell/features/settings/presentation/settings_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CloudSystemSnapshot snapshotWith({
  required bool wslAvailable,
  required List<String> distros,
  String defaultDistro = '',
  bool? wslEngineAvailable,
  List<CloudWslDistributionSnapshot> wslDistros =
      const <CloudWslDistributionSnapshot>[],
}) {
  return CloudSystemSnapshot(
    deviceName: 'CloudOS-Test',
    networkName: 'Test Network',
    volume: 0.5,
    brightness: 0.5,
    batteryPercent: 100,
    wslAvailable: wslAvailable,
    wslEngineAvailable: wslEngineAvailable ?? wslAvailable,
    distros: distros,
    defaultDistro: defaultDistro,
    wslDistros: wslDistros,
  );
}

Future<void> openWslSettings(
  WidgetTester tester,
  CloudSystemSnapshot snapshot,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: SettingsWindow(snapshot: snapshot),
        ),
      ),
    ),
  );

  await tester.tap(find.text('WSL e Linux'));
  await tester.pumpAndSettle();
}

void main() {
  group('WSL settings honesty', () {
    testWidgets('reports legacy Ubuntu without inventing WSL2 or Kali', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          distros: const <String>['Ubuntu'],
          defaultDistro: 'Ubuntu',
        ),
      );

      expect(find.text('Linux Runtime / WSL'), findsOneWidget);
      expect(
        find.text('Detectado • 1 distro(s) registrada(s)'),
        findsOneWidget,
      );
      expect(find.text('Ubuntu'), findsWidgets);
      expect(find.text('Padrão'), findsOneWidget);
      expect(find.text('Kali Linux não instalada'), findsOneWidget);
      expect(find.text('Kali não instalada'), findsOneWidget);
      expect(find.text('Registrada • versão não comprovada'), findsOneWidget);

      expect(find.text('Ativo e Operacional'), findsNothing);
      expect(find.text('Registrada • WSL 2'), findsNothing);
    });

    testWidgets('renders WSL2 only when typed broker evidence proves it', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          distros: const <String>['Ubuntu'],
          defaultDistro: 'Ubuntu',
          wslDistros: const <CloudWslDistributionSnapshot>[
            CloudWslDistributionSnapshot(
              name: 'Ubuntu',
              version: 2,
              isDefault: true,
            ),
          ],
        ),
      );

      expect(find.text('Registrada • WSL 2'), findsOneWidget);
      expect(find.text('Registrada • versão não comprovada'), findsNothing);
    });

    testWidgets('marks a detected Kali distro as security runtime', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          distros: const <String>['Ubuntu', 'kali-linux'],
          defaultDistro: 'Ubuntu',
          wslDistros: const <CloudWslDistributionSnapshot>[
            CloudWslDistributionSnapshot(
              name: 'Ubuntu',
              version: 2,
              isDefault: true,
            ),
            CloudWslDistributionSnapshot(name: 'kali-linux', version: 2),
          ],
        ),
      );

      expect(find.text('kali-linux'), findsWidgets);
      expect(find.text('Segurança'), findsOneWidget);
      expect(find.text('Kali Linux não instalada'), findsNothing);
      expect(find.text('Kali não instalada'), findsNothing);
    });

    testWidgets('distinguishes WSL engine from missing distro inventory', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: false,
          wslEngineAvailable: true,
          distros: const <String>[],
        ),
      );

      expect(find.text('Detectado • nenhuma distro registrada'), findsOneWidget);
      expect(find.text('Nenhuma distro detectada'), findsOneWidget);
      expect(find.text('WSL indisponível'), findsNothing);
    });

    testWidgets('does not claim a Linux session when WSL engine is unavailable', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: false,
          wslEngineAvailable: false,
          distros: const <String>[],
        ),
      );

      expect(find.text('Indisponível'), findsOneWidget);
      expect(find.text('WSL indisponível'), findsOneWidget);
      expect(
        find.textContaining('Sessões Linux permanecem desativadas'),
        findsOneWidget,
      );
    });
  });
}
