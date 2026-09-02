class TerminalLaunchContext {
  const TerminalLaunchContext({
    required this.appId,
    required this.workingDirectory,
    this.distro,
  });

  final String appId;
  final String workingDirectory;
  final String? distro;

  bool get isWsl => appId == 'wsl:terminal';

  Map<String, dynamic> get params => <String, dynamic>{
    'initialWorkingDirectory': workingDirectory,
    if (distro != null && distro!.isNotEmpty) 'initialDistro': distro!,
  };
}

TerminalLaunchContext? resolveTerminalLaunchContext(
  String rawPath, {
  String? distroHint,
}) {
  final path = rawPath.trim();
  if (path.isEmpty) return null;

  final windowsNormalized = path.replaceAll('/', '\\');
  final lower = windowsNormalized.toLowerCase();
  const prefixes = <String>[
    '\\\\wsl.localhost\\',
    '\\\\wsl\$\\',
  ];

  for (final prefix in prefixes) {
    if (!lower.startsWith(prefix.toLowerCase())) continue;

    final remainder = windowsNormalized.substring(prefix.length);
    final components = remainder
        .split(RegExp(r'[\\/]+'))
        .where((component) => component.isNotEmpty)
        .toList(growable: false);
    if (components.isEmpty) return null;

    final distro = components.first.trim();
    if (distro.isEmpty) return null;

    final linuxPath = components.length == 1
        ? '/'
        : '/${components.skip(1).join('/')}';
    return TerminalLaunchContext(
      appId: 'wsl:terminal',
      distro: distro,
      workingDirectory: linuxPath,
    );
  }

  final hint = distroHint?.trim() ?? '';
  if (path.startsWith('/') && hint.isNotEmpty) {
    return TerminalLaunchContext(
      appId: 'wsl:terminal',
      distro: hint,
      workingDirectory: path,
    );
  }

  // A POSIX path without a distro is ambiguous and cannot safely be passed to
  // a Windows ConPTY process. Refuse it instead of silently opening PowerShell
  // with a bogus working directory.
  if (path.startsWith('/')) return null;

  // FilesController resolves virtual aliases such as "home" before this
  // function is called. Refuse unresolved virtual IDs instead of inventing a
  // filesystem location.
  final lowerPath = path.toLowerCase();
  if (lowerPath == 'home' || lowerPath.startsWith('wsl:')) return null;

  return TerminalLaunchContext(
    appId: 'cloudos:terminal',
    workingDirectory: path,
  );
}
