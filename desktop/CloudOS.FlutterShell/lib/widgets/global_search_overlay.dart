import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/app_registry.dart';
import '../services/cloudos_logger.dart';

enum SearchCategory {
  apps,
  files,
  settings,
  projects,
  wsl,
}

class SearchResultItem {
  const SearchResultItem({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final SearchCategory category;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  String get categoryLabel {
    switch (category) {
      case SearchCategory.apps:
        return 'APLICATIVOS';
      case SearchCategory.files:
        return 'ARQUIVOS';
      case SearchCategory.settings:
        return 'CONFIGURAÇÕES';
      case SearchCategory.projects:
        return 'PROJETOS';
      case SearchCategory.wsl:
        return 'WSL';
    }
  }

  Color get categoryColor {
    switch (category) {
      case SearchCategory.apps:
        return const Color(0xFF58A6FF);
      case SearchCategory.files:
        return const Color(0xFFE3B341);
      case SearchCategory.settings:
        return const Color(0xFFBC8CFF);
      case SearchCategory.projects:
        return const Color(0xFF39D353);
      case SearchCategory.wsl:
        return const Color(0xFFFFA657);
    }
  }
}

class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({
    super.key,
    required this.apps,
    required this.onSelectApp,
    required this.onClose,
  });

  final List<CloudApp> apps;
  final ValueChanged<String> onSelectApp;
  final VoidCallback onClose;

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  Timer? _debounceTimer;
  List<SearchResultItem> _fileResults = <SearchResultItem>[];

  static const _settingsPages = <Map<String, String>>[
    {'title': 'Sistema', 'desc': 'Informações de hardware, CPU e memória'},
    {'title': 'Telas e Monitores', 'desc': 'Resolução, escala e múltiplos monitores'},
    {'title': 'Som e Áudio', 'desc': 'Dispositivos de saída e volume mestre'},
    {'title': 'Notificações', 'desc': 'Preferências e central de alertas'},
    {'title': 'Armazenamento', 'desc': 'Uso de disco e limpeza de arquivos'},
    {'title': 'Personalização', 'desc': 'Temas dark glass, cores de destaque e transparência'},
    {'title': 'Rede & Internet', 'desc': 'Adaptadores Wi-Fi, Ethernet e conectividade'},
    {'title': 'Aplicativos & ConPTY', 'desc': 'Gerenciamento de apps e terminais nativos'},
    {'title': 'Contas & Segurança', 'desc': 'Identidade, bloqueio e permissões'},
    {'title': 'Sobre o CloudOS', 'desc': 'Versão 22.1, arquitetura e compliance'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    setState(() => _query = val.trim());
    _debounceTimer?.cancel();
    if (_query.length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 200), () => _searchFilesIncremental(_query));
    } else {
      setState(() => _fileResults = <SearchResultItem>[]);
    }
  }

  void _searchFilesIncremental(String q) {
    if (!mounted) return;
    try {
      final results = <SearchResultItem>[];
      final searchDirs = <Directory>[];

      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final desktop = Directory('$userProfile\\Desktop');
        final docs = Directory('$userProfile\\Documents');
        if (desktop.existsSync()) searchDirs.add(desktop);
        if (docs.existsSync()) searchDirs.add(docs);
      }

      final localApp = Platform.environment['LOCALAPPDATA'];
      if (localApp != null) {
        final drive = Directory('$localApp\\CloudOS\\Drive');
        if (drive.existsSync()) searchDirs.add(drive);
      }

      final qLower = q.toLowerCase();
      int count = 0;

      for (final d in searchDirs) {
        if (count >= 6) break;
        try {
          final list = d.listSync(followLinks: false);
          for (final entity in list) {
            if (count >= 6) break;
            final name = entity.path.split(RegExp(r'[\\/]')).last;
            if (name.toLowerCase().contains(qLower)) {
              final isDir = entity is Directory;
              results.add(
                SearchResultItem(
                  title: name,
                  subtitle: entity.path,
                  category: SearchCategory.files,
                  icon: isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                  iconColor: const Color(0xFFE3B341),
                  onTap: () {
                    widget.onClose();
                    if (isDir) {
                      widget.onSelectApp('cloudos:files');
                    } else {
                      widget.onSelectApp('cloudos:notepad');
                    }
                  },
                ),
              );
              count++;
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _fileResults = results);
      }
    } catch (e, st) {
      CloudOSLogger.error('GlobalSearch', 'searchFilesIncremental', e, st);
    }
  }

  List<SearchResultItem> _buildResults() {
    final list = <SearchResultItem>[];
    final q = _query.toLowerCase();

    // 1. Apps
    for (final app in AppRegistry.definedApps) {
      if (q.isEmpty || app.name.toLowerCase().contains(q) || app.subtitle.toLowerCase().contains(q) || app.id.toLowerCase().contains(q)) {
        list.add(
          SearchResultItem(
            title: app.name,
            subtitle: app.subtitle,
            category: SearchCategory.apps,
            icon: app.icon,
            iconColor: const Color(0xFF58A6FF),
            onTap: () {
              widget.onClose();
              widget.onSelectApp(app.id);
            },
          ),
        );
      }
    }

    // 2. Settings Pages
    for (final p in _settingsPages) {
      final title = p['title'] ?? '';
      final desc = p['desc'] ?? '';
      if (q.isNotEmpty && (title.toLowerCase().contains(q) || desc.toLowerCase().contains(q))) {
        list.add(
          SearchResultItem(
            title: title,
            subtitle: desc,
            category: SearchCategory.settings,
            icon: Icons.settings_rounded,
            iconColor: const Color(0xFFBC8CFF),
            onTap: () {
              widget.onClose();
              widget.onSelectApp('cloudos:settings');
            },
          ),
        );
      }
    }

    // 3. WSL Distros
    if (q.isNotEmpty && ('wsl'.contains(q) || 'ubuntu'.contains(q) || 'linux'.contains(q) || 'kali'.contains(q) || 'debian'.contains(q))) {
      list.add(
        SearchResultItem(
          title: 'WSL Linux Terminal',
          subtitle: 'Ambiente integrado ConPTY no CloudOS',
          category: SearchCategory.wsl,
          icon: Icons.computer_rounded,
          iconColor: const Color(0xFFFFA657),
          onTap: () {
            widget.onClose();
            widget.onSelectApp('cloudos:terminal');
          },
        ),
      );
    }

    // 4. Projects
    if (q.isEmpty || 'projeto'.contains(q) || 'workspace'.contains(q) || 'cloudos'.contains(q)) {
      list.add(
        SearchResultItem(
          title: 'CloudOS V22 Core Workspace',
          subtitle: r'C:\CloudOS\desktop\CloudOS.FlutterShell',
          category: SearchCategory.projects,
          icon: Icons.workspaces_rounded,
          iconColor: const Color(0xFF39D353),
          onTap: () {
            widget.onClose();
            widget.onSelectApp('cloudos:projects');
          },
        ),
      );
    }

    // 5. Files from debounce
    list.addAll(_fileResults);

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final results = _buildResults();

    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        alignment: const Alignment(0, -0.4),
        child: GestureDetector(
          onTap: () {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: 600,
                decoration: BoxDecoration(
                  color: const Color(0xF20E1322),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: CloudOSColors.accent.withValues(alpha: 0.5), width: 1.5),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black87, blurRadius: 40, offset: Offset(0, 16)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Campo de Busca
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.search_rounded, size: 22, color: CloudOSColors.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focusNode,
                              style: const TextStyle(fontSize: 15, color: Colors.white),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                fillColor: Colors.transparent,
                                hintText: 'Busca Global no CloudOS (Apps, Arquivos, Configurações)...',
                                hintStyle: TextStyle(fontSize: 14, color: Colors.white38),
                              ),
                              onChanged: _onQueryChanged,
                            ),
                          ),
                          if (_query.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white60),
                              onPressed: () {
                                _ctrl.clear();
                                _onQueryChanged('');
                              },
                            ),
                        ],
                      ),
                    ),

                    // Lista de Resultados
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: results.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Nenhum resultado encontrado.',
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: results.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0x0DFFFFFF)),
                              itemBuilder: (context, i) {
                                final item = results[i];
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: item.iconColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(item.icon, size: 18, color: item.iconColor),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.categoryColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: item.categoryColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          item.categoryLabel,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: item.categoryColor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    item.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white24),
                                  onTap: item.onTap,
                                );
                              },
                            ),
                    ),

                    // Rodapé
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text('Use ↑ ↓ para navegar • Enter para abrir', style: TextStyle(fontSize: 11, color: Colors.white38)),
                          Text('ESC para fechar', style: TextStyle(fontSize: 11, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
