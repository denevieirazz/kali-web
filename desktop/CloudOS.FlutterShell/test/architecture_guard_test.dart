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
}
