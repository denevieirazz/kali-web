import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/services/broker_filesystem_service.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/cloudos_drive_service.dart';
import 'package:cloudos_flutter_shell/services/project_filesystem_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokerFsBridge extends CloudOSBridge {
  _BrokerFsBridge({
    Set<String>? existingDirectories,
    Map<String, List<CloudFileItem>>? listings,
  })  : directories = existingDirectories ?? <String>{},
        listings = listings ?? <String, List<CloudFileItem>>{},
        super();

  final Set<String> directories;
  final Map<String, List<CloudFileItem>> listings;
  final List<String> created = <String>[];

  String normalize(String value) {
    var result = value.trim().replaceAll('/', r'\');
    while (result.length > 3 && result.endsWith(r'\')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async {
    return const <KnownFolderModel>[
      KnownFolderModel(
        id: 'home',
        name: 'Início',
        path: r'Z:\Profiles\Tester',
        iconKey: 'home',
      ),
    ];
  }

  @override
  Future<Map<String, Object?>> invokeBrokerRpc(
    String method,
    Map<String, Object?> payload,
  ) async {
    if (method == 'files.resolvePath') {
      final raw = payload['path'] as String? ?? '';
      final path = normalize(raw);
      return <String, Object?>{
        'input': raw,
        'resolvedPath': path,
        'exists': directories.contains(path) || _findFile(path) != null,
      };
    }
    throw CloudOSBridgeException('unsupported_test_rpc', method);
  }

  CloudFileItem? _findFile(String path) {
    for (final items in listings.values) {
      for (final item in items) {
        if (normalize(item.path) == path) return item;
      }
    }
    return null;
  }

  @override
  Future<CloudFileItem?> getFileMetadata(String rawPath) async {
    final path = normalize(rawPath);
    final file = _findFile(path);
    if (file != null) return file;
    if (!directories.contains(path)) return null;
    return _folderItem(path);
  }

  @override
  Future<bool> createFolder(String parentPath, String name) async {
    final parent = normalize(parentPath);
    final target = normalize(
      parent.endsWith(r'\') ? '$parent$name' : '$parent\\$name',
    );
    if (!directories.contains(parent)) return false;
    directories.add(target);
    created.add(target);
    return true;
  }

  @override
  Future<List<CloudFileItem>> listFiles(
    String rawPath, {
    int pageSize = 200,
    String continuationToken = '',
    FileSortField sortField = FileSortField.name,
    bool ascending = true,
    bool showHidden = false,
    String searchText = '',
  }) async {
    return listings[normalize(rawPath)] ?? const <CloudFileItem>[];
  }
}

CloudFileItem _folderItem(String path) {
  final name = path.split(r'\').where((part) => part.isNotEmpty).last;
  return CloudFileItem(
    id: 'folder:$path',
    name: name,
    displayName: name,
    path: path,
    canonicalPath: path,
    locationKind: path.startsWith(r'\\wsl.localhost\')
        ? LocationKind.wsl
        : LocationKind.windows,
    fileKind: FileKind.folder,
    extension: '',
    size: 0,
    sizeFormatted: '',
    modifiedFormatted: '2026-09-02T10:30:00.000Z',
    createdFormatted: '2026-09-01T10:30:00.000Z',
    isDirectory: true,
    isHidden: false,
    isReadOnly: false,
    isSystem: false,
    isSymlink: false,
    distro: '',
    iconKey: 'folder',
  );
}

CloudFileItem _fileItem(String parent, String name) {
  final path = '$parent\\$name';
  final extension = name.contains('.') ? '.${name.split('.').last}' : '';
  return CloudFileItem(
    id: 'file:$path',
    name: name,
    displayName: name,
    path: path,
    canonicalPath: path,
    locationKind: LocationKind.windows,
    fileKind: FileKind.code,
    extension: extension,
    size: 10,
    sizeFormatted: '10 B',
    modifiedFormatted: '2026-09-02T10:30:00.000Z',
    createdFormatted: '2026-09-02T10:00:00.000Z',
    isDirectory: false,
    isHidden: false,
    isReadOnly: false,
    isSystem: false,
    isSymlink: false,
    distro: '',
    iconKey: 'file_code',
  );
}

void main() {
  group('BrokerFilesystemService V23', () {
    test('creates a missing Windows directory tree only through Files RPC', () async {
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{
          'Z:\\',
          r'Z:\Profiles',
          r'Z:\Profiles\Tester',
        },
      );
      final service = BrokerFilesystemService(bridge);

      final result = await service.ensureDirectory(
        r'Z:\Profiles\Tester\AppData\Local\CloudOS\Drive',
      );

      expect(result.exists, isTrue);
      expect(result.isDirectory, isTrue);
      expect(
        bridge.created,
        <String>[
          r'Z:\Profiles\Tester\AppData',
          r'Z:\Profiles\Tester\AppData\Local',
          r'Z:\Profiles\Tester\AppData\Local\CloudOS',
          r'Z:\Profiles\Tester\AppData\Local\CloudOS\Drive',
        ],
      );
    });

    test('creates inside actual WSL UNC root without hardcoded distro', () async {
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{r'\\wsl.localhost\kali-linux'},
      );
      final service = BrokerFilesystemService(bridge);
      final result = await service.ensureDirectory(
        r'\\wsl.localhost\kali-linux\home\tester\repo',
      );

      expect(result.exists, isTrue);
      expect(bridge.created.first, r'\\wsl.localhost\kali-linux\home');
      expect(
        bridge.created.last,
        r'\\wsl.localhost\kali-linux\home\tester\repo',
      );
      expect(bridge.created.join(' '), isNot(contains('Ubuntu')));
    });
  });

  group('CloudOSDriveService V23', () {
    test('derives local Drive from Broker profile and does not add starter files', () async {
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{
          'Z:\\',
          r'Z:\Profiles',
          r'Z:\Profiles\Tester',
        },
      );
      final service = CloudOSDriveService(bridge);
      final snapshot = await service.load();

      expect(snapshot, isNotNull);
      expect(
        snapshot!.path,
        r'Z:\Profiles\Tester\AppData\Local\CloudOS\Drive',
      );
      expect(snapshot.items, isEmpty);
      expect(bridge.created.any((path) => path.endsWith(r'\Drive')), isTrue);
    });
  });

  group('ProjectFilesystemService V23', () {
    test('detects Flutter project from Broker listing', () async {
      const path = r'Z:\Work\CloudOS';
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{'Z:\\', r'Z:\Work', path},
        listings: <String, List<CloudFileItem>>{
          path: <CloudFileItem>[_fileItem(path, 'pubspec.yaml')],
        },
      );
      final service = ProjectFilesystemService(bridge);
      final snapshot = await service.inspect(path);

      expect(snapshot.available, isTrue);
      expect(snapshot.type, 'Flutter / Dart');
      expect(snapshot.modifiedAt, isNotNull);
    });

    test('reports missing project without fabricating availability', () async {
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{'Z:\\', r'Z:\Work'},
      );
      final service = ProjectFilesystemService(bridge);
      final snapshot = await service.inspect(r'Z:\Work\Missing');

      expect(snapshot.available, isFalse);
      expect(snapshot.type, 'Pasta indisponível');
    });

    test('prepare can create project path through Broker', () async {
      final bridge = _BrokerFsBridge(
        existingDirectories: <String>{'Z:\\', r'Z:\Work'},
      );
      final service = ProjectFilesystemService(bridge);
      final snapshot = await service.prepare(
        r'Z:\Work\NewProject',
        createIfMissing: true,
      );

      expect(snapshot.available, isTrue);
      expect(snapshot.path, r'Z:\Work\NewProject');
      expect(bridge.created, <String>[r'Z:\Work\NewProject']);
    });
  });
}
