import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudOSBridge Recovery & Lifecycle V26 (Etapa 7 & 8)', () {
    const channel = MethodChannel('cloudos/native/v19.recovery-lifecycle-test');
    final bridge = CloudOSBridge(channel: channel);

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'broker.invokeRpc') {
          final args = call.arguments as Map;
          final rpcMethod = args['method'] as String;

          switch (rpcMethod) {
            case 'recovery.getStatus':
              return jsonEncode({
                'schema': 22,
                'state': 'HEALTHY',
                'reason': 'readiness and heartbeat healthy; process tree supervised',
                'transition_sequence': 3,
                'supervisor_pid': 19296,
                'shell_pid': 14768,
                'broker_pid': 26392,
                'session_id': 1,
                'failure_count': 0,
                'job_kill_on_close_assigned': true,
                'previous_unclean': false,
                'is_remote_session': false,
                'success': true,
              });

            case 'recovery.enterSafeMode':
              return jsonEncode({'success': true});

            case 'system.requestShutdown':
              return jsonEncode({'success': true});

            case 'system.getCapabilities':
              return jsonEncode({
                'capabilities': [
                  'display.listMonitors',
                  'audio.getEndpoints',
                  'system.getPowerStatus',
                  'recovery.getStatus',
                  'system.getCapabilities',
                ],
                'capability_map': {
                  'audio_control': true,
                  'brightness_control': true,
                  'wsl_runtime': true,
                  'economy_mode': false,
                  'rdp_session': false,
                  'multi_monitor': false,
                  'battery_present': false,
                  'bluetooth_available': true,
                  'wifi_available': true,
                },
                'success': true,
              });

            case 'performance.getMetrics':
              return jsonEncode({
                'profile': 'economy',
                'total_ram_mb': 16384,
                'free_ram_mb': 8192,
                'cpu_cores': 8,
                'memory_load_percent': 50,
                'is_low_end_hardware': false,
                'on_battery': true,
                'battery_percent': 75,
                'success': true,
              });

            case 'performance.setProfile':
              return jsonEncode({'success': true, 'profile': args['params']?['profile'] ?? 'economy'});

            default:
              return jsonEncode({'error': 'unsupported_method'});
          }
        }
        if (call.method == 'setPerformanceProfile') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getRecoveryStatus parses supervisor state and PID metadata correctly', () async {
      final status = await bridge.getRecoveryStatus();
      expect(status, isNotNull);
      expect(status!.schema, equals(22));
      expect(status.state, equals('HEALTHY'));
      expect(status.isHealthy, isTrue);
      expect(status.isSafeMode, isFalse);
      expect(status.isCrashLoop, isFalse);
      expect(status.supervisorPid, equals(19296));
      expect(status.shellPid, equals(14768));
      expect(status.brokerPid, equals(26392));
      expect(status.failureCount, equals(0));
      expect(status.jobKillOnCloseAssigned, isTrue);
      expect(status.previousUnclean, isFalse);
      expect(status.isRemoteSession, isFalse);
    });

    test('enterSafeMode requests transition and returns success', () async {
      final ok = await bridge.enterSafeMode();
      expect(ok, isTrue);
    });

    test('requestShutdown triggers orderly shutdown signal', () async {
      final ok = await bridge.requestShutdown();
      expect(ok, isTrue);
    });

    test('getSystemCapabilities parses capability list and capability map', () async {
      final caps = await bridge.getSystemCapabilities();
      expect(caps, isNotNull);
      expect(caps!.capabilities, contains('recovery.getStatus'));
      expect(caps.audioControl, isTrue);
      expect(caps.brightnessControl, isTrue);
      expect(caps.wslRuntime, isTrue);
      expect(caps.economyMode, isFalse);
      expect(caps.rdpSession, isFalse);
      expect(caps.bluetoothAvailable, isTrue);
    });

    test('getHardwareMetrics parses RAM, CPU and economy profile metrics', () async {
      final metrics = await bridge.getHardwareMetrics();
      expect(metrics, isNotNull);
      expect(metrics!.currentProfile, equals('economy'));
      expect(metrics.isEconomyProfile, isTrue);
      expect(metrics.totalRamMb, equals(16384));
      expect(metrics.freeRamMb, equals(8192));
      expect(metrics.cpuCores, equals(8));
      expect(metrics.onBattery, isTrue);
      expect(metrics.batteryPercent, equals(75));
    });

    test('setPerformanceProfile updates active profile successfully', () async {
      final ok = await bridge.setPerformanceProfile('economy');
      expect(ok, isTrue);
    });
  });
}
