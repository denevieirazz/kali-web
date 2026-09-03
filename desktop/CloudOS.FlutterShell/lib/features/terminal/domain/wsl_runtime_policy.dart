class WslRuntimePolicy {
  WslRuntimePolicy({
    required bool wslAvailable,
    required Iterable<String> installedDistros,
    String defaultDistro = '',
  })  : wslAvailable = wslAvailable,
        installedDistros = _normalizeDistros(installedDistros),
        defaultDistro = _resolveDefault(
          _normalizeDistros(installedDistros),
          defaultDistro,
        );

  final bool wslAvailable;
  final List<String> installedDistros;
  final String defaultDistro;

  bool get hasInstalledDistros => installedDistros.isNotEmpty;

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
    if (candidate.isNotEmpty && containsDistro(candidate)) {
      return installedDistros.firstWhere(
        (item) => item.toLowerCase() == candidate.toLowerCase(),
      );
    }
    if (defaultDistro.isNotEmpty) return defaultDistro;
    return installedDistros.isEmpty ? '' : installedDistros.first;
  }

  String statusLabelFor(String distro) {
    if (isKali(distro)) return '$distro • Security';
    if (distro == defaultDistro) return '$distro • Default';
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

  static String _resolveDefault(List<String> distros, String requestedDefault) {
    final wanted = requestedDefault.trim().toLowerCase();
    if (wanted.isNotEmpty) {
      for (final distro in distros) {
        if (distro.toLowerCase() == wanted) return distro;
      }
    }
    return distros.isEmpty ? '' : distros.first;
  }
}
