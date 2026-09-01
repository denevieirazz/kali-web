import 'package:cloudos_flutter_shell/models/cloud_app.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/shell/cloudos_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorkspaceRecordingBridge extends CloudOSBridge {
  final List<int> requestedWorkspaces = <int>[];

  @override
  Future<List<CloudApp>> loadApps() async => CloudOSBridge.previewApps;

  @override
  Future<CloudSystemSnapshot> loadSystemSnapshot() async =>
      CloudOSBridge.previewSnapshot;

  @override
  Future<Map<String, bool>> loadShellSurfaceStates() async =>
      const <String, bool>{'browser': false, 'terminal': false};

  @override
  Future<int?> getCurrentWorkspace() async => 2;

  @override
  Future<bool> switchWorkspace(int workspace) async {
    requestedWorkspaces.add(workspace);
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
        case 'getCurrentWorkspace':
          return 3;
        case 'switchWorkspace':
          final args = call.arguments! as Map<Object?, Object?>;
          return args['workspace'];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('workspace query uses the typed NativeShell method', () async {
    const bridge = CloudOSBridge(channel: channel);

    final workspace = await bridge.getCurrentWorkspace();

    expect(workspace, 3);
    expect(calls.single.method, 'getCurrentWorkspace');
  });

  test('workspace switch forwards only a bounded 1..4 index', () async {
    const bridge = CloudOSBridge(channel: channel);

    final switched = await bridge.switchWorkspace(4);

    expect(switched, true);
    expect(calls.single.method, 'switchWorkspace');
    expect(calls.single.arguments, <String, Object?>{'workspace': 4});
  });

  test('workspace switch rejects out-of-range values before native IPC', () async {
    const bridge = CloudOSBridge(channel: channel);

    expect(await bridge.switchWorkspace(0), false);
    expect(await bridge.switchWorkspace(5), false);
    expect(calls, isEmpty);
  });

  testWidgets('taskbar workspace switch uses NativeShell authority', (tester) async {
    final bridge = _WorkspaceRecordingBridge();
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: CloudOSShell(bridge: bridge)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('Área de Trabalho 4 (Ctrl+Alt+4)'),
    );
    await tester.pumpAndSettle();

    expect(bridge.requestedWorkspaces, <int>[4]);
  });
}
