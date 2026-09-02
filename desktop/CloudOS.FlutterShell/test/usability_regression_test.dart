import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart' hide CloudFileItem;
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/files_controller.dart';
import 'package:cloudos_flutter_shell/services/system_metrics_service.dart';
import 'package:cloudos_flutter_shell/services/window_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FilesBridge extends CloudOSBridge {
  _FilesBridge() : super();

  String? lastListedPath;

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async =>
      const <KnownFolderModel>[
        KnownFolderModel(
          id: 'home',
          name: 'Início',
          path: r'D:\Users\Tester',
          iconKey: 'home',
        ),
      ];

  @override
  Future<List<DriveInfoModel>> getDrives() async => const <DriveInfoModel>[
        DriveInfoModel(
          letter: 'D:',
          path: 'D:\\',
          label: 'Dados',
          filesystem: 'NTFS',
          totalBytes: 100,
          freeBytes: 50,
          totalFormatted: '100 B',
          freeFormatted: '50 B',
          isRemovable: false,
          isReady: true,
          driveType: 'fixed',
        ),
      ];

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
    lastListedPath = path;
    return const <CloudFileItem>[];
  }
}

void main() {
  group('CloudOS usability regressions', () {
    test('FilesController honors requested initialPath', () async {
      final bridge = _FilesBridge();
      final controller = FilesController(
        bridge: bridge,
        initialPath: r'D:\Work\CloudOS',
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.activeTab?.currentPath, r'D:\Work\CloudOS');
      expect(bridge.lastListedPath, r'D:\Work\CloudOS');
      controller.dispose();
    });

    test('WindowManager never creates fake external or unknown windows', () {
      final manager = WindowManager();

      manager.openWindow('windows:vscode');
      manager.openWindow('this-app-does-not-exist');
      expect(manager.windows, isEmpty);

      manager.openWindow(
        'cloudos:files',
        params: const <String, dynamic>{'initialPath': r'D:\Work'},
      );
      expect(manager.windows, hasLength(1));
      expect(manager.windows.single.appId, 'cloudos:files');
      expect(manager.windows.single.customParams['initialPath'], r'D:\Work');
      manager.dispose();
    });

    test('WindowManager preserves terminal working directory parameters', () {
      final manager = WindowManager();

      manager.openWindow(
        'cloudos:terminal',
        params: const <String, dynamic>{
          'initialWorkingDirectory': r'D:\Work\CloudOS',
        },
      );

      expect(manager.windows, hasLength(1));
      expect(manager.windows.single.appId, 'cloudos:terminal');
      expect(
        manager.windows.single.customParams['initialWorkingDirectory'],
        r'D:\Work\CloudOS',
      );
      manager.dispose();
    });

    test('WindowManager preserves selected WSL distro and directory parameters', () {
      final manager = WindowManager();

      manager.openWindow(
        'wsl:terminal',
        params: const <String, dynamic>{
          'initialDistro': 'kali-linux',
          'initialWorkingDirectory': '/home/cloudos/project',
        },
      );

      expect(manager.windows, hasLength(1));
      expect(manager.windows.single.appId, 'wsl:terminal');
      expect(
        manager.windows.single.customParams['initialDistro'],
        'kali-linux',
      );
      expect(
        manager.windows.single.customParams['initialWorkingDirectory'],
        '/home/cloudos/project',
      );
      manager.dispose();
    });

    test('WindowManager restores workspace context and custom parameters', () {
      final manager = WindowManager();
      manager.restoreSavedWindows(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'win_12_cloudos:files',
            'appId': 'cloudos:files',
            'title': 'Arquivos',
            'x': 42.0,
            'y': 30.0,
            'width': 900.0,
            'height': 610.0,
            'previousX': 100.0,
            'previousY': 80.0,
            'previousWidth': 820.0,
            'previousHeight': 560.0,
            'minimized': false,
            'maximized': true,
            'focused': true,
            'workspaceIndex': 2,
            'customParams': <String, dynamic>{
              'initialPath': r'D:\Evidence',
            },
          },
          <String, dynamic>{
            'id': 'win_13_windows:vscode',
            'appId': 'windows:vscode',
            'title': 'VS Code',
            'workspaceIndex': 2,
          },
        ],
        2,
      );

      expect(manager.activeWorkspace, 2);
      expect(manager.windows, hasLength(1));
      final restored = manager.windows.single;
      expect(restored.customParams['initialPath'], r'D:\Evidence');
      expect(restored.previousWidth, 820.0);
      expect(restored.maximized, isTrue);
      expect(restored.focused, isTrue);
      manager.dispose();
    });

    test('unavailable system capabilities default to false', () {
      const snapshot = CloudSystemSnapshot(
        deviceName: '',
        networkName: '',
        volume: 0,
        brightness: 0,
        batteryPercent: -1,
        wslAvailable: false,
        distros: <String>[],
      );

      expect(snapshot.batteryAvailable, isFalse);
      expect(snapshot.networkAvailable, isFalse);
      expect(snapshot.volumeAvailable, isFalse);
      expect(snapshot.brightnessAvailable, isFalse);
    });

    test('malformed drive payload does not fabricate C: or NTFS', () {
      final drive = DriveInfoModel.fromJson(const <String, Object?>{});
      expect(drive.letter, isEmpty);
      expect(drive.path, isEmpty);
      expect(drive.filesystem, isEmpty);
      expect(drive.isReady, isFalse);
      expect(drive.driveType, 'unknown');
    });

    test('system disk metrics follow systemDrive instead of first disk', () {
      const metrics = RealSystemMetrics(
        cpuPercent: 10,
        totalRamMb: 100,
        usedRamMb: 50,
        freeRamMb: 50,
        systemDrive: 'C:',
        disks: <DiskMetricItem>[
          DiskMetricItem(
            name: 'D:',
            totalGb: 1000,
            usedGb: 900,
            freeGb: 100,
            percentUsed: 90,
          ),
          DiskMetricItem(
            name: 'C:',
            totalGb: 500,
            usedGb: 125,
            freeGb: 375,
            percentUsed: 25,
          ),
        ],
        activeProcesses: <ProcessMetricItem>[],
        uptimeSeconds: 1,
        uptimeFormatted: '0m',
        isLive: true,
      );

      expect(metrics.systemDisk?.name, 'C:');
      expect(metrics.totalDiskGb, 500);
      expect(metrics.usedDiskGb, 125);
      expect(metrics.diskUsagePercent, 25);
    });
  });
}
