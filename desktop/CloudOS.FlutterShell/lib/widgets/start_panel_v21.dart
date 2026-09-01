import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class StartPanelV21 extends StatefulWidget {
  const StartPanelV21({
    required this.apps,
    required this.snapshot,
    required this.onLaunch,
    required this.onClose,
    super.key,
  });

  final List<CloudApp> apps;
  final CloudSystemSnapshot snapshot;
  final ValueChanged<CloudApp> onLaunch;
  final VoidCallback onClose;

  @override
  State<StartPanelV21> createState() => _StartPanelV21State();
}

class _StartPanelV21State extends State<StartPanelV21> {
  final TextEditingController _search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CloudApp> get _filtered {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return widget.apps;
    return widget.apps.where((app) {
      return app.name.toLowerCase().contains(normalized) ||
          app.id.toLowerCase().contains(normalized) ||
          (app.subtitle?.toLowerCase().contains(normalized) ?? false) ||
          (app.distro?.toLowerCase().contains(normalized) ?? false) ||
          app.category.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  Color _platformColor(CloudAppPlatform platform) => switch (platform) {
        CloudAppPlatform.windows => CloudOSColors.windows,
        CloudAppPlatform.linux => CloudOSColors.linux,
        CloudAppPlatform.cloudos => CloudOSColors.accent,
      };

  String _platformLabel(CloudAppPlatform platform) => switch (platform) {
        CloudAppPlatform.windows => 'Windows',
        CloudAppPlatform.linux => 'WSL',
        CloudAppPlatform.cloudos => 'CloudOS',
      };

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pinned = filtered.where((app) => app.isPinned).toList(growable: false);
    final shown = query.trim().isEmpty ? (pinned.isEmpty ? filtered : pinned) : filtered;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 68),
        child: SizedBox(
          width: 610,
          height: 560,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: const Color(0xF4121A25),
            borderColor: CloudOSColors.borderStrong,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
                      child: const Icon(Icons.cloud_rounded, color: CloudOSColors.accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'CloudOS V21',
                            style: TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Aplicativos reais via System Broker',
                            style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => query = '');
                            },
                            icon: const Icon(Icons.clear_rounded, size: 17),
                          ),
                    hintText: 'Pesquisar aplicativos...',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text(
                      query.trim().isEmpty ? 'Fixados' : 'Resultados',
                      style: const TextStyle(
                        color: CloudOSColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${shown.length} app(s)',
                      style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum aplicativo encontrado.',
                            style: TextStyle(color: CloudOSColors.caption),
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final app = shown[index];
                            final color = _platformColor(app.platform);
                            return InkWell(
                              onTap: () => widget.onLaunch(app),
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
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(app.icon, color: color, size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            app.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: CloudOSColors.text,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_platformLabel(app.platform)} • ${app.subtitle ?? app.category}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: CloudOSColors.accentSoft,
                      child: Text(
                        widget.snapshot.userName.isEmpty
                            ? '?'
                            : widget.snapshot.userName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: CloudOSColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.snapshot.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CloudOSColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${widget.snapshot.deviceName} • sessão ${widget.snapshot.sessionId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ),
                    if (widget.snapshot.wslAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: CloudOSColors.linuxSoft,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          widget.snapshot.distros.isEmpty ? 'WSL' : widget.snapshot.distros.first,
                          style: const TextStyle(
                            color: CloudOSColors.linux,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
