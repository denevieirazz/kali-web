import 'package:cloudos_flutter_shell/features/settings/presentation/settings_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CloudSystemSnapshot snapshotWith({
  required bool wslAvailable,
  required List<String> distros,
  String defaultDistro = '',
}) {
  return CloudSystemSnapshot(
    deviceName: 'CloudOS-Test',
    networkName: 'Test Network',
    volume: 0.5,
    brightness: 0.5,
    batteryPercent: 100,
    wslAvailable: wslAvailable,
    distros: distros,
    defaultDistro: defaultDistro,
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
    testWidgets('reports Ubuntu without pretending Kali is installed', (
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

      // These claims require runtime evidence the current snapshot does not carry.
      expect(find.text('Ativo e Operacional'), findsNothing);
      expect(find.text('WSL 2'), findsNothing);
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
        ),
      );

      expect(find.text('kali-linux'), findsWidgets);
      expect(find.text('Segurança'), findsOneWidget);
      expect(find.text('Kali Linux não instalada'), findsNothing);
      expect(find.text('Kali não instalada'), findsNothing);
    });

    testWidgets('does not claim a Linux session when WSL is unavailable', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(wslAvailable: false, distros: const <String>[]),
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
