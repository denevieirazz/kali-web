import 'dart:io';

import 'package:cloudos_flutter_shell/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectRecord _project(
  String id,
  String name,
  String path, {
  DateTime? lastOpenedAt,
}) {
  return ProjectRecord(
    id: id,
    name: name,
    path: path,
    createdAt: DateTime.utc(2026, 9, 2, 12),
    lastOpenedAt: lastOpenedAt,
  );
}

void main() {
  group('ProjectStore V23 durability', () {
    test('serialized concurrent saves leave the last complete snapshot', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-projects-queue-');
      try {
        final store = ProjectStore.forTesting(root);
        final first = <ProjectRecord>[
          _project('one', 'One', r'D:\One'),
        ];
        final second = <ProjectRecord>[
          _project('two', 'Two', r'Z:\Two'),
          _project(
            'three',
            'Three',
            r'\\wsl.localhost\kali-linux\home\user\three',
            lastOpenedAt: DateTime.utc(2026, 9, 2, 13),
          ),
        ];

        final firstWrite = store.saveRecords(first);
        final secondWrite = store.saveRecords(second);
        await Future.wait(<Future<void>>[firstWrite, secondWrite]);
        await store.flush();

        final fresh = ProjectStore.forTesting(root);
        final loaded = await fresh.loadRecords();
        expect(loaded.map((project) => project.id), <String>['two', 'three']);
        expect(loaded.last.path, r'\\wsl.localhost\kali-linux\home\user\three');
        expect(loaded.last.lastOpenedAt, DateTime.utc(2026, 9, 2, 13).toLocal());
        expect(await File('${root.path}\\projects.json.tmp').exists(), isFalse);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('corrupt primary recovers the previous known-good backup', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-projects-recovery-');
      try {
        final store = ProjectStore.forTesting(root);
        await store.saveRecords(<ProjectRecord>[
          _project('stable', 'Stable', r'D:\Stable'),
        ]);
        await store.saveRecords(<ProjectRecord>[
          _project('newer', 'Newer', r'D:\Newer'),
        ]);
        await store.flush();

        final primary = File('${root.path}\\projects.json');
        final backup = File('${root.path}\\projects.json.bak');
        expect(await primary.exists(), isTrue);
        expect(await backup.exists(), isTrue);

        await primary.writeAsString('{broken-json', flush: true);

        final recovery = ProjectStore.forTesting(root);
        final recovered = await recovery.loadRecords();
        expect(recovered, hasLength(1));
        expect(recovered.single.id, 'stable');
        expect(recovered.single.path, r'D:\Stable');

        // loadRecords restores the backup to primary; another fresh instance
        // must read the primary successfully without fallback.
        final verifier = ProjectStore.forTesting(root);
        final verified = await verifier.loadRecords();
        expect(verified.single.id, 'stable');
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('read deduplicates IDs and case-insensitive paths', () async {
      final root = await Directory.systemTemp.createTemp('cloudos-projects-dedupe-');
      try {
        final file = File('${root.path}\\projects.json');
        final timestamp = DateTime.utc(2026, 9, 2).toIso8601String();
        await file.writeAsString(
          '''[
  {"id":"a","name":"A","path":"D:\\\\Work","createdAt":"$timestamp","lastOpenedAt":null},
  {"id":"a","name":"A duplicate id","path":"D:\\\\Other","createdAt":"$timestamp","lastOpenedAt":null},
  {"id":"b","name":"B duplicate path","path":"d:\\\\work","createdAt":"$timestamp","lastOpenedAt":null},
  {"id":"c","name":"C","path":"Z:\\\\Unique","createdAt":"$timestamp","lastOpenedAt":null}
]''',
          flush: true,
        );

        final store = ProjectStore.forTesting(root);
        final loaded = await store.loadRecords();
        expect(loaded.map((project) => project.id), <String>['a', 'c']);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    });

    test('compatibility helpers never inspect user workspace filesystem', () {
      expect(ProjectStore.detectType(r'Z:\Whatever'), 'Workspace');
      expect(ProjectStore.lastModified(r'Z:\Whatever'), isNull);
      expect(ProjectStore.makeId(r'D:\Work'), ProjectStore.makeId(r'd:\work'));
      expect(
        ProjectStore.makeId(r'D:\Work'),
        isNot(ProjectStore.makeId(r'D:\Different')),
      );
    });
  });
}
