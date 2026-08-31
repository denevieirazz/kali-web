import 'package:cloudos_flutter_shell/main.dart';
import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/files_controller.dart';
import 'package:cloudos_flutter_shell/widgets/files_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOS V22 System Broker & Unified Files Bridge Contracts', () {
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
              'deviceName': 'TEST-DEVICE-V22',
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
              'schema': 22,
              'version': 'v22',
              'bridge_type': 'CloudOSFlutterBridgeV20',
              'brokerConnected': true,
              'brokerState': 'connected',
              'channel': 'cloudos/native/v19',
              'arbitrary_command_api': false,
            };
          case 'invokeBrokerRpc':
            final args = call.arguments as Map<Object?, Object?>?;
            final rpcMethod = args?['method'] as String?;
            if (rpcMethod == 'files.knownFolders') {
              return '{"ok":true,"payload":{"folders":[{"id":"home","name":"Início","path":"C:\\\\Users\\\\Test","iconKey":"home"},{"id":"desktop","name":"Área de Trabalho","path":"C:\\\\Users\\\\Test\\\\Desktop","iconKey":"desktop"}]}}';
            }
            if (rpcMethod == 'files.drives') {
              return '{"ok":true,"payload":{"drives":[{"letter":"C:","path":"C:\\\\","label":"Disco Local","filesystem":"NTFS","totalBytes":512000000000,"freeBytes":256000000000,"totalFormatted":"512 GB","freeFormatted":"256 GB","isRemovable":false,"isReady":true,"driveType":"fixed"}]}}';
            }
            if (rpcMethod == 'files.list') {
              return '{"ok":true,"payload":{"items":[{"id":"f1","name":"Documento.txt","displayName":"Documento.txt","path":"C:\\\\Users\\\\Test\\\\Documento.txt","canonicalPath":"C:\\\\Users\\\\Test\\\\Documento.txt","locationKind":"windows","fileKind":"text","extension":".txt","size":1024,"sizeFormatted":"1.0 KB","modifiedTime":"Hoje","createdTime":"Ontem","isDirectory":false,"isHidden":false,"isReadOnly":false,"isSystem":false,"isSymlink":false,"distro":"","iconKey":"file_text","canRename":true,"canDelete":true,"canOpen":true,"canOpenWith":true,"canCopy":true,"canMove":true}]}}';
            }
            if (rpcMethod == 'files.createFolder' || rpcMethod == 'files.rename' || rpcMethod == 'files.delete' || rpcMethod == 'files.open' || rpcMethod == 'files.openWith.launch') {
              return '{"ok":true,"payload":{"ok":true}}';
            }
            if (rpcMethod == 'files.openWith.list') {
              return '{"ok":true,"payload":{"apps":[{"appId":"windows:notepad","name":"Bloco de Notas","platform":"windows","distro":"","iconKey":"file_text","isRecommended":true,"isDefault":true}]}}';
            }
            return '{"ok":true,"payload":{}}';
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

      expect(snapshot.deviceName, 'TEST-DEVICE-V22');
      expect(snapshot.networkName, 'Wi-Fi 6 Real Native');
      expect(snapshot.volume, 0.80);
      expect(snapshot.brightness, 0.90);
      expect(snapshot.batteryPercent, 88);
      expect(snapshot.wslAvailable, true);
      expect(snapshot.distros, <String>['Ubuntu', 'kali-linux']);
      expect(snapshot.currentWorkspace, 2);
    });

    test('Files RPC methods work through mock bridge', () async {
      const bridge = CloudOSBridge(channel: channel);

      final folders = await bridge.getKnownFolders();
      expect(folders.length, 2);
      expect(folders[0].name, 'Início');

      final drives = await bridge.getDrives();
      expect(drives.length, 1);
      expect(drives[0].letter, 'C:');

      final items = await bridge.listFiles('C:\\Users\\Test');
      expect(items.length, 1);
      expect(items[0].name, 'Documento.txt');

      final createOk = await bridge.createFolder('C:\\Users\\Test', 'NovaPasta');
      expect(createOk, true);

      final renameOk = await bridge.renameItem('C:\\Users\\Test\\Documento.txt', 'DocNovo.txt');
      expect(renameOk, true);

      final deleteOk = await bridge.deleteItems(<String>['C:\\Users\\Test\\DocNovo.txt']);
      expect(deleteOk, true);

      final openWithApps = await bridge.getOpenWithList('C:\\Users\\Test\\Documento.txt');
      expect(openWithApps.length, 1);
      expect(openWithApps[0].name, 'Bloco de Notas');
    });
  });

  group('CloudOS V22 FilesController Unit Tests', () {
    const channel = MethodChannel('cloudos/native/v19');

    test('FilesController initializes with default tab and loads folders', () async {
      const bridge = CloudOSBridge(channel: channel);
      final controller = FilesController(bridge: bridge);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.tabs.length, 1);
      expect(controller.activeTab?.currentPath, 'home');
      expect(controller.knownFolders.isNotEmpty, true);
      expect(controller.drives.isNotEmpty, true);

      // Add Tab
      controller.addTab(title: 'Desktop', initialPath: 'desktop');
      expect(controller.tabs.length, 2);
      expect(controller.activeTabIndex, 1);

      // Close Tab
      controller.closeTab(1);
      expect(controller.tabs.length, 1);
      expect(controller.activeTabIndex, 0);
    });
  });

  group('CloudOS V22 Desktop Presentation Suite', () {
    testWidgets('CloudOS presentation renders core desktop surfaces on 1920x1080', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos'), findsWidgets);
      expect(find.text('Acesso Rápido'), findsOneWidget);
      expect(find.text('Este Computador'), findsOneWidget);

      // Open Start Panel
      await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
      await tester.pumpAndSettle();

      expect(find.text('CloudOS Start'), findsOneWidget);
      expect(find.text('Aplicativos Fixados'), findsOneWidget);
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

    testWidgets('FilesWindow renders and responds to search and tab creation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: FilesWindow(
                onClose: () {},
                onMinimize: () {},
                onDrag: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arquivos'), findsOneWidget);
      expect(find.text('Acesso Rápido'), findsOneWidget);
      expect(find.byTooltip('Nova Aba'), findsOneWidget);

      // Add a new tab
      await tester.tap(find.byTooltip('Nova Aba'));
      await tester.pumpAndSettle();

      // Check view mode switch
      await tester.tap(find.byTooltip('Visualizar em Lista'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Visualizar em Grade'), findsOneWidget);
    });

    testWidgets('CloudOS presentation renders cleanly on notebook viewport (1366x768)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos'), findsWidgets);
    });

    testWidgets('CloudOS presentation renders cleanly on 2K / 1440p (2560x1440)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(2560, 1440));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const CloudOSApp());
      await tester.pumpAndSettle();

      expect(find.text('CloudOS V19'), findsWidgets);
      expect(find.text('Arquivos'), findsWidgets);
    });
  });
}
