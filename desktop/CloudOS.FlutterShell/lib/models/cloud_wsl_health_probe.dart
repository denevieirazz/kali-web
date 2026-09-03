class CloudWslHealthProbeResult {
  const CloudWslHealthProbeResult({
    required this.distro,
    required this.attempted,
    required this.healthy,
    required this.timedOut,
    required this.markerSeen,
    required this.exitCode,
    required this.durationMs,
    required this.output,
    required this.errorCode,
    required this.errorMessage,
  });

  final String distro;
  final bool attempted;
  final bool healthy;
  final bool timedOut;
  final bool markerSeen;
  final int exitCode;
  final int durationMs;
  final String output;
  final String errorCode;
  final String errorMessage;

  bool get completed => attempted && !timedOut;
  bool get protocolEvidenceConsistent =>
      !healthy || (attempted && !timedOut && markerSeen && exitCode == 0);

  String get statusLabel {
    if (healthy) return 'Saudável';
    if (timedOut) return 'Timeout';
    if (!attempted) return 'Não iniciado';
    if (errorCode.isNotEmpty) return 'Falhou';
    return 'Não saudável';
  }

  static CloudWslHealthProbeResult? fromNativeMap(Map<Object?, Object?> raw) {
    final distro = (raw['distro'] as String? ?? '').trim();
    final attempted = raw['attempted'] as bool? ?? false;
    final healthy = raw['healthy'] as bool? ?? false;
    final timedOut = raw['timedOut'] as bool? ?? false;
    final markerSeen = raw['markerSeen'] as bool? ?? false;
    final exitCode = (raw['exitCode'] as num?)?.toInt() ?? -1;
    final durationMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
    final output = raw['output'] as String? ?? '';
    final errorCode = raw['errorCode'] as String? ?? '';
    final errorMessage = raw['errorMessage'] as String? ?? '';

    final result = CloudWslHealthProbeResult(
      distro: distro,
      attempted: attempted,
      healthy: healthy,
      timedOut: timedOut,
      markerSeen: markerSeen,
      exitCode: exitCode,
      durationMs: durationMs < 0 ? 0 : durationMs,
      output: output,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );

    // Never allow a malformed native payload to be promoted to a healthy
    // runtime in presentation code.
    if (!result.protocolEvidenceConsistent) return null;
    return result;
  }
}
