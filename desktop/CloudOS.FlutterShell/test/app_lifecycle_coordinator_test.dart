import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:cloudos_flutter_shell/models/window_model.dart';
import 'package:cloudos_flutter_shell/services/app_lifecycle_coordinator.dart';
import 'package:cloudos_flutter_shell/services/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CloudWindow _window(String id) {
  return CloudWindow(
    id: id,
    appId: 'cloudos:files',
    title: 'Arquivos',
    icon: Icons.folder_rounded,
    x: 80,
    y: 60,
    width: 900,
    height: 620,
    focused: true,
    workspaceIndex: 1,
    customParams: const <String, dynamic>{'initialPath': r'D:\Evidence'},
  );
}

void main() {
  group('AppLifecycleCoordinator', () {
    test('allows exit after queued Session V3 write is durable', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-exit-ok-');
      try {
        final session = SessionService.forTesting(root);
        await session.saveSession(
          windows: <CloudWindow>[_window('files-ok')],
          activeWorkspace: 1,
          mruWindowIds: const <String>['files-ok'],
        );

        final coordinator = AppLifecycleCoordinator(
          sessionService: session,
          exitQuiescence: Duration.zero,
        );
        final response = await coordinator.handleExitRequest();

        expect(response, AppExitResponse.exit);
        expect(session.hasWriteFailure, isFalse);
        expect(await File('${root.path}\\desktop_session.json').exists(), isTrue);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('cancels exit when durable session write failed', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-exit-fail-');
      try {
        final blocker = File('${root.path}\\not-a-directory');
        await blocker.writeAsString('block', flush: true);
        final session = SessionService.forTesting(Directory(blocker.path));

        await session.saveSession(
          windows: <CloudWindow>[_window('files-fail')],
          activeWorkspace: 1,
          mruWindowIds: const <String>['files-fail'],
        );
        expect(session.hasWriteFailure, isTrue);

        final coordinator = AppLifecycleCoordinator(
          sessionService: session,
          exitQuiescence: Duration.zero,
        );
        final response = await coordinator.handleExitRequest();

        expect(response, AppExitResponse.cancel);
        expect(session.hasWriteFailure, isTrue);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('coalesces simultaneous exit requests into one decision', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-exit-coalesce-');
      try {
        final session = SessionService.forTesting(root);
        await session.saveSession(
          windows: <CloudWindow>[_window('files-coalesce')],
          activeWorkspace: 1,
        );
        final coordinator = AppLifecycleCoordinator(
          sessionService: session,
          exitQuiescence: const Duration(milliseconds: 20),
        );

        final first = coordinator.handleExitRequest();
        final second = coordinator.handleExitRequest();
        expect(identical(first, second), isTrue);
        expect(await first, AppExitResponse.exit);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });
  });
}
