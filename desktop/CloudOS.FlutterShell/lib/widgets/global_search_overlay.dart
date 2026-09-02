import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/app_registry.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/project_store.dart';

typedef AppSelectionCallback = void Function(
  String appId, {
  Map<String, dynamic>? params,
});

enum SearchCategory {
  apps,
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

  String get categoryLabel => switch (category) {
        SearchCategory.apps => 'APLICATIVOS',
        SearchCategory.settings => 'CONFIGURAÇÕES',
        SearchCategory.projects => 'PROJETOS',
        SearchCategory.wsl => 'WSL',
      };

  Color get categoryColor => switch (category) {
        SearchCategory.apps => const Color(0xFF58A6FF),
        SearchCategory.settings => const Color(0xFFBC8CFF),
        SearchCategory.projects => const Color(0xFF39D353),
        SearchCategory.wsl => const Color(0xFFFFA657),
      };
}

class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({
    super.key,
    required this.apps,
    required this.onSelectApp,
    required this.onClose,
    this.bridge = const CloudOSBridge(),
  });

  final List<CloudApp> apps;
  final AppSelectionCallback onSelectApp;
  final VoidCallback onClose;
  final CloudOSBridge bridge;

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  List<ProjectRecord> _projects = const <ProjectRecord>[];

  static const List<Map<String, String>> _settingsPages = <Map<String, String>>[
    <String, String>{
      'title': 'Sistema',
      'desc': 'Nome do dispositivo, Broker e informações do sistema',
    },
    <String, String>{
      'title': 'Tela',
      'desc': 'Brilho quando suportado e recursos de exibição disponíveis',
    },
    <String, String>{
      'title': 'Som',
      'desc': 'Volume do endpoint de áudio padrão',
    },
    <String, String>{
      'title': 'Rede & Internet',
      'desc': 'Estado do adaptador de rede detectado',
    },
    <String, String>{
      'title': 'Bluetooth',
      'desc': 'Disponibilidade do backend Bluetooth',
    },
    <String, String>{
      'title': 'Energia & Bateria',
      'desc': 'Bateria quando detectada pelo sistema',
    },
    <String, String>{
      'title': 'Armazenamento',
      'desc': 'Unidades reais retornadas pelo System Broker',
    },
    <String, String>{
      'title': 'Personalização',
      'desc': 'Recursos de aparência disponíveis no CloudOS',
    },
    <String, String>{
      'title': 'WSL (Linux)',
      'desc': 'Distribuições WSL realmente detectadas',
    },
    <String, String>{
      'title': 'Sobre o CloudOS',
      'desc': 'Bridge, protocolo e estado de integração',
    },
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ProjectStore.load();
      if (!mounted) return;
      setState(() => _projects = projects);
    } catch (error, stackTrace) {
      CloudOSLogger.error('GlobalSearch', 'loadProjects', error, stackTrace);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final next = value.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  bool _matches(String query, Iterable<String?> fields) {
    if (query.isEmpty) return true;
    for (final field in fields) {
      if (field != null && field.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  Future<void> _launchRuntimeApp(CloudApp app) async {
    widget.onClose();

    if (app.platform == CloudAppPlatform.linux ||
        app.id.toLowerCase().startsWith('wsl:')) {
      final distro = app.distro?.trim() ?? '';
      widget.onSelectApp(
        'wsl:terminal',
        params: distro.isEmpty
            ? null
            : <String, dynamic>{'initialDistro': distro},
      );
      return;
    }

    final def = AppRegistry.findById(app.id);
    if (def?.isInternal == true || app.platform == CloudAppPlatform.cloudos) {
      widget.onSelectApp(def?.id ?? app.id);
      return;
    }

    try {
      final launched = await widget.bridge.launchApp(app.id);
      if (!launched && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Não foi possível abrir ${app.name}.')),
        );
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error('GlobalSearch', 'launchRuntimeApp', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Falha ao abrir ${app.name}: $error')),
        );
      }
    }
  }

  List<SearchResultItem> _buildResults() {
    final query = _query.toLowerCase();
    final results = <SearchResultItem>[];
    final seenAppIds = <String>{};

    // Internal CloudOS surfaces are defined by the presentation layer itself.
    for (final app in AppRegistry.definedApps) {
      if (!app.isInternal) continue;
      if (!_matches(query, <String?>[app.name, app.subtitle, app.id])) continue;

      seenAppIds.add(app.id.toLowerCase());
      results.add(
        SearchResultItem(
          title: app.name,
          subtitle: app.subtitle,
          category: app.id.startsWith('wsl:')
              ? SearchCategory.wsl
              : SearchCategory.apps,
          icon: app.icon,
          iconColor: app.id.startsWith('wsl:')
              ? const Color(0xFFFFA657)
              : const Color(0xFF58A6FF),
          onTap: () {
            widget.onClose();
            widget.onSelectApp(app.id);
          },
        ),
      );
    }

    // External/availability-driven apps come exclusively from the Broker catalog.
    for (final app in widget.apps) {
      final normalizedId = app.id.toLowerCase();
      if (seenAppIds.contains(normalizedId)) continue;
      if (!_matches(
        query,
        <String?>[app.name, app.subtitle, app.id, app.category, app.distro],
      )) {
        continue;
      }

      seenAppIds.add(normalizedId);
      final isLinux = app.platform == CloudAppPlatform.linux ||
          normalizedId.startsWith('wsl:');
      results.add(
        SearchResultItem(
          title: app.name,
          subtitle: isLinux
              ? (app.distro?.isNotEmpty == true
                  ? 'Terminal integrado · ${app.distro}'
                  : 'Aplicativo Linux detectado pelo Broker')
              : (app.subtitle ?? 'Aplicativo disponível no sistema'),
          category: isLinux ? SearchCategory.wsl : SearchCategory.apps,
          icon: app.icon,
          iconColor: isLinux
              ? const Color(0xFFFFA657)
              : const Color(0xFF58A6FF),
          onTap: () => unawaited(_launchRuntimeApp(app)),
        ),
      );
    }

    if (query.isNotEmpty) {
      for (final page in _settingsPages) {
        final title = page['title'] ?? '';
        final desc = page['desc'] ?? '';
        if (!_matches(query, <String?>[title, desc])) continue;
        results.add(
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

    for (final project in _projects) {
      if (!_matches(query, <String?>[project.name, project.path])) continue;
      results.add(
        SearchResultItem(
          title: project.name,
          subtitle: project.path,
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

    return results.take(30).toList(growable: false);
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
                  border: Border.all(
                    color: CloudOSColors.accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 40,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.search_rounded,
                            size: 22,
                            color: CloudOSColors.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                fillColor: Colors.transparent,
                                hintText:
                                    'Buscar apps, configurações, projetos e WSL...',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white38,
                                ),
                              ),
                              onChanged: _onQueryChanged,
                            ),
                          ),
                          if (_query.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white60,
                              ),
                              onPressed: () {
                                _ctrl.clear();
                                _onQueryChanged('');
                              },
                            ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: results.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'Nenhum resultado encontrado.',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Arquivos continuam pesquisáveis dentro do app Arquivos até o Broker expor resultados globais tipados.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: results.length,
                              separatorBuilder: (context, index) => const Divider(
                                height: 1,
                                color: Color(0x0DFFFFFF),
                              ),
                              itemBuilder: (context, index) {
                                final item = results[index];
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: item.iconColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      item.icon,
                                      size: 18,
                                      color: item.iconColor,
                                    ),
                                  ),
                                  title: Row(
                                    children: <Widget>[
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item.categoryColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: item.categoryColor.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
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
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: Colors.white24,
                                  ),
                                  onTap: item.onTap,
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0x1AFFFFFF)),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            'Resultados vêm de fontes reais do CloudOS',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                          Text(
                            'ESC para fechar',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
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
