import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import 'glass_surface.dart';

class FilesWindow extends StatelessWidget {
  const FilesWindow({
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 960,
      height: 620,
      child: GlassSurface(
        borderRadius: 18,
        blur: 28,
        color: const Color(0xF5111C26),
        child: Column(
          children: <Widget>[
            _TitleBar(onClose: onClose, onMinimize: onMinimize, onDrag: onDrag),
            const Divider(height: 1),
            const Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(width: 220, child: _Sidebar()),
                  VerticalDivider(width: 1),
                  Expanded(child: _FilesContent()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose, required this.onMinimize, required this.onDrag});

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDrag(details.delta),
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 16),
            const Icon(Icons.folder_rounded, color: CloudOSColors.accent, size: 20),
            const SizedBox(width: 9),
            const Text('Arquivos', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            const _SourceBadge(label: 'Windows + Linux', color: CloudOSColors.accent),
            const Spacer(),
            IconButton(onPressed: onMinimize, icon: const Icon(Icons.remove_rounded, size: 17)),
            const IconButton(onPressed: null, icon: Icon(Icons.crop_square_rounded, size: 17)),
            IconButton(
              onPressed: onClose,
              color: CloudOSColors.danger,
              icon: const Icon(Icons.close_rounded, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  static const entries = <(String, IconData, Color)>[
    ('Início', Icons.home_rounded, CloudOSColors.accent),
    ('Área de Trabalho', Icons.desktop_windows_rounded, CloudOSColors.secondary),
    ('Documentos', Icons.description_rounded, CloudOSColors.secondary),
    ('Downloads', Icons.download_rounded, CloudOSColors.secondary),
    ('CloudOS Drive', Icons.cloud_rounded, CloudOSColors.success),
    ('Projetos', Icons.workspaces_rounded, CloudOSColors.success),
    ('Windows', Icons.window_rounded, CloudOSColors.accent),
    ('Ubuntu', Icons.terminal_rounded, CloudOSColors.linux),
    ('Lixeira', Icons.delete_outline_rounded, CloudOSColors.secondary),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x44111C26),
      padding: const EdgeInsets.all(10),
      child: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, index) => index == 3 || index == 5
            ? const Divider(height: 16)
            : const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _SideItem(
            label: entry.$1,
            icon: entry.$2,
            color: entry.$3,
            selected: index == 0,
          );
        },
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.label, required this.icon, required this.color, this.selected = false});

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? CloudOSColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? CloudOSColors.text : CloudOSColors.secondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesContent extends StatelessWidget {
  const _FilesContent();

  static const entries = <(String, IconData, Color, String)>[
    ('Área de Trabalho', Icons.desktop_windows_rounded, CloudOSColors.accent, 'Windows'),
    ('Documentos', Icons.description_rounded, CloudOSColors.success, 'Windows'),
    ('Downloads', Icons.download_rounded, CloudOSColors.accent, 'Windows'),
    ('Projetos', Icons.workspaces_rounded, CloudOSColors.success, 'CloudOS'),
    ('Ubuntu', Icons.terminal_rounded, CloudOSColors.linux, 'Linux'),
    ('home', Icons.folder_special_rounded, CloudOSColors.linux, 'Ubuntu'),
    ('shared', Icons.folder_shared_rounded, CloudOSColors.success, 'CloudOS'),
    ('README.md', Icons.article_rounded, CloudOSColors.secondary, 'Arquivo'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              _ToolbarButton(icon: Icons.arrow_back_rounded),
              _ToolbarButton(icon: Icons.arrow_forward_rounded),
              _ToolbarButton(icon: Icons.arrow_upward_rounded),
              SizedBox(width: 8),
              Expanded(child: _AddressBar()),
              SizedBox(width: 8),
              SizedBox(width: 210, child: _SearchBox()),
            ],
          ),
          const SizedBox(height: 18),
          Text('Início', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 5),
          const Text(
            'Acesse Windows, CloudOS Drive e WSL sem sair do Files.',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisExtent: 120,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _FileTile(
                  name: entry.$1,
                  icon: entry.$2,
                  color: entry.$3,
                  source: entry.$4,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () {},
        style: IconButton.styleFrom(backgroundColor: CloudOSColors.surface),
        icon: Icon(icon, size: 18),
      );
}

class _AddressBar extends StatelessWidget {
  const _AddressBar();

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: CloudOSColors.surface,
          border: Border.all(color: CloudOSColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.home_rounded, size: 16, color: CloudOSColors.caption),
            SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 16, color: CloudOSColors.caption),
            SizedBox(width: 6),
            Text('Início', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 40,
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            hintText: 'Pesquisar',
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.name, required this.icon, required this.color, required this.source});

  final String name;
  final IconData icon;
  final Color color;
  final String source;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CloudOSColors.surface.withValues(alpha: 0.62),
            border: Border.all(color: CloudOSColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: color, size: 34),
              const Spacer(),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(source, style: const TextStyle(color: CloudOSColors.caption, fontSize: 10)),
            ],
          ),
        ),
      );
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}
