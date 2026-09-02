import 'dart:async';

import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/broker_event_bridge_v23.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/runtime_event_service.dart';
import 'package:cloudos_flutter_shell/services/system_tray_state_service.dart';
import 'package:cloudos_flutter_shell/widgets/cloud_taskbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SystemBridgeFake extends CloudOSBridge {
  _SystemBridgeFake({
    required CloudSystemSnapshot initial,
    this.volumeWriteResult = true,
    this.brightnessWriteResult = false,
  }) : _snapshot = initial;

  CloudSystemSnapshot _snapshot;
  bool volumeWriteResult;
  bool brightnessWriteResult;
  int loads = 0;
  final List<double> volumeWrites = <double>[];
  final List<double> brightnessWrites = <double>[];

  set snapshot(CloudSystemSnapshot value) => _snapshot = value;

  @override
  Future<CloudSystemSnapshot> loadSystemSnapshot() async {
    loads++;
    return _snapshot;
  }

  @override
  Future<bool> setVolume(double value) async {
    volumeWrites.add(value);
    if (volumeWriteResult) {
      _snapshot = _snapshot.copyWith(volume: value, volumeAvailable: true);
    }
    return volumeWriteResult;
  }

  @override
  Future<bool> setBrightness(double value) async {
    brightnessWrites.add(value);
    if (brightnessWriteResult) {
      _snapshot = _snapshot.copyWith(
        brightness: value,
        brightnessAvailable: true,
      );
    }
    return brightnessWriteResult;
  }
}

CloudSystemSnapshot _snapshot({
  String device = 'DEVBOX',
  bool network = true,
  String networkName = 'Ethernet',
  bool volumeAvailable = true,
  double volume = 0.5,
  bool battery = true,
  int batteryPercent = 72,
  bool brightnessAvailable = false,
  double brightness = 0,
}) {
  return CloudSystemSnapshot(
    deviceName: device,
    networkName: networkName,
    volume: volume,
    brightness: brightness,
    batteryPercent: batteryPercent,
    wslAvailable: false,
    distros: const <String>[],
    batteryAvailable: battery,
    networkAvailable: network,
    volumeAvailable: volumeAvailable,
    brightnessAvailable: brightnessAvailable,
  );
}

RuntimeEventService _runtime() {
  return RuntimeEventService(
    nativeEvents: const Stream<NativeBrokerEventFrame>.empty(),
    nativeConnectionEvents:
        const Stream<NativeBrokerConnectionEvent>.empty(),
  );
}

void main() {
  group('CloudSystemSnapshot normalization', () {
    test('clamps untrusted numeric state and removes duplicate distros', () {
      const raw = CloudSystemSnapshot(
        deviceName: '  BOX  ',
        networkName: '  Wi-Fi  ',
        volume: 8,
        brightness: -5,
        batteryPercent: 900,
        wslAvailable: true,
        distros: <String>[' Kali ', 'kali', '', 'Ubuntu'],
        defaultDistro: ' Kali ',
        currentWorkspace: 99,
        batteryAvailable: true,
        networkAvailable: true,
        volumeAvailable: true,
        brightnessAvailable: true,
      );

      final normalized = raw.normalized();
      expect(normalized.deviceName, 'BOX');
      expect(normalized.networkName, 'Wi-Fi');
      expect(normalized.volume, 1);
      expect(normalized.brightness, 0);
      expect(normalized.batteryPercent, 100);
      expect(normalized.distros, <String>['Kali', 'Ubuntu']);
      expect(normalized.defaultDistro, 'Kali');
      expect(normalized.currentWorkspace, 0);
    });

    test('unavailable battery/network never carry fabricated values', () {
      final normalized = _snapshot(
        network: false,
        networkName: 'should disappear',
        battery: false,
        batteryPercent: 55,
      ).normalized();
      expect(normalized.networkName, isEmpty);
      expect(normalized.batteryPercent, -1);
    });
  });

  group('SystemTrayStateService', () {
    test('initial refresh loads the real bridge snapshot', () async {
      final runtime = _runtime();
      final bridge = _SystemBridgeFake(initial: _snapshot());
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
      );

      service.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.loads, 1);
      expect(service.snapshot.deviceName, 'DEVBOX');
      expect(service.snapshot.networkName, 'Ethernet');
      expect(service.lastRefreshAt, isNotNull);

      service.dispose();
      runtime.dispose();
    });

    test('volume event patches state without another snapshot RPC', () async {
      final runtime = _runtime();
      final bridge = _SystemBridgeFake(initial: _snapshot(volume: 0.25));
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
      );
      service.replaceSnapshotForTesting(_snapshot(volume: 0.25));

      service.ingestEventForTesting(
        const BrokerRuntimeEvent(
          name: 'system.volumeChanged',
          payload: <String, Object?>{'volume': 0.88},
          timestampMs: 1,
          rawJson: '{}',
          nativeDroppedEvents: 0,
        ),
      );

      expect(service.snapshot.volume, closeTo(0.88, 0.0001));
      expect(bridge.loads, 0);
      service.dispose();
      runtime.dispose();
    });

    test('snapshot invalidation debounces and refreshes once', () async {
      final runtime = _runtime();
      final bridge = _SystemBridgeFake(initial: _snapshot(device: 'A'));
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
        eventRefreshDebounce: const Duration(milliseconds: 1),
      );
      service.replaceSnapshotForTesting(_snapshot(device: 'OLD'));
      bridge.snapshot = _snapshot(device: 'NEW');

      const event = BrokerRuntimeEvent(
        name: 'system.snapshotChanged',
        payload: <String, Object?>{},
        timestampMs: 1,
        rawJson: '{}',
        nativeDroppedEvents: 0,
      );
      service.ingestEventForTesting(event);
      service.ingestEventForTesting(event);
      service.ingestEventForTesting(event);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bridge.loads, 1);
      expect(service.snapshot.deviceName, 'NEW');
      service.dispose();
      runtime.dispose();
    });

    test('successful volume mutation remains committed', () async {
      final runtime = _runtime();
      final bridge = _SystemBridgeFake(initial: _snapshot(volume: 0.2));
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
      );
      service.replaceSnapshotForTesting(_snapshot(volume: 0.2));

      expect(await service.setVolume(0.77), isTrue);
      expect(bridge.volumeWrites, <double>[0.77]);
      expect(service.snapshot.volume, closeTo(0.77, 0.0001));
      service.dispose();
      runtime.dispose();
    });

    test('failed volume mutation rolls optimistic state back', () async {
      final runtime = _runtime();
      final bridge = _SystemBridgeFake(
        initial: _snapshot(volume: 0.2),
        volumeWriteResult: false,
      );
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
      );
      service.replaceSnapshotForTesting(_snapshot(volume: 0.2));

      expect(await service.setVolume(0.9), isFalse);
      expect(service.snapshot.volume, closeTo(0.2, 0.0001));
      service.dispose();
      runtime.dispose();
    });

    test('reconnect refreshes snapshot through the bridge', () async {
      final events = StreamController<NativeBrokerEventFrame>.broadcast();
      final connections =
          StreamController<NativeBrokerConnectionEvent>.broadcast();
      final runtime = RuntimeEventService(
        nativeEvents: events.stream,
        nativeConnectionEvents: connections.stream,
      );
      final bridge = _SystemBridgeFake(initial: _snapshot(device: 'ONE'));
      final service = SystemTrayStateService(
        bridge: bridge,
        runtime: runtime,
        pollInterval: null,
      );
      service.start();
      await Future<void>.delayed(Duration.zero);
      final baselineLoads = bridge.loads;

      runtime.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(state: 'disconnected', droppedEvents: 0),
      );
      bridge.snapshot = _snapshot(device: 'TWO');
      runtime.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(state: 'connected', droppedEvents: 0),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.loads, greaterThan(baselineLoads));
      expect(service.snapshot.deviceName, 'TWO');

      service.dispose();
      runtime.dispose();
      await events.close();
      await connections.close();
    });
  });

  group('CloudTaskbar truthful tray', () {
    Widget host({
      required CloudSystemSnapshot snapshot,
      int? notifications,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: CloudTaskbar(
            onStart: () {},
            onFiles: () {},
            onQuickSettings: () {},
            onNotifications: () {},
            startOpen: false,
            quickSettingsOpen: false,
            notificationsOpen: false,
            systemSnapshot: snapshot,
            notificationCount: notifications,
          ),
        ),
      );
    }

    testWidgets('offline snapshot exposes offline network and no fake battery', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          snapshot: _snapshot(
            network: false,
            networkName: '',
            volumeAvailable: false,
            battery: false,
          ),
        ),
      );

      expect(find.byIcon(Icons.signal_wifi_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.battery_full_rounded), findsNothing);
      expect(find.byTooltip('Rede indisponível'), findsOneWidget);
      expect(find.byTooltip('Volume indisponível'), findsOneWidget);
    });

    testWidgets('live battery and volume are represented from snapshot values', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(snapshot: _snapshot(volume: 0.72, batteryPercent: 72)),
      );

      expect(find.byTooltip('Volume: 72%'), findsOneWidget);
      expect(find.byTooltip('Bateria: 72%'), findsOneWidget);
      expect(find.byTooltip('Rede: Ethernet'), findsOneWidget);
    });

    testWidgets('notification override caps badge at 99+', (tester) async {
      await tester.pumpWidget(host(snapshot: _snapshot(), notifications: 145));
      expect(find.text('99+'), findsOneWidget);
      expect(find.byTooltip('145 notificação(ões) não lida(s)'), findsOneWidget);
    });
  });
}
