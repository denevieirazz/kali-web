import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';
import '../../domain/start_running_app.dart';
import 'start_app_views.dart';

class StartOverview extends StatelessWidget {
  const StartOverview({
    required this.pinnedApps,
    required this.recentApps,
    required this.runningApps,
    required this.onLaunch,
    required this.onActivateWindow,
    required this.onCloseWindow,
    super.key,
  });

  final List<CloudApp> pinnedApps;
  final List<CloudApp> recentApps;
  final List<StartRunningApp> runningApps;
  final ValueChanged<CloudApp> onLaunch;
  final ValueChanged<String> onActivateWindow;
  final ValueChanged<String> onCloseWindow;

  StartRunningApp? _runningAppFor(CloudApp app) {
    for (final runningApp in runningApps) {
      if (runningApp.matchesAppId(app.id)) return runningApp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              Text(
                'Aplicativos Fixados',
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
          delegate: SliverChildBuilderDelegate((context, index) {
            final app = pinnedApps[index];
            final runningApp = _runningAppFor(app);
            return StartPinnedAppCard(
              app: app,
              onTap: runningApp == null
                  ? () => onLaunch(app)
                  : () => onActivateWindow(runningApp.id),
              runningApp: runningApp,
              onClose: runningApp == null
                  ? null
                  : () => onCloseWindow(runningApp.id),
            );
          }, childCount: pinnedApps.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: Row(
            children: <Widget>[
              Text(
                'Atividades Recentes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
          delegate: SliverChildBuilderDelegate((context, index) {
            final app = recentApps[index];
            return StartRecentTile(app: app, onTap: () => onLaunch(app));
          }, childCount: recentApps.length),
        ),
      ],
    );
  }
}
