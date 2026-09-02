import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/window_manager.dart';

class CloudOSDriveWindow extends StatefulWidget {
  const CloudOSDriveWindow({
    super.key,
    required this.bridge,
    required this.windowManager,
  });

  final CloudOSBridge bridge;
  final WindowManager windowManager;

  @override
  State<CloudOSDriveWindow> createState() => _CloudOSDriveWindowState();
}

class _CloudOSDriveWindowState extends State<CloudOSDriveWindow> {
  final List<CloudFileItem> _driveFiles = <CloudFileItem>[];
  late final Directory _driveDir;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];
    final base = localAppData?.trim().isNotEmpty == true
        ? localAppData!
        : (userProfile?.trim().isNotEmpty == true
            ? '$userProfile\\AppData\\Local'
            : Directory.current.path);
    _driveDir = Directory('$base\\CloudOS\\Drive');
    unawaited(_loadDriveFiles());
  }

  Future<void> _loadDriveFiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      if (!await _driveDir.exists()) {
        await _driveDir.create(recursive: true);
      }

      final items = <CloudFileItem>[];
      await for (final entity in _driveDir.list(followLinks: false)) {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        final name = entity.path.split(RegExp(r'[\\/]')).last;
        final ext = isDir || !name.contains('.')
            ? ''
            : '.${name.split('.').last}';

        items.add(
          CloudFileItem(
            id: entity.path,
            name: name,
            displayName: name,
            path: entity.path,
            canonicalPath: entity.path,
            locationKind: LocationKind.windows,
            fileKind: isDir ? FileKind.folder : _determineFileKind(ext),
            extension: ext,
            size: stat.size.toDouble(),
            sizeFormatted: isDir
                ? '--'
                : '${(stat.size / 1024).toStringAsFixed(1)} KB',
            modifiedFormatted:
                '${stat.modified.day.toString().padLeft(2, '0')}/${stat.modified.month.toString().padLeft(2, '0')} ${stat.modified.hour.toString().padLeft(2, '0')}:${stat.modified.minute.toString().padLeft(2, '0')}',
            createdFormatted: '',
            isDirectory: isDir,
            isHidden: name.startsWith('.'),
            isReadOnly: false,
            isSystem: false,
            isSymlink: entity is Link,
            distro: '',
            iconKey: isDir ? 'folder' : 'file_document',
          ),
        );
      }

      items.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _driveFiles
          ..clear()
          ..addAll(items);
      });
    } catch (error, stackTrace) {
      CloudOSLogger.error('CloudOSDriveWindow', 'loadDriveFiles', error, stackTrace);
      if (mounted) {
        setState(() => _loadError = 'Não foi possível ler o CloudOS Drive: $error');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  FileKind _determineFileKind(String ext) {
    final lower = ext.toLowerCase();
    if (<String>{
      '.txt',
      '.md',
      '.log',
      '.csv',
      '.dart',
      '.c',
      '.h',
      '.cpp',
      '.hpp',
      '.js',
      '.ts',
      '.py',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
    }.contains(lower)) {
      return FileKind.code;
    }
    if (<String>{'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(lower)) {
      return FileKind.image;
    }
    if (<String>{'.mp3', '.wav', '.flac', '.ogg'}.contains(lower)) {
      return FileKind.audio;
    }
    if (<String>{'.mp4', '.mkv', '.avi', '.webm'}.contains(lower)) {
      return FileKind.video;
    }
    return FileKind.document;
  }

  bool _isInternalTextFile(CloudFileItem item) {
    final ext = item.extension.toLowerCase();
    return <String>{
      '.txt',
      '.md',
      '.log',
      '.csv',
      '.dart',
      '.c',
      '.h',
      '.cpp',
      '.hpp',
      '.js',
      '.ts',
      '.py',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
    }.contains(ext);
  }

  Future<void> _openItem(CloudFileItem item) async {
    if (item.isDirectory) {
      widget.windowManager.openWindow(
        'cloudos:files',
        params: <String, dynamic>{'initialPath': item.path},
      );
      return;
    }

    if (_isInternalTextFile(item)) {
      widget.windowManager.openWindow(
        'cloudos:notepad',
        params: <String, dynamic>{'initialFilePath': item.path},
      );
      return;
    }

    try {
      final opened = await widget.bridge.openDefault(item.path);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir ${item.name}.')),
        );
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error('CloudOSDriveWindow', 'openDefault', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao abrir ${item.name}: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F141C),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(
                bottom: BorderSide(color: Color(0xFF30363D), width: 1),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.folder_special_rounded,
                  color: Color(0xFF3FB950),
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'CloudOS Drive Local',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Armazenamento local em %LOCALAPPDATA%\\CloudOS\\Drive — sem sincronização em nuvem.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B949E),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar Arquivos',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Color(0xFF8B949E),
                  ),
                  onPressed: () => unawaited(_loadDriveFiles()),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    widget.windowManager.openWindow(
                      'cloudos:files',
                      params: <String, dynamic>{'initialPath': _driveDir.path},
                    );
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text(
                    'Abrir no Files',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF21262D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF58A6FF)),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B949E)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(_loadDriveFiles()),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_driveFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.folder_open_outlined,
              size: 48,
              color: Color(0xFF484F58),
            ),
            const SizedBox(height: 16),
            const Text(
              'Seu CloudOS Drive está vazio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Adicione arquivos ou crie documentos para armazená-los localmente no CloudOS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF8B949E)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => widget.windowManager.openWindow('cloudos:notepad'),
              icon: const Icon(Icons.note_add_rounded, size: 16),
              label: const Text('Novo Documento'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: ListView.separated(
        itemCount: _driveFiles.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          color: Color(0xFF21262D),
        ),
        itemBuilder: (context, index) {
          final item = _driveFiles[index];
          return ListTile(
            dense: true,
            leading: Icon(
              item.isDirectory
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_rounded,
              color: item.isDirectory
                  ? const Color(0xFF58A6FF)
                  : const Color(0xFF8B949E),
              size: 20,
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            subtitle: Text(
              '${item.sizeFormatted} • Modificado em ${item.modifiedFormatted}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8B949E),
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: Color(0xFF484F58),
            ),
            onTap: () => unawaited(_openItem(item)),
          );
        },
      ),
    );
  }
}
