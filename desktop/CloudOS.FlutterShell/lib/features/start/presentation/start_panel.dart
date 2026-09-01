import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../widgets/glass_surface.dart';
import '../domain/start_app_filter.dart';
import 'widgets/start_app_views.dart';
import 'widgets/start_footer.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final filtered = filterStartApps(
      apps: widget.apps,
      query: query,
      selectedFilter: selectedFilter,
    );
    final pinnedApps = filtered.where((app) => app.isPinned).toList(growable: false);
    final recentApps = widget.apps.where((app) => app.isRecent).take(4).toList(growable: false);

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
                _StartHeader(onClose: widget.onClose),
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
                _StartFilterBar(
                  selectedFilter: selectedFilter,
                  onSelected: (filter) => setState(() => selectedFilter = filter),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: normalized.isNotEmpty
                      ? StartSearchResultsList(
                          results: filtered,
                          onLaunch: widget.onLaunch,
                        )
                      : _StartOverview(
                          pinnedApps: pinnedApps,
                          recentApps: recentApps,
                          onLaunch: widget.onLaunch,
                        ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                const StartFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartHeader extends StatelessWidget {
  const _StartHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Fechar (Esc)',
          child: IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ),
      ],
    );
  }
}

class _StartFilterBar extends StatelessWidget {
  const _StartFilterBar({
    required this.selectedFilter,
    required this.onSelected,
  });

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: startFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final filter = startFilters[index];
          final isSelected = filter == selectedFilter;
          return InkWell(
            onTap: () => onSelected(filter),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? CloudOSColors.accentSoft
                    : CloudOSColors.elevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? CloudOSColors.accent : CloudOSColors.border,
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isSelected
                      ? CloudOSColors.text
                      : CloudOSColors.secondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StartOverview extends StatelessWidget {
  const _StartOverview({
    required this.pinnedApps,
    required this.recentApps,
    required this.onLaunch,
  });

  final List<CloudApp> pinnedApps;
  final List<CloudApp> recentApps;
  final ValueChanged<CloudApp> onLaunch;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              Text('Aplicativos Fixados', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '${pinnedApps.length} itens',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 68,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final app = pinnedApps[index];
              return StartPinnedAppCard(
                app: app,
                onTap: () => onLaunch(app),
              );
            },
            childCount: pinnedApps.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              Text('Atividades Recentes', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              const Text(
                'Sessão ativa',
                style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final app = recentApps[index];
              return StartRecentTile(
                app: app,
                onTap: () => onLaunch(app),
              );
            },
            childCount: recentApps.length,
          ),
        ),
      ],
    );
  }
}
