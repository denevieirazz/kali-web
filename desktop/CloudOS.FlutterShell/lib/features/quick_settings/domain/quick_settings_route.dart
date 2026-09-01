enum QuickSettingsRoute {
  root,
  wifi,
  bluetooth,
  nightLight,
  focus,
}

String quickSettingsLaunchId(QuickSettingsRoute route) {
  return switch (route) {
    QuickSettingsRoute.root => 'cloudos:settings',
    QuickSettingsRoute.wifi => 'cloudos:settings:wifi',
    QuickSettingsRoute.bluetooth => 'cloudos:settings:bluetooth',
    QuickSettingsRoute.nightLight => 'cloudos:settings:nightlight',
    QuickSettingsRoute.focus => 'cloudos:settings:focus',
  };
}
