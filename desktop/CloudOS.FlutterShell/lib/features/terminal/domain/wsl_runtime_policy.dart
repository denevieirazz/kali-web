enum WslRuntimeReadiness {
  unavailable,
  engineOnly,
  registeredUnknown,
  passiveReady,
  wsl2Ready,
  securityReady,
}

enum WslSessionRequirement { any, wsl2, security }

class WslSessionPlan {
  const WslSessionPlan._({
    required this.allowed,
    required this.distro,
    required this.requirement,
    required this.reason,
    required this.version,
    required this.storageEvidence,
  });

  /// Small const compatibility constructor for presentation-only denied plans.
  /// Runtime policy code should prefer [WslSessionPlan.denied] so it can carry
  /// the exact distro/version/storage evidence that caused the rejection.
  const WslSessionPlan.deny(String reason)
    : allowed = false,
      distro = '',
      requirement = WslSessionRequirement.security,
      reason = reason,
      version = 0,
      storageEvidence = null;

  factory WslSessionPlan.allowed({
    required String distro,
    required WslSessionRequirement requirement,
    required int version,
    required bool? storageEvidence,
    String reason = '',
  }) {
    return WslSessionPlan._(
      allowed: true,
      distro: distro,
      requirement: requirement,
      reason: reason,
      version: version,
      storageEvidence: storageEvidence,
    );
  }

  factory WslSessionPlan.denied({
    required WslSessionRequirement requirement,
    required String reason,
    String distro = '',
    int version = 0,
    bool? storageEvidence,
  }) {
    return WslSessionPlan._(
      allowed: false,
      distro: distro,
      requirement: requirement,
      reason: reason,
      version: version,
      storageEvidence: storageEvidence,
    );
  }

  final bool allowed;
  final String distro;
  final WslSessionRequirement requirement;
  final String reason;
  final int version;

  /// null means an older broker/bridge did not transport BasePath evidence.
  final bool? storageEvidence;

  bool get versionKnown => version == 1 || version == 2;
  bool get isWsl2 => version == 2;
  bool get storageEvidenceKnown => storageEvidence != null;
  bool get storagePresent => storageEvidence == true;
}

class WslRuntimePolicy {
  WslRuntimePolicy({
    required bool wslAvailable,
    required Iterable<String> installedDistros,
    String defaultDistro = '',
    bool? engineAvailable,
    Map<String, int> distroVersions = const <String, int>{},
    Map<String, bool> distroStorageEvidence = const <String, bool>{},
    String preferredSecurityDistro = '',
  })  : wslAvailable = wslAvailable,
        engineAvailable = engineAvailable ?? wslAvailable,
        installedDistros = _normalizeDistros(installedDistros),
        defaultDistro = _resolveReportedDefault(
          _normalizeDistros(installedDistros),
          defaultDistro,
        ),
        distroVersions = _normalizeVersions(
          _normalizeDistros(installedDistros),
          distroVersions,
        ),
        distroStorageEvidence = _normalizeStorageEvidence(
          _normalizeDistros(installedDistros),
          distroStorageEvidence,
        ),
        brokerPreferredSecurityDistro = _resolveSecurityCandidate(
          _normalizeDistros(installedDistros),
          preferredSecurityDistro,
        );

  /// Legacy V21 "engine + registered distro" signal.
  final bool wslAvailable;

  /// Passive evidence that the Windows WSL engine exists. This can be true
  /// even before any distribution is registered.
  final bool engineAvailable;

  final List<String> installedDistros;

  /// Default distro only when the broker/Windows explicitly reports one that
  /// is also present in the inventory. No first-item guess is stored here.
  final String defaultDistro;

  /// Broker-proven WSL generation keyed by canonical inventory name. Missing
  /// entries are deliberately unknown; CloudOS never upgrades "unknown" to 2.
  final Map<String, int> distroVersions;

  /// Passive registered BasePath evidence. Absence of a map entry means an old
  /// bridge did not transport that evidence, not that storage is missing.
  final Map<String, bool> distroStorageEvidence;

  /// Optional broker-selected candidate, validated against the local inventory
  /// and Kali identity before it is trusted even as a passive candidate.
  final String brokerPreferredSecurityDistro;

  bool get hasInstalledDistros => installedDistros.isNotEmpty;

  /// Compatibility launch gate. Older V21 bridges do not publish BasePath
  /// evidence, so a registered distro remains launchable unless storage is
  /// explicitly proven missing.
  bool get canStartWslSession =>
      engineAvailable &&
      installedDistros.any((distro) => storageFor(distro) != false);

  bool get hasWsl2Distros =>
      installedDistros.any((distro) => versionFor(distro) == 2);

  bool get hasStorageEvidence => distroStorageEvidence.isNotEmpty;
  bool get passiveReadinessKnown => hasStorageEvidence;
  bool get passiveReady =>
      engineAvailable &&
      installedDistros.any((distro) => storageFor(distro) == true);

  int get launchCandidateCount =>
      installedDistros.where((distro) => storageFor(distro) == true).length;

  WslRuntimeReadiness get readiness {
    if (!engineAvailable) return WslRuntimeReadiness.unavailable;
    if (!hasInstalledDistros) return WslRuntimeReadiness.engineOnly;
    if (preferredSecurityPassiveReadyDistro.isNotEmpty) {
      return WslRuntimeReadiness.securityReady;
    }
    if (installedDistros.any(
      (distro) => versionFor(distro) == 2 && storageFor(distro) == true,
    )) {
      return WslRuntimeReadiness.wsl2Ready;
    }
    if (passiveReady) return WslRuntimeReadiness.passiveReady;
    return WslRuntimeReadiness.registeredUnknown;
  }

  /// Distro used for a generic WSL session when the caller did not request a
  /// specific distro. A first-item fallback may be launched, but it is never
  /// labelled as the Windows default.
  String get launchFallbackDistro {
    if (defaultDistro.isNotEmpty && storageFor(defaultDistro) != false) {
      return defaultDistro;
    }
    for (final distro in installedDistros) {
      if (storageFor(distro) != false) return distro;
    }
    return '';
  }

  String get preferredSecurityDistro {
    if (brokerPreferredSecurityDistro.isNotEmpty) {
      return brokerPreferredSecurityDistro;
    }
    for (final distro in installedDistros) {
      if (isKali(distro)) return distro;
    }
    return '';
  }

  /// Kali + WSL2 is proven. Storage may still be unknown on an old bridge.
  String get preferredSecurityWsl2Distro {
    final brokerCandidate = brokerPreferredSecurityDistro;
    if (brokerCandidate.isNotEmpty && versionFor(brokerCandidate) == 2) {
      return brokerCandidate;
    }
    for (final distro in installedDistros) {
      if (isKali(distro) && versionFor(distro) == 2) return distro;
    }
    return '';
  }

  /// Strongest passive security candidate: Kali + WSL2 + registered storage.
  String get preferredSecurityPassiveReadyDistro {
    final brokerCandidate = brokerPreferredSecurityDistro;
    if (brokerCandidate.isNotEmpty &&
        versionFor(brokerCandidate) == 2 &&
        storageFor(brokerCandidate) == true) {
      return brokerCandidate;
    }
    for (final distro in installedDistros) {
      if (isKali(distro) &&
          versionFor(distro) == 2 &&
          storageFor(distro) == true) {
        return distro;
      }
    }
    return '';
  }

  bool get kaliInstalled => preferredSecurityDistro.isNotEmpty;
  bool get kaliWsl2Ready => preferredSecurityWsl2Distro.isNotEmpty;
  bool get kaliPassiveReady => preferredSecurityPassiveReadyDistro.isNotEmpty;

  bool containsDistro(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    return installedDistros.any((item) => item.toLowerCase() == wanted);
  }

  int versionFor(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return 0;
    for (final entry in distroVersions.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return 0;
  }

  bool? storageFor(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final entry in distroStorageEvidence.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  bool isWsl2Distro(String distro) => versionFor(distro) == 2;

  String resolveRequestedDistro(String? requested) {
    final candidate = requested?.trim() ?? '';
    if (candidate.isNotEmpty) {
      if (!containsDistro(candidate)) return '';
      final canonical = installedDistros.firstWhere(
        (item) => item.toLowerCase() == candidate.toLowerCase(),
      );
      return storageFor(canonical) == false ? '' : canonical;
    }
    return launchFallbackDistro;
  }

  WslSessionPlan planSession({
    String? requestedDistro,
    WslSessionRequirement requirement = WslSessionRequirement.any,
  }) {
    if (!engineAvailable) {
      return WslSessionPlan.denied(
        requirement: requirement,
        reason: 'WSL_ENGINE_UNAVAILABLE',
      );
    }
    if (!hasInstalledDistros) {
      return WslSessionPlan.denied(
        requirement: requirement,
        reason: 'WSL_NO_REGISTERED_DISTRO',
      );
    }

    final requested = requestedDistro?.trim() ?? '';
    if (requested.isNotEmpty && !containsDistro(requested)) {
      return WslSessionPlan.denied(
        requirement: requirement,
        distro: requested,
        reason: 'WSL_DISTRO_NOT_INSTALLED',
      );
    }

    String distro;
    if (requirement == WslSessionRequirement.security && requested.isEmpty) {
      distro = preferredSecurityDistro;
    } else if (requested.isNotEmpty) {
      // Preserve an explicitly requested registered distro long enough to
      // report its exact storage/version failure. Generic fallback selection
      // intentionally skips a distro whose registered storage is missing.
      distro = installedDistros.firstWhere(
        (item) => item.toLowerCase() == requested.toLowerCase(),
      );
    } else {
      distro = launchFallbackDistro;
    }

    if (distro.isEmpty) {
      return WslSessionPlan.denied(
        requirement: requirement,
        reason: requirement == WslSessionRequirement.security
            ? 'KALI_NOT_INSTALLED'
            : 'WSL_NO_LAUNCH_CANDIDATE',
      );
    }

    final version = versionFor(distro);
    final storage = storageFor(distro);
    if (storage == false) {
      return WslSessionPlan.denied(
        requirement: requirement,
        distro: distro,
        version: version,
        storageEvidence: storage,
        reason: 'WSL_DISTRO_STORAGE_MISSING',
      );
    }

    if (requirement == WslSessionRequirement.wsl2 && version != 2) {
      return WslSessionPlan.denied(
        requirement: requirement,
        distro: distro,
        version: version,
        storageEvidence: storage,
        reason: version == 1 ? 'WSL2_REQUIRED' : 'WSL_VERSION_UNKNOWN',
      );
    }

    if (requirement == WslSessionRequirement.security) {
      if (!isKali(distro)) {
        return WslSessionPlan.denied(
          requirement: requirement,
          distro: distro,
          version: version,
          storageEvidence: storage,
          reason: 'SECURITY_DISTRO_NOT_KALI',
        );
      }
      if (version != 2) {
        return WslSessionPlan.denied(
          requirement: requirement,
          distro: distro,
          version: version,
          storageEvidence: storage,
          reason: version == 1 ? 'KALI_WSL2_REQUIRED' : 'KALI_VERSION_UNKNOWN',
        );
      }
      if (storage != true) {
        return WslSessionPlan.denied(
          requirement: requirement,
          distro: distro,
          version: version,
          storageEvidence: storage,
          reason: 'KALI_STORAGE_NOT_PROVEN',
        );
      }
    }

    return WslSessionPlan.allowed(
      distro: distro,
      requirement: requirement,
      version: version,
      storageEvidence: storage,
      reason: storage == null ? 'LEGACY_STORAGE_EVIDENCE_UNKNOWN' : '',
    );
  }

  String statusLabelFor(String distro) {
    final parts = <String>[distro];
    if (isKali(distro)) parts.add('Security');
    if (defaultDistro.isNotEmpty &&
        distro.toLowerCase() == defaultDistro.toLowerCase()) {
      parts.add('Default');
    }

    switch (versionFor(distro)) {
      case 1:
        parts.add('WSL1');
        break;
      case 2:
        parts.add('WSL2');
        break;
      default:
        parts.add('WSL ?');
        break;
    }

    switch (storageFor(distro)) {
      case true:
        parts.add('Storage ✓');
        break;
      case false:
        parts.add('Storage missing');
        break;
      case null:
        break;
    }
    return parts.join(' • ');
  }

  static bool isKali(String distro) {
    return distro.trim().toLowerCase().contains('kali');
  }

  static List<String> _normalizeDistros(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isEmpty) continue;
      final key = normalized.toLowerCase();
      if (seen.add(key)) result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }

  static Map<String, int> _normalizeVersions(
    List<String> distros,
    Map<String, int> versions,
  ) {
    final result = <String, int>{};
    for (final distro in distros) {
      final wanted = distro.toLowerCase();
      for (final entry in versions.entries) {
        if (entry.key.trim().toLowerCase() != wanted) continue;
        if (entry.value == 1 || entry.value == 2) {
          result[distro] = entry.value;
        }
        break;
      }
    }
    return Map<String, int>.unmodifiable(result);
  }

  static Map<String, bool> _normalizeStorageEvidence(
    List<String> distros,
    Map<String, bool> evidence,
  ) {
    final result = <String, bool>{};
    for (final distro in distros) {
      final wanted = distro.toLowerCase();
      for (final entry in evidence.entries) {
        if (entry.key.trim().toLowerCase() != wanted) continue;
        result[distro] = entry.value;
        break;
      }
    }
    return Map<String, bool>.unmodifiable(result);
  }

  static String _resolveReportedDefault(
    List<String> distros,
    String requestedDefault,
  ) {
    final wanted = requestedDefault.trim().toLowerCase();
    if (wanted.isEmpty) return '';
    for (final distro in distros) {
      if (distro.toLowerCase() == wanted) return distro;
    }
    return '';
  }

  static String _resolveSecurityCandidate(
    List<String> distros,
    String reportedCandidate,
  ) {
    final wanted = reportedCandidate.trim().toLowerCase();
    if (wanted.isEmpty || !wanted.contains('kali')) return '';
    for (final distro in distros) {
      if (distro.toLowerCase() == wanted && isKali(distro)) return distro;
    }
    return '';
  }
}
