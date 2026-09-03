class CloudWslDistributionSnapshot {
  const CloudWslDistributionSnapshot({
    required this.name,
    this.version,
    this.isDefault = false,
  });

  final String name;

  /// Broker-authoritative WSL generation. Null means the passive Windows
  /// registration metadata did not prove whether this distro is WSL1 or WSL2.
  final int? version;
  final bool isDefault;

  bool get versionKnown => version == 1 || version == 2;
  bool get isWsl1 => version == 1;
  bool get isWsl2 => version == 2;
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

  final int currentWorkspace;

  // Compatibility/readability aliases for newer Linux-runtime code.
  bool get wslInstalled => wslEngineAvailable;
  bool get wslVersion2Available => wslDistros.any((item) => item.isWsl2);
  bool get hasUnknownWslVersions =>
      wslDistros.any((item) => !item.versionKnown);

  int distroVersion(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return 0;
    for (final item in wslDistros) {
      if (item.name.toLowerCase() == wanted) return item.version ?? 0;
    }
    return 0;
  }

  Map<String, int> get distroVersions => <String, int>{
        for (final item in wslDistros)
          if (item.versionKnown) item.name: item.version!,
      };
}
