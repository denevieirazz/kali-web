import 'dart:convert';

import 'cloudos_bridge.dart';

class BrokerTextFileException implements Exception {
  const BrokerTextFileException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : '$code: $message';
}

class BrokerTextFileService {
  BrokerTextFileService(this.bridge);

  static const int maxFileBytes = 16 * 1024 * 1024;
  static const int rpcChunkBytes = 64 * 1024;
  static const int writeChunkBytes = 48 * 1024;

  static int _transactionCounter = 0;

  final CloudOSBridge bridge;

  Future<String> readText(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw const BrokerTextFileException(
        'invalid_path',
        'O caminho do arquivo está vazio.',
      );
    }

    final output = StringBuffer();
    var offset = 0;
    int? totalBytes;
    var iterations = 0;

    while (true) {
      if (++iterations > 512) {
        throw const BrokerTextFileException(
          'read_iteration_limit',
          'A leitura excedeu o limite seguro de blocos.',
        );
      }

      final response = await bridge.invokeBrokerRpc(
        'files.text.readChunk',
        <String, Object?>{
          'path': normalizedPath,
          'offsetBytes': offset,
          'maxBytes': rpcChunkBytes,
        },
      );
      _requireOk(response, 'text_read_failed');

      final reportedTotal = (response['totalBytes'] as num?)?.toInt();
      if (reportedTotal == null || reportedTotal < 0) {
        throw const BrokerTextFileException(
          'invalid_read_response',
          'O Broker não informou o tamanho do arquivo.',
        );
      }
      totalBytes ??= reportedTotal;
      if (totalBytes != reportedTotal) {
        throw const BrokerTextFileException(
          'file_changed_during_read',
          'O arquivo mudou de tamanho durante a leitura.',
        );
      }
      if (reportedTotal > maxFileBytes) {
        throw const BrokerTextFileException(
          'file_too_large',
          'O arquivo é maior que 16 MB.',
        );
      }

      final content = response['content'] as String? ?? '';
      final nextOffset = (response['nextOffsetBytes'] as num?)?.toInt();
      final eof = response['eof'] == true;
      if (nextOffset == null || nextOffset < offset) {
        throw const BrokerTextFileException(
          'invalid_read_offset',
          'O Broker retornou um offset de leitura inválido.',
        );
      }
      if (!eof && nextOffset == offset) {
        throw const BrokerTextFileException(
          'read_stalled',
          'A leitura do arquivo não avançou.',
        );
      }

      output.write(content);
      offset = nextOffset;
      if (eof) return output.toString();
    }
  }

  Future<void> writeText(
    String path,
    String text, {
    bool createParents = true,
    bool overwrite = true,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw const BrokerTextFileException(
        'invalid_path',
        'O caminho do arquivo está vazio.',
      );
    }

    final bytes = utf8.encode(text);
    if (bytes.length > maxFileBytes) {
      throw const BrokerTextFileException(
        'file_too_large',
        'O conteúdo excede o limite de 16 MB do editor.',
      );
    }

    final transactionId = _newTransactionId();
    var offset = 0;
    var committed = false;

    try {
      if (bytes.isEmpty) {
        final response = await bridge.invokeBrokerRpc(
          'files.text.writeChunk',
          <String, Object?>{
            'path': normalizedPath,
            'transactionId': transactionId,
            'offsetBytes': 0,
            'content': '',
            'finalChunk': true,
            'createParents': createParents,
            'overwrite': overwrite,
          },
        );
        _requireOk(response, 'text_write_failed');
        committed = response['committed'] == true;
        if (!committed) {
          throw const BrokerTextFileException(
            'commit_not_confirmed',
            'O Broker não confirmou a gravação do arquivo.',
          );
        }
        return;
      }

      while (offset < bytes.length) {
        var end = (offset + writeChunkBytes).clamp(0, bytes.length).toInt();
        if (end < bytes.length) {
          while (end > offset && (bytes[end] & 0xC0) == 0x80) {
            end--;
          }
        }
        if (end <= offset) {
          throw const BrokerTextFileException(
            'utf8_chunk_boundary',
            'Não foi possível formar um bloco UTF-8 seguro.',
          );
        }

        final chunk = utf8.decode(bytes.sublist(offset, end));
        final finalChunk = end == bytes.length;
        final response = await bridge.invokeBrokerRpc(
          'files.text.writeChunk',
          <String, Object?>{
            'path': normalizedPath,
            'transactionId': transactionId,
            'offsetBytes': offset,
            'content': chunk,
            'finalChunk': finalChunk,
            'createParents': createParents,
            'overwrite': overwrite,
          },
        );
        _requireOk(response, 'text_write_failed');

        final nextOffset = (response['nextOffsetBytes'] as num?)?.toInt();
        if (!finalChunk && nextOffset != end) {
          throw const BrokerTextFileException(
            'write_offset_mismatch',
            'O Broker confirmou um offset de gravação inesperado.',
          );
        }

        if (finalChunk) {
          committed = response['committed'] == true;
          if (!committed) {
            throw const BrokerTextFileException(
              'commit_not_confirmed',
              'O Broker não confirmou o commit atômico do arquivo.',
            );
          }
        }
        offset = end;
      }
    } catch (_) {
      if (!committed) {
        try {
          await bridge.invokeBrokerRpc(
            'files.text.abortWrite',
            <String, Object?>{
              'path': normalizedPath,
              'transactionId': transactionId,
            },
          );
        } catch (_) {
          // The original write error remains authoritative.
        }
      }
      rethrow;
    }
  }

  Future<String?> preferredDirectory() async {
    try {
      final folders = await bridge.getKnownFolders();
      for (final wanted in const <String>['documents', 'home']) {
        for (final folder in folders) {
          if (folder.id.toLowerCase() == wanted && folder.path.trim().isNotEmpty) {
            return folder.path.trim();
          }
        }
      }
    } catch (_) {
      // Caller can still accept a manually entered absolute path.
    }
    return null;
  }

  String joinPath(String parent, String name) {
    final cleanParent = parent.trim();
    final cleanName = name.trim().replaceFirst(RegExp(r'^[\\/]+'), '');
    if (cleanParent.isEmpty) return cleanName;
    if (cleanName.isEmpty) return cleanParent;
    if (cleanParent.endsWith(r'\') || cleanParent.endsWith('/')) {
      return '$cleanParent$cleanName';
    }
    return '$cleanParent\\$cleanName';
  }

  static String _newTransactionId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final counter = (_transactionCounter = (_transactionCounter + 1) & 0x7fffffff);
    return 'flutter-$now-$counter';
  }

  static void _requireOk(Map<String, Object?> response, String fallbackCode) {
    if (response['ok'] == true) return;
    throw BrokerTextFileException(
      response['error'] as String? ?? fallbackCode,
      response['message'] as String? ?? 'O Broker rejeitou a operação de texto.',
    );
  }
}
