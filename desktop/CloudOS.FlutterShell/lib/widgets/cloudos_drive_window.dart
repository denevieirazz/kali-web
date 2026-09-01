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

  @override
  void initState() {
    super.initState();
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? r'C:\CloudOS';
    _driveDir = Directory('$localAppData\\CloudOS\\Drive');
    _loadDriveFiles();
  }

  Future<void> _loadDriveFiles() async {
    setState(() => _isLoading = true);
    try {
      if (!_driveDir.existsSync()) {
        _driveDir.createSync(recursive: true);
      }

      final entities = _driveDir.listSync();
      _driveFiles.clear();

      for (final e in entities) {
        final stat = e.statSync();
        final isDir = e is Directory;
        final name = e.path.split(RegExp(r'[\\/]')).last;
        final ext = isDir ? '' : (name.contains('.') ? '.${name.split('.').last}' : '');

        _driveFiles.add(
          CloudFileItem(
            id: e.path,
            name: name,
            displayName: name,
            path: e.path,
            canonicalPath: e.path,
            locationKind: LocationKind.windows,
            fileKind: isDir ? FileKind.folder : _determineFileKind(ext),
            extension: ext,
            size: stat.size.toDouble(),
            sizeFormatted: isDir ? '--' : '${(stat.size / 1024).toStringAsFixed(1)} KB',
            modifiedFormatted: '${stat.modified.day}/${stat.modified.month} ${stat.modified.hour}:${stat.modified.minute.toString().padLeft(2, '0')}',
            createdFormatted: '${stat.changed.day}/${stat.changed.month}',
            isDirectory: isDir,
            isHidden: name.startsWith('.'),
            isReadOnly: false,
            isSystem: false,
            isSymlink: false,
            distro: '',
            iconKey: isDir ? 'folder' : 'file_document',
          ),
        );
      }
    } catch (e, st) {
      CloudOSLogger.error('CloudOSDriveWindow', 'loadDriveFiles', e, st);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  FileKind _determineFileKind(String ext) {
    final lower = ext.toLowerCase();
    if (['.dart', '.cpp', '.h', '.js', '.ts', '.py', '.json', '.yaml', '.xml'].contains(lower)) {
      return FileKind.code;
    }
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(lower)) {
      return FileKind.image;
    }
    if (['.mp3', '.wav', '.flac'].contains(lower)) {
      return FileKind.audio;
    }
    if (['.mp4', '.mkv', '.avi'].contains(lower)) {
      return FileKind.video;
    }
    return FileKind.document;
  }

  void _openItem(CloudFileItem item) {
    if (item.isDirectory) {
      widget.windowManager.openWindow('cloudos:files', params: {'initialPath': item.path});
    } else {
      widget.windowManager.openWindow('cloudos:notepad', params: {'initialFilePath': item.path});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F141C),
      child: Column(
        children: [
          // Header Drive Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: Color(0xFF30363D), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Color(0xFF3FB950), size: 20),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CloudOS Drive Local',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Armazenamento físico em %LOCALAPPDATA%\\CloudOS\\Drive',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Atualizar Arquivos',
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF8B949E)),
                  onPressed: _loadDriveFiles,
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    widget.windowManager.openWindow('cloudos:files', params: {'initialPath': _driveDir.path});
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Abrir no Files', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF21262D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          // File List or Onboarding
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF58A6FF)))
                : _driveFiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFF484F58)),
                            const SizedBox(height: 16),
                            const Text(
                              'Seu CloudOS Drive está pronto e vazio',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Adicione arquivos ou crie novos documentos para sincronizar no seu desktop.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF8B949E)),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () {
                                widget.windowManager.openWindow('cloudos:notepad');
                              },
                              icon: const Icon(Icons.note_add_rounded, size: 16),
                              label: const Text('Novo Documento'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF238636),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        child: ListView.separated(
                          itemCount: _driveFiles.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF21262D)),
                          itemBuilder: (context, index) {
                            final item = _driveFiles[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                item.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                color: item.isDirectory ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
                                size: 20,
                              ),
                              title: Text(item.name, style: const TextStyle(fontSize: 13, color: Colors.white)),
                              subtitle: Text(
                                '${item.sizeFormatted} • Modificado em ${item.modifiedFormatted}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF484F58)),
                              onTap: () => _openItem(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
