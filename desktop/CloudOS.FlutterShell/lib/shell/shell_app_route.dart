import '../features/terminal/domain/terminal_launch_coordinator.dart';

enum ShellAppRoute {
  files,
  browser,
  terminal,
  external,
}

ShellAppRoute classifyShellAppRoute(String appId) {
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
