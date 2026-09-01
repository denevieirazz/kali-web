import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native volume and brightness failures propagate as false', () async {
    const channel = MethodChannel('cloudos/native/v19.failure-test');
    const bridge = CloudOSBridge(channel: channel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setVolume' || call.method == 'setBrightness') {
        throw PlatformException(
          code: 'BROKER_WRITE_FAILED',
          message: 'System Broker rejected the write',
        );
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await bridge.setVolume(0.25), isFalse);
    expect(await bridge.setBrightness(0.55), isFalse);
  });

  test('native snapshot failure never falls back to healthy preview state', () async {
    const channel = MethodChannel('cloudos/native/v19.snapshot-failure-test');
    const bridge = CloudOSBridge(channel: channel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSystemSnapshot') {
        throw PlatformException(
          code: 'BROKER_UNAVAILABLE',
          message: 'System Broker is unavailable',
        );
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final snapshot = await bridge.loadSystemSnapshot();
    expect(snapshot, same(CloudOSBridge.degradedSnapshot));
    expect(snapshot.networkAvailable, isFalse);
    expect(snapshot.volumeAvailable, isFalse);
    expect(snapshot.brightnessAvailable, isFalse);
    expect(snapshot.batteryAvailable, isFalse);
    expect(snapshot.batteryPercent, 0);
    expect(snapshot.wslAvailable, isFalse);
    expect(snapshot.distros, isEmpty);
  });
}
