import 'package:cloudos_flutter_shell/main.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOS V21 System Broker Bridge Contracts', () {
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
              'deviceName': 'TEST-DEVICE-V21',
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
      expect(apps[2].id, 'cloudos:files');
      expect(apps[2].platform, CloudAppPlatform.cloudos);
    });

    test('loadSystemSnapshot maps all properties from native snapshot', () async {
      const bridge = CloudOSBridge(channel: channel);
      final snap = await bridge.loadSystemSnapshot();

      expect(snap.deviceName, 'TEST-DEVICE-V21');
      expect(snap.networkName, 'Wi-Fi 6 Real Native');
      expect(snap.volume, 0.80);
      expect(snap.brightness, 0.90);
      expect(snap.batteryPercent, 88);
      expect(snap.wslAvailable, true);
      expect(snap.distros, ['Ubuntu', 'kali-linux']);
      expect(snap.currentWorkspace, 2);
    });

    test('launchApp sends typed ID argument to channel', () async {
      const bridge = CloudOSBridge(channel: channel);
      final success = await bridge.launchApp('windows:notepad');

      expect(success, isTrue);
      expect(log.length, 1);
      expect(log.first.method, 'launchApp');
      expect(log.first.arguments, {'id': 'windows:notepad'});
    });

    test('setVolume and setBrightness pass values to native channel', () async {
      const bridge = CloudOSBridge(channel: channel);
      final volResult = await bridge.setVolume(0.65);
      final briResult = await bridge.setBrightness(0.75);

      expect(volResult, isTrue);
      expect(briResult, isTrue);
      expect(log.length, 2);
      expect(log[0].method, 'setVolume');
      expect(log[0].arguments, {'value': 0.65});
      expect(log[1].method, 'setBrightness');
      expect(log[1].arguments, {'value': 0.75});
    });

    test('getBridgeInfo returns schema 21 and arbitrary_command_api false', () async {
      const bridge = CloudOSBridge(channel: channel);
      final info = await bridge.getBridgeInfo();

      expect(info['schema'], 21);
      expect(info['arbitrary_command_api'], isFalse);
      expect(info['brokerConnected'], isTrue);
      expect(info['brokerState'], 'connected');
    });

    test('preview fallback activates gracefully when channel throws MissingPluginException', () async {
      const unmockedChannel = MethodChannel('cloudos/unregistered');
      const bridge = CloudOSBridge(channel: unmockedChannel);

      final apps = await bridge.loadApps();
      expect(apps.isNotEmpty, isTrue);

      final snap = await bridge.loadSystemSnapshot();
      expect(snap.deviceName, isNotEmpty);

      final launchResult = await bridge.launchApp('cloudos:files');
      expect(launchResult, isTrue);

      final info = await bridge.getBridgeInfo();
      expect(info['schema'], 21);
      expect(info['bridge_type'], 'PreviewFallback');
      expect(info['arbitrary_command_api'], isFalse);
    });
  });

  group('CloudOS Multi-Viewport UI Smoke Tests', () {
    const channel = MethodChannel('cloudos/native/v19');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('renders full Desktop environment with Taskbar and Desktop icons', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('Arquivos'), findsWidgets);
      expect(find.text('Navegador Web'), findsWidgets);
      expect(find.text('Terminal ConPTY'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('opens and closes Start Menu cleanly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      final startButton = find.byTooltip('Iniciar');
      expect(startButton, findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(find.text('Fixados'), findsOneWidget);
      expect(find.text('Recentes'), findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(find.text('Fixados'), findsNothing);
    });

    testWidgets('opens Quick Settings flyout and adjusts sliders without overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      final quickSettingsBtn = find.byTooltip('Configurações rápidas');
      expect(quickSettingsBtn, findsOneWidget);

      await tester.tap(quickSettingsBtn);
      await tester.pumpAndSettle();

      expect(find.text('Ajustes Rápidos'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens Notification Center and renders without header overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      final notifBtn = find.byTooltip('Notificações');
      expect(notifBtn, findsOneWidget);

      await tester.tap(notifBtn);
      await tester.pumpAndSettle();

      expect(find.text('Central de Notificações'), findsOneWidget);
      expect(find.text('Limpar tudo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
