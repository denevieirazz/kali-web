import 'package:cloudos_flutter_shell/features/settings/presentation/settings_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CloudSystemSnapshot snapshotWith({
  required bool wslAvailable,
  required List<String> distros,
  String defaultDistro = '',
  bool? wslEngineAvailable,
  bool? wslPassiveReady,
  String preferredSecurityDistro = '',
  int? wslRegisteredCount,
  int? wslLaunchCandidateCount,
  int? wsl1Count,
  int? wsl2Count,
  List<CloudWslDistributionSnapshot> wslDistros =
      const <CloudWslDistributionSnapshot>[],
  bool volumeAvailable = true,
  bool brightnessAvailable = true,
  bool batteryAvailable = true,
  bool networkAvailable = true,
}) {
  return CloudSystemSnapshot(
    deviceName: 'CloudOS-Test',
    networkAvailable: networkAvailable,
    networkName: networkAvailable ? 'Test Network' : 'Desconectado',
    volumeAvailable: volumeAvailable,
    volume: 0.5,
    brightnessAvailable: brightnessAvailable,
    brightness: 0.5,
    batteryAvailable: batteryAvailable,
    batteryPercent: 100,
    wslAvailable: wslAvailable,
    wslEngineAvailable: wslEngineAvailable ?? wslAvailable,
    distros: distros,
    defaultDistro: defaultDistro,
    wslDistros: wslDistros,
    wslPassiveReady: wslPassiveReady,
    preferredSecurityDistro: preferredSecurityDistro,
    wslRegisteredCount: wslRegisteredCount,
    wslLaunchCandidateCount: wslLaunchCandidateCount,
    wsl1Count: wsl1Count,
    wsl2Count: wsl2Count,
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
          height: 900,
          child: SettingsWindow(snapshot: snapshot),
        ),
      ),
    ),
  );

  await tester.tap(find.text('WSL e Linux'));
  await tester.pumpAndSettle();
}

Future<void> scrollWslTo(
  WidgetTester tester,
  Finder target, {
  double delta = 260,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).last,
  );
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
      expect(
        find.text('Distro registrada • prontidão não comprovada'),
        findsOneWidget,
      );
      expect(find.textContaining('Ativo e Operacional'), findsNothing);
      expect(
        find.textContaining('WSL 2 • armazenamento registrado presente'),
        findsNothing,
      );

      final missingKaliValue = find.text('Kali Linux não instalada');
      await scrollWslTo(tester, missingKaliValue);
      expect(missingKaliValue, findsOneWidget);

      final defaultBadge = find.text('Padrão');
      await scrollWslTo(tester, defaultBadge);
      expect(find.text('Ubuntu'), findsWidgets);
      expect(defaultBadge, findsOneWidget);
      expect(
        find.text('Registrada • versão não comprovada • armazenamento não comprovado'),
        findsOneWidget,
      );

      final missingKaliNotice = find.text('Kali não instalada');
      await scrollWslTo(tester, missingKaliNotice);
      expect(missingKaliNotice, findsOneWidget);
    });

    testWidgets('renders WSL2 only when typed broker evidence proves it', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          wslPassiveReady: true,
          distros: const <String>['Ubuntu'],
          defaultDistro: 'Ubuntu',
          wslRegisteredCount: 1,
          wslLaunchCandidateCount: 1,
          wsl1Count: 0,
          wsl2Count: 1,
          wslDistros: const <CloudWslDistributionSnapshot>[
            CloudWslDistributionSnapshot(
              name: 'Ubuntu',
              version: 2,
              isDefault: true,
              basePathPresent: true,
              securityCandidate: false,
            ),
          ],
        ),
      );

      expect(
        find.text('WSL2 + armazenamento presentes • boot não testado'),
        findsOneWidget,
      );
      expect(find.text('1'), findsWidgets);

      final typedEvidence = find.text(
        'Registrada • WSL 2 • armazenamento registrado presente',
      );
      await scrollWslTo(tester, typedEvidence);
      expect(typedEvidence, findsOneWidget);
    });

    testWidgets('marks only passively proven Kali as security candidate', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          wslPassiveReady: true,
          distros: const <String>['Ubuntu', 'kali-linux'],
          defaultDistro: 'Ubuntu',
          preferredSecurityDistro: 'kali-linux',
          wslRegisteredCount: 2,
          wslLaunchCandidateCount: 2,
          wsl2Count: 2,
          wslDistros: const <CloudWslDistributionSnapshot>[
            CloudWslDistributionSnapshot(
              name: 'Ubuntu',
              version: 2,
              isDefault: true,
              basePathPresent: true,
              securityCandidate: false,
            ),
            CloudWslDistributionSnapshot(
              name: 'kali-linux',
              version: 2,
              basePathPresent: true,
              securityCandidate: true,
            ),
          ],
        ),
      );

      expect(
        find.text('Kali/WSL2 candidata • execução ainda não testada'),
        findsOneWidget,
      );

      final passiveCandidate = find.text('kali-linux • candidata passiva');
      await scrollWslTo(tester, passiveCandidate);
      expect(passiveCandidate, findsOneWidget);

      final securityBadge = find.text('Segurança');
      await scrollWslTo(tester, securityBadge);
      expect(find.text('kali-linux'), findsWidgets);
      expect(securityBadge, findsOneWidget);
      expect(find.text('Kali Linux não instalada'), findsNothing);
      expect(find.text('Kali não instalada'), findsNothing);
    });

    testWidgets('does not call Kali ready when storage is explicitly missing', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: true,
          wslPassiveReady: false,
          distros: const <String>['kali-linux'],
          preferredSecurityDistro: '',
          wslRegisteredCount: 1,
          wslLaunchCandidateCount: 0,
          wsl2Count: 1,
          wslDistros: const <CloudWslDistributionSnapshot>[
            CloudWslDistributionSnapshot(
              name: 'kali-linux',
              version: 2,
              basePathPresent: false,
              securityCandidate: false,
            ),
          ],
        ),
      );

      final notReady = find.textContaining('ainda não pronta');
      await scrollWslTo(tester, notReady);
      expect(notReady, findsOneWidget);

      final missingStorage = find.textContaining('armazenamento registrado AUSENTE');
      await scrollWslTo(tester, missingStorage);
      expect(missingStorage, findsOneWidget);
      expect(find.text('kali-linux • candidata passiva'), findsNothing);

      final notice = find.text('Kali ainda não comprovada como backend');
      await scrollWslTo(tester, notice);
      expect(notice, findsOneWidget);
    });

    testWidgets('distinguishes WSL engine from missing distro inventory', (
      tester,
    ) async {
      await openWslSettings(
        tester,
        snapshotWith(
          wslAvailable: false,
          wslEngineAvailable: true,
          wslPassiveReady: false,
          distros: const <String>[],
          wslRegisteredCount: 0,
          wslLaunchCandidateCount: 0,
        ),
      );

      expect(find.text('Detectado • nenhuma distro registrada'), findsOneWidget);
      expect(find.text('Engine presente • sem distro'), findsOneWidget);
      expect(find.text('WSL indisponível'), findsNothing);

      final noDistro = find.text('Nenhuma distro detectada');
      await scrollWslTo(tester, noDistro);
      expect(noDistro, findsOneWidget);
    });

    testWidgets('does not claim Linux when WSL engine is unavailable', (
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
      expect(find.text('WSL indisponível'), findsWidgets);

      final disabled = find.textContaining('Sessões Linux permanecem desativadas');
      await scrollWslTo(tester, disabled);
      expect(disabled, findsOneWidget);
    });
  });

  group('system setting capability honesty', () {
    testWidgets('does not describe missing battery as AC power proof', (
      tester,
    ) async {
      final snapshot = snapshotWith(
        wslAvailable: false,
        distros: const <String>[],
        batteryAvailable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: SettingsWindow(snapshot: snapshot),
            ),
          ),
        ),
      );

      expect(find.text('Não detectada neste dispositivo'), findsOneWidget);
      expect(find.textContaining('Alimentação CA'), findsNothing);
    });

    testWidgets('disables unavailable brightness and volume controls', (
      tester,
    ) async {
      final snapshot = snapshotWith(
        wslAvailable: false,
        distros: const <String>[],
        volumeAvailable: false,
        brightnessAvailable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: SettingsWindow(snapshot: snapshot),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Áudio e Vídeo'));
      await tester.pumpAndSettle();

      expect(find.text('Volume do Sistema • indisponível'), findsOneWidget);
      expect(find.text('Brilho do Display • indisponível'), findsOneWidget);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      expect(sliders.every((slider) => slider.onChanged == null), isTrue);
      expect(find.text('N/A'), findsNWidgets(2));
    });
  });
}
