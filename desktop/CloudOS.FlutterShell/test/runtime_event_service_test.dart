import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/broker_event_bridge_v23.dart';
import '../lib/services/runtime_event_service.dart';

NativeBrokerEventFrame frame(
  String name, {
  Map<String, Object?> payload = const <String, Object?>{},
  int dropped = 0,
  int timestamp = 1000,
}) {
  return NativeBrokerEventFrame(
    json: jsonEncode(<String, Object?>{
      'protocol': 21,
      'type': 'event',
      'event': name,
      'payload': payload,
      'timestamp': timestamp,
    }),
    droppedEvents: dropped,
  );
}

void main() {
  group('BrokerRuntimeEvent.tryParse', () {
    test('parses a valid V21 event envelope', () {
      final parsed = BrokerRuntimeEvent.tryParse(
        frame(
          'files.changed',
          payload: const <String, Object?>{'path': r'C:\repo\a.txt'},
          timestamp: 42,
        ),
      );

      expect(parsed, isNotNull);
      expect(parsed!.name, 'files.changed');
      expect(parsed.payload['path'], r'C:\repo\a.txt');
      expect(parsed.timestampMs, 42);
    });

    test('rejects malformed and non-event frames', () {
      expect(
        BrokerRuntimeEvent.tryParse(
          const NativeBrokerEventFrame(
            json: '{broken',
            droppedEvents: 0,
          ),
        ),
        isNull,
      );
      expect(
        BrokerRuntimeEvent.tryParse(
          NativeBrokerEventFrame(
            json: jsonEncode(<String, Object?>{
              'protocol': 21,
              'type': 'response',
              'id': 'x',
              'ok': true,
            }),
            droppedEvents: 0,
          ),
        ),
        isNull,
      );
    });

    test('rejects empty and excessively long event names', () {
      expect(BrokerRuntimeEvent.tryParse(frame('')), isNull);
      final tooLong = List<String>.filled(257, 'x').join();
      expect(BrokerRuntimeEvent.tryParse(frame(tooLong)), isNull);
    });
  });

  group('RuntimeEventService', () {
    test('records invalid frames without fabricating notifications', () {
      final service = RuntimeEventService();
      service.ingestForTesting(
        const NativeBrokerEventFrame(
          json: 'not-json',
          droppedEvents: 0,
        ),
      );

      expect(service.invalidFrameCount, 1);
      expect(service.journal, isEmpty);
      expect(service.notifications, isEmpty);
      expect(service.unreadCount, 0);
      service.dispose();
    });

    test('valid event converges connection state to connected', () {
      final service = RuntimeEventService();
      expect(
        service.connectionState,
        RuntimeBrokerConnectionState.unavailable,
      );

      service.ingestForTesting(frame('files.changed'));

      expect(service.connectionState, RuntimeBrokerConnectionState.connected);
      expect(service.journal, hasLength(1));
      service.dispose();
    });

    test('job.completed produces one unread notification', () {
      final service = RuntimeEventService();
      service.ingestForTesting(
        frame(
          'job.completed',
          payload: const <String, Object?>{'jobId': 'job-12'},
        ),
      );

      expect(service.notifications, hasLength(1));
      expect(service.notifications.single.title, 'Operação concluída');
      expect(service.notifications.single.message, 'Job job-12');
      expect(service.unreadCount, 1);
      service.dispose();
    });

    test('job.failed uses broker error text when available', () {
      final service = RuntimeEventService();
      service.ingestForTesting(
        frame(
          'job.failed',
          payload: const <String, Object?>{
            'jobId': 'job-3',
            'error': 'destination_denied',
          },
        ),
      );

      expect(service.notifications, hasLength(1));
      expect(service.notifications.single.title, 'Operação falhou');
      expect(service.notifications.single.message, 'destination_denied');
      service.dispose();
    });

    test('job.cancelled produces cancellation notification', () {
      final service = RuntimeEventService();
      service.ingestForTesting(
        frame(
          'job.cancelled',
          payload: const <String, Object?>{'jobId': 'job-9'},
        ),
      );

      expect(service.notifications, hasLength(1));
      expect(service.notifications.single.title, 'Operação cancelada');
      expect(service.unreadCount, 1);
      service.dispose();
    });

    test('job.progress never creates notification spam', () {
      final service = RuntimeEventService();
      for (var i = 0; i < 100; i++) {
        service.ingestForTesting(
          frame(
            'job.progress',
            payload: <String, Object?>{
              'jobId': 'job-1',
              'progress': i.toDouble(),
            },
            timestamp: i,
          ),
        );
      }

      expect(service.journal, hasLength(100));
      expect(service.notifications, isEmpty);
      expect(service.unreadCount, 0);
      service.dispose();
    });

    test('journal is bounded to the newest 256 events', () {
      final service = RuntimeEventService();
      for (var i = 0; i < 400; i++) {
        service.ingestForTesting(
          frame(
            'files.changed',
            payload: <String, Object?>{'index': i},
            timestamp: i,
          ),
        );
      }

      expect(service.journal, hasLength(RuntimeEventService.maxJournalEntries));
      expect(service.journal.first.payload['index'], 144);
      expect(service.journal.last.payload['index'], 399);
      service.dispose();
    });

    test('notifications are bounded to newest 100 entries', () {
      final service = RuntimeEventService();
      for (var i = 0; i < 150; i++) {
        service.ingestForTesting(
          frame(
            'job.completed',
            payload: <String, Object?>{'jobId': 'job-$i'},
            timestamp: i,
          ),
        );
      }

      expect(
        service.notifications,
        hasLength(RuntimeEventService.maxNotifications),
      );
      expect(service.unreadCount, RuntimeEventService.maxNotifications);
      expect(service.notifications.first.message, 'Job job-149');
      expect(service.notifications.last.message, 'Job job-50');
      service.dispose();
    });

    test('native dropped count is monotonic', () {
      final service = RuntimeEventService();
      service.ingestForTesting(frame('files.changed', dropped: 5));
      service.ingestForTesting(frame('files.changed', dropped: 2));
      service.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(
          state: 'connected',
          droppedEvents: 9,
        ),
      );

      expect(service.nativeDroppedEventCount, 9);
      service.dispose();
    });

    test('disconnect and reconnect create truthful state notices', () {
      final service = RuntimeEventService();
      service.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(
          state: 'connected',
          droppedEvents: 0,
        ),
      );
      expect(service.notifications, isEmpty);

      service.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(
          state: 'disconnected',
          droppedEvents: 0,
        ),
      );
      expect(service.notifications, hasLength(1));
      expect(service.notifications.first.title, 'System Broker desconectado');

      service.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(
          state: 'connecting',
          droppedEvents: 0,
        ),
      );
      service.ingestConnectionForTesting(
        const NativeBrokerConnectionEvent(
          state: 'connected',
          droppedEvents: 0,
        ),
      );

      expect(service.notifications, hasLength(2));
      expect(service.notifications.first.title, 'System Broker reconectado');
      service.dispose();
    });

    test('mark read, dismiss and clear keep unread state coherent', () {
      final service = RuntimeEventService();
      service.ingestForTesting(
        frame(
          'job.completed',
          payload: const <String, Object?>{'jobId': 'job-a'},
        ),
      );
      service.ingestForTesting(
        frame(
          'job.cancelled',
          payload: const <String, Object?>{'jobId': 'job-b'},
        ),
      );
      expect(service.unreadCount, 2);

      service.markAllRead();
      expect(service.unreadCount, 0);
      expect(service.notifications, hasLength(2));

      final id = service.notifications.first.id;
      service.dismissNotification(id);
      expect(service.notifications, hasLength(1));

      service.clearNotifications();
      expect(service.notifications, isEmpty);
      expect(service.unreadCount, 0);
      service.dispose();
    });
  });
}
