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
    this.wslInstalled = false,
    this.wslVersion2Available = false,
    this.distroVersions = const <String, int>{},
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

  /// Backward-compatible V21 field. True only when CloudOS has at least one
  /// registered WSL distribution that is usable by the broker.
  final bool wslAvailable;

  /// True when the Windows WSL executable/runtime is present, even if there
  /// are currently no registered distributions.
  final bool wslInstalled;

  /// True when at least one registered distribution is explicitly WSL2.
  final bool wslVersion2Available;

  final List<String> distros;
  final String defaultDistro;

  /// Broker-authoritative WSL version per registered distribution. Missing or
  /// zero means unknown; callers must not infer WSL2 from the distro name.
  final Map<String, int> distroVersions;

  final int currentWorkspace;

  int distroVersion(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return 0;
    for (final entry in distroVersions.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return 0;
  }
}
