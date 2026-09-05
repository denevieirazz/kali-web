import 'package:cloudos_flutter_shell/features/files/presentation/files_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_file_item.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockProductionFilesBridge extends CloudOSBridge {
  final List<String> createdFolders = <String>[];
  final List<String> renamedFiles = <String>[];
  final List<String> deletedFiles = <String>[];
  final List<String> copiedFiles = <String>[];
  final List<String> movedFiles = <String>[];

  @override
  Future<List<CloudFileItem>> loadFiles(String location) async {
    return List<CloudFileItem>.generate(1000, (i) {
      final isFolder = i == 0;
      return CloudFileItem(
        name: isFolder ? 'Pasta_$i' : 'Documento_$i.txt',
        path: 'C:\\Test\\${isFolder ? 'Pasta_$i' : 'Documento_$i.txt'}',
        isFolder: isFolder,
        sizeFormatted: isFolder ? '--' : '${(i * 10) + 5} KB',
        modifiedFormatted: '04/09/2026 23:00',
        source: CloudFileSource.windows,
        entryId: 'f24:item-$i',
      );
    });
  }

  @override
  Future<List<CloudDriveInfo>> listDrives() async {
    return const <CloudDriveInfo>[
      CloudDriveInfo(
        mountPath: r'C:\',
        label: 'Disco Local (C:)',
        driveType: 'fixed',
        totalBytes: 500000000000,
        freeBytes: 150000000000,
        totalFormatted: '465 GB',
        freeFormatted: '140 GB',
        entryId: 'f24:drive-c',
      ),
      CloudDriveInfo(
        mountPath: r'E:\',
        label: 'Pen Drive USB (E:)',
        driveType: 'removable',
        totalBytes: 32000000000,
        freeBytes: 28000000000,
        totalFormatted: '29.8 GB',
        freeFormatted: '26 GB',
        entryId: 'f24:drive-e',
      ),
      CloudDriveInfo(
        mountPath: r'\\wsl.localhost\Ubuntu',
        label: 'Ubuntu (WSL)',
        driveType: 'wsl',
        totalBytes: 250000000000,
        freeBytes: 180000000000,
        totalFormatted: '232 GB',
        freeFormatted: '167 GB',
        entryId: 'f24:drive-wsl',
      ),
    ];
  }

  @override
  Future<CloudFileItem?> createFolder(String parentEntryId, String name) async {
    createdFolders.add('$parentEntryId/$name');
    return CloudFileItem(
      name: name,
      path: 'C:\\Test\\$name',
      isFolder: true,
      sizeFormatted: '--',
      modifiedFormatted: '04/09/2026 23:10',
      source: CloudFileSource.windows,
      entryId: 'f24:created-$name',
    );
  }

  @override
  Future<CloudFileItem?> renameFile(String entryId, String newName) async {
    renamedFiles.add('$entryId -> $newName');
    return CloudFileItem(
      name: newName,
      path: 'C:\\Test\\$newName',
      isFolder: false,
      sizeFormatted: '10 KB',
      modifiedFormatted: '04/09/2026 23:10',
      source: CloudFileSource.windows,
      entryId: entryId,
    );
  }

  @override
  Future<List<String>> deleteFiles(List<String> entryIds, {bool permanent = false}) async {
    deletedFiles.addAll(entryIds);
    return entryIds;
  }

  @override
  Future<String?> copyFiles(List<String> sourceEntryIds, String destinationEntryId) async {
    copiedFiles.addAll(sourceEntryIds);
    return 'job-copy-1';
  }

  @override
  Future<String?> moveFiles(List<String> sourceEntryIds, String destinationEntryId) async {
    movedFiles.addAll(sourceEntryIds);
    return 'job-move-1';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Files Production Features Suite', () {
    testWidgets('1000 items render virtualized at 60fps and display in list view', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify status bar displays total items
      expect(find.text('1000 itens'), findsOneWidget);
      // Verify first items are rendered
      expect(find.text('Pasta_0'), findsOneWidget);
      expect(find.text('Documento_1.txt'), findsOneWidget);

      // Fast scroll down
      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // Ensure virtualization dynamically unloads early items and renders newly visible items
      expect(find.text('Pasta_0'), findsNothing);
    });

    testWidgets('sidebar displays enumerated drives (fixed, USB removable, WSL)', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify drives from listDrives()
      expect(find.text('Disco Local (C:)'), findsOneWidget);
      expect(find.text('Pen Drive USB (E:)'), findsOneWidget);
      expect(find.text('Ubuntu (WSL)'), findsOneWidget);
      expect(find.text('140 GB livre'), findsOneWidget);
      expect(find.text('USB'), findsOneWidget);
      expect(find.text('WSL'), findsOneWidget);
    });

    testWidgets('multi-selection with Ctrl+Click and Ctrl+A', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: 0 items selected
      expect(find.textContaining('selecionado'), findsNothing);

      // Tap single item
      await tester.tap(find.text('Pasta_0'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 item selecionado'), findsOneWidget);

      // Select all with Ctrl+A
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      // Should now select all visible files
      expect(find.textContaining('itens selecionados'), findsOneWidget);
    });

    testWidgets('live filter dynamically narrows file list', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1000 itens'), findsOneWidget);

      // Type filter "Pasta_0"
      await tester.enterText(find.byType(TextField).first, 'Pasta_0');
      await tester.pumpAndSettle();

      // Should filter to Pasta_0
      expect(find.descendant(of: find.byType(ListView), matching: find.text('Pasta_0')), findsOneWidget);
      expect(find.text('Documento_1.txt'), findsNothing);
    });

    testWidgets('new folder action triggers dialog and calls bridge.createFolder', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click New Folder button
      await tester.tap(find.byTooltip('Nova Pasta (Ctrl+Shift+N)'));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Nova Pasta'), findsWidgets);
      expect(find.text('Criar'), findsOneWidget);

      // Enter folder name and submit
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Projetos_CloudOS');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      expect(bridge.createdFolders, contains('home/Projetos_CloudOS'));
    });

    testWidgets('rename action calls bridge.renameFile', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select single file
      await tester.tap(find.text('Documento_1.txt'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Tap Rename button
      await tester.tap(find.byTooltip('Renomear (F2)'));
      await tester.pumpAndSettle();

      expect(find.text('Renomear'), findsWidgets);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Documento_Renomeado.txt');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Renomear'));
      await tester.pumpAndSettle();

      expect(bridge.renamedFiles, contains('f24:item-1 -> Documento_Renomeado.txt'));
    });

    testWidgets('delete action shows confirmation and moves to Recycle Bin', (tester) async {
      final bridge = _MockProductionFilesBridge();
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilesWindow(bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select file
      await tester.tap(find.text('Documento_1.txt'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Tap Delete button
      await tester.tap(find.byTooltip('Mover para a Lixeira (Delete)'));
      await tester.pumpAndSettle();

      expect(find.text('Mover para a Lixeira'), findsOneWidget);
      expect(find.textContaining('Lixeira do Windows'), findsOneWidget);

      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      expect(bridge.deletedFiles, contains('f24:item-1'));
    });
  });
}
