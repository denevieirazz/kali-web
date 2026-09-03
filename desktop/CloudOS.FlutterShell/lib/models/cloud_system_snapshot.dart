class CloudWslDistributionSnapshot {
  const CloudWslDistributionSnapshot({
    required this.name,
    this.version,
    this.isDefault = false,
  });

  final String name;

  /// Registered WSL generation when the native broker can prove it.
  /// Null means unknown; callers must not infer WSL2 from the distro name.
  final int? version;
  final bool isDefault;

  bool get versionKnown => version == 1 || version == 2;
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

  /// Legacy V21 meaning: the WSL runtime is usable by existing callers, which
  /// requires both the Windows WSL engine and at least one registered distro.
  final bool wslAvailable;

  /// Additive evidence that wsl.exe exists even if no distro is registered.
  final bool wslEngineAvailable;

  /// Legacy V21 distro-name list kept for compatibility.
  final List<String> distros;
  final String defaultDistro;

  /// Passive typed inventory reported by the System Broker. No distro is
  /// started merely to populate this list.
  final List<CloudWslDistributionSnapshot> wslDistros;

  final int currentWorkspace;
}
