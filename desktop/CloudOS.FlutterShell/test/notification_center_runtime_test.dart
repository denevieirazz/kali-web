import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/shell_models.dart';
import '../lib/services/broker_event_bridge_v23.dart';
import '../lib/services/runtime_event_service.dart';
import '../lib/widgets/notification_center.dart';

RuntimeEventService testRuntime() {
  return RuntimeEventService(
    nativeEvents: const Stream<NativeBrokerEventFrame>.empty(),
    nativeConnectionEvents:
        const Stream<NativeBrokerConnectionEvent>.empty(),
  );
}

NativeBrokerEventFrame jobCompleted(String id) {
  return NativeBrokerEventFrame(
    json: jsonEncode(<String, Object?>{
      'protocol': 21,
      'type': 'event',
      'event': 'job.completed',
      'payload': <String, Object?>{'jobId': id},
      'timestamp': 100,
    }),
    droppedEvents: 0,
  );
}

void main() {
  testWidgets('compatibility notifications still render', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NotificationCenter(
            initialNotifications: <CloudNotification>[
              CloudNotification(
                id: 'legacy-1',
                title: 'Compatível',
                message: 'Notificação fornecida pelo teste',
                time: '10:00',
                icon: Icons.info_outline,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Compatível'), findsOneWidget);
    expect(find.text('Notificação fornecida pelo teste'), findsOneWidget);
  });

  testWidgets('runtime mode renders real EventBus notification', (tester) async {
    final runtime = testRuntime();
    runtime.ingestForTesting(jobCompleted('job-77'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationCenter(runtimeService: runtime),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Centro de Notificações'), findsOneWidget);
    expect(find.text('Operação concluída'), findsOneWidget);
    expect(find.text('Job job-77'), findsOneWidget);
    expect(find.textContaining('EventBus:'), findsOneWidget);

    runtime.dispose();
  });

  testWidgets('clear all removes runtime notifications', (tester) async {
    final runtime = testRuntime();
    runtime.ingestForTesting(jobCompleted('job-1'));
    runtime.ingestForTesting(jobCompleted('job-2'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationCenter(runtimeService: runtime),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Limpar Tudo'), findsOneWidget);
    await tester.tap(find.text('Limpar Tudo'));
    await tester.pump();

    expect(find.text('Operação concluída'), findsNothing);
    expect(find.text('Sem novas notificações'), findsOneWidget);
    runtime.dispose();
  });
}
