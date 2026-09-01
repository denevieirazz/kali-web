import 'dart:io';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class FilesWindowV21 extends StatefulWidget {
  const FilesWindowV21({
    required this.snapshot,
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  State<FilesWindowV21> createState() => _FilesWindowV21State();
}

class _FilesWindowV21State extends State<FilesWindowV21> {
  final TextEditingController _search = TextEditingController();
  late String currentPath;
  List<FileSystemEntity> entries = const <FileSystemEntity>[];
  bool loading = true;
  String? error;
  String query = '';

  @override
  void initState() {
    super.initState();
    currentPath = _homePath;
    _load(currentPath);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _homePath => Platform.environment['USERPROFILE'] ?? r'C:\';

  List<_QuickLocation> get _locations {
    final profile = _homePath;
    final items = <_QuickLocation>[
      _QuickLocation('Início', profile, Icons.home_rounded, CloudOSColors.accent),
      _QuickLocation('Área de Trabalho', '$profile\\Desktop', Icons.desktop_windows_rounded, CloudOSColors.secondary),
      _QuickLocation('Documentos', '$profile\\Documents', Icons.description_rounded, CloudOSColors.secondary),
      _QuickLocation('Downloads', '$profile\\Downloads', Icons.download_rounded, CloudOSColors.secondary),
      const _QuickLocation('Disco Local (C:)', r'C:\', Icons.storage_rounded, CloudOSColors.windows),
    ];

    for (final distro in widget.snapshot.distros) {
      if (distro.trim().isEmpty) continue;
      items.add(
        _QuickLocation(
          '$distro (WSL)',
          '\\\\wsl.localhost\\$distro',
          Icons.terminal_rounded,
          CloudOSColors.linux,
        ),
      );
    }
    return items;
  }

  Future<void> _load(String path) async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        throw FileSystemException('Pasta não encontrada', path);
      }

      final loaded = await dir.list(followLinks: false).toList();
      loaded.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return _entityName(a).toLowerCase().compareTo(_entityName(b).toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        currentPath = dir.path;
        entries = loaded;
        loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.osError?.message ?? e.message;
        entries = const <FileSystemEntity>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
        entries = const <FileSystemEntity>[];
      });
    }
  }

  String _entityName(FileSystemEntity entity) {
    var path = entity.path.replaceAll('/', r'\');
    while (path.endsWith(r'\') && path.length > 3) {
      path = path.substring(0, path.length - 1);
    }
    final index = path.lastIndexOf(r'\');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  List<FileSystemEntity> get _visibleEntries {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return entries;
    return entries
        .where((entry) => _entityName(entry).toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      await _load(entity.path);
      return;
    }

    try {
      await Process.start(
        'explorer.exe',
        <String>[entity.path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o arquivo no Windows.')),
      );
    }
  }

  Future<void> _goUp() async {
    final parent = Directory(currentPath).parent.path;
    if (parent == currentPath) return;
    await _load(parent);
  }

  Future<void> _openInExplorer() async {
    try {
      await Process.start(
        'explorer.exe',
        <String>[currentPath],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esta pasta no Explorer.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEntries;
    return SizedBox(
      width: 980,
      height: 610,
      child: GlassSurface(
        borderRadius: 14,
        blur: 24,
        color: const Color(0xF4101822),
        borderColor: CloudOSColors.borderStrong,
        child: Column(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => widget.onDrag(details.delta),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 14),
                    const Icon(Icons.folder_rounded, color: CloudOSColors.accent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Arquivos V21',
                      style: TextStyle(color: CloudOSColors.text, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'filesystem real',
                      style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Minimizar',
                      onPressed: widget.onMinimize,
                      icon: const Icon(Icons.remove_rounded, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, size: 17, color: CloudOSColors.danger),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 218,
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 4, 8, 7),
                          child: Text(
                            'LOCAIS',
                            style: TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        for (final location in _locations)
                          _LocationTile(
                            location: location,
                            selected: _samePath(location.path, currentPath),
                            onTap: () => _load(location.path),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: 48,
                          child: Row(
                            children: <Widget>[
                              IconButton(
                                tooltip: 'Subir pasta',
                                onPressed: _goUp,
                                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Atualizar',
                                onPressed: () => _load(currentPath),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                              ),
                              Expanded(
                                child: Container(
                                  height: 32,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: CloudOSColors.elevated.withValues(alpha: 0.45),
                                    border: Border.all(color: CloudOSColors.border),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    currentPath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: CloudOSColors.secondary, fontSize: 11),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 190,
                                height: 32,
                                child: TextField(
                                  controller: _search,
                                  onChanged: (value) => setState(() => query = value),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search_rounded, size: 17),
                                    hintText: 'Filtrar...',
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Abrir no Explorer',
                                onPressed: _openInExplorer,
                                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: loading
                              ? const Center(child: CircularProgressIndicator())
                              : error != null
                                  ? _FilesError(message: error!, onRetry: () => _load(currentPath))
                                  : visible.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'Nenhum item encontrado.',
                                            style: TextStyle(color: CloudOSColors.caption),
                                          ),
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          itemCount: visible.length,
                                          itemBuilder: (context, index) {
                                            final entity = visible[index];
                                            final isDir = entity is Directory;
                                            return ListTile(
                                              dense: true,
                                              leading: Icon(
                                                isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                                color: isDir ? CloudOSColors.accent : CloudOSColors.secondary,
                                                size: 20,
                                              ),
                                              title: Text(
                                                _entityName(entity),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: CloudOSColors.text, fontSize: 12),
                                              ),
                                              subtitle: Text(
                                                entity.path,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                                              ),
                                              trailing: Icon(
                                                isDir ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                                                size: 17,
                                                color: CloudOSColors.caption,
                                              ),
                                              onTap: () => _openEntity(entity),
                                            );
                                          },
                                        ),
                        ),
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: CloudOSColors.border)),
                          ),
                          child: Text(
                            loading ? 'Carregando...' : '${visible.length} item(ns)',
                            style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _samePath(String a, String b) {
    String normalize(String value) => value.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
    return normalize(a) == normalize(b);
  }
}

class _QuickLocation {
  const _QuickLocation(this.label, this.path, this.icon, this.color);

  final String label;
  final String path;
  final IconData icon;
  final Color color;
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  final _QuickLocation location;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: CloudOSColors.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(location.icon, size: 17, color: selected ? CloudOSColors.accent : location.color),
        title: Text(
          location.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? CloudOSColors.text : CloudOSColors.secondary,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _FilesError extends StatelessWidget {
  const _FilesError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, color: CloudOSColors.danger, size: 32),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CloudOSColors.secondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
