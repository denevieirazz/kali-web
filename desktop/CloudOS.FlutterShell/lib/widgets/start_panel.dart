import 'dart:io';
import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import 'glass_surface.dart';

class StartPanel extends StatefulWidget {
  const StartPanel({
    required this.apps,
    required this.onLaunch,
    required this.onClose,
    super.key,
  });

  final List<CloudApp> apps;
  final ValueChanged<CloudApp> onLaunch;
  final VoidCallback onClose;

  @override
  State<StartPanel> createState() => _StartPanelState();
}

class _StartPanelState extends State<StartPanel> {
  final TextEditingController _searchController = TextEditingController();
  String query = '';
  String selectedFilter = 'Todos';

  static const filters = <String>[
    'Todos',
    'Produtividade',
    'Linux / WSL',
    'Sistema',
    'Utilitários',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final filtered = widget.apps
        .where((app) {
          final matchesQuery =
              normalized.isEmpty ||
              app.name.toLowerCase().contains(normalized) ||
              (app.subtitle?.toLowerCase().contains(normalized) ?? false) ||
              (app.distro?.toLowerCase().contains(normalized) ?? false) ||
              app.category.toLowerCase().contains(normalized);

          if (!matchesQuery) return false;

          if (selectedFilter == 'Todos') return true;
          if (selectedFilter == 'Linux / WSL')
            return app.platform == CloudAppPlatform.linux;
          return app.category == selectedFilter;
        })
        .toList(growable: false);

    final pinnedApps = filtered
        .where((a) => a.isPinned)
        .toList(growable: false);
    final recentApps = widget.apps
        .where((a) => a.isRecent)
        .take(4)
        .toList(growable: false);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 68),
        child: SizedBox(
          width: 660,
          height: 580,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: const Color(0xF4121A25),
            borderColor: CloudOSColors.borderStrong,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: CloudOSColors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.cloud_rounded,
                        color: CloudOSColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'CloudOS Start',
                            style: TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Ambiente unificado Windows + Linux',
                            style: TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Fechar (Esc)',
                      child: IconButton(
                        onPressed: widget.onClose,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: CloudOSColors.secondary,
                    ),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => query = '');
                            },
                          )
                        : null,
                    hintText: 'Pesquisar apps, arquivos, comandos e WSL...',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final f = filters[index];
                      final isSelected = f == selectedFilter;
                      return InkWell(
                        onTap: () => setState(() => selectedFilter = f),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? CloudOSColors.accentSoft
                                : CloudOSColors.elevated.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? CloudOSColors.accent
                                  : CloudOSColors.border,
                            ),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              color: isSelected
                                  ? CloudOSColors.text
                                  : CloudOSColors.secondary,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: normalized.isNotEmpty
                      ? _SearchResultsList(
                          results: filtered,
                          onLaunch: widget.onLaunch,
                        )
                      : CustomScrollView(
                          slivers: <Widget>[
                            SliverToBoxAdapter(
                              child: Row(
                                children: <Widget>[
                                  Text(
                                    'Aplicativos Fixados',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${pinnedApps.length} itens',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 8),
                            ),
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisExtent: 68,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final app = pinnedApps[index];
                                return _AppCard(
                                  app: app,
                                  onTap: () => widget.onLaunch(app),
                                );
                              }, childCount: pinnedApps.length),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 14),
                            ),
                            SliverToBoxAdapter(
                              child: Row(
                                children: <Widget>[
                                  Text(
                                    'Atividades Recentes',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Sessão ativa',
                                    style: TextStyle(
                                      color: CloudOSColors.caption,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 6),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final app = recentApps[index];
                                return _RecentTile(
                                  app: app,
                                  onTap: () => widget.onLaunch(app),
                                );
                              }, childCount: recentApps.length),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: CloudOSColors.accentSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: CloudOSColors.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: CloudOSColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Douglas',
                          style: TextStyle(
                            color: CloudOSColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Administrador • Sessão Ativa',
                          style: TextStyle(
                            color: CloudOSColors.caption,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _FooterAction(
                      icon: Icons.lock_outline_rounded,
                      tooltip: 'Bloquear Sessão',
                      onPressed: () {
                        const CloudOSBridge().lockSession();
                      },
                    ),
                    const SizedBox(width: 4),
                    _FooterAction(
                      icon: Icons.power_settings_new_rounded,
                      tooltip: 'Opções de Energia',
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF101524),
                            title: const Text('Opções de Energia CloudOS', style: TextStyle(color: Colors.white, fontSize: 15)),
                            content: const Text('Selecione a ação desejada para o CloudOS:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.danger),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  exit(0);
                                },
                                child: const Text('Sair do CloudOS', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});

  final CloudApp app;
  final VoidCallback onTap;

  Color get platformColor => switch (app.platform) {
    CloudAppPlatform.windows => CloudOSColors.windows,
    CloudAppPlatform.linux => CloudOSColors.linux,
    CloudAppPlatform.cloudos => CloudOSColors.accent,
  };

  String get platformLabel => switch (app.platform) {
    CloudAppPlatform.windows => 'Win',
    CloudAppPlatform.linux => 'WSL',
    CloudAppPlatform.cloudos => 'Cloud',
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CloudOSColors.elevated.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CloudOSColors.border),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: platformColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(app.icon, color: platformColor, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CloudOSColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: platformColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          platformLabel,
                          style: TextStyle(
                            color: platformColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          app.subtitle ?? app.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CloudOSColors.caption,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.app, required this.onTap});

  final CloudApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(app.icon, size: 17, color: CloudOSColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.name,
                  style: const TextStyle(
                    color: CloudOSColors.text,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                app.subtitle ?? 'Recente',
                style: const TextStyle(
                  color: CloudOSColors.caption,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.results, required this.onLaunch});

  final List<CloudApp> results;
  final ValueChanged<CloudApp> onLaunch;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: CloudOSColors.caption,
            ),
            SizedBox(height: 8),
            Text(
              'Nenhum resultado encontrado',
              style: TextStyle(color: CloudOSColors.secondary, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              'Tente buscar por outro termo ou nome de aplicativo',
              style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final app = results[index];
        return _AppCard(app: app, onTap: () => onLaunch(app));
      },
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: CloudOSColors.elevated.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
