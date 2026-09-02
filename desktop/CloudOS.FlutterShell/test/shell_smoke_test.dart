import 'package:cloudos_flutter_shell/models/file_models.dart' as files;
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/files_controller.dart';
import 'package:cloudos_flutter_shell/services/window_manager.dart';
import 'package:cloudos_flutter_shell/shell/cloudos_shell.dart';
import 'package:cloudos_flutter_shell/widgets/browser_window.dart';
import 'package:cloudos_flutter_shell/widgets/cloudos_drive_window.dart';
import 'package:cloudos_flutter_shell/widgets/files_window.dart';
import 'package:cloudos_flutter_shell/widgets/projects_window.dart';
import 'package:cloudos_flutter_shell/widgets/settings_window.dart';
import 'package:cloudos_flutter_shell/widgets/system_monitor_window.dart';
import 'package:cloudos_flutter_shell/widgets/terminal_window.dart';
import 'package:cloudos_flutter_shell/services/system_metrics_service.dart';
import 'package:cloudos_flutter_shell/widgets/context_menu.dart';
import 'package:cloudos_flutter_shell/widgets/desktop_widgets.dart';
import 'package:cloudos_flutter_shell/widgets/notepad_window.dart';
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
                    'id': 'wsl:Ubuntu:terminal',
                    'name': 'Ubuntu Terminal',
                    'platform': 'linux',
                    'subtitle': 'Linux shell',
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
                if (rpcMethod == 'apps.list') {
                  return '{"ok":true,"payload":{"apps":[{"id":"windows:notepad","name":"Bloco de Notas","platform":"windows","subtitle":"Editor de Texto","category":"Produtividade","source":"Windows","canLaunch":true,"pinned":true,"recent":false},{"id":"wsl:Ubuntu:terminal","name":"Ubuntu Terminal","platform":"linux","subtitle":"Linux shell","distro":"Ubuntu","category":"Utilitários","source":"Ubuntu (WSL)","canLaunch":true,"pinned":true,"recent":false},{"id":"cloudos:files","name":"Arquivos","platform":"cloudos","subtitle":"Windows + Linux","category":"Sistema","source":"CloudOS","canLaunch":true,"pinned":true,"recent":false}]}}';
                }
                if (rpcMethod == 'system.snapshot') {
                  return '{"ok":true,"payload":{"deviceName":"TEST-DEVICE-V22","networkName":"Rede de teste","networkAvailable":true,"volumeAvailable":true,"volume":0.8,"brightnessAvailable":false,"brightness":0.0,"batteryAvailable":true,"batteryPercent":88,"wslAvailable":true,"distros":["Ubuntu","kali-linux"],"currentWorkspace":2}}';
                }
                if (rpcMethod == 'files.knownFolders') {
                  return '{"ok":true,"payload":{"folders":[{"id":"home","name":"Início","path":"C:\\\\Users\\\\Test","iconKey":"home"},{"id":"desktop","name":"Área de Trabalho","path":"C:\\\\Users\\\\Test\\\\Desktop","iconKey":"desktop"}]}}';
                }
                if (rpcMethod == 'files.drives') {
                  return '{"ok":true,"payload":{"drives":[{"letter":"C:","path":"C:\\\\","label":"Disco Local","filesystem":"NTFS","totalBytes":512000000000,"freeBytes":256000000000,"totalFormatted":"512 GB","freeFormatted":"256 GB","isRemovable":false,"isReady":true,"driveType":"fixed"}]}}';
                }
                if (rpcMethod == 'files.list') {
                  return '{"ok":true,"payload":{"items":[{"id":"f1","name":"Documento.txt","displayName":"Documento.txt","path":"C:\\\\Users\\\\Test\\\\Documento.txt","canonicalPath":"C:\\\\Users\\\\Test\\\\Documento.txt","locationKind":"windows","fileKind":"text","extension":".txt","size":1024,"sizeFormatted":"1.0 KB","modifiedTime":"Hoje","createdTime":"Ontem","isDirectory":false,"isHidden":false,"isReadOnly":false,"isSystem":false,"isSymlink":false,"distro":"","iconKey":"file_text","canRename":true,"canDelete":true,"canOpen":true,"canOpenWith":true,"canCopy":true,"canMove":true}]}}';
                }
                if (rpcMethod == 'files.createFolder' ||
                    rpcMethod == 'files.rename' ||
                    rpcMethod == 'files.delete' ||
                    rpcMethod == 'files.open' ||
                    rpcMethod == 'files.openWith.launch') {
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

    test(
      'loadApps parses Windows, Linux, and CloudOS apps correctly',
      () async {
        const bridge = CloudOSBridge(channel: channel);
        final apps = await bridge.loadApps();

        expect(apps.length, 3);
        expect(apps[0].id, 'windows:notepad');
        expect(apps[0].platform, CloudAppPlatform.windows);
        expect(apps[1].id, 'wsl:Ubuntu:terminal');
        expect(apps[1].platform, CloudAppPlatform.linux);
        expect(apps[1].distro, 'Ubuntu');
        expect(apps[2].id, 'cloudos:files');
        expect(apps[2].platform, CloudAppPlatform.cloudos);
      },
    );

    test(
      'loadSystemSnapshot parses native snapshot fields correctly',
      () async {
        const bridge = CloudOSBridge(channel: channel);
        final snapshot = await bridge.loadSystemSnapshot();

        expect(snapshot.deviceName, 'TEST-DEVICE-V22');
        expect(snapshot.networkName, 'Rede de teste');
        expect(snapshot.volume, 0.80);
        expect(snapshot.brightness, 0.0);
        expect(snapshot.batteryPercent, 88);
        expect(snapshot.wslAvailable, true);
        expect(snapshot.distros, <String>['Ubuntu', 'kali-linux']);
        expect(snapshot.currentWorkspace, 2);
      },
    );

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

      final createOk = await bridge.createFolder(
        'C:\\Users\\Test',
        'NovaPasta',
      );
      expect(createOk, true);

      final renameOk = await bridge.renameItem(
        'C:\\Users\\Test\\Documento.txt',
        'DocNovo.txt',
      );
      expect(renameOk, true);

      final deleteOk = await bridge.deleteItems(<String>[
        'C:\\Users\\Test\\DocNovo.txt',
      ]);
      expect(deleteOk, true);

      final openWithApps = await bridge.getOpenWithList(
        'C:\\Users\\Test\\Documento.txt',
      );
      expect(openWithApps.length, 1);
      expect(openWithApps[0].name, 'Bloco de Notas');
    });
  });

  group('CloudOS V22 FilesController Unit Tests', () {
    test(
      'FilesController initializes with default tab and loads folders',
      () async {
        const bridge = _TestBridge();
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
      },
    );
  });

  group('CloudOS V22 Desktop Presentation Suite', () {
    tearDown(() => SystemMetricsService.instance.forceStop());

    testWidgets(
      'CloudOS presentation renders core desktop surfaces on 1920x1080',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(home: CloudOSShell(bridge: _TestBridge())),
        );
        await tester.pumpAndSettle();

        expect(find.text('Arquivos'), findsWidgets);
        expect(find.text('Navegador'), findsWidgets);
        expect(find.text('Configurações'), findsWidgets);

        // Open Start Panel
        await tester.tap(find.byTooltip('Iniciar (Ctrl+Alt+A)'));
        await tester.pumpAndSettle();

        expect(find.text('CloudOS Start'), findsOneWidget);
        expect(find.text('Aplicativos Fixados'), findsOneWidget);
        expect(find.text('Bloco de Notas'), findsWidgets);

        // Close Start
        await tester.tap(find.byTooltip('Fechar (Esc)'));
        await tester.pumpAndSettle();
        expect(find.text('CloudOS Start'), findsNothing);

        // Open Quick Settings
        await tester.tap(find.byTooltip('Configurações Rápidas (Ctrl+Alt+Q)'));
        await tester.pumpAndSettle();
        expect(find.text('Configurações Rápidas'), findsOneWidget);
        expect(find.text('Rede'), findsOneWidget);
        expect(find.text('Luz Noturna'), findsOneWidget);

        // Open Notifications
        await tester.tap(find.byTooltip('Notificações'));
        await tester.pumpAndSettle();
        expect(find.text('Centro de Notificações'), findsOneWidget);
        if (find.text('Limpar Tudo').evaluate().isNotEmpty) {
          await tester.tap(find.text('Limpar Tudo'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Sem novas notificações'), findsWidgets);

        // Close Notifications
        await tester.tap(find.byTooltip('Notificações'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('FilesWindow renders and responds to search and tab creation', (
      tester,
    ) async {
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
                bridge: const _TestBridge(),
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

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'CloudOS presentation renders cleanly on notebook viewport (1366x768)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1366, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(home: CloudOSShell(bridge: _TestBridge())),
        );
        await tester.pumpAndSettle();

        expect(find.text('Arquivos'), findsWidgets);
        expect(find.text('Navegador'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'CloudOS presentation renders cleanly on 2K / 1440p (2560x1440)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(2560, 1440));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(home: CloudOSShell(bridge: _TestBridge())),
        );
        await tester.pumpAndSettle();

        expect(find.text('Arquivos'), findsWidgets);
        expect(find.text('Navegador'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('CloudOS presentation renders cleanly on 1600x900', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: CloudOSShell(bridge: _TestBridge())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arquivos'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Files remains overflow-free at 200 percent text scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            home: Scaffold(
              body: FilesWindow(
                onClose: _noop,
                onMinimize: _noop,
                onDrag: _noopDrag,
                bridge: _TestBridge(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arquivos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('CloudOS WindowManager & Internal Desktop Applications Suite', () {
    tearDown(() => SystemMetricsService.instance.forceStop());

    test('WindowManager manages open, minimize, maximize, restore, focus, and close', () {
      final wm = WindowManager();
      expect(wm.windows.isEmpty, true);

      // Open Files Window
      wm.openWindow('cloudos:files');
      expect(wm.windows.length, 1);
      expect(wm.isAppOpen('cloudos:files'), true);
      expect(wm.isAppFocused('cloudos:files'), true);
      expect(wm.isAppMinimized('cloudos:files'), false);

      // Open Terminal Window
      wm.openWindow('cloudos:terminal');
      expect(wm.windows.length, 2);
      expect(wm.isAppFocused('cloudos:terminal'), true);
      expect(wm.isAppFocused('cloudos:files'), false);

      // Minimize Terminal
      final termWin = wm.windows.firstWhere((w) => w.appId == 'cloudos:terminal');
      wm.minimizeWindow(termWin.id);
      expect(wm.isAppMinimized('cloudos:terminal'), true);
      expect(wm.isAppFocused('cloudos:files'), true);

      // Toggle Files Window (should minimize since it's focused)
      wm.toggleWindow('cloudos:files');
      expect(wm.isAppMinimized('cloudos:files'), true);

      // Toggle Files Window again (should restore and focus)
      wm.toggleWindow('cloudos:files');
      expect(wm.isAppFocused('cloudos:files'), true);

      // Maximize / Restore
      final filesWin = wm.windows.firstWhere((w) => w.appId == 'cloudos:files');
      wm.toggleMaximizeWindow(filesWin.id, const Size(1920, 1080));
      expect(filesWin.maximized, true);
      expect(filesWin.width, 1920);

      wm.toggleMaximizeWindow(filesWin.id, const Size(1920, 1080));
      expect(filesWin.maximized, false);

      // Close Window
      wm.closeWindow(filesWin.id);
      expect(wm.isAppOpen('cloudos:files'), false);
    });

    testWidgets('TerminalWindow renders with tabs and handles input command', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TerminalWindow(bridge: _TestBridge()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('PowerShell'), findsWidgets);

      final inputFinder = find.byType(TextField);
      if (inputFinder.evaluate().isNotEmpty) {
        await tester.enterText(inputFinder.first, 'help');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }
    });

    testWidgets('BrowserWindow renders tabs, navigation bar and favorites', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrowserWindow(bridge: _TestBridge()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nova Guia'), findsWidgets);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('SettingsWindow renders 10 settings pages and switches correctly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsWindow(bridge: _TestBridge()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Configurações'), findsWidgets);
      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Som'), findsOneWidget);
      expect(find.text('Rede & Internet'), findsOneWidget);

      // Switch to Sound page
      await tester.tap(find.text('Som'));
      await tester.pumpAndSettle();
      expect(find.text('Saída de Áudio do Sistema'), findsOneWidget);

      // Switch to About page
      await tester.tap(find.text('Sobre o CloudOS'));
      await tester.pumpAndSettle();
      expect(find.text('CloudOS Desktop V22.1'), findsOneWidget);
    });

    testWidgets('SystemMonitorWindow renders metrics cards and processes table', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SystemMonitorWindow(bridge: _TestBridge()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('Memória RAM'), findsOneWidget);
      expect(find.textContaining('Armazenamento'), findsOneWidget);
      expect(find.textContaining('Processos Ativos'), findsOneWidget);
    });

    testWidgets('ProjectsWindow renders workspaces and quick action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wm = WindowManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectsWindow(bridge: const _TestBridge(), windowManager: wm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gerenciador de Projetos & Workspaces'), findsOneWidget);
      expect(find.text('CloudOS Core & Shell V22.1'), findsOneWidget);
      expect(find.byTooltip('Abrir no Terminal'), findsWidgets);
    });

    testWidgets('CloudOSDriveWindow renders storage info and sync files', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wm = WindowManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudOSDriveWindow(bridge: const _TestBridge(), windowManager: wm),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CloudOS Drive Local'), findsOneWidget);
    });

    testWidgets('NotepadWindow renders editor with tabs, line numbers and status', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotepadWindow(bridge: _TestBridge()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem título'), findsOneWidget);
      expect(find.byTooltip('Novo Documento (Ctrl+N)'), findsOneWidget);
      expect(find.byTooltip('Salvar no Disco (Ctrl+S)'), findsOneWidget);
      expect(find.textContaining('UTF-8'), findsOneWidget);

      // Add a new tab
      await tester.tap(find.byTooltip('Novo Documento (Ctrl+N)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem título 2.txt'), findsOneWidget);
    });

    testWidgets('DesktopClockWidget and DesktopMetricsWidget render on desktop', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                DesktopClockWidget(),
                DesktopMetricsWidget(bridge: _TestBridge()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Performance'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('DISCO'), findsOneWidget);
    });

    testWidgets('ContextMenuOverlay renders options and responds to tap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenuOverlay(
              position: const Offset(100, 100),
              items: <ContextMenuItemData>[
                ContextMenuItemData(
                  title: 'Nova Pasta',
                  icon: Icons.create_new_folder_outlined,
                  onTap: () => tapped = true,
                ),
                ContextMenuItemData(
                  title: 'Atualizar',
                  icon: Icons.refresh_rounded,
                  onTap: () {},
                ),
              ],
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nova Pasta'), findsOneWidget);
      expect(find.text('Atualizar'), findsOneWidget);

      await tester.tap(find.text('Nova Pasta'));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    test('WindowManager supports Aero Snapping (Left, Right, and Top Maximize)', () {
      final wm = WindowManager();
      const viewport = Size(1920, 1080);
      wm.openWindow('cloudos:files');

      final win = wm.windows.first;
      expect(win.maximized, false);

      // Snap Left
      wm.snapWindowLeft(win.id, viewport);
      expect(win.x, 0.0);
      expect(win.width, 960.0);
      expect(win.height, 1032.0);

      // Snap Right
      wm.snapWindowRight(win.id, viewport);
      expect(win.x, 960.0);
      expect(win.width, 960.0);
      expect(win.height, 1032.0);

      // Snap Top / Maximize
      wm.toggleMaximizeWindow(win.id, viewport);
      expect(win.maximized, true);
      expect(win.width, 1920.0);
    });
  });
}

void _noop() {}

void _noopDrag(Offset _) {}

class _TestBridge extends CloudOSBridge {
  const _TestBridge();

  @override
  Future<List<CloudApp>> loadApps() async => const <CloudApp>[
    CloudApp(
      id: 'windows:notepad',
      name: 'Bloco de Notas',
      icon: Icons.edit_note_rounded,
      platform: CloudAppPlatform.windows,
    ),
    CloudApp(
      id: 'cloudos:files',
      name: 'Arquivos',
      icon: Icons.folder_rounded,
      platform: CloudAppPlatform.cloudos,
    ),
  ];

  @override
  Future<CloudSystemSnapshot> loadSystemSnapshot() async =>
      const CloudSystemSnapshot(
        deviceName: 'TEST-DEVICE-V22',
        networkName: 'Rede de teste',
        volume: 0.8,
        brightness: 0,
        batteryPercent: 88,
        wslAvailable: true,
        distros: <String>['Ubuntu'],
        networkAvailable: true,
        volumeAvailable: true,
        brightnessAvailable: false,
      );

  @override
  Future<List<files.KnownFolderModel>> getKnownFolders() async =>
      const <files.KnownFolderModel>[
        files.KnownFolderModel(
          id: 'home',
          name: 'Início',
          path: r'C:\Users\Test',
          iconKey: 'home',
        ),
      ];

  @override
  Future<List<files.DriveInfoModel>> getDrives() async =>
      const <files.DriveInfoModel>[
        files.DriveInfoModel(
          letter: 'C:',
          path: 'C:\\',
          label: 'Disco Local',
          filesystem: 'NTFS',
          totalBytes: 1000,
          freeBytes: 500,
          totalFormatted: '1 KB',
          freeFormatted: '500 B',
          isRemovable: false,
          isReady: true,
          driveType: 'fixed',
        ),
      ];

  @override
  Future<List<files.CloudFileItem>> listFiles(
    String path, {
    int pageSize = 200,
    String continuationToken = '',
    files.FileSortField sortField = files.FileSortField.name,
    bool ascending = true,
    bool showHidden = false,
    String searchText = '',
  }) async => const <files.CloudFileItem>[];

  @override
  Future<bool> setVolume(double value) async => true;

  @override
  Future<bool> setBrightness(double value) async => false;
}
