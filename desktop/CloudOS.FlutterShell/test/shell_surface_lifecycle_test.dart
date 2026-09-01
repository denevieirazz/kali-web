import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
          return <String, Object?>{
            'browser': true,
            'terminal': false,
          };
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

  test('surface state query returns native Browser and Terminal state', () async {
    const bridge = CloudOSBridge(channel: channel);

    final states = await bridge.loadShellSurfaceStates();

    expect(states['browser'], true);
    expect(states['terminal'], false);
    expect(calls.single.method, 'getShellSurfaceStates');
  });

  test('focus uses a typed allowlisted surface id', () async {
    const bridge = CloudOSBridge(channel: channel);

    final focused = await bridge.focusShellSurface('cloudos:browser');

    expect(focused, true);
    expect(calls.single.method, 'focusShellSurface');
    expect(
      calls.single.arguments,
      <String, Object?>{'id': 'cloudos:browser'},
    );
  });

  test('close uses a typed allowlisted surface id', () async {
    const bridge = CloudOSBridge(channel: channel);

    final closed = await bridge.closeShellSurface('cloudos:terminal');

    expect(closed, true);
    expect(calls.single.method, 'closeShellSurface');
    expect(
      calls.single.arguments,
      <String, Object?>{'id': 'cloudos:terminal'},
    );
  });
}