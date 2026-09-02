import 'dart:io';

import 'package:cloudos_flutter_shell/models/window_model.dart';
import 'package:cloudos_flutter_shell/services/session_service.dart';
import 'package:cloudos_flutter_shell/services/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _savedWindows(Map<String, dynamic> session) {
  final raw = session['windows'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _savedMru(Map<String, dynamic> session) {
  final raw = session['mruWindowIds'];
  return raw is List ? raw.whereType<String>().toList(growable: false) : const <String>[];
}

CloudWindow _window({
  required String id,
  required String initialPath,
  int workspace = 1,
}) {
  return CloudWindow(
    id: id,
    appId: 'cloudos:files',
    title: 'Arquivos',
    icon: Icons.folder_rounded,
    x: 120,
    y: 80,
    width: 900,
    height: 620,
    focused: true,
    workspaceIndex: workspace,
    customParams: <String, dynamic>{'initialPath': initialPath},
  );
}

void main() {
  group('Session V3 disk persistence', () {
    test('flush survives a fresh service and WindowManager instance', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-session-v23-');
      final writer = SessionService.forTesting(root);
      final firstManager = WindowManager(
        sessionService: writer,
        persistenceDebounce: Duration.zero,
      );

      try {
        firstManager.openWindow(
          'cloudos:files',
          params: const <String, dynamic>{'initialPath': r'D:\Evidence'},
        );
        firstManager.openWindow(
          'cloudos:terminal',
          params: const <String, dynamic>{
            'initialWorkingDirectory': r'D:\Work',
          },
        );

        final files = firstManager.windows.firstWhere(
          (window) => window.appId == 'cloudos:files',
        );
        firstManager.resizeWindow(
          files.id,
          910,
          610,
          const Size(1600, 900),
        );
        firstManager.moveWindowToWorkspace(files.id, 3);
        firstManager.setWorkspace(3);
        firstManager.focusWindow(files.id);
        await firstManager.flushSession();

        firstManager.dispose();
        await writer.flush();

        final reader = SessionService.forTesting(root);
        final session = await reader.loadSession();
        expect(session, isNotNull);
        expect(session!['schemaVersion'], SessionService.schemaVersion);
        expect(session['activeWorkspace'], 3);

        final restoredManager = WindowManager(
          sessionService: reader,
          persistenceDebounce: Duration.zero,
        );
        restoredManager.restoreSavedWindows(
          _savedWindows(session),
          session['activeWorkspace'] as int,
          _savedMru(session),
        );

        expect(restoredManager.activeWorkspace, 3);
        expect(restoredManager.windows, hasLength(2));
        final restoredFiles = restoredManager.windows.firstWhere(
          (window) => window.appId == 'cloudos:files',
        );
        expect(restoredFiles.workspaceIndex, 3);
        expect(restoredFiles.width, 910);
        expect(restoredFiles.height, 610);
        expect(restoredFiles.customParams['initialPath'], r'D:\Evidence');
        expect(restoredManager.focusedWindow?.id, restoredFiles.id);
        expect(restoredManager.mruWindowIds.first, restoredFiles.id);

        final restoredTerminal = restoredManager.windows.firstWhere(
          (window) => window.appId == 'cloudos:terminal',
        );
        expect(
          restoredTerminal.customParams['initialWorkingDirectory'],
          r'D:\Work',
        );

        restoredManager.dispose();
        await reader.flush();
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('corrupt primary recovers the last-known-good backup', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-session-recovery-');
      try {
        final writer = SessionService.forTesting(root);
        await writer.saveSession(
          windows: <CloudWindow>[
            _window(id: 'files-one', initialPath: r'D:\First'),
          ],
          activeWorkspace: 1,
          mruWindowIds: const <String>['files-one'],
        );
        await writer.flush();

        await writer.saveSession(
          windows: <CloudWindow>[
            _window(
              id: 'files-one',
              initialPath: r'D:\Second',
              workspace: 2,
            ),
          ],
          activeWorkspace: 2,
          mruWindowIds: const <String>['files-one'],
        );
        await writer.flush();

        final primary = File('${root.path}\\desktop_session.json');
        final backup = File('${root.path}\\desktop_session.json.bak');
        final temporary = File('${root.path}\\desktop_session.json.tmp');
        expect(await primary.exists(), isTrue);
        expect(await backup.exists(), isTrue);
        expect(await temporary.exists(), isFalse);

        await primary.writeAsString('{broken', flush: true);

        final recovery = SessionService.forTesting(root);
        final recovered = await recovery.loadSnapshot();
        expect(recovered, isNotNull);
        expect(recovered!.activeWorkspace, 1);
        expect(
          recovered.windows.single.customParams['initialPath'],
          r'D:\First',
        );

        // Recovery copies the known-good backup back to primary. A fresh
        // service must therefore read the restored primary without guessing.
        final verifier = SessionService.forTesting(root);
        final verified = await verifier.loadSnapshot();
        expect(verified, isNotNull);
        expect(verified!.activeWorkspace, 1);
        expect(
          verified.windows.single.customParams['initialPath'],
          r'D:\First',
        );
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  });
}
