import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class StartPinnedAppCard extends StatelessWidget {
  const StartPinnedAppCard({
    super.key,
    required this.app,
    required this.onTap,
  });

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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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

class StartRecentTile extends StatelessWidget {
  const StartRecentTile({
    super.key,
    required this.app,
    required this.onTap,
  });

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

class StartSearchResultsList extends StatelessWidget {
  const StartSearchResultsList({
    super.key,
    required this.results,
    required this.onLaunch,
  });

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
              style: TextStyle(
                color: CloudOSColors.secondary,
                fontSize: 13,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Tente buscar por outro termo ou nome de aplicativo',
              style: TextStyle(
                color: CloudOSColors.caption,
                fontSize: 11,
              ),
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
        return StartPinnedAppCard(
          app: app,
          onTap: () => onLaunch(app),
        );
      },
    );
  }
}
