class CloudSystemSnapshot {
  const CloudSystemSnapshot({
    required this.deviceName,
    required this.networkName,
    required this.volume,
    required this.brightness,
    required this.batteryPercent,
    required this.wslAvailable,
    required this.distros,
    this.networkAvailable = true,
    this.volumeAvailable = true,
    this.brightnessAvailable = true,
    this.currentWorkspace = 1,
  });

  final String deviceName;
  final bool networkAvailable;
  final String networkName;
  final bool volumeAvailable;
  final double volume;
  final bool brightnessAvailable;
  final double brightness;
  final int batteryPercent;
  final bool wslAvailable;
  final List<String> distros;
  final int currentWorkspace;
}
