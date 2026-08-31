import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
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
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final filtered = widget.apps
        .where((app) =>
            normalized.isEmpty ||
            app.name.toLowerCase().contains(normalized) ||
            (app.subtitle?.toLowerCase().contains(normalized) ?? false) ||
            (app.distro?.toLowerCase().contains(normalized) ?? false))
        .toList(growable: false);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 0, 76),
        child: SizedBox(
          width: 650,
          height: 620,
          child: GlassSurface(
            borderRadius: 24,
            blur: 32,
            color: const Color(0xF014202B),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: CloudOSColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_rounded, color: CloudOSColors.accent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'CloudOS',
                            style: TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Windows + Linux, em um único lugar',
                            style: TextStyle(color: CloudOSColors.caption, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Pesquisar apps, arquivos e comandos',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: <Widget>[
                    Text(
                      normalized.isEmpty ? 'Fixados e recentes' : 'Resultados',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length} apps',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisExtent: 108,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      return _AppTile(
                        app: app,
                        onTap: () => widget.onLaunch(app),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: CloudOSColors.accentSoft,
                      child: Icon(Icons.person_rounded, size: 18, color: CloudOSColors.text),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CloudOS User',
                      style: TextStyle(color: CloudOSColors.text, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    _FooterAction(icon: Icons.lock_outline_rounded, tooltip: 'Bloquear'),
                    const SizedBox(width: 6),
                    _FooterAction(icon: Icons.power_settings_new_rounded, tooltip: 'Energia'),
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

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onTap});

  final CloudApp app;
  final VoidCallback onTap;

  Color get platformColor => switch (app.platform) {
        CloudAppPlatform.windows => CloudOSColors.accent,
        CloudAppPlatform.linux => CloudOSColors.linux,
        CloudAppPlatform.cloudos => CloudOSColors.success,
      };

  String get platformLabel => switch (app.platform) {
        CloudAppPlatform.windows => 'Windows',
        CloudAppPlatform.linux => app.distro ?? 'Linux',
        CloudAppPlatform.cloudos => 'CloudOS',
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: CloudOSColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CloudOSColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: platformColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(app.icon, color: platformColor, size: 21),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: platformColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      platformLabel,
                      style: TextStyle(color: platformColor, fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CloudOSColors.text, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (app.subtitle != null)
                Text(
                  app.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: () {},
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(backgroundColor: CloudOSColors.surface),
      ),
    );
  }
}
