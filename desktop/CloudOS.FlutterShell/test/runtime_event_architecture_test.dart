import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void expectMarkers(String source, Iterable<String> markers, String label) {
  for (final marker in markers) {
    expect(
      source,
      contains(marker),
      reason: '$label missing required marker: $marker',
    );
  }
}

void expectAbsent(String source, Iterable<String> markers, String label) {
  for (final marker in markers) {
    expect(
      source,
      isNot(contains(marker)),
      reason: '$label contains forbidden marker: $marker',
    );
  }
}

void main() {
  test('native EventBus transport is dedicated, bounded and reconnecting', () {
    final header = read('windows/runner/cloudos_broker_event_client_v23.h');
    final source = read('windows/runner/cloudos_broker_event_client_v23.cpp');
    final cmake = read('windows/runner/CMakeLists.txt');
    final window = read('windows/runner/flutter_window.cpp');

    expectMarkers(header, <String>[
      'kDispatchMessage = WM_APP + 0x442',
      'kMaxPendingUiEvents = 256',
      'kMaxPendingUiBytes = 4 * 1024 * 1024',
      'void Initialize(',
      'void Shutdown()',
      'void DrainPlatformEvents()',
    ], 'event client header');

    expectMarkers(source, <String>[
      'cloudos/native/events/v23',
      'events.subscribe',
      r'{\"pattern\":\"*\"}',
      'GetCurrentUserSidString',
      'ProcessIdToSessionId',
      'WaitNamedPipeW',
      'kInitialReconnectDelayMs = 250',
      'kMaxReconnectDelayMs = 5000',
      'pending_ui_events_',
      'dropped_events_',
      'broker.onEvent',
      'broker.onConnectionState',
      'call.method_name() == "start"',
      'call.method_name() == "stop"',
      'call.method_name() == "status"',
    ], 'event client source');

    expectAbsent(source, <String>[
      'shell.execute',
      'files.execute',
      'cmd.exe /c',
      'powershell.exe -Command',
    ], 'event client source');

    expect(cmake, contains('cloudos_broker_event_client_v23.cpp'));
    expectMarkers(window, <String>[
      'CloudOSBrokerEventClientV23::Instance().Initialize',
      'CloudOSBrokerEventClientV23::Instance().Shutdown',
      'CloudOSBrokerEventClientV23::kDispatchMessage',
      'DrainPlatformEvents',
    ], 'flutter window');
  });

  test('Dart event channel is separate from business RPC', () {
    final bridge = read('lib/services/broker_event_bridge_v23.dart');
    final runtime = read('lib/services/runtime_event_service.dart');

    expectMarkers(bridge, <String>[
      "MethodChannel('cloudos/native/events/v23')",
      "invokeMethod<bool>('start')",
      "invokeMapMethod<String, Object?>('status')",
      "call.method == 'broker.onEvent'",
      "call.method == 'broker.onConnectionState'",
    ], 'Dart event bridge');
    expectAbsent(bridge, <String>[
      'invokeBrokerRpc',
      'apps.launch',
      'files.open',
    ], 'Dart event bridge');

    expectMarkers(runtime, <String>[
      'maxJournalEntries = 256',
      'maxNotifications = 100',
      "event.name == 'job.completed'",
      "event.name == 'job.failed'",
      "event.name == 'job.cancelled'",
      'nativeDroppedEventCount',
      'markAllRead()',
    ], 'runtime event service');
  });

  test('Start and Taskbar do not fabricate identity or notification count', () {
    final start = read('lib/widgets/start_panel.dart');
    final taskbar = read('lib/widgets/cloud_taskbar.dart');
    final identity = read('lib/services/session_identity_service.dart');

    expectAbsent(start, <String>[
      'Platform.environment',
      "return 'Usuário'",
      "'Administrador'",
    ], 'StartPanel');
    expectMarkers(start, <String>[
      'SessionIdentityService',
      'Identidade indisponível',
      'Sessão ativa • identidade indisponível',
      'ID ${_identity.sessionId}',
    ], 'StartPanel');

    expectAbsent(taskbar, <String>[
      'notificationCount = 3',
      'notificationCount = 1',
    ], 'Taskbar');
    expectMarkers(taskbar, <String>[
      'RuntimeEventService',
      'widget.notificationCount ?? _runtime.unreadCount',
      "'99+'",
    ], 'Taskbar');

    expectMarkers(identity, <String>[
      "'system.snapshot'",
      "raw['userName']",
      "raw['sessionId']",
      'SessionIdentity.unavailable',
    ], 'session identity service');
  });

  test('System Broker exposes truthful identity and text capabilities', () {
    final system = read('../CloudOS.SystemBroker/src/system_service_v21.cpp');

    expectMarkers(system, <String>[
      'GetComputerNameW',
      'GetUserNameW',
      'SecurityV21::GetCurrentSessionId()',
      'files.text.readChunk',
      'files.text.writeChunk',
      'files.text.abortWrite',
    ], 'SystemServiceV21');
    expectAbsent(system, <String>[
      'snapshot_.device_name = "CloudOS Desktop"',
      'snapshot_.user_name = "User"',
    ], 'SystemServiceV21');
  });

  test('production application title no longer calls itself Preview', () {
    final main = read('lib/main.dart');
    expect(main, contains("title: 'CloudOS Desktop'"));
    expect(main, isNot(contains("title: 'CloudOS Flutter Preview'")));
    expect(main, contains('RuntimeEventService.instance.start()'));
  });
}
