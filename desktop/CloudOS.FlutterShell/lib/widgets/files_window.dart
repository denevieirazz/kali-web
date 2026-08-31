import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../core/cloudos_theme.dart';
import '../models/file_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/files_controller.dart';
import 'glass_surface.dart';

class FilesWindow extends StatefulWidget {
  const FilesWindow({
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
    this.bridge,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;
  final CloudOSBridge? bridge;

  @override
  State<FilesWindow> createState() => _FilesWindowState();
}

class _FilesWindowState extends State<FilesWindow> {
  late final FilesController _controller;
  final TextEditingController _pathInputController = TextEditingController();
  final TextEditingController _searchInputController = TextEditingController();
  bool _isEditingPath = false;

  @override
  void initState() {
    super.initState();
    _controller = FilesController(bridge: widget.bridge);
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      final tab = _controller.activeTab;
      if (tab != null && !_isEditingPath) {
        _pathInputController.text = tab.currentPath;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _pathInputController.dispose();
    _searchInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = _controller.activeTab;
    final viewport = MediaQuery.sizeOf(context);
    final windowWidth = math.min(1020.0, math.max(680.0, viewport.width - 40));
    final windowHeight = math.min(640.0, math.max(480.0, viewport.height - 96));

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Handle keyboard shortcuts
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: windowWidth,
        height: windowHeight,
        child: GlassSurface(
          borderRadius: 14,
          blur: 24,
          color: const Color(0xF4101822),
          borderColor: CloudOSColors.borderStrong,
          child: Column(
            children: <Widget>[
              // Title Bar + Tabs
              _buildTitleBar(tab),
              const Divider(height: 1),

              // Navigation Toolbar
              _buildToolbar(tab),
              const Divider(height: 1),

              // Main Body: Sidebar + File Grid/List
              Expanded(
                child: Row(
                  children: <Widget>[
                    // Sidebar
                    SizedBox(
                      width: windowWidth < 840 ? 180 : 220,
                      child: _buildSidebar(tab),
                    ),
                    const VerticalDivider(width: 1),

                    // File View
                    Expanded(child: _buildFileView(tab)),
                  ],
                ),
              ),

              // Status Bar
              _buildStatusBar(tab),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(FilesTabState? tab) {
    return GestureDetector(
      onPanUpdate: (details) => widget.onDrag(details.delta),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.transparent,
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.folder_rounded,
              size: 18,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            const Text(
              'Arquivos',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CloudOSColors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),

            // Tabs Row
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _controller.tabs.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    if (index == _controller.tabs.length) {
                      return IconButton(
                        icon: const Icon(Icons.add_rounded, size: 16),
                        tooltip: 'Nova Aba',
                        onPressed: () => _controller.addTab(),
                        color: CloudOSColors.textSecondary,
                      );
                    }

                    final t = _controller.tabs[index];
                    final isActive = index == _controller.activeTabIndex;

                    return InkWell(
                      onTap: () => _controller.selectTab(index),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0x2838BDF8)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive
                                ? CloudOSColors.accent.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              t.title,
                              style: TextStyle(
                                fontSize: 12,
                                color: isActive
                                    ? CloudOSColors.accent
                                    : CloudOSColors.textSecondary,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (_controller.tabs.length > 1) ...<Widget>[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _controller.closeTab(index),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: CloudOSColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Window Controls
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 16),
              tooltip: 'Minimizar',
              onPressed: widget.onMinimize,
              color: CloudOSColors.textSecondary,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: 'Fechar',
              onPressed: widget.onClose,
              color: CloudOSColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(FilesTabState? tab) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          // Back / Forward / Up / Refresh
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            tooltip: 'Voltar (Alt+Seta Esquerda)',
            onPressed: tab?.canGoBack == true
                ? () => _controller.goBack()
                : null,
            color: CloudOSColors.textPrimary,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            tooltip: 'Avançar (Alt+Seta Direita)',
            onPressed: tab?.canGoForward == true
                ? () => _controller.goForward()
                : null,
            color: CloudOSColors.textPrimary,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            tooltip: 'Pasta Acima',
            onPressed: () => _controller.goToParent(),
            color: CloudOSColors.textPrimary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Atualizar (F5)',
            onPressed: () => _controller.refresh(),
            color: CloudOSColors.textPrimary,
          ),
          const SizedBox(width: 8),

          // Location Breadcrumbs / Input Bar
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0x18FFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: CloudOSColors.borderSubtle),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: CloudOSColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _pathInputController,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CloudOSColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                        border: InputBorder.none,
                        hintText:
                            'Digite o caminho (ex: C:\\ ou \\\\wsl.localhost\\Ubuntu)',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: CloudOSColors.textTertiary,
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _controller.navigateTo(value.trim());
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Search Box
          SizedBox(
            width: 180,
            height: 32,
            child: TextField(
              controller: _searchInputController,
              style: const TextStyle(
                fontSize: 12,
                color: CloudOSColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: CloudOSColors.borderSubtle,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: CloudOSColors.textSecondary,
                ),
                hintText: 'Buscar...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: CloudOSColors.textTertiary,
                ),
              ),
              onChanged: (value) => _controller.setSearchQuery(value),
            ),
          ),
          const SizedBox(width: 8),

          // Actions: New Folder, Grid/List view toggle
          IconButton(
            icon: const Icon(Icons.create_new_folder_rounded, size: 18),
            tooltip: 'Nova Pasta',
            onPressed: () => _showCreateFolderDialog(),
            color: CloudOSColors.textPrimary,
          ),
          IconButton(
            icon: Icon(
              tab?.isGridView == true
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              size: 18,
            ),
            tooltip: tab?.isGridView == true
                ? 'Visualizar em Lista'
                : 'Visualizar em Grade',
            onPressed: () => _controller.toggleViewMode(),
            color: CloudOSColors.textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(FilesTabState? tab) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      children: <Widget>[
        // Acesso Rápido / Known Folders
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Acesso Rápido',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CloudOSColors.textTertiary,
            ),
          ),
        ),
        for (final kf in _controller.knownFolders)
          _buildSidebarItem(
            id: kf.id,
            name: kf.name,
            icon: kf.icon,
            color: kf.id.startsWith('wsl:')
                ? CloudOSColors.linux
                : CloudOSColors.accent,
            isSelected:
                tab?.currentPath == kf.path || tab?.currentPath == kf.id,
            onTap: () => _controller.navigateTo(kf.path, title: kf.name),
          ),

        const SizedBox(height: 12),
        // Dispositivos e Unidades
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Este Computador',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CloudOSColors.textTertiary,
            ),
          ),
        ),
        for (final drive in _controller.drives)
          _buildSidebarItem(
            id: drive.letter,
            name: drive.label.isNotEmpty
                ? '${drive.label} (${drive.letter})'
                : drive.letter,
            icon: drive.isRemovable ? Icons.usb_rounded : Icons.storage_rounded,
            color: CloudOSColors.windows,
            isSelected:
                tab?.currentPath == drive.path ||
                tab?.currentPath == drive.letter,
            badge: drive.freeFormatted.isNotEmpty
                ? '${drive.freeFormatted} livres'
                : null,
            onTap: () =>
                _controller.navigateTo(drive.path, title: drive.letter),
          ),
      ],
    );
  }

  Widget _buildSidebarItem({
    required String id,
    required String name,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x2838BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? CloudOSColors.accent.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? CloudOSColors.accent
                      : CloudOSColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 58),
                child: Text(
                  badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: CloudOSColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileView(FilesTabState? tab) {
    if (tab == null) return const SizedBox.shrink();

    if (tab.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: CloudOSColors.accent),
      );
    }

    if (tab.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: Color(0xFFF43F5E),
            ),
            const SizedBox(height: 8),
            Text(
              tab.errorMessage!,
              style: const TextStyle(
                fontSize: 13,
                color: CloudOSColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _controller.refresh(),
              child: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (tab.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: CloudOSColors.textTertiary,
            ),
            SizedBox(height: 8),
            Text(
              'Esta pasta está vazia.',
              style: TextStyle(
                fontSize: 13,
                color: CloudOSColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _controller.clearSelection(),
      child: tab.isGridView ? _buildGridView(tab) : _buildListView(tab),
    );
  }

  Widget _buildGridView(FilesTabState tab) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: tab.items.length,
      itemBuilder: (context, index) {
        final item = tab.items[index];
        final isSelected = tab.selectedPaths.contains(item.path);

        return InkWell(
          onTap: () => _controller.selectItem(item.path),
          onDoubleTap: () => _controller.openItem(item),
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition, item),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0x3038BDF8)
                  : const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? CloudOSColors.accent
                    : CloudOSColors.borderSubtle,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(item.icon, size: 36, color: item.iconColor),
                const SizedBox(height: 6),
                Text(
                  item.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? CloudOSColors.accent
                        : CloudOSColors.textPrimary,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView(FilesTabState tab) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: tab.items.length,
      itemBuilder: (context, index) {
        final item = tab.items[index];
        final isSelected = tab.selectedPaths.contains(item.path);

        return InkWell(
          onTap: () => _controller.selectItem(item.path),
          onDoubleTap: () => _controller.openItem(item),
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition, item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0x3038BDF8) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? CloudOSColors.accent : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(item.icon, size: 18, color: item.iconColor),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? CloudOSColors.accent
                          : CloudOSColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.modifiedFormatted,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CloudOSColors.textSecondary,
                    ),
                    maxLines: 1,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    item.sizeFormatted,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CloudOSColors.textSecondary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(FilesTabState? tab) {
    final count = tab?.items.length ?? 0;
    final selectedCount = tab?.selectedPaths.length ?? 0;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0x10000000),
      child: Row(
        children: <Widget>[
          Text(
            '$count itens',
            style: const TextStyle(
              fontSize: 11,
              color: CloudOSColors.textSecondary,
            ),
          ),
          if (selectedCount > 0) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '$selectedCount selecionado(s)',
              style: const TextStyle(fontSize: 11, color: CloudOSColors.accent),
            ),
          ],
          const Spacer(),
          if (_controller.hasActiveJob) ...<Widget>[
            Flexible(
              child: Text(
                '${_controller.activeJobStatus} ${_controller.activeJobProgress.toStringAsFixed(0)}%',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: CloudOSColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (tab?.locationKind == LocationKind.wsl)
            const Text(
              'Linux / WSL2 Filesystem',
              style: TextStyle(fontSize: 11, color: CloudOSColors.linux),
            )
          else
            const Text(
              'Windows Filesystem',
              style: TextStyle(fontSize: 11, color: CloudOSColors.windows),
            ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    CloudFileItem item,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: CloudOSColors.textPrimary,
              ),
              SizedBox(width: 8),
              Text('Abrir'),
            ],
          ),
        ),
        if (!item.isDirectory)
          const PopupMenuItem<String>(
            value: 'open_with',
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.apps_rounded,
                  size: 16,
                  color: CloudOSColors.textPrimary,
                ),
                SizedBox(width: 8),
                Text('Abrir com...'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.copy_rounded,
                size: 16,
                color: CloudOSColors.textPrimary,
              ),
              SizedBox(width: 8),
              Text('Copiar (Ctrl+C)'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'cut',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.cut_rounded,
                size: 16,
                color: CloudOSColors.textPrimary,
              ),
              SizedBox(width: 8),
              Text('Recortar (Ctrl+X)'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.edit_rounded,
                size: 16,
                color: CloudOSColors.textPrimary,
              ),
              SizedBox(width: 8),
              Text('Renomear (F2)'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: Color(0xFFF43F5E),
              ),
              SizedBox(width: 8),
              Text('Excluir (Lixeira)'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'properties',
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: CloudOSColors.textPrimary,
              ),
              SizedBox(width: 8),
              Text('Propriedades'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'open') {
        _controller.openItem(item);
      } else if (value == 'open_with') {
        _showOpenWithDialog(item);
      } else if (value == 'copy') {
        _controller.copySelected();
      } else if (value == 'cut') {
        _controller.cutSelected();
      } else if (value == 'rename') {
        _showRenameDialog(item);
      } else if (value == 'delete') {
        _controller.deleteSelected(permanent: false);
      } else if (value == 'properties') {
        _showPropertiesDialog(item);
      }
    });
  }

  void _showOpenWithDialog(CloudFileItem item) async {
    List<OpenWithAppModel> apps;
    try {
      apps = await _controller.getOpenWith(item.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível consultar “Abrir com”: $error'),
        ),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('Abrir "${item.name}" com:'),
          content: SizedBox(
            width: 380,
            child: apps.isEmpty
                ? const Text('Nenhum aplicativo compatível foi encontrado.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: apps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        leading: Icon(
                          app.icon,
                          color: app.platform == 'linux'
                              ? CloudOSColors.linux
                              : CloudOSColors.windows,
                        ),
                        title: Text(
                          app.name,
                          style: const TextStyle(
                            fontSize: 13,
                            color: CloudOSColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          app.platform == 'linux'
                              ? 'Aplicativo Linux (WSLg)'
                              : 'Aplicativo Windows',
                          style: const TextStyle(
                            fontSize: 11,
                            color: CloudOSColors.textSecondary,
                          ),
                        ),
                        trailing: app.isDefault
                            ? const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: CloudOSColors.accent,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).pop();
                          _controller.launchOpenWith(item.path, app);
                        },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController(text: 'Nova Pasta');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Criar Nova Pasta'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome da Pasta'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  _controller.createFolder(name);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Criar'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _showRenameDialog(CloudFileItem item) {
    final controller = TextEditingController(text: item.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Renomear Item'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Novo Nome'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty && name != item.name) {
                  _controller.renameItem(item.path, name);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Renomear'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _showPropertiesDialog(CloudFileItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: <Widget>[
              Icon(item.icon, size: 24, color: item.iconColor),
              const SizedBox(width: 8),
              Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Tipo: ${item.isDirectory ? "Pasta de Arquivos" : (item.extension.isNotEmpty ? item.extension : "Arquivo")}',
              ),
              const SizedBox(height: 4),
              Text(
                'Tamanho: ${item.sizeFormatted.isNotEmpty ? item.sizeFormatted : "0 B"}',
              ),
              const SizedBox(height: 4),
              Text('Caminho: ${item.path}'),
              const SizedBox(height: 4),
              Text('Modificado: ${item.modifiedFormatted}'),
              const SizedBox(height: 4),
              Text(
                'Origem: ${item.locationKind == LocationKind.wsl ? "Linux / WSL (${item.distro})" : "Windows"}',
              ),
            ],
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
