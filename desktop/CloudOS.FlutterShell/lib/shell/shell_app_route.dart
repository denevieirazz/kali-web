enum ShellAppRoute {
  files,
  browser,
  terminal,
  external,
}

ShellAppRoute resolveShellAppRoute(String appId) {
  return switch (appId) {
    'files' || 'cloudos:files' => ShellAppRoute.files,
    'browser' || 'cloudos:browser' => ShellAppRoute.browser,
    'terminal' || 'cloudos:terminal' ||
    'ubuntu-terminal' || 'wsl:ubuntu-terminal' || 'linux:ubuntu-terminal' =>
      ShellAppRoute.terminal,
    _ => ShellAppRoute.external,
  };
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
