class CloudWslDistributionSnapshot {
  const CloudWslDistributionSnapshot({
    required this.name,
    this.version,
    this.isDefault = false,
    this.basePathPresent,
    this.securityCandidate,
  });

  final String name;

  /// Broker-authoritative WSL generation. Null means the passive Windows
  /// registration metadata did not prove whether this distro is WSL1 or WSL2.
  final int? version;
  final bool isDefault;

  /// Null means an older bridge/broker did not publish BasePath evidence.
  /// true proves only that the registered distro storage directory exists; it
  /// does not prove first-run provisioning or successful command execution.
  final bool? basePathPresent;

  /// Null means the broker did not publish the conservative security-candidate
  /// decision. true is passive evidence only, never an active Kali health test.
  final bool? securityCandidate;

  bool get versionKnown => version == 1 || version == 2;
  bool get isWsl1 => version == 1;
  bool get isWsl2 => version == 2;
  bool get storageEvidenceKnown => basePathPresent != null;
  bool get storagePresent => basePathPresent == true;
  bool get securityCandidateKnown => securityCandidate != null;
  bool get isSecurityCandidate => securityCandidate == true;
}

class CloudSystemSnapshot {
  const CloudSystemSnapshot({
    required this.deviceName,
    required this.networkName,
    required this.volume,
    required this.brightness,
    required this.batteryPercent,
    required this.wslAvailable,
    required this.distros,
    this.defaultDistro = '',
    this.wslEngineAvailable = false,
    this.wslDistros = const <CloudWslDistributionSnapshot>[],
    this.wslPassiveReady,
    this.preferredSecurityDistro = '',
    this.wslRegisteredCount,
    this.wslLaunchCandidateCount,
    this.wsl1Count,
    this.wsl2Count,
    this.networkAvailable = true,
    this.volumeAvailable = true,
    this.brightnessAvailable = true,
    this.batteryAvailable = true,
    this.currentWorkspace = 1,
  });

  final String deviceName;
  final bool networkAvailable;
  final String networkName;
  final bool volumeAvailable;
  final double volume;
  final bool brightnessAvailable;
  final double brightness;
  final bool batteryAvailable;
  final int batteryPercent;

  /// Backward-compatible V21 field. True only when CloudOS has a detected WSL
  /// engine and at least one registered distribution usable by legacy callers.
  final bool wslAvailable;

  /// Passive evidence that the Windows WSL engine exists. This is independent
  /// from whether any Linux distribution is currently registered.
  final bool wslEngineAvailable;

  /// Legacy name-only inventory kept for compatibility with existing widgets.
  final List<String> distros;
  final String defaultDistro;

  /// Typed broker inventory. Version is null unless Windows registration
  /// metadata proves WSL1 or WSL2; the UI must not infer WSL2 from a name.
  final List<CloudWslDistributionSnapshot> wslDistros;

  /// Stronger passive readiness published by newer brokers. Null means the
  /// bridge did not transport that evidence. Even true is not an active boot
  /// or command-execution health check.
  final bool? wslPassiveReady;

  /// Conservative broker-selected Kali/WSL2/storage candidate. Empty means no
  /// candidate was proven or the field was unavailable.
  final String preferredSecurityDistro;

  /// Optional broker counters. Null intentionally means "not transported".
  final int? wslRegisteredCount;
  final int? wslLaunchCandidateCount;
  final int? wsl1Count;
  final int? wsl2Count;

  final int currentWorkspace;

  // Compatibility/readability aliases for newer Linux-runtime code.
  bool get wslInstalled => wslEngineAvailable;
  bool get wslVersion2Available => wslDistros.any((item) => item.isWsl2);
  bool get hasUnknownWslVersions =>
      wslDistros.any((item) => !item.versionKnown);
  bool get hasTypedWslInventory => wslDistros.isNotEmpty;
  bool get passiveReadinessKnown => wslPassiveReady != null;
  bool get passiveReady => wslPassiveReady == true;

  int get effectiveRegisteredCount => wslRegisteredCount ?? distros.length;
  int get effectiveWsl1Count =>
      wsl1Count ?? wslDistros.where((item) => item.isWsl1).length;
  int get effectiveWsl2Count =>
      wsl2Count ?? wslDistros.where((item) => item.isWsl2).length;
  int? get effectiveLaunchCandidateCount {
    if (wslLaunchCandidateCount != null) return wslLaunchCandidateCount;
    if (wslDistros.isEmpty ||
        wslDistros.any((item) => !item.storageEvidenceKnown)) {
      return null;
    }
    return wslDistros.where((item) => item.storagePresent).length;
  }

  int distroVersion(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return 0;
    for (final item in wslDistros) {
      if (item.name.toLowerCase() == wanted) return item.version ?? 0;
    }
    return 0;
  }

  CloudWslDistributionSnapshot? distroInfo(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final item in wslDistros) {
      if (item.name.toLowerCase() == wanted) return item;
    }
    return null;
  }

  Map<String, int> get distroVersions => <String, int>{
        for (final item in wslDistros)
          if (item.versionKnown) item.name: item.version!,
      };

  Map<String, bool> get distroStorageEvidence => <String, bool>{
        for (final item in wslDistros)
          if (item.storageEvidenceKnown) item.name: item.storagePresent,
      };
}
