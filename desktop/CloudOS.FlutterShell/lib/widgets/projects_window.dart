import 'dart:io';
import 'package:flutter/material.dart';
import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
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
  final List<Map<String, String>> _projects = <Map<String, String>>[
    <String, String>{
      'name': 'CloudOS Core & Shell V22.1',
      'path': r'C:\CloudOS',
      'type': 'Flutter + C++ Native + Rust/Go Core',
      'status': 'Compilado / Ativo',
      'lastModified': 'Hoje',
    },
    <String, String>{
      'name': 'CloudOS Flutter Presentation Layer',
      'path': r'C:\CloudOS\desktop\CloudOS.FlutterShell',
      'type': 'Flutter Desktop Windows x64',
      'status': 'Release x64 Pronto',
      'lastModified': 'Hoje',
    },
    <String, String>{
      'name': 'System Broker V21 Service',
      'path': r'C:\CloudOS\desktop\CloudOS.SystemBroker',
      'type': 'C++20 / Named Pipe IPC',
      'status': '53 Assertions Pass',
      'lastModified': 'Hoje',
    },
    <String, String>{
      'name': 'Linux Workspace (WSL2)',
      'path': r'\\wsl.localhost',
      'type': 'WSL2 Linux Environment',
      'status': 'Pronto',
      'lastModified': 'Hoje',
    },
  ];

  Future<void> _showNewWorkspaceDialog() async {
    final nameCtrl = TextEditingController();
    final pathCtrl = TextEditingController(text: Platform.environment['USERPROFILE'] ?? r'C:\');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101524),
        title: const Text('Adicionar Novo Workspace', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Nome do Projeto / Workspace:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(hintText: 'Ex: Meu App Flutter'),
            ),
            const SizedBox(height: 12),
            const Text('Caminho da Pasta:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: pathCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Consolas'),
              decoration: const InputDecoration(hintText: r'Ex: C:\Projetos\MeuApp'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.accent, foregroundColor: const Color(0xFF05070B)),
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && pathCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == true) {
      final p = pathCtrl.text.trim();
      final dir = Directory(p);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (e, st) {
          CloudOSLogger.error('ProjectsWindow', 'createWorkspaceDir', e, st);
        }
      }

      setState(() {
        _projects.add(<String, String>{
          'name': nameCtrl.text.trim(),
          'path': p,
          'type': 'Workspace Customizado',
          'status': 'Ativo',
          'lastModified': 'Agora',
        });
      });
    }
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Gerenciador de Projetos & Workspaces',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Novo Workspace', style: TextStyle(fontSize: 12)),
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

          Expanded(
            child: ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final proj = _projects[index];
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
                        child: const Icon(Icons.account_tree_rounded, size: 24, color: CloudOSColors.accent),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              proj['name']!,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              proj['path']!,
                              style: const TextStyle(fontSize: 11.5, color: Colors.white60, fontFamily: 'Consolas'),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(proj['type']!, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                ),
                                Text(proj['status']!, style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Botões de Ação Rápida
                      Row(
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.amberAccent),
                            tooltip: 'Abrir no Files',
                            onPressed: () {
                              widget.windowManager.openWindow('cloudos:files');
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.terminal_rounded, size: 18, color: Colors.cyanAccent),
                            tooltip: 'Abrir no Terminal',
                            onPressed: () {
                              widget.windowManager.openWindow('cloudos:terminal');
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.code_rounded, size: 18, color: Colors.blueAccent),
                            tooltip: 'Abrir no VS Code',
                            onPressed: () {
                              widget.bridge.launchApp('windows:vscode');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
