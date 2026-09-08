import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/system_metrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MetricsBridge extends CloudOSBridge {
  _MetricsBridge(this.responses) : super();

  final List<Map<String, Object?>> responses;
  int calls = 0;

  @override
  Future<Map<String, Object?>> getSystemMetrics() async {
    calls++;
    if (responses.isEmpty) return const <String, Object?>{};
    return responses.removeAt(0);
  }
}

Map<String, Object?> _snapshot({
  double cpu = 37.5,
  double totalRam = 16384,
  double usedRam = 8192,
  String systemDrive = 'D:',
}) {
  return <String, Object?>{
    'cpuLoadPercent': cpu,
    'ramTotalMb': totalRam,
    'ramUsedMb': usedRam,
    'ramFreeMb': totalRam - usedRam,
    'uptimeSeconds': 3661,
    'systemDrive': systemDrive,
    'disks': <Object?>[
      <String, Object?>{
        'name': 'C:',
        'totalGb': 100.0,
        'usedGb': 10.0,
        'freeGb': 90.0,
        'percentUsed': 10.0,
      },
      <String, Object?>{
        'name': 'D:',
        'totalGb': 200.0,
        'usedGb': 150.0,
        'freeGb': 50.0,
        'percentUsed': 75.0,
      },
    ],
    'processes': <Object?>[
      <String, Object?>{
        'pid': 42,
        'name': 'cloudos_flutter_shell.exe',
        'memoryMb': 256.5,
        'cpuTimeSeconds': 12.3,
      },
      <String, Object?>{
        'pid': 0,
        'name': 'invalid.exe',
        'memoryMb': 999.0,
        'cpuTimeSeconds': 1.0,
      },
    ],
  };
}

void main() {
  group('RealSystemMetrics.tryParse', () {
    test('does not fabricate a live snapshot from empty/unknown payload', () {
      expect(RealSystemMetrics.tryParse(const <String, Object?>{}), isNull);
      expect(
        RealSystemMetrics.tryParse(const <String, Object?>{'unknown': 1}),
        isNull,
      );
    });

    test('clamps malformed numeric input and filters invalid processes', () {
      final parsed = RealSystemMetrics.tryParse(
        _snapshot(cpu: 170, totalRam: 1024, usedRam: 5000),
      );
      expect(parsed, isNotNull);
      expect(parsed!.isLive, isTrue);
      expect(parsed.cpuPercent, 100);
      expect(parsed.usedRamMb, 1024);
      expect(parsed.freeRamMb, 0);
      expect(parsed.activeProcesses, hasLength(1));
      expect(parsed.activeProcesses.single.pid, 42);
      expect(parsed.uptimeFormatted, '1h 1m');
    });

    test('system disk follows native systemDrive instead of first disk', () {
      final parsed = RealSystemMetrics.tryParse(_snapshot(systemDrive: 'D:'))!;
      expect(parsed.systemDisk?.name, 'D:');
      expect(parsed.totalDiskGb, 200);
      expect(parsed.usedDiskGb, 150);
      expect(parsed.diskUsagePercent, 75);
    });
  });

  group('SystemMetricsService', () {
    test('refresh uses the injected bridge and publishes native snapshot', () async {
      final bridge = _MetricsBridge(<Map<String, Object?>>[_snapshot(cpu: 22)]);
      final service = SystemMetricsService(
        bridge: bridge,
        enablePeriodicPolling: false,
      );
      final emitted = <RealSystemMetrics>[];
      final sub = service.metricsStream.listen(emitted.add);

      await service.refresh();

      expect(bridge.calls, 1);
      expect(service.current.isLive, isTrue);
      expect(service.current.cpuPercent, 22);
      expect(emitted, hasLength(1));
      await sub.cancel();
      service.dispose();
    });

    test('empty bridge response preserves last known-good metrics', () async {
      final bridge = _MetricsBridge(<Map<String, Object?>>[
        _snapshot(cpu: 55),
        const <String, Object?>{},
      ]);
      final service = SystemMetricsService(
        bridge: bridge,
        enablePeriodicPolling: false,
      );

      await service.refresh();
      expect(service.current.cpuPercent, 55);
      await service.refresh();
      expect(service.current.cpuPercent, 55);
      expect(service.current.isLive, isTrue);
      service.dispose();
    });

    test('start/stop reference count does not create hidden process-env gates', () async {
      final bridge = _MetricsBridge(<Map<String, Object?>>[_snapshot()]);
      final service = SystemMetricsService(
        bridge: bridge,
        enablePeriodicPolling: false,
      );

      service.start();
      service.start();
      await Future<void>.delayed(Duration.zero);
      expect(service.isRunning, isTrue);
      service.stop();
      expect(service.isRunning, isTrue);
      service.stop();
      expect(service.isRunning, isFalse);
      service.dispose();
    });
  });
}
