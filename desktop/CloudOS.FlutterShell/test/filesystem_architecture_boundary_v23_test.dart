import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('V23 user-filesystem architecture boundary', () {
    final brokerBackedSources = <String>[
      'lib/widgets/cloudos_drive_window.dart',
      'lib/widgets/projects_window.dart',
      'lib/widgets/notepad_window.dart',
      'lib/services/cloudos_drive_service.dart',
      'lib/services/project_filesystem_service.dart',
      'lib/services/broker_filesystem_service.dart',
      'lib/services/broker_text_file_service.dart',
    ];

    for (final path in brokerBackedSources) {
      test('$path does not bypass the System Broker', () {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains("import 'dart:io'")));
        expect(source, isNot(contains('Platform.environment')));
        expect(source, isNot(contains('Directory(')));
        expect(source, isNot(contains('File(')));
        expect(source, isNot(contains('Process.start')));
        expect(source, isNot(contains('Process.run')));
      });
    }

    test('ProjectStore limits dart:io to CloudOS-owned metadata persistence', () {
      final source = File('lib/services/project_store.dart').readAsStringSync();
      expect(source, contains('projects.json'));
      expect(source, isNot(contains('Directory(path)')));
      expect(source, isNot(contains("File('$path")));
      expect(source, isNot(contains('existsSync')));
      expect(source, isNot(contains('statSync')));
    });

    test('native bridge exposes only the three typed text RPC methods', () {
      final source = File(
        'windows/runner/cloudos_flutter_bridge_v20.cpp',
      ).readAsStringSync();
      expect(source, contains('"files.text.readChunk"'));
      expect(source, contains('"files.text.writeChunk"'));
      expect(source, contains('"files.text.abortWrite"'));
      expect(source, isNot(contains('"files.execute"')));
      expect(source, isNot(contains('"files.command"')));
    });
  });
}
