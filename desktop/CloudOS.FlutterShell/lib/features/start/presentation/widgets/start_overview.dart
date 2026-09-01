import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';
import 'start_app_views.dart';

class StartOverview extends StatelessWidget {
  const StartOverview({
    required this.pinnedApps,
    required this.recentApps,
    required this.onLaunch,
    super.key,
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
