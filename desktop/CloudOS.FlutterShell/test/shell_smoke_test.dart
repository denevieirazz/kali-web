import 'package:cloudos_flutter_shell/main.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOS V20 Native MethodChannel Bridge Contracts', () {
    const channel = MethodChannel('cloudos/native/v19');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        switch (call.method) {
          case 'getApps':
            return <Map<String, Object?>>[
              <String, Object?>{
                'id': 'windows:notepad',
                'name': 'Bloco de Notas',
                'platform': 'windows',
                'subtitle': 'Editor de Texto',
                'category': 'Produtividade',
                'source': 'Windows',
                'canLaunch': true,
                'pinned': true,
                'recent': false,
              },
              <String, Object?>{
                'id': 'wsl:gimp',
                'name': 'GIMP',
                'platform': 'linux',
                'subtitle': 'Image Editor',
                'distro': 'Ubuntu',
                'category': 'Produtividade',
                'source': 'Ubuntu (WSL)',
                'canLaunch': true,
                'pinned': true,
                'recent': false,
              },
              <String, Object?>{
                'id': 'cloudos:files',
                'name': 'Arquivos',
                'platform': 'cloudos',
                'subtitle': 'Windows + Linux',
                'category': 'Sistema',
                'source': 'CloudOS',
                'canLaunch': true,
                'pinned': true,
                'recent': false,
              },
            ];
          case 'getSystemSnapshot':
            return <String, Object?>{
              'deviceName': 'TEST-DEVICE-V20',
              'networkName': 'Wi-Fi 6 Real Native',
              'volume': 0.80,
              'brightness': 0.90,
              'batteryPercent': 88,
              'wslAvailable': true,
              'distros': <String>['Ubuntu', 'kali-linux'],
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
              'schema': 20,
              'version': 'v20',
              'bridge_type': 'CloudOSFlutterBridgeV20',
              'channel': 'cloudos/native/v19',
              'arbitrary_command_api': false,
            };
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('loadApps parses Windows, Linux, and CloudOS apps correctly', () async {
      const bridge = CloudOSBridge(channel: channel);
      final apps = await bridge.loadApps();

      expect(apps.length, 3);
      expect(apps[0].id, 'windows:notepad');
      expect(apps[0].platform, CloudAppPlatform.windows);
      expect(apps[1].id, 'wsl:gimp');
      expect(apps[1].platform, CloudAppPlatform.linux);
      expect(apps[1].distro, 'Ubuntu');
      expect(apps[2].id, 'cloudos:files');
      expect(apps[2].platform, CloudAppPlatform.cloudos);
    });

    test('loadSystemSnapshot parses native snapshot fields correctly', () async {
      const bridge = CloudOSBridge(channel: channel);
      final snapshot = await bridge.loadSystemSnapshot();

      expect(snapshot.deviceName, 'TEST-DEVICE-V20');
      expect(snapshot.networkName, 'Wi-Fi 6 Real Native');
      expect(snapshot.volume, 0.80);
      expect(snapshot.brightness, 0.90);
      expect(snapshot.batteryPercent, 88);
      expect(snapshot.wslAvailable, true);
      expect(snapshot.distros, <String>['Ubuntu', 'kali-linux']);
      expect(snapshot.currentWorkspace, 2);
    });

    test('launchApp forwards app id and handles success', () async {
      const bridge = CloudOSBridge(channel: channel);
      final success = await bridge.launchApp('windows:notepad');

      expect(success, true);
      expect(log.last.method, 'launchApp');
      expect(log.last.arguments, <String, Object?>{'id': 'windows:notepad'});
    });

    test('setVolume and setBrightness forward values', () async {
      const bridge = CloudOSBridge(channel: channel);
      await bridge.setVolume(0.5);
      expect(log.last.method, 'setVolume');
      expect(log.last.arguments, <String, Object?>{'value': 0.5});

      await bridge.setBrightness(0.75);
      expect(log.last.method, 'setBrightness');
      expect(log.last.arguments, <String, Object?>{'value': 0.75});
    });

    test('getBridgeInfo returns schema 20 metadata', () async {
      const bridge = CloudOSBridge(channel: channel);
      final info = await bridge.getBridgeInfo();

      expect(info['schema'], 20);
      expect(info['bridge_type'], 'CloudOSFlutterBridgeV20');
      expect(info['arbitrary_command_api'], false);
    });

    test('preview fallback handles missing plugin without throwing', () async {
      const missingChannel = MethodChannel('non_existent_channel');
      const bridge = CloudOSBridge(channel: missingChannel);

      final apps = await bridge.loadApps();
      expect(apps.isNotEmpty, true);
      expect(apps, CloudOSBridge.previewApps);

      final snapshot = await bridge.loadSystemSnapshot();
      expect(snapshot.deviceName, CloudOSBridge.previewSnapshot.deviceName);

      final launchResult = await bridge.launchApp('anything');
      expect(launchResult, true);
    });
  });

  group('CloudOS V20 Desktop Presentation Suite', () {
    testWidgets('CloudOS presentation renders core desktop surfaces on 1920x1080', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
      expect(find.text('Windows + Linux (WSL2)'), findsOneWidget);
      expect(find.text('ACESSO RÁPIDO'), findsOneWidget);
      expect(find.text('ARMAZENAMENTO'), findsOneWidget);
      expect(find.text('CloudOS Drive'), findsWidgets);
      expect(find.text('Ubuntu WSL'), findsWidgets);

      // Open Start Panel
      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      expect(find.text('CloudOS Start'), findsOneWidget);
      expect(find.text('Aplicativos Fixados'), findsOneWidget);
      expect(find.text('Visual Studio Code'), findsOneWidget);
      expect(find.text('Ubuntu Terminal'), findsOneWidget);

      // Test Search
      await tester.enterText(find.byType(TextField).first, 'Code');
      await tester.pumpAndSettle();
      expect(find.text('Visual Studio Code'), findsOneWidget);

      // Close Start
      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();
      expect(find.text('CloudOS Start'), findsNothing);

      // Open Quick Settings
      await tester.tap(find.byTooltip('Configurações Rápidas (Ctrl+Alt+Q)'));
      await tester.pumpAndSettle();
      expect(find.text('Configurações Rápidas'), findsOneWidget);
      expect(find.text('Wi‑Fi 6'), findsOneWidget);
      expect(find.text('Luz Noturna'), findsOneWidget);

      // Open Notifications
      await tester.tap(find.byTooltip('Notificações'));
      await tester.pumpAndSettle();
      expect(find.text('Centro de Notificações'), findsOneWidget);
      expect(find.text('Limpar Tudo'), findsOneWidget);

      // Clear all notifications
      await tester.tap(find.text('Limpar Tudo'));
      await tester.pumpAndSettle();
      expect(find.text('Sem novas notificações'), findsOneWidget);
    });

    testWidgets('CloudOS presentation renders cleanly on notebook viewport (1366x768)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
    });

    testWidgets('CloudOS presentation renders cleanly on 2K / 1440p (2560x1440)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(2560, 1440));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos • Início'), findsOneWidget);
    });
  });
}
