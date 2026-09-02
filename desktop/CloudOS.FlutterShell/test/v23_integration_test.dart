import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/desktop_broker_service.dart';
import 'package:cloudos_flutter_shell/services/search_settings_catalog.dart';
import 'package:cloudos_flutter_shell/widgets/settings_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DesktopBridge extends CloudOSBridge {
  _DesktopBridge({this.existing = const <CloudFileItem>[]}) : super();

  final List<CloudFileItem> existing;
  String? listedPath;
  String? createdParent;
  String? createdName;

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async {
    return const <KnownFolderModel>[
      KnownFolderModel(
        id: 'home',
        name: 'Início',
        path: r'Z:\Profiles\Tester',
        iconKey: 'home',
      ),
      KnownFolderModel(
        id: 'desktop',
        name: 'Área de Trabalho',
        path: r'Z:\Profiles\Tester\Desk',
        iconKey: 'desktop',
      ),
    ];
  }

  @override
  Future<List<CloudFileItem>> listFiles(
    String path, {
    int pageSize = 200,
    String continuationToken = '',
    FileSortField sortField = FileSortField.name,
    bool ascending = true,
    bool showHidden = false,
    String searchText = '',
  }) async {
    listedPath = path;
    return existing;
  }

  @override
  Future<bool> createFolder(String parentPath, String name) async {
    createdParent = parentPath;
    createdName = name;
    return true;
  }

  @override
  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    return CloudOSBridge.unavailableSnapshot;
  }

  @override
  Future<List<DriveInfoModel>> getDrives() async {
    return const <DriveInfoModel>[];
  }

  @override
  Future<Map<String, Object?>> getBridgeInfo() async {
    return const <String, Object?>{
      'brokerConnected': true,
      'brokerState': 'connected',
    };
  }
}

CloudFileItem _folder(String name) {
  return CloudFileItem(
    id: 'folder:$name',
    name: name,
    displayName: name,
    path: r'Z:\Profiles\Tester\Desk\' + name,
    canonicalPath: r'Z:\Profiles\Tester\Desk\' + name,
    locationKind: LocationKind.windows,
    fileKind: FileKind.folder,
    extension: '',
    size: 0,
    sizeFormatted: '',
    modifiedFormatted: '',
    createdFormatted: '',
    isDirectory: true,
    isHidden: false,
    isReadOnly: false,
    isSystem: false,
    isSymlink: false,
    distro: '',
    iconKey: 'folder',
  );
}

void main() {
  group('V23 integration', () {
    test('settings catalog has stable typed IDs and indexes', () {
      expect(SearchSettingsCatalog.pageIndex('system'), 0);
      expect(SearchSettingsCatalog.pageIndex('sound'), 2);
      expect(SearchSettingsCatalog.pageIndex('storage'), 6);
      expect(SearchSettingsCatalog.pageIndex('does-not-exist'), 0);
      expect(SearchSettingsCatalog.findById('wsl')?.requiresWsl, isTrue);
    });

    test('DesktopBrokerService resolves Desktop exclusively from bridge data', () async {
      final bridge = _DesktopBridge();
      final service = DesktopBrokerService(bridge);
      expect(await service.desktopPath(), r'Z:\Profiles\Tester\Desk');
      expect(await service.desktopPath(), r'Z:\Profiles\Tester\Desk');
    });

    test('DesktopBrokerService creates collision-free folder through Files RPC', () async {
      final bridge = _DesktopBridge(
        existing: <CloudFileItem>[
          _folder('Nova Pasta'),
          _folder('Nova Pasta (2)'),
        ],
      );
      final service = DesktopBrokerService(bridge);
      final created = await service.createUniqueFolder();

      expect(bridge.listedPath, r'Z:\Profiles\Tester\Desk');
      expect(bridge.createdParent, r'Z:\Profiles\Tester\Desk');
      expect(bridge.createdName, 'Nova Pasta (3)');
      expect(created, r'Z:\Profiles\Tester\Desk\Nova Pasta (3)');
    });

    testWidgets('SettingsWindow honors typed Search deep link', (tester) async {
      final bridge = _DesktopBridge();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: SettingsWindow(
                key: const ValueKey<String>('settings-v23'),
                bridge: bridge,
                initialPageId: 'sound',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saída de Áudio do Sistema'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('settings-page-sound')), findsOneWidget);
    });

    testWidgets('Settings singleton-style param update changes active page', (tester) async {
      final bridge = _DesktopBridge();

      Widget build(String page) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: SettingsWindow(
                key: const ValueKey<String>('settings-v23'),
                bridge: bridge,
                initialPageId: page,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(build('sound'));
      await tester.pumpAndSettle();
      expect(find.text('Saída de Áudio do Sistema'), findsOneWidget);

      await tester.pumpWidget(build('storage'));
      await tester.pumpAndSettle();
      expect(find.text('Unidades de Armazenamento'), findsOneWidget);
    });
  });
}
