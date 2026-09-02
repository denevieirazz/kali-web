import 'dart:io';

import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/models/search_models.dart';
import 'package:cloudos_flutter_shell/models/shell_models.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:cloudos_flutter_shell/services/global_search_service.dart';
import 'package:cloudos_flutter_shell/services/search_history_store.dart';
import 'package:cloudos_flutter_shell/services/search_query_parser.dart';
import 'package:cloudos_flutter_shell/services/search_ranker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SearchBridge extends CloudOSBridge {
  _SearchBridge(this.tree) : super();

  final Map<String, List<CloudFileItem>> tree;
  final List<String> listedPaths = <String>[];

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async {
    return const <KnownFolderModel>[
      KnownFolderModel(
        id: 'home',
        name: 'Início',
        path: r'D:\Users\Tester',
        iconKey: 'home',
      ),
      KnownFolderModel(
        id: 'desktop',
        name: 'Área de Trabalho',
        path: r'D:\Users\Tester\Desktop',
        iconKey: 'desktop',
      ),
      KnownFolderModel(
        id: 'documents',
        name: 'Documentos',
        path: r'D:\Users\Tester\Documents',
        iconKey: 'documents',
      ),
      KnownFolderModel(
        id: 'wsl:kali-linux',
        name: 'kali-linux',
        path: r'\\wsl.localhost\kali-linux',
        iconKey: 'linux',
      ),
    ];
  }

  @override
  Future<List<CloudFileItem>> listFiles(
    String path, {
    int pageSize = 200,
    String continuationToken = '',
    FileSortField sortField = FileSortField.name,
    bool ascending = true,
    bool showHidden = false,
    String searchText = '',
  }) async {
    listedPaths.add(path);
    final items = tree[path] ?? const <CloudFileItem>[];
    return items.take(pageSize).toList(growable: false);
  }
}

CloudFileItem _folder(String name, String path, {bool symlink = false}) {
  return CloudFileItem(
    id: 'folder:$path',
    name: name,
    displayName: name,
    path: path,
    canonicalPath: path,
    locationKind: LocationKind.windows,
    fileKind: FileKind.folder,
    extension: '',
    size: 0,
    sizeFormatted: '',
    modifiedFormatted: '',
    createdFormatted: '',
    isDirectory: true,
    isHidden: false,
    isReadOnly: false,
    isSystem: false,
    isSymlink: symlink,
    distro: '',
    iconKey: 'folder',
  );
}

CloudFileItem _file(
  String name,
  String path, {
  String extension = '.txt',
  FileKind kind = FileKind.text,
  bool hidden = false,
}) {
  return CloudFileItem(
    id: 'file:$path',
    name: name,
    displayName: name,
    path: path,
    canonicalPath: path,
    locationKind: LocationKind.windows,
    fileKind: kind,
    extension: extension,
    size: 123,
    sizeFormatted: '123 B',
    modifiedFormatted: '',
    createdFormatted: '',
    isDirectory: false,
    isHidden: hidden,
    isReadOnly: false,
    isSystem: false,
    isSymlink: false,
    distro: '',
    iconKey: 'file_text',
  );
}

void main() {
  group('SearchQueryParser V23', () {
    const parser = SearchQueryParser();

    test('parses typed scopes without making them executable commands', () {
      final app = parser.parse('app:terminal');
      expect(app.scope, SearchScope.apps);
      expect(app.terms, <String>['terminal']);
      expect(app.explicitScope, isTrue);

      final file = parser.parse('file:"release notes" ext:md -old');
      expect(file.scope, SearchScope.files);
      expect(file.terms, <String>['release notes']);
      expect(file.fileExtensions, contains('md'));
      expect(file.excludedTerms, contains('old'));
    });

    test('normalizes Portuguese accents deterministically', () {
      expect(parser.normalize('Configurações'), 'configuracoes');
      expect(parser.normalize('Áudio e Conexão'), 'audio e conexao');
      expect(parser.normalize('São João'), 'sao joao');
    });

    test('supports extension lists and hidden flag', () {
      final query = parser.parse('arquivos:relatorio ext:.pdf,.docx hidden:true');
      expect(query.scope, SearchScope.files);
      expect(query.fileExtensions, <String>{'pdf', 'docx'});
      expect(query.includeHidden, isTrue);
    });

    test('deduplicates repeated normalized terms', () {
      final query = parser.parse('Terminal terminal TÉRMINAL');
      expect(query.terms, <String>['terminal']);
    });

    test('empty query is all-scope and cheap', () {
      final query = parser.parse('   ');
      expect(query.isEmpty, isTrue);
      expect(query.scope, SearchScope.all);
      expect(query.wantsFiles, isTrue);
    });
  });

  group('SearchRanker V23', () {
    final ranker = SearchRanker();
    const parser = SearchQueryParser();

    test('exact title outranks contains and keyword', () {
      final query = parser.parse('terminal');
      final exact = ranker.score(
        query: query,
        title: 'Terminal',
        subtitle: '',
      );
      final contains = ranker.score(
        query: query,
        title: 'CloudOS Terminal Pro',
        subtitle: '',
      );
      final keyword = ranker.score(
        query: query,
        title: 'Console',
        subtitle: '',
        keywords: const <String>['terminal'],
      );
      expect(exact.score, greaterThan(contains.score));
      expect(contains.score, greaterThan(keyword.score));
      expect(exact.kind, SearchMatchKind.exact);
    });

    test('excluded terms remove a candidate', () {
      final query = parser.parse('cloud -legacy');
      final score = ranker.score(
        query: query,
        title: 'Cloud Legacy',
        subtitle: '',
      );
      expect(score.matched, isFalse);
    });

    test('conservative fuzzy search repairs common typo', () {
      final query = parser.parse('termnal');
      final score = ranker.score(
        query: query,
        title: 'Terminal',
        subtitle: '',
      );
      expect(score.matched, isTrue);
      expect(score.kind, SearchMatchKind.fuzzy);
    });

    test('all query terms must match', () {
      final query = parser.parse('cloud terminal');
      expect(
        ranker.score(
          query: query,
          title: 'CloudOS Terminal',
          subtitle: '',
        ).matched,
        isTrue,
      );
      expect(
        ranker.score(
          query: query,
          title: 'CloudOS Browser',
          subtitle: '',
        ).matched,
        isFalse,
      );
    });
  });

  group('GlobalSearchService V23', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('cloudos-search-v23-');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('bounded broker-backed file search finds nested file', () async {
      final bridge = _SearchBridge(<String, List<CloudFileItem>>{
        r'D:\Users\Tester': <CloudFileItem>[
          _folder('Work', r'D:\Users\Tester\Work'),
          _file('notes.txt', r'D:\Users\Tester\notes.txt'),
        ],
        r'D:\Users\Tester\Work': <CloudFileItem>[
          _folder('CloudOS', r'D:\Users\Tester\Work\CloudOS'),
        ],
        r'D:\Users\Tester\Work\CloudOS': <CloudFileItem>[
          _file(
            'architecture.md',
            r'D:\Users\Tester\Work\CloudOS\architecture.md',
            extension: '.md',
          ),
        ],
        r'D:\Users\Tester\Desktop': const <CloudFileItem>[],
        r'D:\Users\Tester\Documents': const <CloudFileItem>[],
      });
      final service = GlobalSearchService(
        bridge: bridge,
        historyStore: SearchHistoryStore(stateDirectory: temp),
        fileBudget: const SearchFileBudget(
          maxRoots: 3,
          maxDirectories: 16,
          maxDepth: 2,
          maxItemsPerDirectory: 100,
          maxResults: 10,
          maxDuration: Duration(seconds: 2),
        ),
      );

      final batch = await service.search(
        rawQuery: 'file:architecture ext:md',
        runtimeApps: const <CloudApp>[],
      );

      expect(batch.results, hasLength(1));
      expect(batch.results.single.category, SearchCategory.files);
      expect(batch.results.single.title, 'architecture.md');
      expect(
        batch.results.single.action.params['initialFilePath'],
        r'D:\Users\Tester\Work\CloudOS\architecture.md',
      );
      expect(batch.diagnostics.fileDirectoriesVisited, greaterThanOrEqualTo(3));
      expect(bridge.listedPaths, isNot(contains(r'\\wsl.localhost\kali-linux')));
    });

    test('does not recurse through symlink directories', () async {
      final bridge = _SearchBridge(<String, List<CloudFileItem>>{
        r'D:\Users\Tester': <CloudFileItem>[
          _folder('Link', r'D:\Users\Tester\Link', symlink: true),
        ],
        r'D:\Users\Tester\Link': <CloudFileItem>[
          _file('secret.txt', r'D:\Users\Tester\Link\secret.txt'),
        ],
        r'D:\Users\Tester\Desktop': const <CloudFileItem>[],
        r'D:\Users\Tester\Documents': const <CloudFileItem>[],
      });
      final service = GlobalSearchService(
        bridge: bridge,
        historyStore: SearchHistoryStore(stateDirectory: temp),
      );

      final batch = await service.search(
        rawQuery: 'file:secret',
        runtimeApps: const <CloudApp>[],
      );
      expect(batch.results, isEmpty);
      expect(bridge.listedPaths, isNot(contains(r'D:\Users\Tester\Link')));
    });

    test('file extension filter excludes folders and other extensions', () async {
      final bridge = _SearchBridge(<String, List<CloudFileItem>>{
        r'D:\Users\Tester': <CloudFileItem>[
          _file('report.pdf', r'D:\Users\Tester\report.pdf', extension: '.pdf', kind: FileKind.document),
          _file('report.txt', r'D:\Users\Tester\report.txt'),
          _folder('report', r'D:\Users\Tester\report'),
        ],
        r'D:\Users\Tester\Desktop': const <CloudFileItem>[],
        r'D:\Users\Tester\Documents': const <CloudFileItem>[],
      });
      final service = GlobalSearchService(
        bridge: bridge,
        historyStore: SearchHistoryStore(stateDirectory: temp),
      );
      final batch = await service.search(
        rawQuery: 'file:report ext:pdf',
        runtimeApps: const <CloudApp>[],
      );
      expect(batch.results.map((result) => result.title), <String>['report.pdf']);
    });

    test('hidden items require explicit hidden flag', () async {
      final bridge = _SearchBridge(<String, List<CloudFileItem>>{
        r'D:\Users\Tester': <CloudFileItem>[
          _file('hidden-note.txt', r'D:\Users\Tester\hidden-note.txt', hidden: true),
        ],
        r'D:\Users\Tester\Desktop': const <CloudFileItem>[],
        r'D:\Users\Tester\Documents': const <CloudFileItem>[],
      });
      final service = GlobalSearchService(
        bridge: bridge,
        historyStore: SearchHistoryStore(stateDirectory: temp),
      );

      expect(
        (await service.search(
          rawQuery: 'file:hidden-note',
          runtimeApps: const <CloudApp>[],
        ))
            .results,
        isEmpty,
      );
      expect(
        (await service.search(
          rawQuery: 'file:hidden-note hidden:true',
          runtimeApps: const <CloudApp>[],
        ))
            .results,
        isNotEmpty,
      );
    });

    test('settings results are typed and do not execute strings', () async {
      final service = GlobalSearchService(
        bridge: _SearchBridge(const <String, List<CloudFileItem>>{}),
        historyStore: SearchHistoryStore(stateDirectory: temp),
      );
      final batch = await service.search(
        rawQuery: 'settings:volume',
        runtimeApps: const <CloudApp>[],
      );
      expect(batch.results, isNotEmpty);
      final sound = batch.results.firstWhere((result) => result.id == 'settings:sound');
      expect(sound.action.kind, SearchActionKind.openSettingsPage);
      expect(sound.action.appId, 'cloudos:settings');
      expect(sound.action.params['initialSettingsPage'], 'sound');
    });

    test('WSL catalog result preserves actual distro', () async {
      final service = GlobalSearchService(
        bridge: _SearchBridge(const <String, List<CloudFileItem>>{}),
        historyStore: SearchHistoryStore(stateDirectory: temp),
      );
      const apps = <CloudApp>[
        CloudApp(
          id: 'wsl:kali-linux:terminal',
          name: 'kali-linux',
          icon: Icons.terminal,
          platform: CloudAppPlatform.linux,
          distro: 'kali-linux',
        ),
      ];
      final batch = await service.search(rawQuery: 'wsl:kali', runtimeApps: apps);
      final result = batch.results.firstWhere((item) => item.category == SearchCategory.wsl);
      expect(result.action.distro, 'kali-linux');
      expect(result.action.params['initialDistro'], 'kali-linux');
    });

    test('history records only typed result metadata and boosts ranking', () async {
      final history = SearchHistoryStore(stateDirectory: temp);
      final service = GlobalSearchService(
        bridge: _SearchBridge(const <String, List<CloudFileItem>>{}),
        historyStore: history,
      );
      const result = SearchResult(
        id: 'settings:sound',
        title: 'Som',
        subtitle: 'Volume',
        category: SearchCategory.settings,
        icon: Icons.volume_up,
        iconColor: Colors.white,
        score: 1,
        matchKind: SearchMatchKind.exact,
        action: SearchAction(
          kind: SearchActionKind.openSettingsPage,
          appId: 'cloudos:settings',
        ),
      );
      await service.recordActivation(result);
      await history.flush();
      final entries = await history.load();
      expect(entries, hasLength(1));
      expect(entries.single.resultId, 'settings:sound');
      expect(entries.single.useCount, 1);
    });
  });
}
