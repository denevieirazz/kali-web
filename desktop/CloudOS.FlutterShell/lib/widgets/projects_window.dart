import 'dart:io';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/project_store.dart';
import '../services/window_manager.dart';

class ProjectsWindow extends StatefulWidget {
  const ProjectsWindow({
    super.key,
    required this.bridge,
    required this.windowManager,
  });

  final CloudOSBridge bridge;
  final WindowManager windowManager;

  @override
  State<ProjectsWindow> createState() => _ProjectsWindowState();
}

class _ProjectsWindowState extends State<ProjectsWindow> {
  final List<ProjectRecord> _projects = <ProjectRecord>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loaded = await ProjectStore.load();
      if (!mounted) return;
      setState(() {
        _projects
          ..clear()
          ..addAll(loaded);
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectsWindow', 'loadProjects', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os workspaces salvos.';
      });
    }
  }

  Future<void> _persistProjects() async {
    try {
      await ProjectStore.save(_projects);
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectsWindow', 'persistProjects', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar a lista de projetos.')),
      );
    }
  }

  Future<void> _showNewWorkspaceDialog() async {
    final nameCtrl = TextEditingController();
    final defaultRoot = Platform.environment['USERPROFILE'];
    final pathCtrl = TextEditingController(text: defaultRoot ?? '');
    var createIfMissing = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF101524),
          title: const Text(
            'Adicionar Workspace',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Nome',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(hintText: 'Ex: Meu projeto'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Caminho da pasta',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: pathCtrl,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'Consolas',
                  ),
                  decoration: const InputDecoration(
                    hintText: r'Ex: C:\Projetos\MeuApp',
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: createIfMissing,
                  activeColor: CloudOSColors.accent,
                  title: const Text(
                    'Criar a pasta se ela ainda não existir',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  onChanged: (value) => setDialogState(
                    () => createIfMissing = value ?? false,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CloudOSColors.accent,
                foregroundColor: const Color(0xFF05070B),
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty &&
                    pathCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text(
                'Adicionar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final path = pathCtrl.text.trim();
    nameCtrl.dispose();
    pathCtrl.dispose();
    if (result != true) return;

    final dir = Directory(path);

    try {
      if (!dir.existsSync()) {
        if (!createIfMissing) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A pasta não existe. Marque a opção de criação ou informe uma pasta existente.',
              ),
            ),
          );
          return;
        }
        dir.createSync(recursive: true);
      }
    } catch (error, stackTrace) {
      CloudOSLogger.error('ProjectsWindow', 'prepareWorkspaceDir', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível preparar a pasta: $error')),
      );
      return;
    }

    final normalized = dir.absolute.path.toLowerCase();
    if (_projects.any((project) => project.path.toLowerCase() == normalized)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esse workspace já está cadastrado.')),
      );
      return;
    }

    setState(() {
      _projects.add(
        ProjectRecord(
          id: ProjectStore.makeId(normalized),
          name: name,
          path: dir.absolute.path,
          createdAt: DateTime.now(),
        ),
      );
    });
    await _persistProjects();
  }

  Future<void> _openInFiles(ProjectRecord project) async {
    final index = _projects.indexWhere((item) => item.id == project.id);
    if (index != -1) {
      setState(() {
        _projects[index] = project.copyWith(lastOpenedAt: DateTime.now());
      });
      await _persistProjects();
    }

    widget.windowManager.openWindow(
      'cloudos:files',
      params: <String, dynamic>{'initialPath': project.path},
    );
  }

  Future<void> _removeProject(ProjectRecord project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101524),
        title: const Text(
          'Remover workspace?',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: Text(
          'Isso remove apenas "${project.name}" da lista do CloudOS. A pasta e seus arquivos não serão apagados.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _projects.removeWhere((item) => item.id == project.id));
    await _persistProjects();
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF131622),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Gerenciador de Projetos & Workspaces',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'CloudOS Core & Shell V22.1',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: CloudOSColors.accent,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Somente pastas realmente cadastradas por você aparecem aqui.',
                      style: TextStyle(fontSize: 11.5, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Abrir no Terminal',
                onPressed: () => widget.windowManager.openWindow('cloudos:terminal'),
                icon: const Icon(Icons.terminal_rounded, color: Colors.cyanAccent),
              ),
              IconButton(
                tooltip: 'Recarregar',
                onPressed: _loadProjects,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'Adicionar Workspace',
                  style: TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CloudOSColors.accent,
                  foregroundColor: const Color(0xFF05070B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _showNewWorkspaceDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.hourglass_top_rounded, size: 30, color: Colors.white38),
            SizedBox(height: 8),
            Text(
              'Carregando projetos...',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 42, color: Colors.orangeAccent),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _loadProjects, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    if (_projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.workspaces_outline, size: 52, color: Colors.white30),
            const SizedBox(height: 14),
            const Text(
              'Nenhum workspace cadastrado',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Adicione uma pasta existente ou crie uma nova pasta de projeto.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showNewWorkspaceDialog,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Adicionar Workspace'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _projects.length,
      itemBuilder: (context, index) {
        final project = _projects[index];
        final exists = Directory(project.path).existsSync();
        final type = ProjectStore.detectType(project.path);
        final modified = ProjectStore.lastModified(project.path);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2030),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CloudOSColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  exists ? Icons.account_tree_rounded : Icons.folder_off_outlined,
                  size: 24,
                  color: exists ? CloudOSColors.accent : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      project.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white60,
                        fontFamily: 'Consolas',
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _badge(type),
                        Text(
                          exists ? 'Disponível' : 'Pasta ausente',
                          style: TextStyle(
                            fontSize: 11,
                            color: exists ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        Text(
                          'Modificado: ${_formatDate(modified)}',
                          style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                        ),
                        if (project.lastOpenedAt != null)
                          Text(
                            'Aberto: ${_formatDate(project.lastOpenedAt)}',
                            style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.folder_open_rounded,
                  size: 18,
                  color: Colors.amberAccent,
                ),
                tooltip: exists ? 'Abrir no Files' : 'Pasta não encontrada',
                onPressed: exists ? () => _openInFiles(project) : null,
              ),
              IconButton(
                icon: const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: Colors.cyanAccent,
                ),
                tooltip: 'Abrir Terminal',
                onPressed: () => widget.windowManager.openWindow('cloudos:terminal'),
              ),
              IconButton(
                icon: const Icon(
                  Icons.code_rounded,
                  size: 18,
                  color: Colors.blueAccent,
                ),
                tooltip: 'Abrir VS Code (aplicativo externo)',
                onPressed: () => widget.bridge.launchApp('windows:vscode'),
              ),
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
                tooltip: 'Remover da lista',
                onPressed: () => _removeProject(project),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }
}
