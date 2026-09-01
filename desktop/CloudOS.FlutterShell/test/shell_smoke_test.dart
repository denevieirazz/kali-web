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
          case 'getFiles':
            return <Map<String, Object?>>[
              <String, Object?>{
                'name': 'Projetos',
                'path': r'C:\Users\tester\Documents\Projetos',
                'isFolder': true,
                'sizeFormatted': 'Pasta',
                'modifiedFormatted': '2026-09-01 08:20',
                'source': 'windows',
                'extension': '',
              },
              <String, Object?>{
                'name': 'relatorio.txt',
                'path': r'C:\Users\tester\Documents\relatorio.txt',
                'isFolder': false,
                'sizeFormatted': '2.4 KB',
                'modifiedFormatted': '2026-09-01 08:21',
                'source': 'windows',
                'extension': 'txt',
              },
            ];
          case 'getSystemSnapshot':
            return <String, Object?>{
              'deviceName': 'TEST-DEVICE-V21',
              'networkAvailable': true,
              'networkName': 'Wi-Fi 6 Real Native',
              'volumeAvailable': true,
              'volume': 0.80,
              'brightnessAvailable': true,
              'brightness': 0.90,
              'batteryPercent': 88,
              'wslAvailable': true,
              'distros': <String>['Ubuntu', 'kali-linux'],
              'currentWorkspace': 2,
            };
          case 'getNotificationState':
            return <String, Object?>{
              'revision': 7,
              'unreadCount': 2,
              'items': <Map<String, Object?>>[
                <String, Object?>{
                  'id': '101',
                  'title': 'CloudOS V21 Pronto',
                  'message': 'System Broker e NativeShell ativos.',
                  'time': '09:31',
                  'severity': 0,
                  'read': false,
                },
                <String, Object?>{
                  'id': '100',
                  'title': 'Subsistema Linux (WSL2)',
                  'message': 'WSL permanece sob demanda.',
                  'time': '09:30',
                  'severity': 0,
                  'read': false,
                },
              ],
            };
          case 'markNotificationsRead':
          case 'dismissNotification':
          case 'clearNotifications':
            return true;
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
              'shell_notification_authority': true,
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

    test('loadFiles forwards allowlisted location and parses native files', () async {
      const bridge = CloudOSBridge(channel: channel);
      final files = await bridge.loadFiles('documents');

      expect(files, hasLength(2));
      expect(files[0].name, 'Projetos');
      expect(files[0].isFolder, true);
      expect(files[0].source, CloudFileSource.windows);
      expect(files[1].name, 'relatorio.txt');
      expect(files[1].extension, 'txt');
      expect(log.last.method, 'getFiles');
      expect(log.last.arguments, <String, Object?>{'location': 'documents'});
    });

    test('loadSystemSnapshot parses native snapshot fields correctly', () async {
      const bridge = CloudOSBridge(channel: channel);
      final snapshot = await bridge.loadSystemSnapshot();

      expect(snapshot.deviceName, 'TEST-DEVICE-V21');
      expect(snapshot.networkAvailable, true);
      expect(snapshot.networkName, 'Wi-Fi 6 Real Native');
      expect(snapshot.volumeAvailable, true);
      expect(snapshot.volume, 0.80);
      expect(snapshot.brightnessAvailable, true);
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

    test('getBridgeInfo returns schema 21 metadata', () async {
      const bridge = CloudOSBridge(channel: channel);
      final info = await bridge.getBridgeInfo();

      expect(info['schema'], 21);
      expect(info['bridge_type'], 'CloudOSFlutterBridgeV20');
      expect(info['brokerConnected'], true);
      expect(info['brokerState'], 'connected');
      expect(info['arbitrary_command_api'], false);
      expect(info['shell_notification_authority'], true);
    });

    test('preview fallback handles missing plugin without throwing', () async {
      const missingChannel = MethodChannel('non_existent_channel');
      const bridge = CloudOSBridge(channel: missingChannel);

      final apps = await bridge.loadApps();
      expect(apps.isNotEmpty, true);
      expect(apps, CloudOSBridge.previewApps);

      final files = await bridge.loadFiles('home');
      expect(files, CloudOSBridge.previewFiles['home']);

      final snapshot = await bridge.loadSystemSnapshot();
      expect(snapshot.deviceName, CloudOSBridge.previewSnapshot.deviceName);

      final launchResult = await bridge.launchApp('anything');
      expect(launchResult, true);
    });
  });

  group('CloudOS V21 Desktop Presentation Suite', () {
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

      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      expect(find.text('CloudOS Start'), findsOneWidget);
      expect(find.text('Aplicativos Fixados'), findsOneWidget);
      expect(find.text('Visual Studio Code'), findsOneWidget);
      expect(find.text('Ubuntu Terminal'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Code');
      await tester.pumpAndSettle();
      expect(find.text('Visual Studio Code'), findsOneWidget);

      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();
      expect(find.text('CloudOS Start'), findsNothing);

      await tester.tap(find.byTooltip('Configurações Rápidas (Ctrl+Alt+Q)'));
      await tester.pumpAndSettle();
      expect(find.text('Configurações Rápidas'), findsOneWidget);
      expect(find.text('Rede'), findsOneWidget);
      expect(find.text(CloudOSBridge.previewSnapshot.networkName), findsOneWidget);
      expect(find.text('Luz Noturna'), findsOneWidget);

      await tester.tap(find.byTooltip('Notificações'));
      await tester.pumpAndSettle();
      expect(find.text('Centro de Notificações'), findsOneWidget);
      expect(find.text('Limpar Tudo'), findsOneWidget);

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
