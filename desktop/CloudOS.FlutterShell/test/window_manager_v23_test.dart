import 'package:cloudos_flutter_shell/models/session_models.dart';
import 'package:cloudos_flutter_shell/models/window_model.dart';
import 'package:cloudos_flutter_shell/services/window_geometry.dart';
import 'package:cloudos_flutter_shell/services/window_manager.dart';
import 'package:cloudos_flutter_shell/services/window_mru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CloudWindow _window(
  String id, {
  String appId = 'cloudos:files',
  int workspace = 1,
  bool minimized = false,
  bool focused = false,
}) {
  return CloudWindow(
    id: id,
    appId: appId,
    title: id,
    icon: Icons.window,
    x: 100,
    y: 60,
    width: 800,
    height: 560,
    minimized: minimized,
    focused: focused,
    workspaceIndex: workspace,
  );
}

void main() {
  group('WindowGeometryEngine V23', () {
    const engine = WindowGeometryEngine();
    const viewport = Size(1600, 900);

    test('work area excludes CloudOS taskbar', () {
      expect(engine.workArea(viewport), const Size(1600, 852));
    });

    test('four quadrant snap geometries exactly partition work area', () {
      final topLeft = engine.geometryForSnap(
        target: WindowSnapTarget.topLeft,
        viewport: viewport,
      );
      final topRight = engine.geometryForSnap(
        target: WindowSnapTarget.topRight,
        viewport: viewport,
      );
      final bottomLeft = engine.geometryForSnap(
        target: WindowSnapTarget.bottomLeft,
        viewport: viewport,
      );
      final bottomRight = engine.geometryForSnap(
        target: WindowSnapTarget.bottomRight,
        viewport: viewport,
      );

      expect(topLeft.rect, const Rect.fromLTWH(0, 0, 800, 426));
      expect(topRight.rect, const Rect.fromLTWH(800, 0, 800, 426));
      expect(bottomLeft.rect, const Rect.fromLTWH(0, 426, 800, 426));
      expect(bottomRight.rect, const Rect.fromLTWH(800, 426, 800, 426));
    });

    test('left and right snap split work area without gap', () {
      final left = engine.geometryForSnap(
        target: WindowSnapTarget.left,
        viewport: viewport,
      );
      final right = engine.geometryForSnap(
        target: WindowSnapTarget.right,
        viewport: viewport,
      );
      expect(left.x, 0);
      expect(left.width, 800);
      expect(right.x, 800);
      expect(right.width, 800);
      expect(left.height, 852);
      expect(right.height, 852);
    });

    test('maximize covers work area, not taskbar', () {
      final maximized = engine.geometryForSnap(
        target: WindowSnapTarget.maximize,
        viewport: viewport,
      );
      expect(maximized.rect, const Rect.fromLTWH(0, 0, 1600, 852));
    });

    test('clamps corrupt and offscreen geometry safely', () {
      final clamped = engine.clampToViewport(
        geometry: const WindowGeometry(
          x: 9000,
          y: 9000,
          width: 4000,
          height: 3000,
        ),
        viewport: const Size(1366, 768),
        minWidth: 360,
        minHeight: 280,
      );
      expect(clamped.width, lessThanOrEqualTo(1366));
      expect(clamped.height, lessThanOrEqualTo(720));
      expect(clamped.x, lessThanOrEqualTo(1266));
      expect(clamped.y, lessThanOrEqualTo(680));
    });

    test('resize never escapes work area', () {
      final resized = engine.resizeFromBottomRight(
        geometry: const WindowGeometry(x: 1000, y: 500, width: 500, height: 500),
        requestedWidth: 2000,
        requestedHeight: 2000,
        viewport: viewport,
        minWidth: 360,
        minHeight: 280,
      );
      expect(resized.width, 600);
      expect(resized.height, 352);
    });

    test('move keeps title bar reachable', () {
      final moved = engine.moveBy(
        geometry: const WindowGeometry(x: 20, y: 20, width: 900, height: 600),
        delta: const Offset(5000, 5000),
        viewport: viewport,
      );
      expect(moved.x, 1500);
      expect(moved.y, 812);
    });

    test('detects top maximize and side targets', () {
      expect(
        engine.detectSnapTarget(
          geometry: const WindowGeometry(x: 400, y: 0, width: 700, height: 500),
          viewport: viewport,
        ),
        WindowSnapTarget.maximize,
      );
      expect(
        engine.detectSnapTarget(
          geometry: const WindowGeometry(x: 0, y: 200, width: 700, height: 500),
          viewport: viewport,
        ),
        WindowSnapTarget.left,
      );
      expect(
        engine.detectSnapTarget(
          geometry: const WindowGeometry(x: 900, y: 200, width: 700, height: 500),
          viewport: viewport,
        ),
        WindowSnapTarget.right,
      );
    });

    test('detects upper corners before generic top edge', () {
      expect(
        engine.detectSnapTarget(
          geometry: const WindowGeometry(x: 0, y: 0, width: 600, height: 420),
          viewport: viewport,
        ),
        WindowSnapTarget.topLeft,
      );
      expect(
        engine.detectSnapTarget(
          geometry: const WindowGeometry(x: 1000, y: 0, width: 600, height: 420),
          viewport: viewport,
        ),
        WindowSnapTarget.topRight,
      );
    });
  });

  group('WindowMruTracker V23', () {
    test('touch maintains unique most-recent-first order', () {
      final mru = WindowMruTracker();
      mru.touch('a');
      mru.touch('b');
      mru.touch('c');
      mru.touch('a');
      expect(mru.ids, <String>['a', 'c', 'b']);
    });

    test('workspace ordering includes minimized windows', () {
      final mru = WindowMruTracker();
      final windows = <CloudWindow>[
        _window('a', minimized: true),
        _window('b'),
        _window('c', workspace: 2),
      ];
      mru.restore(<String>['a', 'b', 'c'], windows);
      expect(
        mru.orderedForWorkspace(windows, 1).map((window) => window.id),
        <String>['a', 'b'],
      );
    });

    test('next cycles forward and backward deterministically', () {
      final mru = WindowMruTracker();
      final windows = <CloudWindow>[_window('a'), _window('b'), _window('c')];
      mru.restore(<String>['c', 'b', 'a'], windows);
      expect(
        mru.next(windows: windows, workspace: 1, currentId: 'c'),
        'b',
      );
      expect(
        mru.next(
          windows: windows,
          workspace: 1,
          currentId: 'c',
          forward: false,
        ),
        'a',
      );
    });

    test('retain removes closed IDs', () {
      final mru = WindowMruTracker();
      mru.touch('a');
      mru.touch('b');
      mru.retain(<String>{'a'});
      expect(mru.ids, <String>['a']);
    });
  });

  group('SessionSnapshot V3', () {
    test('sanitizes custom parameters to JSON-safe data', () {
      final safe = sanitizeSessionParams(<String, dynamic>{
        'path': r'D:\Work',
        'number': 42,
        'enabled': true,
        'list': <Object?>['a', 2, false, null],
        'map': <String, Object?>{'x': 1, 'y': 'two'},
        'unsafe': Object(),
      });
      expect(safe['path'], r'D:\Work');
      expect(safe['list'], <Object?>['a', 2, false, null]);
      expect(safe['unsafe'], isNull);
    });

    test('round trips V3 snapshot with MRU', () {
      final source = SessionSnapshot(
        schemaVersion: 3,
        savedAt: DateTime.utc(2026, 9, 2),
        activeWorkspace: 3,
        windows: <SessionWindowRecord>[
          SessionWindowRecord.fromWindow(
            _window('a', focused: true),
            const <String, Object?>{'initialPath': r'D:\Evidence'},
          ),
          SessionWindowRecord.fromWindow(
            _window('b', appId: 'cloudos:terminal', workspace: 3),
            const <String, Object?>{
              'initialWorkingDirectory': r'D:\Work',
            },
          ),
        ],
        mruWindowIds: const <String>['b', 'a'],
        sequence: 9,
      );
      final decoded = SessionSnapshot.fromJson(
        source.toJson(),
        supportedSchema: 3,
      );
      expect(decoded, isNotNull);
      expect(decoded!.activeWorkspace, 3);
      expect(decoded.sequence, 9);
      expect(decoded.mruWindowIds, <String>['b', 'a']);
      expect(decoded.windows.first.customParams['initialPath'], r'D:\Evidence');
    });

    test('rejects future schema instead of guessing', () {
      final decoded = SessionSnapshot.fromJson(
        <String, Object?>{
          'schemaVersion': 99,
          'activeWorkspace': 1,
          'windows': const <Object?>[],
        },
        supportedSchema: 3,
      );
      expect(decoded, isNull);
    });

    test('deduplicates duplicate window IDs on restore', () {
      final decoded = SessionSnapshot.fromJson(
        <String, Object?>{
          'schemaVersion': 3,
          'activeWorkspace': 1,
          'windows': <Object?>[
            <String, Object?>{'id': 'same', 'appId': 'cloudos:files'},
            <String, Object?>{'id': 'same', 'appId': 'cloudos:terminal'},
          ],
        },
        supportedSchema: 3,
      );
      expect(decoded!.windows, hasLength(1));
    });
  });

  group('WindowManager V23 integration', () {
    test('singleton re-open merges typed params instead of ignoring them', () {
      final manager = WindowManager();
      manager.openWindow(
        'cloudos:settings',
        params: const <String, dynamic>{'initialSettingsPage': 'system'},
      );
      manager.openWindow(
        'cloudos:settings',
        params: const <String, dynamic>{'initialSettingsPage': 'sound'},
      );
      expect(manager.windows, hasLength(1));
      expect(
        manager.windows.single.customParams['initialSettingsPage'],
        'sound',
      );
      manager.dispose();
    });

    test('focus order updates MRU independently of app ID', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      manager.openWindow('cloudos:notepad');
      manager.openWindow('cloudos:browser');
      final files = manager.windows.firstWhere((window) => window.appId == 'cloudos:files');
      manager.focusWindow(files.id);
      expect(manager.mruWindowIds.first, files.id);
      expect(manager.altTabWindows.first.id, files.id);
      manager.dispose();
    });

    test('minimized window remains in AltTab MRU and focus restores it', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      manager.openWindow('cloudos:notepad');
      final files = manager.windows.firstWhere((window) => window.appId == 'cloudos:files');
      manager.minimizeWindow(files.id);
      expect(manager.altTabWindows.any((window) => window.id == files.id), isTrue);
      manager.focusWindow(files.id);
      expect(files.minimized, isFalse);
      expect(manager.focusedWindow?.id, files.id);
      manager.dispose();
    });

    test('quarter snap mutates real window geometry', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      final window = manager.windows.single;
      manager.snapWindowBottomRight(window.id, const Size(1600, 900));
      expect(window.x, 800);
      expect(window.y, 426);
      expect(window.width, 800);
      expect(window.height, 426);
      expect(window.maximized, isFalse);
      manager.dispose();
    });

    test('maximize restore preserves previous geometry', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      final window = manager.windows.single;
      final before = Rect.fromLTWH(window.x, window.y, window.width, window.height);
      manager.toggleMaximizeWindow(window.id, const Size(1600, 900));
      expect(window.maximized, isTrue);
      expect(window.width, 1600);
      expect(window.height, 852);
      manager.toggleMaximizeWindow(window.id, const Size(1600, 900));
      expect(window.maximized, isFalse);
      expect(Rect.fromLTWH(window.x, window.y, window.width, window.height), before);
      manager.dispose();
    });

    test('show desktop minimizes and restores only windows it changed', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      manager.openWindow('cloudos:notepad');
      final files = manager.windows.firstWhere((window) => window.appId == 'cloudos:files');
      final note = manager.windows.firstWhere((window) => window.appId == 'cloudos:notepad');
      manager.minimizeWindow(note.id);
      manager.toggleShowDesktop();
      expect(files.minimized, isTrue);
      expect(note.minimized, isTrue);
      manager.toggleShowDesktop();
      expect(files.minimized, isFalse);
      expect(note.minimized, isTrue);
      manager.dispose();
    });

    test('restore deduplicates singleton windows', () {
      final manager = WindowManager();
      manager.restoreSavedWindows(
        <Map<String, dynamic>>[
          <String, dynamic>{'id': 'one', 'appId': 'cloudos:settings'},
          <String, dynamic>{'id': 'two', 'appId': 'cloudos:settings'},
          <String, dynamic>{'id': 'three', 'appId': 'cloudos:files'},
        ],
        1,
      );
      expect(
        manager.windows.where((window) => window.appId == 'cloudos:settings'),
        hasLength(1),
      );
      manager.dispose();
    });

    test('workspace switch selects most recent visible window', () {
      final manager = WindowManager();
      manager.openWindow('cloudos:files');
      final files = manager.windows.single;
      manager.moveWindowToWorkspace(files.id, 2);
      manager.openWindow('cloudos:notepad');
      manager.setWorkspace(2);
      expect(manager.focusedWindow?.id, files.id);
      manager.dispose();
    });
  });
}
