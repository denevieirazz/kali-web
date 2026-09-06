import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/features/files/presentation/files_window.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';

class _MockAutonomyFilesBridge extends CloudOSBridge {
  const _MockAutonomyFilesBridge();

  @override
  Future<List<CloudFileItem>> loadFiles(String rootId) async {
    return const <CloudFileItem>[
      CloudFileItem(
        name: 'document.txt',
        path: r'C:\Users\test\document.txt',
        entryId: 'entry-doc-1',
        isFolder: false,
        sizeFormatted: '1.2 KB',
        modifiedFormatted: '06/09/2026',
        source: CloudFileSource.windows,
      ),
      CloudFileItem(
        name: 'Pictures',
        path: r'C:\Users\test\Pictures',
        entryId: 'entry-folder-1',
        isFolder: true,
        sizeFormatted: 'Pasta',
        modifiedFormatted: '06/09/2026',
        source: CloudFileSource.windows,
      ),
    ];
  }

  @override
  Future<List<CloudDriveInfo>> listDrives() async {
    return const <CloudDriveInfo>[];
  }
}

void main() {
  group('Flutter Autonomy V1 - Models & Contracts', () {
    test('AppLaunchStatus identifies containment block correctly', () {
      const blocked = AppLaunchStatus(
        id: 'windows:regedit',
        status: 'blocked',
        launched: false,
        platform: 'windows',
        target: 'regedit.exe',
        message: 'Aplicativo Win32 bloqueado por política de contenção.',
      );

      expect(blocked.isBlocked, isTrue);
      expect(blocked.isSuccess, isFalse);
      expect(blocked.launched, isFalse);

      const running = AppLaunchStatus(
        id: 'cloudos:notes',
        status: 'running',
        launched: true,
        platform: 'cloudos',
        target: 'cloudos:notes',
        message: 'Iniciado com sucesso',
      );

      expect(running.isBlocked, isFalse);
      expect(running.isSuccess, isTrue);
    });

    test('CloudDisplayMode exposes modeId, refreshRate, and canonicalId', () {
      const mode = CloudDisplayMode(
        width: 2560,
        height: 1440,
        frequency: 165,
        orientation: 0,
        bitsPerPel: 32,
        modeId: 'canonical_2560_1440_165',
        isRecommended: true,
      );

      expect(mode.modeId, 'canonical_2560_1440_165');
      expect(mode.refreshRate, 165);
      expect(mode.frequency, 165);
      expect(mode.canonicalId, 'canonical_2560_1440_165');
      expect(mode.isRecommended, isTrue);
    });

    test('CapabilityRegistry parses nested broker response correctly', () {
      final payload = <String, dynamic>{
        'display': <String, dynamic>{
          'id': 'display',
          'supported': true,
          'available': true,
          'enabled': true,
          'writable': true,
          'features': ['applyMode'],
        },
        'bluetooth': <String, dynamic>{
          'id': 'bluetooth',
          'supported': true,
          'available': true,
          'enabled': true,
          'writable': false,
          'reason': 'Modo somente leitura',
        },
      };

      final registry = CapabilityRegistry.fromMap(payload);
      expect(registry.isSupported('display'), isTrue);
      expect(registry.isWritable('display'), isTrue);
      expect(registry.isSupported('bluetooth'), isTrue);
      expect(registry.isWritable('bluetooth'), isFalse);
      expect(registry.get('bluetooth').reason, 'Modo somente leitura');
    });
  });

  group('Flutter Autonomy V1 - Files Window Open Contract', () {
    testWidgets('delegates non-folder open to onOpenFile callback', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      CloudFileItem? openedItem;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(
              bridge: const _MockAutonomyFilesBridge(),
              onOpenFile: (item) {
                openedItem = item;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('document.txt'), findsOneWidget);

      // Double tap on document.txt
      await tester.tap(find.text('document.txt'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('document.txt'));
      await tester.pumpAndSettle();

      expect(openedItem, isNotNull);
      expect(openedItem!.name, 'document.txt');
      expect(openedItem!.entryId, 'entry-doc-1');
    });
  });
}
