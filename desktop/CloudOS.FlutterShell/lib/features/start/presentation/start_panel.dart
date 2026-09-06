import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../core/responsive/cloud_responsive_layout.dart';
import '../../../models/shell_models.dart';
import '../../../widgets/glass_surface.dart';
import '../domain/start_app_filter.dart';
import '../domain/start_running_app.dart';
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
    required this.runningApps,
    required this.onActivateWindow,
    required this.onCloseWindow,
    required this.onClose,
    this.onLockSession,
    this.onPowerOptions,
    this.onPinToggle,
    super.key,
  });

  final List<CloudApp> apps;
  final ValueChanged<CloudApp> onLaunch;
  final List<StartRunningApp> runningApps;
  final ValueChanged<String> onActivateWindow;
  final ValueChanged<String> onCloseWindow;
  final VoidCallback onClose;
  final VoidCallback? onLockSession;
  final VoidCallback? onPowerOptions;
  final ValueChanged<CloudApp>? onPinToggle;

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
      includeDeepLocations: true,
    );
    final pinnedApps = filtered
        .where((app) => app.isPinned)
        .toList(growable: false);
    final recentApps = widget.apps
        .where((app) => app.isRecent && !pinnedApps.any((p) => p.id == app.id))
        .take(4)
        .toList(growable: false);
    final isSearching = query.trim().isNotEmpty;
    final isRunningView = selectedFilter == 'Abertos';
    final runningApps = query.trim().isEmpty
        ? widget.runningApps
        : widget.runningApps
              .where(
                (app) => app.title.toLowerCase().contains(
                  query.trim().toLowerCase(),
                ),
              )
              .toList(growable: false);

    final metrics = context.cloudMetrics;
    final panelWidth = metrics.startPanelWidth;
    final bottomPadding = metrics.taskbarHeight + 12.0;
    final maxAvailableHeight = (metrics.screenHeight - bottomPadding - 16.0).clamp(280.0, 720.0);
    final panelHeight = metrics.startPanelHeight.clamp(280.0, maxAvailableHeight);
    final isDark = cloudThemeNotifier.value.isDark;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 0, bottomPadding),
        child: SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: isDark ? const Color(0xF4121A25) : const Color(0xF4FFFFFF),
            borderColor: isDark ? CloudOSColors.borderStrong : const Color(0xFFCBD5E1),
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
                  runningCount: widget.runningApps.length,
                  onSelected: (filter) {
                    setState(() => selectedFilter = filter);
                  },
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: isRunningView
                      ? StartRunningAppsList(
                          apps: runningApps,
                          onActivate: widget.onActivateWindow,
                          onClose: widget.onCloseWindow,
                        )
                      : (isSearching || selectedFilter != 'Todos')
                      ? StartSearchResultsList(
                          results: filtered,
                          onLaunch: widget.onLaunch,
                          onPinToggle: widget.onPinToggle,
                        )
                      : StartOverview(
                          pinnedApps: pinnedApps,
                          recentApps: recentApps,
                          runningApps: widget.runningApps,
                          allApps: widget.apps,
                          onLaunch: widget.onLaunch,
                          onActivateWindow: widget.onActivateWindow,
                          onCloseWindow: widget.onCloseWindow,
                          onPinToggle: widget.onPinToggle,
                        ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                StartFooter(
                  onLockSession: widget.onLockSession,
                  onPowerOptions: widget.onPowerOptions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
