class WslRuntimePolicy {
  WslRuntimePolicy({
    required bool wslAvailable,
    required Iterable<String> installedDistros,
    String defaultDistro = '',
    bool? engineAvailable,
    Map<String, int> distroVersions = const <String, int>{},
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
        );

  /// Legacy V21 "usable WSL" signal.
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

  bool get hasInstalledDistros => installedDistros.isNotEmpty;
  bool get canStartWslSession => engineAvailable && hasInstalledDistros;
  bool get hasWsl2Distros =>
      installedDistros.any((distro) => versionFor(distro) == 2);

  /// Distro used for a generic WSL session when the caller did not request a
  /// specific distro. A first-item fallback may be launched, but it is never
  /// labelled as the Windows default.
  String get launchFallbackDistro {
    if (defaultDistro.isNotEmpty) return defaultDistro;
    return installedDistros.isEmpty ? '' : installedDistros.first;
  }

  String get preferredSecurityDistro {
    for (final distro in installedDistros) {
      if (isKali(distro)) return distro;
    }
    return '';
  }

  /// Security backend candidate only when both Kali identity and WSL2 are
  /// proven. Kali with unknown/WSL1 generation is not promoted to ready.
  String get preferredSecurityWsl2Distro {
    for (final distro in installedDistros) {
      if (isKali(distro) && versionFor(distro) == 2) return distro;
    }
    return '';
  }

  bool get kaliInstalled => preferredSecurityDistro.isNotEmpty;
  bool get kaliWsl2Ready => preferredSecurityWsl2Distro.isNotEmpty;

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

  bool isWsl2Distro(String distro) => versionFor(distro) == 2;

  String resolveRequestedDistro(String? requested) {
    final candidate = requested?.trim() ?? '';
    if (candidate.isNotEmpty) {
      if (!containsDistro(candidate)) return '';
      return installedDistros.firstWhere(
        (item) => item.toLowerCase() == candidate.toLowerCase(),
      );
    }
    return launchFallbackDistro;
  }

  String statusLabelFor(String distro) {
    final parts = <String>[distro];
    if (isKali(distro)) parts.add('Security');
    if (defaultDistro.isNotEmpty && distro == defaultDistro) {
      parts.add('Default');
    }

    switch (versionFor(distro)) {
      case 1:
        parts.add('WSL1');
      case 2:
        parts.add('WSL2');
      default:
        parts.add('WSL ?');
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
}
