import 'dart:async';

import 'package:flutter/material.dart';

import '../models/file_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_drive_service.dart';
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
  late final CloudOSDriveService _service;
  List<CloudFileItem> _driveFiles = const <CloudFileItem>[];
  String? _drivePath;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _service = CloudOSDriveService(widget.bridge);
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
      final snapshot = await _service.load();
      if (!mounted) return;
      if (snapshot == null) {
        setState(() {
          _driveFiles = const <CloudFileItem>[];
          _drivePath = null;
          _loadError =
              'O Files V22 não conseguiu resolver o armazenamento local do CloudOS.';
        });
        return;
      }
      setState(() {
        _drivePath = snapshot.path;
        _driveFiles = snapshot.items;
      });
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'CloudOSDriveWindow',
        'loadDriveFiles',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() {
          _loadError = 'Não foi possível ler o CloudOS Drive pelo Files V22.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isInternalTextFile(CloudFileItem item) {
    return item.fileKind == FileKind.text || item.fileKind == FileKind.code;
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
      CloudOSLogger.error(
        'CloudOSDriveWindow',
        'openDefault',
        error,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao abrir ${item.name}.')),
        );
      }
    }
  }

  void _openInFiles() {
    final path = _drivePath;
    if (path == null || path.isEmpty) return;
    widget.windowManager.openWindow(
      'cloudos:files',
      params: <String, dynamic>{'initialPath': path},
    );
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
                        'Armazenamento local do perfil via Files V22 — sem sincronização em nuvem.',
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
                  onPressed: _drivePath == null ? null : _openInFiles,
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
              'Nenhum arquivo de exemplo é criado automaticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF8B949E)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _drivePath == null ? null : _openInFiles,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Gerenciar no Files'),
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
          final modified = item.modifiedFormatted.trim();
          return ListTile(
            dense: true,
            leading: Icon(item.icon, color: item.iconColor, size: 20),
            title: Text(
              item.name,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            subtitle: Text(
              modified.isEmpty
                  ? item.sizeFormatted
                  : '${item.sizeFormatted} • $modified',
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
