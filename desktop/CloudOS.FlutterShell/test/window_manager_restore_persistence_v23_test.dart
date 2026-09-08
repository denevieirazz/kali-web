import 'dart:io';

import 'package:cloudos_flutter_shell/services/session_service.dart';
import 'package:cloudos_flutter_shell/services/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowManager restored geometry durability', () {
    test('offscreen restored geometry is clamped and persisted once', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-geometry-restore-');
      try {
        final session = SessionService.forTesting(root);
        final manager = WindowManager(
          sessionService: session,
          persistenceDebounce: Duration.zero,
        );
        manager.restoreSavedWindows(
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'offscreen-files',
              'appId': 'cloudos:files',
              'title': 'Arquivos',
              'x': 9000.0,
              'y': 9000.0,
              'width': 5000.0,
              'height': 4000.0,
              'workspaceIndex': 2,
              'focused': true,
              'customParams': <String, dynamic>{'initialPath': 'home'},
            },
          ],
          2,
          const <String>['offscreen-files'],
        );

        final before = manager.windows.single;
        expect(before.x, 9000);
        expect(before.width, 5000);

        manager.ensureWithinBounds(const Size(1366, 768));
        final corrected = manager.windows.single;
        expect(corrected.x, lessThan(9000));
        expect(corrected.y, lessThan(9000));
        expect(corrected.width, lessThanOrEqualTo(1366));
        expect(corrected.height, lessThanOrEqualTo(720));

        // ensureWithinBounds queues an immediate write only when it actually
        // changes geometry. Draining the same SessionService proves the clamp
        // was not merely an in-memory presentation correction.
        await session.flush(requireSuccessfulWrite: true);
        final fresh = SessionService.forTesting(root);
        final snapshot = await fresh.loadSnapshot();
        expect(snapshot, isNotNull);
        expect(snapshot!.activeWorkspace, 2);
        expect(snapshot.windows, hasLength(1));
        expect(snapshot.windows.single.x, corrected.x);
        expect(snapshot.windows.single.y, corrected.y);
        expect(snapshot.windows.single.width, corrected.width);
        expect(snapshot.windows.single.height, corrected.height);
        expect(snapshot.windows.single.customParams['initialPath'], 'home');

        // Calling the clamp again with the same viewport must be stable.
        final firstSequence = snapshot.sequence;
        manager.ensureWithinBounds(const Size(1366, 768));
        await session.flush(requireSuccessfulWrite: true);
        final stable = await SessionService.forTesting(root).loadSnapshot();
        expect(stable, isNotNull);
        expect(stable!.sequence, firstSequence);

        manager.dispose();
        await session.flush();
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('strict manager flush surfaces a durable write failure', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-geometry-fail-');
      try {
        final blocker = File('${root.path}\\state-file');
        await blocker.writeAsString('not a directory', flush: true);
        final session = SessionService.forTesting(Directory(blocker.path));
        final manager = WindowManager(
          sessionService: session,
          persistenceDebounce: Duration.zero,
        );
        manager.openWindow('cloudos:files');

        await expectLater(
          manager.flushSession(requireSuccessfulWrite: true),
          throwsA(isA<Object>()),
        );
        expect(session.hasWriteFailure, isTrue);

        manager.dispose();
        await session.flush();
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  });
}
