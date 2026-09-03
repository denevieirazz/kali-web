import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';
import '../../domain/start_running_app.dart';

class StartPinnedAppCard extends StatelessWidget {
  const StartPinnedAppCard({
    super.key,
    required this.app,
    required this.onTap,
    this.runningApp,
    this.onClose,
  });

  final CloudApp app;
  final VoidCallback onTap;
  final StartRunningApp? runningApp;
  final VoidCallback? onClose;

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
          border: Border.all(
            color: runningApp != null
                ? CloudOSColors.accent.withValues(alpha: 0.75)
                : CloudOSColors.border,
          ),
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
                    children: runningApp != null
                        ? <Widget>[
                            const SizedBox(
                              width: 6,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: CloudOSColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                runningApp!.isActive
                                    ? 'Ativo'
                                    : runningApp!.isMinimized
                                    ? 'Minimizado'
                                    : 'Aberto',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CloudOSColors.success,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ]
                        : <Widget>[
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
            if (runningApp != null) ...<Widget>[
              const SizedBox(width: 5),
              Tooltip(
                message: 'Fechar ${app.name}',
                child: InkWell(
                  key: ValueKey<String>('close-running-${runningApp!.id}'),
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      Icons.close_rounded,
                      color: CloudOSColors.secondary,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StartRunningAppsList extends StatelessWidget {
  const StartRunningAppsList({
    super.key,
    required this.apps,
    required this.onActivate,
    required this.onClose,
  });

  final List<StartRunningApp> apps;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.layers_clear_rounded,
              size: 42,
              color: CloudOSColors.caption,
            ),
            SizedBox(height: 10),
            Text(
              'Nenhum aplicativo aberto',
              style: TextStyle(
                color: CloudOSColors.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Os aplicativos em execução aparecerão aqui.',
              style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Aplicativos abertos',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            Text(
              '${apps.length} em execução',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: apps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              final app = apps[index];
              final status = app.isActive
                  ? 'Ativo agora'
                  : app.isMinimized
                  ? 'Minimizado'
                  : 'Em execução';
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey<String>('activate-running-${app.id}'),
                  onTap: () => onActivate(app.id),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                    decoration: BoxDecoration(
                      color: app.isActive
                          ? CloudOSColors.accentSoft.withValues(alpha: 0.55)
                          : CloudOSColors.elevated.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: app.isActive
                            ? CloudOSColors.accent.withValues(alpha: 0.75)
                            : CloudOSColors.border,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: CloudOSColors.accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            app.icon,
                            color: CloudOSColors.accent,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                app.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CloudOSColors.text,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: app.isActive
                                          ? CloudOSColors.accent
                                          : CloudOSColors.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    status,
                                    style: const TextStyle(
                                      color: CloudOSColors.caption,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Fechar ${app.title}',
                          child: IconButton(
                            key: ValueKey<String>('close-running-${app.id}'),
                            onPressed: () => onClose(app.id),
                            icon: const Icon(Icons.close_rounded),
                            color: CloudOSColors.secondary,
                            hoverColor: Colors.redAccent.withValues(
                              alpha: 0.15,
                            ),
                            highlightColor: Colors.redAccent.withValues(
                              alpha: 0.2,
                            ),
                            iconSize: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class StartRecentTile extends StatelessWidget {
  const StartRecentTile({super.key, required this.app, required this.onTap});

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
        return StartPinnedAppCard(app: app, onTap: () => onLaunch(app));
      },
    );
  }
}
