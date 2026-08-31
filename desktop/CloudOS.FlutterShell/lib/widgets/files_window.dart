import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import 'glass_surface.dart';

class FilesWindow extends StatefulWidget {
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
  State<FilesWindow> createState() => _FilesWindowState();
}

class _FilesWindowState extends State<FilesWindow> {
  String currentLocation = 'home';
  String currentTitle = 'Início';
  String query = '';
  bool isGridView = true;
  String? selectedItemPath;

  static const sidebarSections = <_SidebarSection>[
    _SidebarSection(
      title: 'Acesso Rápido',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'home', label: 'Início', icon: Icons.home_rounded, color: CloudOSColors.accent),
        _SidebarEntry(id: 'desktop', label: 'Área de Trabalho', icon: Icons.desktop_windows_rounded, color: CloudOSColors.secondary),
        _SidebarEntry(id: 'documents', label: 'Documentos', icon: Icons.description_rounded, color: CloudOSColors.secondary),
        _SidebarEntry(id: 'downloads', label: 'Downloads', icon: Icons.download_rounded, color: CloudOSColors.secondary),
      ],
    ),
    _SidebarSection(
      title: 'Armazenamento',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'cloud-drive', label: 'CloudOS Drive', icon: Icons.cloud_circle_rounded, color: CloudOSColors.accent, badge: '10 GB'),
        _SidebarEntry(id: 'windows-c', label: 'Disco Local (C:)', icon: Icons.storage_rounded, color: CloudOSColors.windows),
        _SidebarEntry(id: 'ubuntu-wsl', label: 'Ubuntu (WSL2)', icon: Icons.terminal_rounded, color: CloudOSColors.linux, badge: 'WSLg'),
      ],
    ),
    _SidebarSection(
      title: 'Sistema',
      items: <_SidebarEntry>[
        _SidebarEntry(id: 'trash', label: 'Lixeira CloudOS', icon: Icons.delete_outline_rounded, color: CloudOSColors.secondary),
      ],
    ),
  ];

  List<CloudFileItem> get _currentFiles {
    final allFiles = CloudOSBridge.previewFiles['home'] ?? <CloudFileItem>[];
    if (query.trim().isEmpty) return allFiles;
    final q = query.trim().toLowerCase();
    return allFiles.where((f) => f.name.toLowerCase().contains(q)).toList(growable: false);
  }

  void _navigateTo(String id, String label) {
    setState(() {
      currentLocation = id;
      currentTitle = label;
      selectedItemPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = _currentFiles;

    return SizedBox(
      width: 960,
      height: 600,
      child: GlassSurface(
        borderRadius: 14,
        blur: 24,
        color: const Color(0xF4101822),
        borderColor: CloudOSColors.borderStrong,
        child: Column(
          children: <Widget>[
            _TitleBar(
              title: currentTitle,
              onClose: widget.onClose,
              onMinimize: widget.onMinimize,
              onDrag: widget.onDrag,
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 210,
                    child: _Sidebar(
                      sections: sidebarSections,
                      selectedId: currentLocation,
                      onSelect: _navigateTo,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _Toolbar(
                          currentTitle: currentTitle,
                          query: query,
                          isGridView: isGridView,
                          onQueryChanged: (val) => setState(() => query = val),
                          onToggleView: () => setState(() => isGridView = !isGridView),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: files.isEmpty
                              ? _EmptyFilesState(query: query)
                              : isGridView
                                  ? _FilesGrid(
                                      files: files,
                                      selectedPath: selectedItemPath,
                                      onSelect: (path) => setState(() => selectedItemPath = path),
                                    )
                                  : _FilesList(
                                      files: files,
                                      selectedPath: selectedItemPath,
                                      onSelect: (path) => setState(() => selectedItemPath = path),
                                    ),
                        ),
                        _StatusBar(
                          itemCount: files.length,
                          selectedPath: selectedItemPath,
                        ),
                      ],
                    ),
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

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDrag(details.delta),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.folder_rounded, color: CloudOSColors.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Arquivos • $title',
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            const _SourceBadge(label: 'Windows + Linux (WSL2)', color: CloudOSColors.accent),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimizar',
              onPressed: onMinimize,
            ),
            const SizedBox(width: 4),
            _WindowButton(
              icon: Icons.crop_square_rounded,
              tooltip: 'Maximizar',
              onPressed: () {},
            ),
            const SizedBox(width: 4),
            _WindowButton(
              icon: Icons.close_rounded,
              tooltip: 'Fechar (Esc)',
              isClose: true,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isClose ? CloudOSColors.danger : CloudOSColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _SidebarSection {
  const _SidebarSection({required this.title, required this.items});
  final String title;
  final List<_SidebarEntry> items;
}

class _SidebarEntry {
  const _SidebarEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.badge,
  });
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String? badge;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.selectedId,
    required this.onSelect,
  });

  final List<_SidebarSection> sections;
  final String selectedId;
  final void Function(String id, String label) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x350D151E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: ListView.separated(
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, sIdx) {
          final section = sections[sIdx];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  section.title.toUpperCase(),
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              for (final item in section.items) ...<Widget>[
                _SidebarItemTile(
                  entry: item,
                  selected: item.id == selectedId,
                  onTap: () => onSelect(item.id, item.label),
                ),
                const SizedBox(height: 2),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SidebarItemTile extends StatelessWidget {
  const _SidebarItemTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _SidebarEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? CloudOSColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? CloudOSColors.accent.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(entry.icon, size: 16, color: selected ? CloudOSColors.accent : entry.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? CloudOSColors.text : CloudOSColors.secondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (entry.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: CloudOSColors.elevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.badge!,
                  style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.currentTitle,
    required this.query,
    required this.isGridView,
    required this.onQueryChanged,
    required this.onToggleView,
  });

  final String currentTitle;
  final String query;
  final bool isGridView;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          _NavButton(icon: Icons.arrow_back_rounded, tooltip: 'Voltar', onPressed: () {}),
          _NavButton(icon: Icons.arrow_forward_rounded, tooltip: 'Avançar', onPressed: () {}),
          _NavButton(icon: Icons.arrow_upward_rounded, tooltip: 'Subir Pasta', onPressed: () {}),
          _NavButton(icon: Icons.refresh_rounded, tooltip: 'Atualizar', onPressed: () {}),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: CloudOSColors.elevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CloudOSColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.folder_open_rounded, size: 15, color: CloudOSColors.accent),
                  const SizedBox(width: 6),
                  const Text('CloudOS', style: TextStyle(fontSize: 11.5, color: CloudOSColors.caption)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 14, color: CloudOSColors.caption),
                  const SizedBox(width: 4),
                  Text(currentTitle, style: const TextStyle(fontSize: 11.5, color: CloudOSColors.text, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            height: 32,
            child: TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 16),
                hintText: 'Filtrar pasta...',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: isGridView ? 'Mudar para exibição em lista' : 'Mudar para exibição em grade',
            child: IconButton(
              onPressed: onToggleView,
              visualDensity: VisualDensity.compact,
              icon: Icon(isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 16, color: CloudOSColors.secondary),
      ),
    );
  }
}

class _FilesGrid extends StatelessWidget {
  const _FilesGrid({
    required this.files,
    required this.selectedPath,
    required this.onSelect,
  });

  final List<CloudFileItem> files;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 116,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final isSelected = item.path == selectedPath;
        return _FileGridCard(
          item: item,
          isSelected: isSelected,
          onTap: () => onSelect(item.path),
        );
      },
    );
  }
}

class _FileGridCard extends StatelessWidget {
  const _FileGridCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final CloudFileItem item;
  final bool isSelected;
  final VoidCallback onTap;

  Color get sourceColor => switch (item.source) {
        CloudFileSource.windows => CloudOSColors.windows,
        CloudFileSource.linux => CloudOSColors.linux,
        CloudFileSource.cloudDrive => CloudOSColors.accent,
        CloudFileSource.trash => CloudOSColors.danger,
      };

  String get sourceLabel => switch (item.source) {
        CloudFileSource.windows => 'Win',
        CloudFileSource.linux => 'WSL',
        CloudFileSource.cloudDrive => 'Cloud',
        CloudFileSource.trash => 'Lixeira',
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? CloudOSColors.accentSoft : CloudOSColors.elevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  item.icon ?? (item.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded),
                  color: item.isFolder ? CloudOSColors.accent : CloudOSColors.secondary,
                  size: 28,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sourceLabel,
                    style: TextStyle(color: sourceColor, fontSize: 8.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CloudOSColors.text, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${item.sizeFormatted} • ${item.modifiedFormatted}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilesList extends StatelessWidget {
  const _FilesList({
    required this.files,
    required this.selectedPath,
    required this.onSelect,
  });

  final List<CloudFileItem> files;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final item = files[index];
        final isSelected = item.path == selectedPath;
        return InkWell(
          onTap: () => onSelect(item.path),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? CloudOSColors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? CloudOSColors.accent.withValues(alpha: 0.5) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon ?? (item.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded),
                  size: 17,
                  color: item.isFolder ? CloudOSColors.accent : CloudOSColors.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.text, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.modifiedFormatted,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    item.sizeFormatted,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyFilesState extends StatelessWidget {
  const _EmptyFilesState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.folder_open_rounded, size: 44, color: CloudOSColors.caption),
          const SizedBox(height: 10),
          Text(
            query.isNotEmpty ? 'Nenhum arquivo correspondente a "$query"' : 'Pasta vazia',
            style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.itemCount, required this.selectedPath});
  final int itemCount;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0x350D151E),
        border: Border(top: BorderSide(color: CloudOSColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$itemCount itens',
            style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
          if (selectedPath != null) ...<Widget>[
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: CloudOSColors.caption)),
            const SizedBox(width: 8),
            const Text(
              '1 item selecionado',
              style: TextStyle(color: CloudOSColors.accent, fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ],
          const Spacer(),
          const Icon(Icons.cloud_done_rounded, size: 13, color: CloudOSColors.success),
          const SizedBox(width: 5),
          const Text(
            'Sistema de arquivos unificado e sincronizado',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
        ),
      );
}
