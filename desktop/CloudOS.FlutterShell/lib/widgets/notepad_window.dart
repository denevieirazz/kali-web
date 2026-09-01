import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/cloudos_theme.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';

class NotepadDocTab {
  NotepadDocTab({
    required this.id,
    required this.title,
    String initialContent = '',
    this.filePath,
  }) : controller = TextEditingController(text: initialContent),
       focusNode = FocusNode();

  final String id;
  String title;
  String? filePath;
  final TextEditingController controller;
  final FocusNode focusNode;
  bool isModified = false;
}

class NotepadWindow extends StatefulWidget {
  const NotepadWindow({
    super.key,
    required this.bridge,
    this.initialFilePath,
    this.initialContent,
  });

  final CloudOSBridge bridge;
  final String? initialFilePath;
  final String? initialContent;

  @override
  State<NotepadWindow> createState() => _NotepadWindowState();
}

class _NotepadWindowState extends State<NotepadWindow> {
  final List<NotepadDocTab> _tabs = <NotepadDocTab>[];
  int _activeTabIndex = 0;
  int _tabCounter = 1;
  int _currentLine = 1;
  int _currentCol = 1;

  @override
  void initState() {
    super.initState();
    _createInitialTab();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.controller.dispose();
      tab.focusNode.dispose();
    }
    super.dispose();
  }

  void _createInitialTab() {
    final path = widget.initialFilePath;
    String content = widget.initialContent ?? '';
    String title = 'Sem título 1.txt';

    if (path != null && path.isNotEmpty) {
      title = path.split(RegExp(r'[\\/]')).last;
      try {
        final f = File(path);
        if (f.existsSync()) {
          content = f.readAsStringSync();
        }
      } catch (e, st) {
        CloudOSLogger.error('NotepadWindow', 'readFileContent', e, st);
      }
    }

    final tab = NotepadDocTab(
      id: 'doc_${_tabCounter++}',
      title: title,
      initialContent: content,
      filePath: path,
    );

    tab.controller.addListener(() {
      _updateCursorPosition(tab);
      if (!tab.isModified) {
        setState(() => tab.isModified = true);
      }
    });

    _tabs.add(tab);
  }

  NotepadDocTab? get _activeTab =>
      (_tabs.isNotEmpty && _activeTabIndex < _tabs.length) ? _tabs[_activeTabIndex] : null;

  void _updateCursorPosition(NotepadDocTab tab) {
    final sel = tab.controller.selection;
    if (sel.baseOffset < 0) return;
    final text = tab.controller.text.substring(0, sel.baseOffset);
    final lines = text.split('\n');
    final line = lines.length;
    final col = lines.last.length + 1;
    if (line != _currentLine || col != _currentCol) {
      setState(() {
        _currentLine = line;
        _currentCol = col;
      });
    }
  }

  void _addNewTab() {
    setState(() {
      final counter = _tabCounter++;
      final tab = NotepadDocTab(
        id: 'doc_$counter',
        title: 'Sem título $counter.txt',
        initialContent: '',
      );
      tab.controller.addListener(() => _updateCursorPosition(tab));
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
  }

  Future<void> _closeTab(int index) async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[index];

    if (tab.isModified) {
      final shouldClose = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF101524),
          title: const Text('Salvar alterações?', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Text('O arquivo "${tab.title}" foi modificado. Deseja fechar sem salvar?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fechar Sem Salvar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (shouldClose != true) return;
    }

    if (_tabs.length <= 1) {
      setState(() {
        tab.controller.clear();
        tab.title = 'Sem título 1.txt';
        tab.filePath = null;
        tab.isModified = false;
      });
      return;
    }

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  Future<void> _openFileDialog() async {
    final pathCtrl = TextEditingController(text: r'C:\');
    final selectedPath = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101524),
        title: const Text('Abrir Arquivo do Disco', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Digite o caminho do arquivo:', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 8),
            TextField(
              controller: pathCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Consolas'),
              decoration: const InputDecoration(
                hintText: r'Ex: C:\Users\user\Documents\arquivo.txt',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.accent, foregroundColor: const Color(0xFF05070B)),
            onPressed: () => Navigator.pop(ctx, pathCtrl.text.trim()),
            child: const Text('Abrir Arquivo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (selectedPath != null && selectedPath.isNotEmpty) {
      _openFileFromPath(selectedPath);
    }
  }

  Future<void> _openFileFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showErrorSnackBar('O arquivo "$path" não foi encontrado no disco.');
        return;
      }

      final content = await file.readAsString();
      final title = path.split(RegExp(r'[\\/]')).last;

      setState(() {
        final counter = _tabCounter++;
        final tab = NotepadDocTab(
          id: 'doc_$counter',
          title: title,
          initialContent: content,
          filePath: path,
        );
        tab.isModified = false;
        tab.controller.addListener(() => _updateCursorPosition(tab));
        _tabs.add(tab);
        _activeTabIndex = _tabs.length - 1;
      });
    } catch (e) {
      _showErrorSnackBar('Erro ao ler arquivo: $e');
    }
  }

  Future<void> _saveCurrentTab({bool saveAs = false}) async {
    final tab = _activeTab;
    if (tab == null) return;

    String? targetPath = tab.filePath;

    if (targetPath == null || targetPath.isEmpty || saveAs) {
      final defaultDir = Platform.environment['USERPROFILE'] ?? r'C:\';
      final pathCtrl = TextEditingController(text: '$defaultDir\\Documents\\${tab.title}');

      final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF101524),
          title: const Text('Salvar Arquivo', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Caminho de destino do arquivo:', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 8),
              TextField(
                controller: pathCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Consolas'),
                decoration: const InputDecoration(
                  hintText: r'C:\caminho\para\arquivo.txt',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.neonEmerald, foregroundColor: const Color(0xFF05070B)),
              onPressed: () => Navigator.pop(ctx, pathCtrl.text.trim()),
              child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (chosen == null || chosen.isEmpty) return;
      targetPath = chosen;
    }

    try {
      final file = File(targetPath);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(tab.controller.text, flush: true);

      final title = targetPath.split(RegExp(r'[\\/]')).last;
      setState(() {
        tab.filePath = targetPath;
        tab.title = title;
        tab.isModified = false;
      });

      _showSuccessSnackBar('Arquivo "$title" salvo com sucesso no disco!');
    } catch (e) {
      _showErrorSnackBar('Falha real ao gravar arquivo no disco: $e');
    }
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0D1424),
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        backgroundColor: CloudOSColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTab;
    final totalLines = active != null ? active.controller.text.split('\n').length : 1;
    final totalChars = active != null ? active.controller.text.length : 0;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _saveCurrentTab(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => _saveCurrentTab(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _openFileDialog,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _addNewTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeTab(_activeTabIndex),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: <Widget>[
            // Toolbar Superior com Abas e Ações
            Container(
              height: 38,
              color: const Color(0xFF090D18),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (context, index) {
                        final tab = _tabs[index];
                        final isSelected = index == _activeTabIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _activeTabIndex = index),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF141A2C) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: CloudOSColors.accent.withValues(alpha: 0.4), width: 1)
                                  : Border.all(color: Colors.white.withValues(alpha: 0.04)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.description_outlined, size: 13, color: CloudOSColors.accent),
                                const SizedBox(width: 6),
                                Text(
                                  tab.isModified ? '${tab.title} •' : tab.title,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isSelected ? Colors.white : Colors.white60,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                                if (_tabs.length > 1) ...<Widget>[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => _closeTab(index),
                                    borderRadius: BorderRadius.circular(4),
                                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white54),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Botão Abrir Arquivo
                  IconButton(
                    icon: const Icon(Icons.file_open_outlined, size: 16, color: CloudOSColors.accent),
                    tooltip: 'Abrir Arquivo do Disco (Ctrl+O)',
                    onPressed: _openFileDialog,
                  ),

                  // Botão Nova Aba
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 16, color: CloudOSColors.accent),
                    tooltip: 'Novo Documento (Ctrl+N)',
                    onPressed: _addNewTab,
                  ),

                  // Botão Salvar
                  IconButton(
                    icon: const Icon(Icons.save_outlined, size: 16, color: CloudOSColors.neonEmerald),
                    tooltip: 'Salvar no Disco (Ctrl+S)',
                    onPressed: () => _saveCurrentTab(),
                  ),
                ],
              ),
            ),

            // Área de Edição com Numeração de Linhas Lateral
            Expanded(
              child: active == null
                  ? const SizedBox.shrink()
                  : Container(
                      color: const Color(0xFF06080F),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Gutter de Linhas
                          Container(
                            width: 44,
                            color: const Color(0xFF080B14),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: ListView.builder(
                              itemCount: totalLines,
                              itemBuilder: (context, index) {
                                final isCurrent = (index + 1) == _currentLine;
                                return Text(
                                  '${index + 1}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 12,
                                    color: isCurrent ? CloudOSColors.accent : Colors.white24,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    height: 1.4,
                                  ),
                                );
                              },
                            ),
                          ),

                          const VerticalDivider(width: 1, color: Color(0x1AFFFFFF)),

                          // Editor TextField
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: TextField(
                                controller: active.controller,
                                focusNode: active.focusNode,
                                maxLines: null,
                                expands: true,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 13,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                                cursorColor: CloudOSColors.neonCyan,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  fillColor: Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Barra de Status Inferior do Editor
            Container(
              height: 24,
              color: const Color(0xFF080A12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Linha $_currentLine, Coluna $_currentCol • $totalLines linhas',
                    style: const TextStyle(fontSize: 10.5, color: Colors.white60, fontFamily: 'Consolas'),
                  ),
                  Text(
                    '${active?.filePath ?? "Documento não salvo"} • $totalChars chars • UTF-8',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white60, fontFamily: 'Consolas'),
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
