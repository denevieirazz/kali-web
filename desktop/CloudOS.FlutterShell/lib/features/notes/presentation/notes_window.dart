import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloudos_theme.dart';
import '../data/notes_store.dart';

class NotesWindow extends StatefulWidget {
  const NotesWindow({
    super.key,
    this.store = const FileNotesStore(),
  });

  final NotesStore store;

  @override
  State<NotesWindow> createState() => _NotesWindowState();
}

class _NotesWindowState extends State<NotesWindow> {
  late final List<StoredNote> _notes;
  late String _selectedNoteId;
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  Timer? _saveDebounce;
  bool _storageReady = false;
  bool _loading = true;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _notes = _defaultNotes();
    _selectedNoteId = _notes.first.id;
    _syncControllers(_notes.first);
    unawaited(_loadPersistedNotes());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    if (_storageReady) {
      unawaited(_persistNotes());
    }
    _contentController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  List<StoredNote> _defaultNotes() {
    return <StoredNote>[
      StoredNote(
        id: 'welcome',
        title: 'Bem-vindo ao CloudOS Notes',
        content: '# CloudOS Notes 🚀\n\n'
            'Este é o seu bloco de notas integrado para rascunhos rápidos, comandos e ideias.\n\n'
            'Principais recursos:\n'
            '- Digite suas anotações com salvamento automático local\n'
            '- Organize suas notas na barra lateral\n'
            '- Copie rapidamente para a área de transferência\n'
            '- Compatível com formatação e snippets de código!\n',
        updatedAt: DateTime.now(),
      ),
      StoredNote(
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
  }

  StoredNote get _currentNote {
    return _notes.firstWhere(
      (note) => note.id == _selectedNoteId,
      orElse: () => _notes.first,
    );
  }

  void _syncControllers(StoredNote note) {
    _titleController.text = note.title;
    _contentController.text = note.content;
  }

  Future<void> _loadPersistedNotes() async {
    NotesSnapshot? snapshot;
    try {
      snapshot = await widget.store.load();
    } on Object {
      snapshot = null;
    }
    if (!mounted) return;

    setState(() {
      if (snapshot != null && snapshot.notes.isNotEmpty) {
        _notes
          ..clear()
          ..addAll(snapshot.notes.map((note) => note.copy()));
        _selectedNoteId = snapshot.selectedNoteId ?? _notes.first.id;
        if (!_notes.any((note) => note.id == _selectedNoteId)) {
          _selectedNoteId = _notes.first.id;
        }
        _syncControllers(_currentNote);
      }
      _storageReady = true;
      _loading = false;
    });
  }

  NotesSnapshot _snapshot() {
    return NotesSnapshot(
      notes: _notes.map((note) => note.copy()).toList(growable: false),
      selectedNoteId: _selectedNoteId,
    );
  }

  void _schedulePersist() {
    if (!_storageReady) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistNotes());
    });
  }

  Future<void> _persistNotes() async {
    if (!_storageReady) return;
    final snapshot = _snapshot();
    try {
      await widget.store.save(snapshot);
      if (mounted && _saveFailed) {
        setState(() => _saveFailed = false);
      }
    } on Object {
      if (mounted && !_saveFailed) {
        setState(() => _saveFailed = true);
      }
    }
  }

  void _selectNote(String id) {
    final note = _notes.firstWhere((item) => item.id == id);
    setState(() {
      _selectedNoteId = id;
      _syncControllers(note);
    });
    _schedulePersist();
  }

  void _addNote() {
    final newId = 'note_${DateTime.now().microsecondsSinceEpoch}';
    final newNote = StoredNote(
      id: newId,
      title: 'Nova Nota (${_notes.length + 1})',
      content: '',
      updatedAt: DateTime.now(),
    );
    setState(() {
      _notes.insert(0, newNote);
      _selectedNoteId = newId;
      _syncControllers(newNote);
    });
    _schedulePersist();
  }

  void _deleteCurrentNote() {
    if (_notes.length <= 1) return;
    setState(() {
      _notes.removeWhere((note) => note.id == _selectedNoteId);
      _selectedNoteId = _notes.first.id;
      _syncControllers(_notes.first);
    });
    _schedulePersist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: CloudOSColors.background,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final note = _currentNote;
    final text = _contentController.text;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final characters = text.length;
    final lines = text.isEmpty ? 0 : text.split('\n').length;

    return Container(
      color: CloudOSColors.background,
      child: Row(
        children: <Widget>[
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
          Expanded(
            child: Column(
              children: <Widget>[
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
                          onChanged: (value) {
                            setState(() {
                              note.title = value;
                              note.updatedAt = DateTime.now();
                            });
                            _schedulePersist();
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _contentController,
                      onChanged: (value) {
                        setState(() {
                          note.content = value;
                          note.updatedAt = DateTime.now();
                        });
                        _schedulePersist();
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
                      Text(
                        _saveFailed ? 'Falha ao salvar localmente' : 'Armazenamento local',
                        style: TextStyle(
                          color: _saveFailed ? Colors.redAccent : CloudOSColors.accent,
                          fontSize: 11,
                        ),
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
