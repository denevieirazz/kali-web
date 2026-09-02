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

    expect(await bridge.tryLoadSystemSnapshot(), isNull);

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

  test('transient native observation failures are nullable for polling', () async {
    const channel = MethodChannel('cloudos/native/v19.poll-failure-test');
    const bridge = CloudOSBridge(channel: channel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApps' ||
          call.method == 'getSystemSnapshot' ||
          call.method == 'getNotificationState' ||
          call.method == 'getShellSurfaceStates') {
        throw PlatformException(
          code: 'NATIVE_TEMPORARILY_UNAVAILABLE',
          message: 'Native authority missed one observation cycle',
        );
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await bridge.tryLoadApps(), isNull);
    expect(await bridge.tryLoadSystemSnapshot(), isNull);
    expect(await bridge.tryLoadNotificationState(), isNull);
    expect(await bridge.tryLoadShellSurfaceStates(), isNull);

    expect(await bridge.loadApps(), isEmpty);
    expect(await bridge.loadSystemSnapshot(), same(CloudOSBridge.degradedSnapshot));
    expect((await bridge.loadNotificationState()).items, isEmpty);
    expect(
      await bridge.loadShellSurfaceStates(),
      const <String, bool>{'browser': false, 'terminal': false},
    );
  });

  test('missing plugin remains explicit preview mode for observation probes', () async {
    const channel = MethodChannel('cloudos/native/v19.preview-probe-test');
    const bridge = CloudOSBridge(channel: channel);

    expect(await bridge.tryLoadApps(), CloudOSBridge.previewApps);
    expect(await bridge.tryLoadSystemSnapshot(), CloudOSBridge.previewSnapshot);
    expect(
      (await bridge.tryLoadNotificationState())?.items,
      CloudOSBridge.previewNotifications,
    );
    expect(
      await bridge.tryLoadShellSurfaceStates(),
      const <String, bool>{'browser': false, 'terminal': false},
    );
  });
}
