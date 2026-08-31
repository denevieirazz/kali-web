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
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            _TitleBar(onClose: onClose, onMinimize: onMinimize, onDrag: onDrag),
            const Divider(height: 1),
            const Expanded(child: _FilesBody()),
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
            const Text(
              'Arquivos',
              style: TextStyle(color: CloudOSColors.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: CloudOSColors.accentSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Windows + Linux',
                style: TextStyle(color: CloudOSColors.accent, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            _WindowButton(icon: Icons.remove_rounded, onPressed: onMinimize),
            const _WindowButton(icon: Icons.crop_square_rounded),
            _WindowButton(icon: Icons.close_rounded, onPressed: onClose, danger: true),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, this.onPressed, this.danger = false});

  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: danger ? CloudOSColors.danger : CloudOSColors.secondary,
      ),
      icon: Icon(icon, size: 17),
    );
  }
}

class _FilesBody extends StatelessWidget {
  const _FilesBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(width: 224, child: _Sidebar()),
        Container(width: 1, color: CloudOSColors.border),
        Expanded(
          child: Column(
            children: <Widget>[
              const _Toolbar(),
              Container(height: 1, color: CloudOSColors.border),
              const Expanded(child: _FileContent()),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x55111C26),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: ListView(
        children: const <Widget>[
          _SideHeader('Quick Access'),
          _SideItem(icon: Icons.home_rounded, label: 'Início', selected: true),
          _SideItem(icon: Icons.desktop_windows_rounded, label: 'Área de Trabalho'),
          _SideItem(icon: Icons.description_rounded, label: 'Documentos'),
          _SideItem(icon: Icons.download_rounded, label: 'Downloads'),
          SizedBox(height: 10),
          _SideHeader('CloudOS'),
          _SideItem(icon: Icons.cloud_rounded, label: 'CloudOS Drive', accent: CloudOSColors.success),
          _SideItem(icon: Icons.workspaces_rounded, label: 'Projetos'),
          SizedBox(height: 10),
          _SideHeader('Sistemas'),
          _SideItem(icon: Icons.window_rounded, label: 'Windows', accent: CloudOSColors.accent),
          _SideItem(icon: Icons.terminal_rounded, label: 'Ubuntu', accent: CloudOSColors.linux),
          _SideItem(icon: Icons.delete_outline_rounded, label: 'Lixeira'),
        ],
      ),
    );
  }
}

class _SideHeader extends StatelessWidget {
  const _SideHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: CloudOSColors.caption,
          fontSize: 9,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? (selected ? CloudOSColors.accent : CloudOSColors.secondary);
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? CloudOSColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: selected ? CloudOSColors.text : CloudOSColors.secondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          const _ToolbarIcon(Icons.arrow_back_rounded),
          const SizedBox(width: 4),
          const _ToolbarIcon(Icons.arrow_forward_rounded),
          const SizedBox(width: 4),
          const _ToolbarIcon(Icons.arrow_upward_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 38,
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
                  Text('Início', style: TextStyle(color: CloudOSColors.text, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            height: 38,
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                hintText: 'Pesquisar',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {},
      style: IconButton.styleFrom(backgroundColor: CloudOSColors.surface),
      icon: Icon(icon, size: 18),
    );
  }
}

class _FileContent extends StatelessWidget {
  const _FileContent();

  @override
  Widget build(BuildContext context) {
    const items = <_FileItem>[
      _FileItem('Área de Trabalho', Icons.desktop_windows_rounded, CloudOSColors.accent, 'Windows'),
      _FileItem('Documentos', Icons.description_rounded, CloudOSColors.success, 'Windows'),
      _FileItem('Downloads', Icons.download_rounded, CloudOSColors.accent, 'Windows'),
      _FileItem('Projetos', Icons.workspaces_rounded, CloudOSColors.success, 'CloudOS'),
      _FileItem('Ubuntu', Icons.terminal_rounded, CloudOSColors.linux, 'Linux'),
      _FileItem('home', Icons.folder_special_rounded, CloudOSColors.linux, 'Ubuntu'),
      _FileItem('shared', Icons.folder_shared_rounded, CloudOSColors.success, 'CloudOS'),
      _FileItem('README.md', Icons.article_rounded, CloudOSColors.secondary, 'Arquivo'),
    ];

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Início', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: CloudOSColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: CloudOSColors.border),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.grid_view_rounded, size: 15, color: CloudOSColors.secondary),
                    SizedBox(width: 6),
                    Text('Grade', style: TextStyle(color: CloudOSColors.secondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Acesse Windows, CloudOS Drive e WSL sem sair do Files.',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisExtent: 120,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _FileTile(item: items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileItem {
  const _FileItem(this.name, this.icon, this.color, this.source);

  final String name;
  final IconData icon;
  final Color color;
  final String source;
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.item});

  final _FileItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            Icon(item.icon, color: item.color, size: 34),
            const Spacer(),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CloudOSColors.text, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(item.source, style: const TextStyle(color: CloudOSColors.caption, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
