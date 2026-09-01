import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cloudos/native/v19.notifications-test');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getNotificationState':
          return <Object?, Object?>{
            'revision': 42,
            'unreadCount': 1,
            'items': <Map<Object?, Object?>>[
              <Object?, Object?>{
                'id': '41',
                'title': 'CloudOS pronto',
                'message': 'Sistema iniciado.',
                'time': '09:31',
                'severity': 0,
                'read': false,
              },
              <Object?, Object?>{
                'id': '40',
                'title': 'Alerta',
                'message': 'Teste de severidade.',
                'time': '09:30',
                'severity': 1,
                'read': true,
              },
            ],
          };
        case 'markNotificationsRead':
        case 'dismissNotification':
        case 'clearNotifications':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('loads revision, unread count and native notification fields', () async {
    const bridge = CloudOSBridge(channel: channel);
    final state = await bridge.loadNotificationState();

    expect(state.revision, 42);
    expect(state.unreadCount, 1);
    expect(state.items, hasLength(2));
    expect(state.items.first.id, '41');
    expect(state.items.first.title, 'CloudOS pronto');
    expect(state.items.first.read, false);
    expect(state.items.last.severity, 1);
  });

  test('notification mutations stay typed and id-only', () async {
    const bridge = CloudOSBridge(channel: channel);

    expect(await bridge.markNotificationsRead(), true);
    expect(calls.last.method, 'markNotificationsRead');
    expect(calls.last.arguments, isNull);

    expect(await bridge.dismissNotification('41'), true);
    expect(calls.last.method, 'dismissNotification');
    expect(calls.last.arguments, <String, Object?>{'id': '41'});

    expect(await bridge.clearNotifications(), true);
    expect(calls.last.method, 'clearNotifications');
    expect(calls.last.arguments, isNull);
  });

  test('missing native plugin keeps preview mode usable', () async {
    const missing = CloudOSBridge(
      channel: MethodChannel('cloudos/native/v19.notifications-missing'),
    );

    final state = await missing.loadNotificationState();
    expect(state.items, CloudOSBridge.previewNotifications);
    expect(state.unreadCount, CloudOSBridge.previewNotifications.length);
    expect(await missing.markNotificationsRead(), true);
    expect(await missing.dismissNotification('1'), true);
    expect(await missing.clearNotifications(), true);
  });
}
