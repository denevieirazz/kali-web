import 'package:cloudos_flutter_shell/main.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cloudos/native/v19');
  final log = <MethodCall>[];

  Future<Object?> handler(MethodCall call) async {
    log.add(call);
    switch (call.method) {
      case 'getApps':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cloudos:files',
            'name': 'Arquivos',
            'platform': 'cloudos',
            'subtitle': 'Arquivos locais',
            'category': 'Sistema',
            'source': 'CloudOS',
            'canLaunch': true,
            'pinned': true,
            'recent': true,
          },
          <String, Object?>{
            'id': 'cloudos:browser',
            'name': 'Navegador Web',
            'platform': 'cloudos',
            'subtitle': 'Navegador do sistema',
            'category': 'Produtividade',
            'source': 'CloudOS',
            'canLaunch': true,
            'pinned': true,
            'recent': true,
          },
          <String, Object?>{
            'id': 'windows:vscode',
            'name': 'Visual Studio Code',
            'platform': 'windows',
            'subtitle': 'Code Editor & IDE',
            'category': 'Produtividade',
            'source': 'Windows',
            'canLaunch': true,
            'pinned': true,
            'recent': true,
          },
          <String, Object?>{
            'id': 'wsl:ubuntu-terminal',
            'name': 'kali-linux Terminal',
            'platform': 'linux',
            'subtitle': 'Linux Shell (kali-linux)',
            'distro': 'kali-linux',
            'category': 'Linux / WSL',
            'source': 'kali-linux (WSL)',
            'canLaunch': true,
            'pinned': true,
            'recent': true,
          },
        ];
      case 'getSystemSnapshot':
        return <String, Object?>{
          'deviceName': 'TEST-DEVICE-V21',
          'userName': 'tester',
          'sessionId': 7,
          'batteryAvailable': true,
          'batteryPercent': 88,
          'networkAvailable': true,
          'networkName': 'Ethernet • Test Adapter',
          'volumeAvailable': true,
          'volume': 0.80,
          'brightnessAvailable': true,
          'brightness': 0.90,
          'wslAvailable': true,
          'distros': <String>['kali-linux'],
          'currentWorkspace': 2,
        };
      case 'launchApp':
        return true;
      case 'setVolume':
        return true;
      case 'setBrightness':
        return true;
      case 'getBridgeInfo':
        return <String, Object?>{
          'schema': 21,
          'version': 'v21',
          'bridge_type': 'CloudOSFlutterBridgeV20',
          'brokerConnected': true,
          'brokerState': 'connected',
          'channel': 'cloudos/native/v19',
          'arbitrary_command_api': false,
        };
      default:
        return null;
    }
  }

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('CloudOS V21 System Broker Bridge Contracts', () {
    test('loadApps parses broker app identities and platforms', () async {
      const bridge = CloudOSBridge(channel: channel);
      final apps = await bridge.loadApps();

      expect(apps.length, 4);
      expect(apps.first.id, 'cloudos:files');
      expect(apps.first.platform, CloudAppPlatform.cloudos);
      expect(apps[2].platform, CloudAppPlatform.windows);
      expect(apps[3].platform, CloudAppPlatform.linux);
      expect(apps[3].distro, 'kali-linux');
    });

    test('loadSystemSnapshot parses real capability availability', () async {
      const bridge = CloudOSBridge(channel: channel);
      final snapshot = await bridge.loadSystemSnapshot();

      expect(snapshot.deviceName, 'TEST-DEVICE-V21');
      expect(snapshot.userName, 'tester');
      expect(snapshot.sessionId, 7);
      expect(snapshot.networkAvailable, true);
      expect(snapshot.networkName, 'Ethernet • Test Adapter');
      expect(snapshot.volumeAvailable, true);
      expect(snapshot.volume, 0.80);
      expect(snapshot.brightnessAvailable, true);
      expect(snapshot.brightness, 0.90);
      expect(snapshot.batteryAvailable, true);
      expect(snapshot.batteryPercent, 88);
      expect(snapshot.wslAvailable, true);
      expect(snapshot.distros, <String>['kali-linux']);
      expect(snapshot.currentWorkspace, 2);
    });

    test('launchApp forwards typed app id and returns native result', () async {
      const bridge = CloudOSBridge(channel: channel);
      final success = await bridge.launchApp('windows:vscode');

      expect(success, true);
      expect(log.last.method, 'launchApp');
      expect(log.last.arguments, <String, Object?>{'id': 'windows:vscode'});
    });

    test('setVolume and setBrightness forward values', () async {
      const bridge = CloudOSBridge(channel: channel);
      expect(await bridge.setVolume(0.5), true);
      expect(log.last.method, 'setVolume');
      expect(log.last.arguments, <String, Object?>{'value': 0.5});

      expect(await bridge.setBrightness(0.75), true);
      expect(log.last.method, 'setBrightness');
      expect(log.last.arguments, <String, Object?>{'value': 0.75});
    });

    test('getBridgeInfo returns V21 metadata', () async {
      const bridge = CloudOSBridge(channel: channel);
      final info = await bridge.getBridgeInfo();

      expect(info['schema'], 21);
      expect(info['version'], 'v21');
      expect(info['bridge_type'], 'CloudOSFlutterBridgeV20');
      expect(info['brokerConnected'], true);
      expect(info['brokerState'], 'connected');
      expect(info['arbitrary_command_api'], false);
    });

    test('missing native plugin falls back conservatively', () async {
      const missingChannel = MethodChannel('cloudos/missing-v21');
      const bridge = CloudOSBridge(channel: missingChannel);

      final apps = await bridge.loadApps();
      expect(apps, CloudOSBridge.previewApps);

      final snapshot = await bridge.loadSystemSnapshot();
      expect(snapshot.wslAvailable, false);
      expect(snapshot.networkAvailable, false);
      expect(snapshot.volumeAvailable, false);
      expect(snapshot.brightnessAvailable, false);

      expect(await bridge.launchApp('anything'), false);
      expect(await bridge.setVolume(0.5), false);
      expect(await bridge.setBrightness(0.5), false);
    });
  });

  group('CloudOS V21 Active Desktop Presentation', () {
    testWidgets('renders V21 shell and dynamic Start on desktop viewport', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('TEST-DEVICE-V21'), findsOneWidget);
      expect(find.text('Arquivos V21'), findsOneWidget);
      expect(find.text('kali-linux'), findsWidgets);

      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V21'), findsOneWidget);
      expect(find.text('Aplicativos reais via System Broker'), findsOneWidget);
      expect(find.text('tester'), findsOneWidget);
      expect(find.text('Visual Studio Code'), findsOneWidget);
      expect(find.text('kali-linux Terminal'), findsOneWidget);

      final startSearch = find.byType(TextField).first;
      await tester.enterText(startSearch, 'Code');
      await tester.pumpAndSettle();
      expect(find.text('Visual Studio Code'), findsOneWidget);

      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurações Rápidas (Ctrl+Alt+Q)'));
      await tester.pumpAndSettle();
      expect(find.text('Configurações Rápidas'), findsOneWidget);
      expect(find.text('Rede'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Backend ainda não exposto'), findsWidgets);
    });

    testWidgets('renders without legacy V19 branding on notebook viewport', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('CloudOS V19'), findsNothing);
      expect(find.text('Arquivos V21'), findsOneWidget);
      expect(find.textContaining('Workspace 2'), findsOneWidget);
    });
  });
}
