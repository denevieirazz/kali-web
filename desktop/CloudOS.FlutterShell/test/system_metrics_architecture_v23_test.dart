import 'dart:io';

import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/system_metrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MetricsBridge extends CloudOSBridge {
  _MetricsBridge(this.payload);

  final Map<String, Object?> payload;
  int calls = 0;

  @override
  Future<Map<String, Object?>> getSystemMetrics() async {
    calls++;
    return payload;
  }
}

void main() {
  group('System metrics V23 architecture', () {
    test('service has no process-environment test bypass', () {
      final source = File('lib/services/system_metrics_service.dart').readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('Platform.environment')));
      expect(source, contains('bool enablePeriodicPolling = true'));
      expect(source, contains('Future<void> refresh()'));
    });

    test('SystemMonitor binds metrics to the window bridge, not a global bridge', () {
      final source = File('lib/widgets/system_monitor_window.dart').readAsStringSync();
      expect(source, contains('bridge: widget.bridge'));
      expect(source, contains('enablePeriodicPolling: widget.enablePeriodicPolling'));
      expect(source, isNot(contains('SystemMetricsService.instance.start()')));
      expect(source, isNot(contains('SystemMetricsService.instance.stop()')));
    });

    test('injected bridge drives a one-shot deterministic refresh', () async {
      final bridge = _MetricsBridge(<String, Object?>{
        'cpuLoadPercent': 37.5,
        'ramTotalMb': 16384.0,
        'ramUsedMb': 4096.0,
        'ramFreeMb': 12288.0,
        'systemDrive': 'Z:',
        'uptimeSeconds': 3723,
        'disks': <Object?>[
          <String, Object?>{
            'name': 'Z:',
            'totalGb': 100.0,
            'usedGb': 25.0,
            'freeGb': 75.0,
            'percentUsed': 25.0,
          },
        ],
        'processes': <Object?>[
          <String, Object?>{
            'pid': 4242,
            'name': 'cloudos_flutter_shell.exe',
            'memoryMb': 123.4,
            'cpuTimeSeconds': 5.5,
          },
        ],
      });
      final service = SystemMetricsService(
        bridge: bridge,
        enablePeriodicPolling: false,
      );

      service.start();
      await service.refresh();

      expect(bridge.calls, greaterThanOrEqualTo(1));
      expect(service.current.isLive, isTrue);
      expect(service.current.cpuPercent, 37.5);
      expect(service.current.totalRamMb, 16384.0);
      expect(service.current.systemDrive, 'Z:');
      expect(service.current.systemDisk?.percentUsed, 25.0);
      expect(service.current.activeProcesses.single.pid, 4242);
      expect(service.current.uptimeFormatted, '1h 2m');

      service.dispose();
    });

    test('malformed and impossible values are clamped or rejected', () {
      final parsed = RealSystemMetrics.tryParse(<String, Object?>{
        'cpuLoadPercent': 999,
        'ramTotalMb': 100,
        'ramUsedMb': 200,
        'ramFreeMb': -5,
        'uptimeSeconds': -1,
        'systemDrive': 'X:',
        'disks': <Object?>[
          <String, Object?>{
            'name': 'X:',
            'totalGb': 20,
            'usedGb': 99,
            'freeGb': -1,
            'percentUsed': 400,
          },
          <String, Object?>{
            'name': '',
            'totalGb': 0,
          },
        ],
        'processes': <Object?>[
          <String, Object?>{'pid': 0, 'name': 'invalid'},
          <String, Object?>{'pid': 7, 'name': ''},
        ],
      });

      expect(parsed, isNotNull);
      expect(parsed!.cpuPercent, 100);
      expect(parsed.usedRamMb, 100);
      expect(parsed.freeRamMb, 0);
      expect(parsed.uptimeSeconds, 0);
      expect(parsed.disks.single.usedGb, 20);
      expect(parsed.disks.single.freeGb, 0);
      expect(parsed.disks.single.percentUsed, 100);
      expect(parsed.activeProcesses, isEmpty);
    });

    test('empty native payload remains unavailable instead of fabricating metrics', () {
      expect(RealSystemMetrics.tryParse(const <String, Object?>{}), isNull);
      expect(RealSystemMetrics.initial.isLive, isFalse);
      expect(RealSystemMetrics.initial.disks, isEmpty);
      expect(RealSystemMetrics.initial.activeProcesses, isEmpty);
    });
  });
}
