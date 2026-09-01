import 'package:cloudos_flutter_shell/features/notifications/domain/notification_date_formatter.dart';
import 'package:cloudos_flutter_shell/features/start/domain/start_app_filter.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/shell/shell_app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudOS modular pure logic', () {
    const apps = <CloudApp>[
      CloudApp(
        id: 'windows:notepad',
        name: 'Bloco de Notas',
        icon: Icons.edit_note_rounded,
        platform: CloudAppPlatform.windows,
        subtitle: 'Editor de Texto',
        category: 'Produtividade',
      ),
      CloudApp(
        id: 'wsl:gimp',
        name: 'GIMP',
        icon: Icons.brush_rounded,
        platform: CloudAppPlatform.linux,
        subtitle: 'Image Editor',
        distro: 'Ubuntu',
        category: 'Criatividade',
      ),
      CloudApp(
        id: 'cloudos:settings',
        name: 'Configurações',
        icon: Icons.settings_rounded,
        platform: CloudAppPlatform.cloudos,
        category: 'Sistema',
      ),
    ];

    test('Start search matches name, subtitle, distro, and category', () {
      expect(
        filterStartApps(apps: apps, query: 'notas', selectedFilter: 'Todos'),
        <CloudApp>[apps[0]],
      );
      expect(
        filterStartApps(apps: apps, query: 'ubuntu', selectedFilter: 'Todos'),
        <CloudApp>[apps[1]],
      );
      expect(
        filterStartApps(apps: apps, query: 'sistema', selectedFilter: 'Todos'),
        <CloudApp>[apps[2]],
      );
    });

    test('Start Linux filter uses platform rather than display category', () {
      expect(
        filterStartApps(
          apps: apps,
          query: '',
          selectedFilter: 'Linux / WSL',
        ),
        <CloudApp>[apps[1]],
      );
    });

    test('Notification date formatter uses pt-BR presentation labels', () {
      expect(
        formatNotificationDate(DateTime(2026, 9, 1)),
        'Terça-feira, 1 de Setembro',
      );
    });

    test('shell app routing accepts preview and broker IDs', () {
      expect(resolveShellAppRoute('files'), ShellAppRoute.files);
      expect(resolveShellAppRoute('cloudos:files'), ShellAppRoute.files);
      expect(resolveShellAppRoute('browser'), ShellAppRoute.browser);
      expect(resolveShellAppRoute('cloudos:browser'), ShellAppRoute.browser);
      expect(resolveShellAppRoute('terminal'), ShellAppRoute.terminal);
      expect(resolveShellAppRoute('cloudos:terminal'), ShellAppRoute.terminal);
      expect(resolveShellAppRoute('ubuntu-terminal'), ShellAppRoute.terminal);
      expect(resolveShellAppRoute('wsl:ubuntu-terminal'), ShellAppRoute.terminal);
      expect(resolveShellAppRoute('linux:ubuntu-terminal'), ShellAppRoute.terminal);
      expect(resolveShellAppRoute('windows:notepad'), ShellAppRoute.external);
    });

    test('shell canonical launch IDs match System Broker catalog IDs', () {
      expect(canonicalLaunchId(ShellAppRoute.files), 'cloudos:files');
      expect(canonicalLaunchId(ShellAppRoute.browser), 'cloudos:browser');
      expect(canonicalLaunchId(ShellAppRoute.terminal), 'cloudos:terminal');
    });

    test('shell_models compatibility barrel exposes split model types', () {
      const snapshot = CloudSystemSnapshot(
        deviceName: 'CloudOS Test',
        networkName: 'Test Network',
        volume: 0.5,
        brightness: 0.75,
        batteryPercent: 80,
        wslAvailable: true,
        distros: <String>['Ubuntu'],
      );
      const file = CloudFileItem(
        name: 'Docs',
        path: r'C:\Docs',
        isFolder: true,
        sizeFormatted: '1 item',
        modifiedFormatted: 'Hoje',
        source: CloudFileSource.windows,
      );

      expect(snapshot.distros, <String>['Ubuntu']);
      expect(file.source, CloudFileSource.windows);
    });
  });
}
