import 'dart:convert';

import 'package:cloudos_flutter_shell/models/file_models.dart';
import 'package:cloudos_flutter_shell/services/broker_text_file_service.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _TextBridge extends CloudOSBridge {
  _TextBridge({this.readContent = '', this.failWriteAfterChunk});

  final String readContent;
  final int? failWriteAfterChunk;
  final Map<String, List<int>> pendingWrites = <String, List<int>>{};
  String? committedContent;
  int writeCalls = 0;
  int abortCalls = 0;

  @override
  Future<List<KnownFolderModel>> getKnownFolders() async {
    return const <KnownFolderModel>[
      KnownFolderModel(
        id: 'documents',
        name: 'Documentos',
        path: r'Z:\Users\Tester\Documents',
        iconKey: 'documents',
      ),
    ];
  }

  @override
  Future<Map<String, Object?>> invokeBrokerRpc(
    String method,
    Map<String, Object?> payload,
  ) async {
    switch (method) {
      case 'files.text.readChunk':
        final bytes = utf8.encode(readContent);
        final offset = (payload['offsetBytes'] as num?)?.toInt() ?? 0;
        final maxBytes = (payload['maxBytes'] as num?)?.toInt() ?? 65536;
        final end = (offset + maxBytes).clamp(0, bytes.length).toInt();
        return <String, Object?>{
          'ok': true,
          'content': utf8.decode(bytes.sublist(offset, end)),
          'nextOffsetBytes': end,
          'totalBytes': bytes.length,
          'eof': end >= bytes.length,
          'encoding': 'utf-8',
        };
      case 'files.text.writeChunk':
        writeCalls++;
        if (failWriteAfterChunk != null && writeCalls > failWriteAfterChunk!) {
          return const <String, Object?>{
            'ok': false,
            'error': 'simulated_write_failure',
            'message': 'falha simulada',
          };
        }
        final tx = payload['transactionId'] as String? ?? '';
        final offset = (payload['offsetBytes'] as num?)?.toInt() ?? -1;
        final content = payload['content'] as String? ?? '';
        final bytes = pendingWrites.putIfAbsent(tx, () => <int>[]);
        if (offset != bytes.length) {
          return const <String, Object?>{
            'ok': false,
            'error': 'write_offset_mismatch',
            'message': 'offset inválido',
          };
        }
        bytes.addAll(utf8.encode(content));
        final finalChunk = payload['finalChunk'] == true;
        if (finalChunk) committedContent = utf8.decode(bytes);
        return <String, Object?>{
          'ok': true,
          'committed': finalChunk,
          'nextOffsetBytes': bytes.length,
          'bytesWritten': bytes.length,
        };
      case 'files.text.abortWrite':
        abortCalls++;
        final tx = payload['transactionId'] as String? ?? '';
        pendingWrites.remove(tx);
        return const <String, Object?>{'ok': true, 'deleted': true};
      default:
        throw CloudOSBridgeException('unsupported_test_rpc', method);
    }
  }
}

void main() {
  group('BrokerTextFileService V23', () {
    test('reassembles a file larger than one IPC chunk', () async {
      final content = List<String>.filled(150000, 'a').join();
      final bridge = _TextBridge(readContent: content);
      final service = BrokerTextFileService(bridge);

      final result = await service.readText(r'Z:\Work\large.txt');

      expect(result, content);
    });

    test('writes multi-chunk UTF-8 content and commits once', () async {
      final content = List<String>.filled(70000, 'ação🙂').join();
      final bridge = _TextBridge();
      final service = BrokerTextFileService(bridge);

      await service.writeText(r'Z:\Work\unicode.txt', content);

      expect(bridge.writeCalls, greaterThan(1));
      expect(bridge.committedContent, content);
      expect(bridge.abortCalls, 0);
    });

    test('aborts temporary transaction when a later chunk fails', () async {
      final content = List<String>.filled(150000, 'x').join();
      final bridge = _TextBridge(failWriteAfterChunk: 1);
      final service = BrokerTextFileService(bridge);

      await expectLater(
        service.writeText(r'Z:\Work\failure.txt', content),
        throwsA(isA<BrokerTextFileException>()),
      );

      expect(bridge.abortCalls, 1);
      expect(bridge.committedContent, isNull);
    });

    test('uses Broker known folders for save/open defaults', () async {
      final service = BrokerTextFileService(_TextBridge());

      expect(
        await service.preferredDirectory(),
        r'Z:\Users\Tester\Documents',
      );
      expect(
        service.joinPath(r'Z:\Users\Tester\Documents', 'note.txt'),
        r'Z:\Users\Tester\Documents\note.txt',
      );
    });

    test('rejects content larger than the editor limit before RPC', () async {
      final bridge = _TextBridge();
      final service = BrokerTextFileService(bridge);
      final oversized = 'a' * (BrokerTextFileService.maxFileBytes + 1);

      await expectLater(
        service.writeText(r'Z:\Work\too-large.txt', oversized),
        throwsA(isA<BrokerTextFileException>()),
      );
      expect(bridge.writeCalls, 0);
    });
  });
}
