import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloudos_theme.dart';

class NoteItem {
  NoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  String title;
  String content;
  DateTime updatedAt;
}

class NotesWindow extends StatefulWidget {
  const NotesWindow({super.key});

  @override
  State<NotesWindow> createState() => _NotesWindowState();
}

class _NotesWindowState extends State<NotesWindow> {
  final List<NoteItem> _notes = <NoteItem>[
    NoteItem(
      id: 'welcome',
      title: 'Bem-vindo ao CloudOS Notes',
      content: '# CloudOS Notes 🚀\n\n'
          'Este é o seu bloco de notas integrado para rascunhos rápidos, comandos e ideias.\n\n'
          'Principais recursos:\n'
          '- Digite suas anotações com persistência automática durante a sessão\n'
          '- Organize suas notas na barra lateral\n'
          '- Copie rapidamente para a área de transferência\n'
          '- Compatível com formatação e snippets de código!\n',
      updatedAt: DateTime.now(),
    ),
    NoteItem(
      id: 'commands',
      title: 'Comandos WSL & Kali',
      content: '# Comandos Úteis do Kali Linux\n\n'
          'nmap -sV -sC -Pn <alvo>\n'
          'whois <dominio>\n'
          'dig <dominio> ANY\n'
          'ss -tulpn\n',
      updatedAt: DateTime.now(),
    ),
  ];

  late String _selectedNoteId;
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedNoteId = _notes.first.id;
    _contentController.text = _notes.first.content;
    _titleController.text = _notes.first.title;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  NoteItem get _currentNote {
    return _notes.firstWhere(
      (n) => n.id == _selectedNoteId,
      orElse: () => _notes.first,
    );
  }

  void _selectNote(String id) {
    setState(() {
      _selectedNoteId = id;
      final note = _notes.firstWhere((n) => n.id == id);
      _titleController.text = note.title;
      _contentController.text = note.content;
    });
  }

  void _addNote() {
    final newId = 'note_${DateTime.now().millisecondsSinceEpoch}';
    final newNote = NoteItem(
      id: newId,
      title: 'Nova Nota (${_notes.length + 1})',
      content: '',
      updatedAt: DateTime.now(),
    );
    setState(() {
      _notes.insert(0, newNote);
      _selectNote(newId);
    });
  }

  void _deleteCurrentNote() {
    if (_notes.length <= 1) return;
    setState(() {
      _notes.removeWhere((n) => n.id == _selectedNoteId);
      _selectNote(_notes.first.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = _currentNote;
    final text = _contentController.text;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final characters = text.length;
    final lines = text.isEmpty ? 0 : text.split('\n').length;

    return Container(
      color: CloudOSColors.background,
      child: Row(
        children: <Widget>[
          // Sidebar
          Container(
            width: 210,
            decoration: const BoxDecoration(
              color: Color(0xFF0F1522),
              border: Border(right: BorderSide(color: CloudOSColors.border)),
            ),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.description_rounded, size: 18, color: CloudOSColors.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Anotações',
                          style: TextStyle(
                            color: CloudOSColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 18, color: CloudOSColors.accent),
                        tooltip: 'Nova Nota',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        splashRadius: 14,
                        onPressed: _addNote,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: CloudOSColors.border),
                Expanded(
                  child: ListView.builder(
                    itemCount: _notes.length,
                    itemBuilder: (context, index) {
                      final item = _notes[index];
                      final isSelected = item.id == _selectedNoteId;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: CloudOSColors.accent.withValues(alpha: 0.15),
                          title: Text(
                            item.title.isEmpty ? 'Sem título' : item.title,
                            style: TextStyle(
                              color: isSelected ? Colors.white : CloudOSColors.text,
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.content.trim().isEmpty ? 'Vazio' : item.content.trim().split('\n').first,
                            style: const TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectNote(item.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Editor Area
          Expanded(
            child: Column(
              children: <Widget>[
                // Toolbar
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF131B2B),
                    border: Border(bottom: BorderSide(color: CloudOSColors.border)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          onChanged: (val) {
                            setState(() {
                              note.title = val;
                              note.updatedAt = DateTime.now();
                            });
                          },
                          style: const TextStyle(
                            color: CloudOSColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Título da anotação...',
                            hintStyle: TextStyle(color: CloudOSColors.caption),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16, color: CloudOSColors.caption),
                        tooltip: 'Copiar conteúdo',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _contentController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Nota copiada para a área de transferência!'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      if (_notes.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                          tooltip: 'Excluir nota',
                          onPressed: _deleteCurrentNote,
                        ),
                    ],
                  ),
                ),
                // Text Area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _contentController,
                      onChanged: (val) {
                        setState(() {
                          note.content = val;
                          note.updatedAt = DateTime.now();
                        });
                      },
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        color: CloudOSColors.text,
                        fontSize: 13.5,
                        fontFamily: 'Consolas',
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Comece a escrever aqui...',
                        hintStyle: TextStyle(color: CloudOSColors.caption),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                // Status Bar
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: const Color(0xFF0C111C),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Linhas: $lines  •  Palavras: $words  •  Caracteres: $characters',
                          style: const TextStyle(color: CloudOSColors.caption, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'CloudOS Notes',
                        style: TextStyle(color: CloudOSColors.accent, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
