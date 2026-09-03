class WslRuntimePolicy {
  WslRuntimePolicy({
    required bool wslAvailable,
    required Iterable<String> installedDistros,
    String defaultDistro = '',
    bool? engineAvailable,
  })  : wslAvailable = wslAvailable,
        engineAvailable = engineAvailable ?? wslAvailable,
        installedDistros = _normalizeDistros(installedDistros),
        defaultDistro = _resolveReportedDefault(
          _normalizeDistros(installedDistros),
          defaultDistro,
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

  bool get hasInstalledDistros => installedDistros.isNotEmpty;
  bool get canStartWslSession => engineAvailable && hasInstalledDistros;

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

  bool get kaliInstalled => preferredSecurityDistro.isNotEmpty;

  bool containsDistro(String distro) {
    final wanted = distro.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    return installedDistros.any((item) => item.toLowerCase() == wanted);
  }

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
    if (isKali(distro)) return '$distro • Security';
    if (defaultDistro.isNotEmpty && distro == defaultDistro) {
      return '$distro • Default';
    }
    return distro;
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
