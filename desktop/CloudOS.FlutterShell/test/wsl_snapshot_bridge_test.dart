import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cloudos/test/wsl-snapshot');
  const bridge = CloudOSBridge(channel: channel);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps typed WSL engine and distro version evidence', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getSystemSnapshot');
          return <String, Object?>{
            'deviceName': 'CloudOS-Test',
            'networkAvailable': true,
            'networkName': 'Ethernet',
            'volumeAvailable': true,
            'volume': 0.5,
            'brightnessAvailable': false,
            'brightness': 0.0,
            'batteryAvailable': false,
            'batteryPercent': 0,
            'wslAvailable': true,
            'wslEngineAvailable': true,
            'distros': <String>['Ubuntu', 'kali-linux'],
            'defaultDistro': 'Ubuntu',
            'wslDistros': <Object?>[
              <String, Object?>{
                'name': 'Ubuntu',
                'versionKnown': true,
                'version': 2,
                'isDefault': true,
              },
              <String, Object?>{
                'name': 'kali-linux',
                'versionKnown': true,
                'version': 2,
                'isDefault': false,
              },
            ],
            'currentWorkspace': 1,
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslAvailable, isTrue);
    expect(snapshot.defaultDistro, 'Ubuntu');
    expect(snapshot.wslDistros, hasLength(2));
    expect(snapshot.wslDistros.first.name, 'Ubuntu');
    expect(snapshot.wslDistros.first.version, 2);
    expect(snapshot.wslDistros.first.isDefault, isTrue);
    expect(snapshot.wslDistros.last.name, 'kali-linux');
    expect(snapshot.wslDistros.last.version, 2);
  });

  test('keeps engine available when no distro is registered', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'deviceName': 'CloudOS-Test',
            'networkName': 'Ethernet',
            'volume': 0.0,
            'brightness': 0.0,
            'batteryPercent': 0,
            'wslAvailable': false,
            'wslEngineAvailable': true,
            'distros': <String>[],
            'wslDistros': <Object?>[],
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslAvailable, isFalse);
    expect(snapshot.distros, isEmpty);
    expect(snapshot.wslDistros, isEmpty);
  });

  test('legacy V21 distro list does not become synthetic WSL2 evidence', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'deviceName': 'CloudOS-Test',
            'networkName': 'Ethernet',
            'volume': 0.0,
            'brightness': 0.0,
            'batteryPercent': 0,
            'wslAvailable': true,
            'distros': <String>['Ubuntu'],
            'defaultDistro': 'Ubuntu',
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    // Old brokers have no separate engine field, so compatibility falls back
    // to the old usable signal. Version remains unknown.
    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslDistros, hasLength(1));
    expect(snapshot.wslDistros.single.name, 'Ubuntu');
    expect(snapshot.wslDistros.single.version, isNull);
    expect(snapshot.wslDistros.single.isDefault, isTrue);
  });

  test('ignores invalid version values instead of guessing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'deviceName': 'CloudOS-Test',
            'networkName': 'Ethernet',
            'volume': 0.0,
            'brightness': 0.0,
            'batteryPercent': 0,
            'wslAvailable': true,
            'wslEngineAvailable': true,
            'distros': <String>['OddLinux'],
            'wslDistros': <Object?>[
              <String, Object?>{
                'name': 'OddLinux',
                'versionKnown': false,
                'version': 99,
                'isDefault': false,
              },
            ],
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslDistros.single.version, isNull);
  });
}
