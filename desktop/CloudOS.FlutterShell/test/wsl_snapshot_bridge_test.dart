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

  test('maps complete typed WSL passive runtime evidence', () async {
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
            'wslPassiveReady': true,
            'distros': <String>['Ubuntu', 'kali-linux'],
            'defaultDistro': 'Ubuntu',
            'preferredSecurityDistro': 'kali-linux',
            'wslRegisteredCount': 2,
            'wslLaunchCandidateCount': 2,
            'wsl1Count': 0,
            'wsl2Count': 2,
            'wslDistros': <Object?>[
              <String, Object?>{
                'name': 'Ubuntu',
                'version': 2,
                'isDefault': true,
                'basePathPresent': true,
                'securityCandidate': false,
              },
              <String, Object?>{
                'name': 'kali-linux',
                'version': 2,
                'isDefault': false,
                'basePathPresent': true,
                'securityCandidate': true,
              },
            ],
            'currentWorkspace': 1,
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslAvailable, isTrue);
    expect(snapshot.wslPassiveReady, isTrue);
    expect(snapshot.passiveReady, isTrue);
    expect(snapshot.defaultDistro, 'Ubuntu');
    expect(snapshot.preferredSecurityDistro, 'kali-linux');
    expect(snapshot.effectiveRegisteredCount, 2);
    expect(snapshot.effectiveLaunchCandidateCount, 2);
    expect(snapshot.effectiveWsl1Count, 0);
    expect(snapshot.effectiveWsl2Count, 2);
    expect(snapshot.wslDistros, hasLength(2));

    final ubuntu = snapshot.distroInfo('ubuntu')!;
    expect(ubuntu.version, 2);
    expect(ubuntu.isDefault, isTrue);
    expect(ubuntu.basePathPresent, isTrue);
    expect(ubuntu.securityCandidate, isFalse);

    final kali = snapshot.distroInfo('KALI-LINUX')!;
    expect(kali.version, 2);
    expect(kali.storagePresent, isTrue);
    expect(kali.isSecurityCandidate, isTrue);
    expect(snapshot.distroVersions['kali-linux'], 2);
    expect(snapshot.distroStorageEvidence['kali-linux'], isTrue);
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
            'wslPassiveReady': false,
            'distros': <String>[],
            'wslDistros': <Object?>[],
            'wslRegisteredCount': 0,
            'wslLaunchCandidateCount': 0,
            'wsl1Count': 0,
            'wsl2Count': 0,
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslAvailable, isFalse);
    expect(snapshot.passiveReady, isFalse);
    expect(snapshot.distros, isEmpty);
    expect(snapshot.wslDistros, isEmpty);
    expect(snapshot.effectiveRegisteredCount, 0);
  });

  test('legacy V21 inventory remains unknown instead of synthetic WSL2', () async {
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

    expect(snapshot.wslEngineAvailable, isTrue);
    expect(snapshot.wslPassiveReady, isNull);
    expect(snapshot.effectiveLaunchCandidateCount, isNull);
    expect(snapshot.wslDistros, hasLength(1));
    expect(snapshot.wslDistros.single.name, 'Ubuntu');
    expect(snapshot.wslDistros.single.version, isNull);
    expect(snapshot.wslDistros.single.basePathPresent, isNull);
    expect(snapshot.wslDistros.single.securityCandidate, isNull);
    expect(snapshot.wslDistros.single.isDefault, isTrue);
  });

  test('does not coerce explicit missing BasePath into readiness', () async {
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
            'wslPassiveReady': false,
            'distros': <String>['Ubuntu'],
            'defaultDistro': 'Ubuntu',
            'wslRegisteredCount': 1,
            'wslLaunchCandidateCount': 0,
            'wslDistros': <Object?>[
              <String, Object?>{
                'name': 'Ubuntu',
                'version': 2,
                'isDefault': true,
                'basePathPresent': false,
                'securityCandidate': false,
              },
            ],
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.passiveReady, isFalse);
    expect(snapshot.effectiveLaunchCandidateCount, 0);
    expect(snapshot.distroStorageEvidence['Ubuntu'], isFalse);
    expect(snapshot.distroInfo('Ubuntu')!.storagePresent, isFalse);
  });

  test('ignores impossible version values instead of guessing', () async {
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
                'version': 99,
                'isDefault': false,
                'basePathPresent': true,
              },
            ],
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslDistros.single.version, isNull);
    expect(snapshot.wslDistros.single.basePathPresent, isTrue);
    expect(snapshot.wslVersion2Available, isFalse);
  });

  test('deduplicates typed distro names case-insensitively', () async {
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
            'distros': <String>['Ubuntu'],
            'wslDistros': <Object?>[
              <String, Object?>{
                'name': 'Ubuntu',
                'version': 2,
                'basePathPresent': true,
              },
              <String, Object?>{
                'name': 'ubuntu',
                'version': 1,
                'basePathPresent': false,
              },
            ],
          };
        });

    final snapshot = await bridge.loadSystemSnapshot();

    expect(snapshot.wslDistros, hasLength(1));
    expect(snapshot.wslDistros.single.name, 'Ubuntu');
    expect(snapshot.wslDistros.single.version, 2);
  });
}
