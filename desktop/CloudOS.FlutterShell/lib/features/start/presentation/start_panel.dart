import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/shell_models.dart';
import '../../../widgets/glass_surface.dart';
import '../domain/start_app_filter.dart';
import 'widgets/start_app_views.dart';
import 'widgets/start_filter_bar.dart';
import 'widgets/start_footer.dart';
import 'widgets/start_header.dart';
import 'widgets/start_overview.dart';
import 'widgets/start_search_field.dart';

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

  void _clearQuery() {
    _searchController.clear();
    setState(() => query = '');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterStartApps(
      apps: widget.apps,
      query: query,
      selectedFilter: selectedFilter,
    );
    final pinnedApps = filtered
        .where((app) => app.isPinned)
        .toList(growable: false);
    final recentApps = widget.apps
        .where((app) => app.isRecent)
        .take(4)
        .toList(growable: false);
    final isSearching = query.trim().isNotEmpty;

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
                StartHeader(onClose: widget.onClose),
                const SizedBox(height: 14),
                StartSearchField(
                  controller: _searchController,
                  query: query,
                  onChanged: (value) => setState(() => query = value),
                  onClear: _clearQuery,
                ),
                const SizedBox(height: 10),
                StartFilterBar(
                  selectedFilter: selectedFilter,
                  onSelected: (filter) {
                    setState(() => selectedFilter = filter);
                  },
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: isSearching
                      ? StartSearchResultsList(
                          results: filtered,
                          onLaunch: widget.onLaunch,
                        )
                      : StartOverview(
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
