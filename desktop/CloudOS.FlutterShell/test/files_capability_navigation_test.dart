import 'package:cloudos_flutter_shell/features/files/presentation/files_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_file_item.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFilesBridge extends CloudOSBridge {
  final List<String> listedEntries = <String>[];
  final List<String> openedEntries = <String>[];

  @override
  Future<List<CloudFileItem>> loadFiles(String location) async =>
      const <CloudFileItem>[
        CloudFileItem(
          name: 'Pasta Segura',
          path: r'C:\Allowed\Folder',
          isFolder: true,
          sizeFormatted: 'Pasta',
          modifiedFormatted: '',
          source: CloudFileSource.windows,
          entryId: 'f21:folder-capability',
        ),
        CloudFileItem(
          name: 'arquivo.txt',
          path: r'C:\Allowed\arquivo.txt',
          isFolder: false,
          sizeFormatted: '1 KB',
          modifiedFormatted: '2026-09-01 10:00',
          source: CloudFileSource.windows,
          entryId: 'f21:file-capability',
        ),
      ];

  @override
  Future<List<CloudFileItem>> loadFilesEntry(String entryId) async {
    listedEntries.add(entryId);
    return const <CloudFileItem>[
      CloudFileItem(
        name: 'interno.txt',
        path: r'C:\Allowed\Folder\interno.txt',
        isFolder: false,
        sizeFormatted: '2 KB',
        modifiedFormatted: '2026-09-01 10:01',
        source: CloudFileSource.windows,
        entryId: 'f21:nested-file-capability',
      ),
    ];
  }

  @override
  Future<bool> openFileEntry(String entryId) async {
    openedEntries.add(entryId);
    return true;
  }
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 40));
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cloudos/native/v19');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getFiles':
          return <Map<String, Object?>>[
            <String, Object?>{
              'name': 'Documentos',
              'path': r'C:\Users\test\Documents',
              'isFolder': true,
              'sizeFormatted': 'Pasta',
              'modifiedFormatted': '',
              'source': 'windows',
              'extension': '',
              'entryId': 'f21:root-folder',
            },
          ];
        case 'getFilesEntry':
          return <Map<String, Object?>>[
            <String, Object?>{
              'name': 'readme.txt',
              'path': r'C:\Users\test\Documents\readme.txt',
              'isFolder': false,
              'sizeFormatted': '1 KB',
              'modifiedFormatted': '2026-09-01 10:00',
              'source': 'windows',
              'extension': 'txt',
              'entryId': 'f21:nested-file',
            },
          ];
        case 'openFileEntry':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Files list maps opaque entryId from native response', () async {
    const bridge = CloudOSBridge(channel: channel);
    final files = await bridge.loadFiles('documents');

    expect(files.single.entryId, 'f21:root-folder');
    expect(calls.single.method, 'getFiles');
    expect(calls.single.arguments, <String, Object?>{'location': 'documents'});
  });

  test('nested list sends only opaque entryId capability', () async {
    const bridge = CloudOSBridge(channel: channel);
    final files = await bridge.loadFilesEntry('f21:root-folder');

    expect(files.single.entryId, 'f21:nested-file');
    expect(calls.single.method, 'getFilesEntry');
    expect(calls.single.arguments, <String, Object?>{'entryId': 'f21:root-folder'});
    expect((calls.single.arguments as Map<Object?, Object?>).containsKey('path'), false);
  });

  test('file open sends only opaque entryId capability', () async {
    const bridge = CloudOSBridge(channel: channel);
    final opened = await bridge.openFileEntry('f21:nested-file');

    expect(opened, true);
    expect(calls.single.method, 'openFileEntry');
    expect(calls.single.arguments, <String, Object?>{'entryId': 'f21:nested-file'});
    expect((calls.single.arguments as Map<Object?, Object?>).containsKey('path'), false);
  });

  testWidgets('double-clicking folder navigates through its capability', (tester) async {
    final bridge = _RecordingFilesBridge();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilesWindow(
            bridge: bridge,
            onClose: () {},
            onMinimize: () {},
            onDrag: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _doubleTap(tester, find.text('Pasta Segura'));
    await tester.pumpAndSettle();

    expect(bridge.listedEntries, <String>['f21:folder-capability']);
    expect(find.text('interno.txt'), findsOneWidget);
  });

  testWidgets('double-clicking file opens only its capability', (tester) async {
    final bridge = _RecordingFilesBridge();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilesWindow(
            bridge: bridge,
            onClose: () {},
            onMinimize: () {},
            onDrag: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _doubleTap(tester, find.text('arquivo.txt'));
    await tester.pumpAndSettle();

    expect(bridge.openedEntries, <String>['f21:file-capability']);
    expect(bridge.listedEntries, isEmpty);
  });
}
