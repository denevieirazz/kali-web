import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/services/cloudos_preferences.dart';

void main() {
  group('CloudOSPreferences Tests', () {
    late Directory tempDir;
    late String prefsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cloudos_prefs_test_');
      prefsPath = '${tempDir.path}${Platform.pathSeparator}prefs.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('default preferences have schemaVersion 2 and safe defaults', () {
      final prefs = CloudOSPreferences();
      expect(prefs.schemaVersion, equals(2));
      expect(prefs.appearanceTheme, equals('auto'));
      expect(prefs.performanceProfile, equals('auto'));
      expect(prefs.filesViewMode, equals('details'));
      expect(prefs.pinnedAppIds, contains('files'));
      expect(prefs.pinnedAppIds, contains('terminal'));
    });

    test('schema migration v1 to v2 clamps coordinates and sanitizes invalid options', () {
      final v1Json = {
        'schemaVersion': 1,
        'firstRunCompleted': true,
        'appearanceTheme': 'invalid_theme',
        'performanceProfile': 'invalid_profile',
        'filesViewMode': 'unknown_mode',
        'desktopIconPositions': {
          'icon1': [-50.0, 999999.0],
          'icon2': [150.0, 200.0],
        },
      };

      final migrated = CloudOSPreferences.fromJson(v1Json);
      expect(migrated.schemaVersion, equals(2));
      expect(migrated.appearanceTheme, equals('auto'));
      expect(migrated.performanceProfile, equals('auto'));
      expect(migrated.filesViewMode, equals('details'));

      final pos1 = migrated.getIconPosition('icon1');
      expect(pos1, isNotNull);
      expect(pos1!.dx, equals(0.0)); // clamped from -50
      expect(pos1.dy, equals(10000.0)); // clamped from 999999

      final pos2 = migrated.getIconPosition('icon2');
      expect(pos2, isNotNull);
      expect(pos2!.dx, equals(150.0));
      expect(pos2.dy, equals(200.0));
    });

    test('atomic save creates file and rotates bounded backups (max 5)', () async {
      final prefs = CloudOSPreferences();
      prefs.appearanceTheme = 'dark';

      // Save initial
      await prefs.save(prefsPath);
      expect(await File(prefsPath).exists(), isTrue);

      // Save 6 more times to trigger backup rotation
      for (var i = 1; i <= 6; i++) {
        prefs.hardwareSummary = 'Save #$i';
        await prefs.save(prefsPath);
      }

      // Check that backups 1 to 5 exist
      for (var i = 1; i <= 5; i++) {
        expect(await File('$prefsPath.backup.$i.json').exists(), isTrue);
      }
      // Check that backup 6 does not exist
      expect(await File('$prefsPath.backup.6.json').exists(), isFalse);
    });

    test('corrupt json file is quarantined and fallback occurs', () async {
      // Create a corrupt file
      final file = File(prefsPath);
      await file.writeAsString('{ invalid json syntax: not closed');

      final loaded = await CloudOSPreferences.load(prefsPath);
      expect(loaded, isNotNull);
      expect(loaded.schemaVersion, equals(2)); // Returned default

      // Verify the corrupt file was quarantined
      final corruptFiles = tempDir
          .listSync()
          .where((f) => f.path.contains('prefs.json.corrupt.'))
          .toList();
      expect(corruptFiles.length, equals(1));
    });

    test('export and import JSON preserves all settings', () {
      final original = CloudOSPreferences(
        firstRunCompleted: true,
        appearanceTheme: 'light',
        performanceProfile: 'performance',
        filesViewMode: 'grid',
      );
      original.setIconPosition('my_file', 400.0, 300.0);
      original.recordAppLaunch('terminal');

      final exported = original.exportJson();
      final imported = CloudOSPreferences.importJson(exported);

      expect(imported.firstRunCompleted, isTrue);
      expect(imported.appearanceTheme, equals('light'));
      expect(imported.performanceProfile, equals('performance'));
      expect(imported.filesViewMode, equals('grid'));
      expect(imported.getIconPosition('my_file')!.dx, equals(400.0));
      expect(imported.getIconPosition('my_file')!.dy, equals(300.0));
      expect(imported.recentAppIds, contains('terminal'));
    });
  });
}
