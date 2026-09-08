import 'cloudos_bridge.dart';

class SessionIdentity {
  const SessionIdentity({
    required this.userName,
    required this.sessionId,
    required this.deviceName,
  });

  const SessionIdentity.unavailable()
    : userName = '',
      sessionId = 0,
      deviceName = '';

  final String userName;
  final int sessionId;
  final String deviceName;

  bool get available => userName.trim().isNotEmpty && sessionId > 0;
}

class SessionIdentityService {
  SessionIdentityService(this._bridge);

  final CloudOSBridge _bridge;

  Future<SessionIdentity> load() async {
    try {
      final raw = await _bridge.invokeBrokerRpc(
        'system.snapshot',
        const <String, Object?>{},
      );
      final userName = (raw['userName'] as String? ?? '').trim();
      final deviceName = (raw['deviceName'] as String? ?? '').trim();
      final sessionId = (raw['sessionId'] as num?)?.toInt() ?? 0;
      if (sessionId < 0 || sessionId > 0xFFFFFFFF) {
        return const SessionIdentity.unavailable();
      }
      return SessionIdentity(
        userName: userName,
        sessionId: sessionId,
        deviceName: deviceName,
      );
    } on CloudOSBridgeException {
      return const SessionIdentity.unavailable();
    }
  }
}
