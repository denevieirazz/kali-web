class CloudOSRecoveryStatus {
  const CloudOSRecoveryStatus({
    required this.schema,
    required this.state,
    required this.reason,
    required this.supervisorPid,
    required this.shellPid,
    required this.brokerPid,
    required this.sessionId,
    required this.failureCount,
    required this.transitionSequence,
    required this.jobKillOnCloseAssigned,
    required this.previousUnclean,
    required this.isRemoteSession,
  });

  final int schema;
  final String state;
  final String reason;
  final int supervisorPid;
  final int shellPid;
  final int brokerPid;
  final int sessionId;
  final int failureCount;
  final int transitionSequence;
  final bool jobKillOnCloseAssigned;
  final bool previousUnclean;
  final bool isRemoteSession;

  bool get isHealthy => state.toUpperCase() == 'HEALTHY';
  bool get isSafeMode => state.toUpperCase() == 'SAFE_MODE';
  bool get isCrashLoop => state.toUpperCase() == 'CRASH_LOOP';
  bool get isDegraded => state.toUpperCase() == 'DEGRADED';

  factory CloudOSRecoveryStatus.fromMap(Map<String, dynamic> map) {
    return CloudOSRecoveryStatus(
      schema: (map['schema'] as num?)?.toInt() ?? 22,
      state: map['state'] as String? ?? 'UNKNOWN',
      reason: map['reason'] as String? ?? '',
      supervisorPid: (map['supervisor_pid'] as num?)?.toInt() ?? 0,
      shellPid: (map['shell_pid'] as num?)?.toInt() ?? 0,
      brokerPid: (map['broker_pid'] as num?)?.toInt() ?? 0,
      sessionId: (map['session_id'] as num?)?.toInt() ?? 0,
      failureCount: (map['failure_count'] as num?)?.toInt() ?? 0,
      transitionSequence: (map['transition_sequence'] as num?)?.toInt() ?? 0,
      jobKillOnCloseAssigned: map['job_kill_on_close_assigned'] as bool? ?? false,
      previousUnclean: map['previous_unclean'] as bool? ?? false,
      isRemoteSession: map['is_remote_session'] as bool? ?? false,
    );
  }
}

class CloudOSSystemCapabilities {
  const CloudOSSystemCapabilities({
    required this.capabilities,
    required this.capabilityMap,
  });

  final List<String> capabilities;
  final Map<String, bool> capabilityMap;

  bool get audioControl => capabilityMap['audio_control'] ?? false;
  bool get brightnessControl => capabilityMap['brightness_control'] ?? false;
  bool get wslRuntime => capabilityMap['wsl_runtime'] ?? false;
  bool get economyMode => capabilityMap['economy_mode'] ?? false;
  bool get rdpSession => capabilityMap['rdp_session'] ?? false;
  bool get multiMonitor => capabilityMap['multi_monitor'] ?? false;
  bool get batteryPresent => capabilityMap['battery_present'] ?? false;
  bool get bluetoothAvailable => capabilityMap['bluetooth_available'] ?? false;
  bool get wifiAvailable => capabilityMap['wifi_available'] ?? false;

  factory CloudOSSystemCapabilities.fromMap(Map<String, dynamic> map) {
    final rawCaps = map['capabilities'] as List<dynamic>? ?? const [];
    final rawMap = map['capability_map'] as Map<String, dynamic>? ?? const {};
    final boolMap = <String, bool>{};
    for (final entry in rawMap.entries) {
      if (entry.value is bool) {
        boolMap[entry.key] = entry.value as bool;
      }
    }
    return CloudOSSystemCapabilities(
      capabilities: rawCaps.whereType<String>().toList(),
      capabilityMap: boolMap,
    );
  }
}
