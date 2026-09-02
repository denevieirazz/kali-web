import 'dart:convert';

import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/services/broker_event_bridge_v23.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/files_controller.dart';
import 'package:cloudos_flutter_shell/services/runtime_event_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FilesEventBridge extends CloudOSBridge {
  _FilesEventBridge({this.fallbackCompletes = false}) : super();

  final bool fallbackCompletes;
  final Map<String, int> listCalls = <String, int>{};
  int jobStatusCalls = 0;
  int copyCalls = 0;

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async {
    return const <KnownFolderModel>[
      KnownFolderModel(
        id: 'home',
        name: 'Início',
        path: r'Z:\Home',
        iconKey: 'home',
      ),
    ];
  }

  @override
  Future<List<DriveInfoModel>> getDrives() async => const <DriveInfoModel>[];

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
    listCalls[path] = (listCalls[path] ?? 0) + 1;
    return const <CloudFileItem>[];
  }

  @override
  Future<String?> copyItems(
    List<String> sources,
    String destination, {
    String overwritePolicy = 'ask',
  }) async {
    copyCalls++;
    return 'job-copy-1';
  }

  @override
  Future<Map<String, Object?>> getJobStatus(String jobId) async {
    jobStatusCalls++;
    return <String, Object?>{
      'jobId': jobId,
      'state': fallbackCompletes ? 'completed' : 'running',
      'progress': fallbackCompletes ? 100.0 : 25.0,
      'error': '',
    };
  }
}

NativeBrokerEventFrame _event(
  String name,
  Map<String, Object?> payload,
) {
  return NativeBrokerEventFrame(
    json: jsonEncode(<String, Object?>{
      'protocol': 21,
      'type': 'event',
      'event': name,
      'payload': payload,
      'timestamp': 1,
    }),
    droppedEvents: 0,
  );
}

Future<void> _settleController() async {
  await Future<void>.delayed(const Duration(milliseconds: 25));
}

void main() {
  group('FilesController EventBus V23', () {
    test('files.changed refreshes only the affected tab', () async {
      final runtime = RuntimeEventService();
      final bridge = _FilesEventBridge();
      final controller = FilesController(
        bridge: bridge,
        runtimeEventService: runtime,
      );
      await _settleController();

      controller.addTab(title: 'Outro', initialPath: r'Z:\Other');
      await _settleController();
      final homeTab = controller.tabs.first;
      final otherTab = controller.tabs.last;
      final homeBefore = bridge.listCalls[homeTab.currentPath] ?? 0;
      final otherBefore = bridge.listCalls[otherTab.currentPath] ?? 0;

      runtime.ingestForTesting(
        _event('files.changed', <String, Object?>{
          'action': 'created',
          'path': r'Z:\Home\nova.txt',
          'parentPath': r'Z:\Home',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(bridge.listCalls[homeTab.currentPath], homeBefore + 1);
      expect(bridge.listCalls[otherTab.currentPath], otherBefore);

      runtime.ingestForTesting(
        _event('files.changed', <String, Object?>{
          'action': 'copied',
          'destination': r'Z:\Unrelated',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(bridge.listCalls[homeTab.currentPath], homeBefore + 1);
      expect(bridge.listCalls[otherTab.currentPath], otherBefore);

      controller.dispose();
      runtime.dispose();
    });

    test('job events complete paste without jobs.status polling', () async {
      final runtime = RuntimeEventService();
      final bridge = _FilesEventBridge();
      final controller = FilesController(
        bridge: bridge,
        runtimeEventService: runtime,
      );
      await _settleController();

      controller.selectItem(r'Z:\Home\source.txt');
      controller.copySelected();
      final paste = controller.paste();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      runtime.ingestForTesting(
        _event('job.progress', const <String, Object?>{
          'jobId': 'job-copy-1',
          'progress': 64.0,
          'state': 'running',
        }),
      );
      expect(controller.activeJobProgress, 64);
      expect(controller.activeJobStatus, 'running');

      runtime.ingestForTesting(
        _event('job.completed', const <String, Object?>{
          'jobId': 'job-copy-1',
          'state': 'completed',
        }),
      );
      await paste;

      expect(bridge.copyCalls, 1);
      expect(bridge.jobStatusCalls, 0);
      expect(controller.hasActiveJob, isFalse);
      expect(controller.activeJobStatus, 'completed');
      expect(controller.activeJobProgress, 100);

      controller.dispose();
      runtime.dispose();
    });

    test('slow status fallback recovers a missed EventBus completion', () async {
      final runtime = RuntimeEventService();
      final bridge = _FilesEventBridge(fallbackCompletes: true);
      final controller = FilesController(
        bridge: bridge,
        runtimeEventService: runtime,
      );
      await _settleController();

      controller.selectItem(r'Z:\Home\source.txt');
      controller.copySelected();
      final stopwatch = Stopwatch()..start();
      await controller.paste();
      stopwatch.stop();

      expect(bridge.jobStatusCalls, 1);
      expect(controller.activeJobStatus, 'completed');
      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));

      controller.dispose();
      runtime.dispose();
    });

    test('unrelated job events never mutate the active Files job', () async {
      final runtime = RuntimeEventService();
      final bridge = _FilesEventBridge(fallbackCompletes: true);
      final controller = FilesController(
        bridge: bridge,
        runtimeEventService: runtime,
      );
      await _settleController();

      controller.selectItem(r'Z:\Home\source.txt');
      controller.copySelected();
      final paste = controller.paste();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      runtime.ingestForTesting(
        _event('job.failed', const <String, Object?>{
          'jobId': 'job-other',
          'state': 'failed',
          'error': 'not ours',
        }),
      );
      expect(controller.activeJobStatus, 'queued');

      await paste;
      expect(controller.activeJobStatus, 'completed');
      controller.dispose();
      runtime.dispose();
    });
  });
}
