import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const legacyFeatureExports = <String, String>{
    'lib/widgets/cloud_taskbar.dart':
        "export '../features/taskbar/presentation/cloud_taskbar.dart';",
    'lib/widgets/files_window.dart':
        "export '../features/files/presentation/files_window.dart';",
    'lib/widgets/notification_center.dart':
        "export '../features/notifications/presentation/notification_center_panel.dart';",
    'lib/widgets/quick_settings_panel.dart':
        "export '../features/quick_settings/presentation/quick_settings_panel.dart';",
    'lib/widgets/start_panel.dart':
        "export '../features/start/presentation/start_panel.dart';",
  };

  test('legacy feature paths stay thin compatibility exports', () {
    for (final entry in legacyFeatureExports.entries) {
      final source = File(entry.key).readAsStringSync();

      expect(source, contains(entry.value), reason: entry.key);
      expect(
        RegExp(r'\b(class|enum|mixin|extension)\s+').hasMatch(source),
        isFalse,
        reason: '${entry.key} must not regain implementation code',
      );

      final executableLines = source
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('//'))
          .toList(growable: false);
      expect(executableLines, <String>[entry.value], reason: entry.key);
    }
  });

  test('production code does not depend on legacy feature paths', () {
    final legacyFragments = legacyFeatureExports.keys
        .map((path) => path.substring('lib/'.length))
        .toList(growable: false);

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (legacyFeatureExports.containsKey(normalizedPath)) continue;

      final source = file.readAsStringSync();
      for (final fragment in legacyFragments) {
        expect(
          source.contains(fragment),
          isFalse,
          reason: '$normalizedPath must import the canonical feature, not $fragment',
        );
      }
    }
  });

  test('shell_models remains a compatibility-only barrel', () {
    final source = File('lib/models/shell_models.dart').readAsStringSync();
    const expectedExports = <String>{
      "export 'cloud_app.dart';",
      "export 'cloud_file_item.dart';",
      "export 'cloud_notification.dart';",
      "export 'cloud_system_snapshot.dart';",
    };

    final executableLines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('//'))
        .toSet();

    expect(executableLines, expectedExports);
    expect(
      RegExp(r'\b(class|enum|mixin|extension)\s+').hasMatch(source),
      isFalse,
      reason: 'shell_models.dart must not regain model implementations',
    );
  });

  test('WSL app discovery stays passive and does not wake Linux', () {
    final appService = File(
      '../CloudOS.SystemBroker/src/app_service_v21.cpp',
    ).readAsStringSync();
    final refreshStart = appService.indexOf('void AppServiceV21::Refresh()');
    final launchStart = appService.indexOf('bool AppServiceV21::LaunchApp');

    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(launchStart, greaterThan(refreshStart));

    final refreshSource = appService.substring(refreshStart, launchStart);
    expect(refreshSource, contains('GetDistributions()'));
    expect(
      refreshSource,
      isNot(contains('ShellExecuteW')),
      reason: 'catalog refresh must not launch wsl.exe or any application',
    );
    expect(
      refreshSource,
      isNot(contains('CreateProcessW')),
      reason: 'catalog refresh must remain passive',
    );
    expect(
      refreshSource,
      isNot(contains('IsWslCommandAvailable(')),
      reason: 'catalog refresh must not probe packages inside a WSL distro',
    );
  });

  test('WSL discovery never fabricates a fallback distro', () {
    final wslService = File(
      '../CloudOS.SystemBroker/src/wsl_service_v21.cpp',
    ).readAsStringSync();

    expect(
      wslService,
      isNot(contains('distros_.push_back("Ubuntu")')),
      reason: 'configured distros must come from Windows state, never fixtures',
    );
    expect(wslService, contains('DefaultDistribution'));
  });
}
