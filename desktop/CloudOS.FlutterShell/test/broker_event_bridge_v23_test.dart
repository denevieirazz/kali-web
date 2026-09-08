import 'package:cloudos_flutter_shell/services/broker_event_bridge_v23.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrokerEventBridgeV23 lifecycle', () {
    const channel = MethodChannel('cloudos/test/events/v23');
    late BrokerEventBridgeV23 bridge;
    var startCalls = 0;
    var stopCalls = 0;

    setUp(() {
      startCalls = 0;
      stopCalls = 0;
      bridge = BrokerEventBridgeV23.forTesting(channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'start':
            startCalls++;
            // First host negotiation fails; a correct bridge must allow retry.
            return startCalls > 1;
          case 'stop':
            stopCalls++;
            return true;
          case 'status':
            return <String, Object?>{
              'started': bridge.isStarted,
              'startCalls': startCalls,
            };
          default:
            return null;
        }
      });
    });

    tearDown(() async {
      await bridge.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('failed first start does not poison later native negotiation', () async {
      expect(await bridge.start(), isFalse);
      expect(bridge.isStarted, isFalse);
      expect(startCalls, 1);

      expect(await bridge.start(), isTrue);
      expect(bridge.isStarted, isTrue);
      expect(startCalls, 2);

      // Concurrent/repeated callers share the established attempt.
      expect(await bridge.start(), isTrue);
      expect(startCalls, 2);
    });

    test('stop clears lifecycle state and next start negotiates again', () async {
      expect(await bridge.start(), isFalse);
      expect(await bridge.start(), isTrue);
      expect(await bridge.stop(), isTrue);
      expect(bridge.isStarted, isFalse);
      expect(stopCalls, 1);

      expect(await bridge.start(), isTrue);
      expect(startCalls, 3);
      expect(bridge.isStarted, isTrue);
    });

    test('status remains a typed lifecycle-only native call', () async {
      expect(await bridge.start(), isFalse);
      expect(await bridge.start(), isTrue);
      final status = await bridge.status();
      expect(status['started'], isTrue);
      expect(status['startCalls'], 2);
    });
  });
}
