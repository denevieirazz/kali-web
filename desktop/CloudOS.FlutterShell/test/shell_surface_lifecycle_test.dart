import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/shell/cloudos_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingBridge extends CloudOSBridge {
  _RecordingBridge({required this.focusResult});

  final bool focusResult;
  final List<String> focusedIds = <String>[];
  final List<String> launchedIds = <String>[];

  @override
  Future<List<CloudApp>> loadApps() async => CloudOSBridge.previewApps;

  @override
  Future<CloudSystemSnapshot> loadSystemSnapshot() async =>
      CloudOSBridge.previewSnapshot;

  @override
  Future<Map<String, bool>> loadShellSurfaceStates() async =>
      const <String, bool>{'browser': false, 'terminal': false};

  @override
  Future<bool> focusShellSurface(String id) async {
    focusedIds.add(id);
    return focusResult;
  }

  @override
  Future<bool> launchApp(String id) async {
    launchedIds.add(id);
    return true;
  }
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
            case 'getShellSurfaceStates':
              return <String, Object?>{'browser': true, 'terminal': false};
            case 'focusShellSurface':
              return true;
            case 'closeShellSurface':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'surface state query returns native Browser and Terminal state',
    () async {
      const bridge = CloudOSBridge(channel: channel);

      final states = await bridge.loadShellSurfaceStates();

      expect(states['browser'], true);
      expect(states['terminal'], false);
      expect(calls.single.method, 'getShellSurfaceStates');
    },
  );

  test('focus uses a typed allowlisted surface id', () async {
    const bridge = CloudOSBridge(channel: channel);

    final focused = await bridge.focusShellSurface('cloudos:browser');

    expect(focused, true);
    expect(calls.single.method, 'focusShellSurface');
    expect(calls.single.arguments, <String, Object?>{'id': 'cloudos:browser'});
  });

  test('close uses a typed allowlisted surface id', () async {
    const bridge = CloudOSBridge(channel: channel);

    final closed = await bridge.closeShellSurface('cloudos:terminal');

    expect(closed, true);
    expect(calls.single.method, 'closeShellSurface');
    expect(calls.single.arguments, <String, Object?>{'id': 'cloudos:terminal'});
  });

  testWidgets('running Browser is focused instead of launched again', (
    tester,
  ) async {
    final bridge = _RecordingBridge(focusResult: true);
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: CloudOSShell(bridge: bridge)));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Navegador Web'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.focusedIds, <String>['cloudos:browser']);
    expect(bridge.launchedIds, isEmpty);
  });

  testWidgets('missing Browser surface falls back to typed launch', (
    tester,
  ) async {
    final bridge = _RecordingBridge(focusResult: false);
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: CloudOSShell(bridge: bridge)));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Navegador Web'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.focusedIds, <String>['cloudos:browser']);
    expect(bridge.launchedIds, <String>['cloudos:browser']);
  });

  testWidgets('Terminal uses the same focus-or-launch lifecycle', (
    tester,
  ) async {
    final bridge = _RecordingBridge(focusResult: true);
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: CloudOSShell(bridge: bridge)));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Terminal ConPTY (Ctrl+Alt+Enter)'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.focusedIds, <String>['cloudos:terminal']);
    expect(bridge.launchedIds, isEmpty);
  });
}
