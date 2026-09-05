import '../features/terminal/domain/terminal_launch_coordinator.dart';

enum ShellAppRoute {
  files,
  browser,
  terminal,
  external,
}

ShellAppRoute classifyShellAppRoute(String appId) {
  if (appId.startsWith('wsl:') && appId.endsWith(':terminal')) {
    return ShellAppRoute.terminal;
  }
  return switch (appId) {
    'files' || 'cloudos:files' => ShellAppRoute.files,
    'browser' || 'cloudos:browser' => ShellAppRoute.browser,
    'terminal' || 'cloudos:terminal' ||
    'windows:cmd' || 'windows:powershell' ||
    'ubuntu-terminal' || 'wsl:ubuntu-terminal' || 'linux:ubuntu-terminal' =>
      ShellAppRoute.terminal,
    _ => ShellAppRoute.external,
  };
}

ShellAppRoute resolveShellAppRoute(String appId) {
  if (appId == 'windows:cmd') {
    TerminalLaunchCoordinator.request(TerminalLaunchProfile.cmd);
  } else if (appId == 'windows:powershell') {
    TerminalLaunchCoordinator.request(TerminalLaunchProfile.powershell);
  } else if (appId.startsWith('wsl:') && appId.endsWith(':terminal')) {
    final parts = appId.split(':');
    final distro = parts.length >= 3 ? parts[1] : '';
    TerminalLaunchCoordinator.request(TerminalLaunchProfile.wsl, distro: distro);
  } else if (appId == 'ubuntu-terminal' ||
      appId == 'wsl:ubuntu-terminal' ||
      appId == 'linux:ubuntu-terminal') {
    TerminalLaunchCoordinator.request(TerminalLaunchProfile.wsl, distro: 'Ubuntu');
  }
  return classifyShellAppRoute(appId);
}

String canonicalLaunchId(ShellAppRoute route) {
  return switch (route) {
    ShellAppRoute.files => 'cloudos:files',
    ShellAppRoute.browser => 'cloudos:browser',
    ShellAppRoute.terminal => 'cloudos:terminal',
    ShellAppRoute.external => throw ArgumentError.value(
        route,
        'route',
        'External routes keep the original app ID.',
      ),
  };
}
