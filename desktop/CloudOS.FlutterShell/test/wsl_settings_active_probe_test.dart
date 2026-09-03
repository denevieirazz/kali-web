import 'package:cloudos_flutter_shell/features/settings/presentation/settings_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cloudos/test/wsl-settings-active');
  const bridge = CloudOSBridge(channel: channel);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  CloudSystemSnapshot healthyCandidates() {
    return const CloudSystemSnapshot(
      deviceName: 'CloudOS-Test',
      networkName: 'Ethernet',
      volume: 0.5,
      brightness: 0.5,
      batteryPercent: 0,
      batteryAvailable: false,
      wslAvailable: true,
      wslEngineAvailable: true,
      wslPassiveReady: true,
      distros: <String>['Ubuntu', 'kali-linux'],
      defaultDistro: 'Ubuntu',
      preferredSecurityDistro: 'kali-linux',
      wslRegisteredCount: 2,
      wslLaunchCandidateCount: 2,
      wsl2Count: 2,
      wslDistros: <CloudWslDistributionSnapshot>[
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
    );
  }

  Future<void> pumpWslSettings(
    WidgetTester tester,
    CloudSystemSnapshot snapshot,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 1000,
            child: SettingsWindow(snapshot: snapshot, bridge: bridge),
          ),
        ),
      ),
    );
    await tester.tap(find.text('WSL e Linux'));
    await tester.pumpAndSettle();
  }

  testWidgets('healthy Kali probe upgrades only the active security evidence', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'probeWslHealth');
          final arguments = call.arguments! as Map<Object?, Object?>;
          expect(arguments['distro'], 'kali-linux');
          expect(arguments['timeoutMs'], 8000);
          return <String, Object?>{
            'distro': 'kali-linux',
            'attempted': true,
            'healthy': true,
            'timedOut': false,
            'markerSeen': true,
            'exitCode': 0,
            'durationMs': 145,
            'output': 'CLOUDOS_WSL_HEALTH_V22\n',
            'errorCode': '',
            'errorMessage': '',
          };
        });

    await pumpWslSettings(tester, healthyCandidates());

    final kaliButton = find.text('Testar Kali (kali-linux)');
    expect(kaliButton, findsOneWidget);
    await tester.ensureVisible(kaliButton);
    await tester.tap(kaliButton);
    await tester.pumpAndSettle();

    expect(
      find.text('kali-linux • backend de segurança saudável'),
      findsOneWidget,
    );
    expect(find.text('kali-linux • health ativo comprovado'), findsOneWidget);
    expect(find.text('kali-linux • Saudável'), findsOneWidget);
    expect(find.textContaining('Marcador confirmado • exit 0'), findsOneWidget);
  });

  testWidgets('failed active probe never becomes healthy presentation state', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'distro': 'Ubuntu',
            'attempted': true,
            'healthy': false,
            'timedOut': false,
            'markerSeen': false,
            'exitCode': 1,
            'durationMs': 50,
            'output': '',
            'errorCode': 'wsl_probe_nonzero_exit',
            'errorMessage': 'The fixed probe returned a non-zero exit code',
          };
        });

    await pumpWslSettings(tester, healthyCandidates());

    final ubuntuButton = find.text('Testar Ubuntu');
    await tester.ensureVisible(ubuntuButton);
    await tester.tap(ubuntuButton);
    await tester.pumpAndSettle();

    expect(find.text('Ubuntu • probe ativo falhou'), findsOneWidget);
    expect(find.text('Ubuntu • Falhou'), findsOneWidget);
    expect(find.textContaining('health ativo comprovado'), findsNothing);
  });

  testWidgets('missing registered storage disables active probe', (tester) async {
    final broken = const CloudSystemSnapshot(
      deviceName: 'CloudOS-Test',
      networkName: 'Ethernet',
      volume: 0,
      brightness: 0,
      batteryPercent: 0,
      wslAvailable: true,
      wslEngineAvailable: true,
      wslPassiveReady: false,
      distros: <String>['Ubuntu'],
      defaultDistro: 'Ubuntu',
      wslRegisteredCount: 1,
      wslLaunchCandidateCount: 0,
      wsl2Count: 1,
      wslDistros: <CloudWslDistributionSnapshot>[
        CloudWslDistributionSnapshot(
          name: 'Ubuntu',
          version: 2,
          isDefault: true,
          basePathPresent: false,
          securityCandidate: false,
        ),
      ],
    );

    await pumpWslSettings(tester, broken);

    final buttonText = find.text('Testar Ubuntu');
    expect(buttonText, findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: buttonText, matching: find.byType(OutlinedButton)),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('armazenamento registrado AUSENTE'), findsOneWidget);
  });
}
