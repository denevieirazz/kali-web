import 'package:flutter_test/flutter_test.dart';

import '../lib/services/cloudos_bridge.dart';
import '../lib/services/session_identity_service.dart';

class _IdentityBridge extends CloudOSBridge {
  _IdentityBridge(this.response, {this.error});

  final Map<String, Object?> response;
  final CloudOSBridgeException? error;
  String? lastMethod;

  @override
  Future<Map<String, Object?>> invokeBrokerRpc(
    String method,
    Map<String, Object?> payload,
  ) async {
    lastMethod = method;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test('loads real session identity from system.snapshot', () async {
    final bridge = _IdentityBridge(const <String, Object?>{
      'userName': 'cloudos-user',
      'sessionId': 7,
      'deviceName': 'WORKSTATION-01',
    });
    final service = SessionIdentityService(bridge);

    final identity = await service.load();

    expect(bridge.lastMethod, 'system.snapshot');
    expect(identity.available, isTrue);
    expect(identity.userName, 'cloudos-user');
    expect(identity.sessionId, 7);
    expect(identity.deviceName, 'WORKSTATION-01');
  });

  test('never fabricates identity when user name is absent', () async {
    final bridge = _IdentityBridge(const <String, Object?>{
      'userName': '',
      'sessionId': 7,
      'deviceName': 'WORKSTATION-01',
    });

    final identity = await SessionIdentityService(bridge).load();

    expect(identity.available, isFalse);
    expect(identity.userName, isEmpty);
    expect(identity.sessionId, 7);
  });

  test('rejects non-interactive or overflowing session ids', () async {
    final zero = await SessionIdentityService(
      _IdentityBridge(const <String, Object?>{
        'userName': 'user',
        'sessionId': 0,
        'deviceName': 'pc',
      }),
    ).load();
    expect(zero.available, isFalse);

    final overflow = await SessionIdentityService(
      _IdentityBridge(const <String, Object?>{
        'userName': 'user',
        'sessionId': 0x1FFFFFFFF,
        'deviceName': 'pc',
      }),
    ).load();
    expect(overflow.available, isFalse);
    expect(overflow.userName, isEmpty);
    expect(overflow.sessionId, 0);
  });

  test('bridge failure becomes explicit unavailable identity', () async {
    final bridge = _IdentityBridge(
      const <String, Object?>{},
      error: const CloudOSBridgeException(
        'bridge_unavailable',
        'unavailable',
      ),
    );

    final identity = await SessionIdentityService(bridge).load();

    expect(identity.available, isFalse);
    expect(identity.userName, isEmpty);
    expect(identity.deviceName, isEmpty);
    expect(identity.sessionId, 0);
  });
}
