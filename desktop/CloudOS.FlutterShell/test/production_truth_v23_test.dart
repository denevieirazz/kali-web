import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('V23 production truth and lifecycle boundary', () {
    test('production bridge contains no preview fixtures or fake machine data', () {
      final source = File('lib/services/cloudos_bridge.dart').readAsStringSync();

      for (final forbidden in <String>[
        'previewSnapshot',
        'previewApps',
        'previewKnownFolders',
        'previewDrives',
        'previewOpenWith',
        'previewFiles',
        'previewNotifications',
        'PreviewFallback',
        'v22-preview',
        r'C:\Users\User',
        'Ubuntu 24.04 LTS',
        'CloudOS Network • Wi-Fi 6',
        '512000000000',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }

      expect(source, contains("'bridge_type': 'Unavailable'"));
      expect(source, contains("'nativeBridgeAvailable': false"));
      expect(source, contains('currentWorkspace: 0'));
    });

    test('Start panel cannot terminate the process abruptly', () {
      final source = File('lib/widgets/start_panel.dart').readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('exit(0)')));
      expect(source, contains('onExitRequested'));
      expect(source, contains('await requestExit()'));
    });

    test('shell flushes durable session before orderly Flutter exit', () {
      final source = File('lib/shell/cloudos_shell.dart').readAsStringSync();
      final flush = source.indexOf('await windowManager.flushSession();');
      final orderlyExit = source.indexOf(
        'ServicesBinding.instance.exitApplication(AppExitType.required)',
      );

      expect(flush, greaterThanOrEqualTo(0));
      expect(orderlyExit, greaterThan(flush));
      expect(source, isNot(contains('exit(0)')));
      expect(source, contains('onExitRequested: _requestApplicationExit'));
    });

    test('shell owns exactly one shared live system-state service', () {
      final source = File('lib/shell/cloudos_shell.dart').readAsStringSync();
      final constructors = RegExp(r'SystemTrayStateService\(').allMatches(source);
      expect(constructors.length, 1);
      expect(
        RegExp(r'systemStateService: _systemState').allMatches(source).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('Broker system snapshot has a bounded cache and no workspace authority', () {
      final header = File(
        '../CloudOS.SystemBroker/src/system_service_v21.h',
      ).readAsStringSync();
      final implementation = File(
        '../CloudOS.SystemBroker/src/system_service_v21.cpp',
      ).readAsStringSync();

      expect(header, isNot(contains('current_workspace')));
      expect(implementation, isNot(contains('"currentWorkspace"')));
      expect(implementation, contains('kSnapshotCacheLifetimeMs = 2000'));
    });
  });
}
