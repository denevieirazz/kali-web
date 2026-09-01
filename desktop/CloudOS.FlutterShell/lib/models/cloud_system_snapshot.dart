class CloudSystemSnapshot {
  const CloudSystemSnapshot({
    required this.deviceName,
    required this.networkName,
    required this.volume,
    required this.brightness,
    required this.batteryPercent,
    required this.wslAvailable,
    required this.distros,
    this.currentWorkspace = 1,
  });

  final String deviceName;
  final String networkName;
  final double volume;
  final double brightness;
  final int batteryPercent;
  final bool wslAvailable;
  final List<String> distros;
  final int currentWorkspace;
}
