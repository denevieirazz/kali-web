import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  WORKSPACE_FOLDERS,
  WORKSPACE_TYPES,
  matchesWorkflowQuery,
  terminalHereCapability,
  workflowFileOpenMode,
  workspaceSearchText,
  type WorkspaceType,
  type WorkflowProvider,
} from '../../core/workflowCore.js';
import { useWindowManager } from '../../stores/windowManager';
import { fileSourceFacade } from '../CloudOSFiles/fileSourceFacade';
import {
  MAX_NOTE_BYTES,
  MAX_NOTE_INDEX_CONTENT_CHARS,
  activateWorkspace,
  archiveWorkspace,
  createWorkspace,
  createWorkspaceNote,
  downloadDestinationLabel,
  duplicateWorkspace,
  getActiveWorkspace,
  getDownloadDestination,
  getWorkspace,
  listWorkspaces,
  listWorkspaceEvidence,
  listWorkspaceNotes,
  loadWorkspaceNote,
  saveWorkspaceEvidenceFile,
  saveWorkspaceEvidenceText,
  saveWorkspaceNote,
  searchWorkspaceNotes,
  setDownloadDestination,
  updateWorkspaceMetadata,
  type WorkflowNoteContent,
  type WorkflowNoteMeta,
  type WorkspaceRecord,
} from '../../services/workflowWorkspace';
import {
  importWorkspaceFile,
  moveWorkspaceSafely,
  workspaceTransferLimits,
} from '../../services/workflowWorkspaceTransfer';
import { downloadWorkspaceZip } from '../../services/workflowWorkspaceZip';
import {
  clearClipboardHistory,
  copyClipboardEntryToSystem,
  listClipboardEntries,
  pasteClipboardEntry,
  toggleClipboardFavorite,
  type ClipboardMetadata,
} from '../../services/workflowClipboard';
import { openExistingBrowser, openFilesAt, openWorkspaceFiles, openWorkspaceTerminal } from '../../services/workflowLaunch';
import './WorkflowWorkspace.css';
import './WorkflowWorkspace36.css';

type WorkspaceTab = 'overview' | 'notes' | 'evidence' | 'downloads' | 'clipboard';
type EvidenceKind = 'note' | 'log' | 'link';
type ExternalTextTarget = { provider: WorkflowProvider; path: string[]; name: string };
type ExternalTextState = ExternalTextTarget & { content: string; savedContent: string; mode?: number };
type WindowParams = { workspaceId?: string; noteFileName?: string; externalTextFile?: ExternalTextTarget };
type TextHit = { fileName: string; start: number; end: number; snippet: string };
type WorkspaceDraftSnapshot = { workspace: WorkspaceRecord; fileName: string; content: string; savedContent: string };

const MAX_VISIBLE_SEARCH_HITS = 100;

function noteMetadata(note: WorkflowNoteContent): WorkflowNoteMeta {
  const { content: _content, ...meta } = note;
  return meta;
}

function MarkdownPreview({ value }: { value: string }) {
  const lines = value.split(/\r?\n/);
  let inCode = false;
  return <div className="ww-markdown-preview" aria-label="Preview Markdown">
    {lines.map((line, index) => {
      if (line.trim().startsWith('```')) {
        inCode = !inCode;
        return <div className="ww-code-fence" key={index}>{inCode ? 'código' : 'fim do código'}</div>;
      }
      if (inCode) return <pre key={index}>{line || ' '}</pre>;
      if (line.startsWith('### ')) return <h4 key={index}>{line.slice(4)}</h4>;
      if (line.startsWith('## ')) return <h3 key={index}>{line.slice(3)}</h3>;
      if (line.startsWith('# ')) return <h2 key={index}>{line.slice(2)}</h2>;
      if (/^[-*] /.test(line)) return <div className="ww-bullet" key={index}>• {line.slice(2)}</div>;
      if (/^\d+\. /.test(line)) return <div className="ww-bullet" key={index}>{line}</div>;
      if (line.startsWith('> ')) return <blockquote key={index}>{line.slice(2)}</blockquote>;
      return <p key={index}>{line || '\u00a0'}</p>;
    })}
  </div>;
}

function workspaceOriginLabel(workspace: WorkspaceRecord) {
  if (workspace.provider === 'opfs') return 'OPFS · CloudOS';
  if (workspace.provider === 'windows') return 'Windows · pasta autorizada';
  return 'Linux · Home';
}

function providerLabel(provider: WorkflowProvider) {
  if (provider === 'windows') return 'Windows · pasta autorizada';
  if (provider === 'wsl') return 'Linux · Home';
  return 'OPFS · CloudOS';
}

function validExternalTarget(value: unknown): value is ExternalTextTarget {
  if (!value || typeof value !== 'object') return false;
  const target = value as ExternalTextTarget;
  return ['opfs', 'windows', 'wsl'].includes(target.provider)
    && Array.isArray(target.path)
    && target.path.every(part => typeof part === 'string' && Boolean(part))
    && typeof target.name === 'string'
    && workflowFileOpenMode(target.name, 'file', false) === 'notes';
}

function textHits(fileName: string, text: string, query: string, limit = MAX_VISIBLE_SEARCH_HITS): TextHit[] {
  const needle = query.trim().toLocaleLowerCase('pt-BR');
  if (!needle) return [];
  const haystack = text.toLocaleLowerCase('pt-BR');
  const hits: TextHit[] = [];
  let offset = 0;
  while (hits.length < limit) {
    const start = haystack.indexOf(needle, offset);
    if (start < 0) break;
    const end = start + needle.length;
    const snippetStart = Math.max(0, start - 45);
    const snippetEnd = Math.min(text.length, end + 70);
    hits.push({ fileName, start, end, snippet: text.slice(snippetStart, snippetEnd).replace(/\s+/g, ' ').trim() });
    offset = Math.max(end, start + 1);
  }
  return hits;
}

function HighlightedText({ value, query }: { value: string; query: string }) {
  const needle = query.trim();
  if (!needle) return <>{value}</>;
  const lower = value.toLocaleLowerCase('pt-BR');
  const target = needle.toLocaleLowerCase('pt-BR');
  const parts: Array<{ text: string; hit: boolean }> = [];
  let offset = 0;
  let count = 0;
  while (offset < value.length && count < 20) {
    const index = lower.indexOf(target, offset);
    if (index < 0) break;
    if (index > offset) parts.push({ text: value.slice(offset, index), hit: false });
    parts.push({ text: value.slice(index, index + target.length), hit: true });
    offset = index + target.length;
    count += 1;
  }
  if (offset < value.length) parts.push({ text: value.slice(offset), hit: false });
  return <>{parts.map((part, index) => part.hit ? <mark key={index}>{part.text}</mark> : <span key={index}>{part.text}</span>)}</>;
}

export default function WorkflowWorkspace({ windowId }: { windowId: string }) {
  const params = useWindowManager(state => state.getWindow(windowId)?.params as WindowParams | undefined);
  const [workspaces, setWorkspaces] = useState<WorkspaceRecord[]>(listWorkspaces);
  const [activeId, setActiveId] = useState(() => params?.workspaceId || getActiveWorkspace()?.id || '');
  const [workspaceSearch, setWorkspaceSearch] = useState('');
  const [showArchived, setShowArchived] = useState(false);
  const [tab, setTab] = useState<WorkspaceTab>(params?.noteFileName || params?.externalTextFile ? 'notes' : 'overview');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [showEdit, setShowEdit] = useState(false);
  const [newType, setNewType] = useState<WorkspaceType>('client');
  const [newProvider, setNewProvider] = useState<WorkflowProvider>('opfs');
  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [newClient, setNewClient] = useState('');
  const [newTags, setNewTags] = useState('');
  const [editType, setEditType] = useState<WorkspaceType>('custom');
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [editClient, setEditClient] = useState('');
  const [editTags, setEditTags] = useState('');
  const [transferProvider, setTransferProvider] = useState<WorkflowProvider>('opfs');

  const [notes, setNotes] = useState<WorkflowNoteMeta[]>([]);
  const [activeNoteFile, setActiveNoteFile] = useState(params?.noteFileName || '');
  const [noteContent, setNoteContent] = useState('');
  const [noteSearch, setNoteSearch] = useState('');
  const [noteSearchFiles, setNoteSearchFiles] = useState<string[]>([]);
  const [noteHits, setNoteHits] = useState<TextHit[]>([]);
  const [noteSearchBusy, setNoteSearchBusy] = useState(false);
  const [noteHitIndex, setNoteHitIndex] = useState(0);
  const [externalHitIndex, setExternalHitIndex] = useState(0);
  const [noteSaving, setNoteSaving] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [previewMarkdown, setPreviewMarkdown] = useState(false);
  const [externalFile, setExternalFile] = useState<ExternalTextState | null>(null);
  const savedNoteContent = useRef('');
  const workspaceDraftRef = useRef<WorkspaceDraftSnapshot | null>(null);
  const noteLoadGenerationRef = useRef(0);
  const noteSearchRef = useRef<HTMLInputElement>(null);
  const noteEditorRef = useRef<HTMLTextAreaElement>(null);
  const workspaceImportRef = useRef<HTMLInputElement>(null);

  const [evidence, setEvidence] = useState<any[]>([]);
  const [evidenceKind, setEvidenceKind] = useState<EvidenceKind>('note');
  const [evidenceText, setEvidenceText] = useState('');
  const evidenceInputRef = useRef<HTMLInputElement>(null);

  const [clipboardEntries, setClipboardEntries] = useState<ClipboardMetadata[]>(listClipboardEntries);
  const [downloadDestination, setDownloadDestinationState] = useState(getDownloadDestination);

  const active = useMemo(() => workspaces.find(item => item.id === activeId) || null, [activeId, workspaces]);
  const activeNote = useMemo(() => notes.find(note => note.fileName === activeNoteFile) || null, [activeNoteFile, notes]);
  const visibleWorkspaces = useMemo(() => workspaces.filter(workspace => (showArchived || workspace.status !== 'archived') && matchesWorkflowQuery(workspaceSearchText(workspace), workspaceSearch)), [showArchived, workspaceSearch, workspaces]);
  const filteredNotes = useMemo(() => {
    if (!noteSearch.trim()) return notes;
    const matched = new Set(noteSearchFiles);
    return notes.filter(note => matched.has(note.fileName));
  }, [noteSearch, noteSearchFiles, notes]);
  const externalHits = useMemo(() => externalFile ? textHits(externalFile.name, externalFile.content, noteSearch) : [], [externalFile, noteSearch]);
  const externalDirty = Boolean(externalFile && externalFile.content !== externalFile.savedContent);
  const workspaceNoteDirty = Boolean(!externalFile && active && activeNoteFile && noteContent !== savedNoteContent.current);
  const transferLimits = useMemo(() => workspaceTransferLimits(), []);

  workspaceDraftRef.current = active && activeNoteFile && !externalFile
    ? { workspace: active, fileName: activeNoteFile, content: noteContent, savedContent: savedNoteContent.current }
    : null;

  const refreshWorkspaces = useCallback(() => {
    const next = listWorkspaces();
    setWorkspaces(next);
    setActiveId(current => next.some(item => item.id === current) ? current : (getActiveWorkspace()?.id || next.find(item => item.status !== 'archived')?.id || next[0]?.id || ''));
  }, []);

  useEffect(() => {
    const changed = () => {
      refreshWorkspaces();
      setDownloadDestinationState(getDownloadDestination());
    };
    window.addEventListener('cloudos:workflow-changed', changed);
    return () => window.removeEventListener('cloudos:workflow-changed', changed);
  }, [refreshWorkspaces]);

  useEffect(() => {
    const changed = () => setClipboardEntries(listClipboardEntries());
    window.addEventListener('cloudos:clipboard-changed', changed);
    return () => window.removeEventListener('cloudos:clipboard-changed', changed);
  }, []);

  useEffect(() => () => {
    const draft = workspaceDraftRef.current;
    if (!draft || draft.content === draft.savedContent) return;
    void saveWorkspaceNote(draft.workspace, { fileName: draft.fileName, content: draft.content }).catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!params?.workspaceId) return;
    const target = getWorkspace(params.workspaceId);
    if (target) {
      setActiveId(target.id);
      if (target.status !== 'archived') void activateWorkspace(target.id).catch(() => undefined);
    }
  }, [params?.workspaceId]);

  useEffect(() => {
    const raw = params?.externalTextFile;
    if (!validExternalTarget(raw)) return;
    let cancelled = false;
    noteLoadGenerationRef.current += 1;
    setBusy(true);
    setError('');
    setNotice('');
    void (async () => {
      try {
        const entries = await fileSourceFacade.list(raw.provider, raw.path, false);
        const entry = entries.find(item => item.name === raw.name);
        if (!entry || entry.kind !== 'file' || entry.symlink) throw new Error('Arquivo não encontrado ou não é um arquivo regular.');
        if (entry.size > MAX_NOTE_BYTES) throw new Error('Arquivo excede o limite de 2 MiB do editor rápido.');
        const file = await fileSourceFacade.readFile(raw.provider, raw.path, entry, MAX_NOTE_BYTES);
        const content = await file.text();
        if (!cancelled) {
          setExternalFile({ ...raw, content, savedContent: content, mode: entry.mode });
          setTab('notes');
          setPreviewMarkdown(false);
          setNoteSearch('');
          setExternalHitIndex(0);
          setNoteSaving('idle');
        }
      } catch (cause) {
        if (!cancelled) setError(cause instanceof Error ? cause.message : 'Falha ao abrir o arquivo no Notes.');
      } finally {
        if (!cancelled) setBusy(false);
      }
    })();
    return () => { cancelled = true; };
  }, [params?.externalTextFile?.name, params?.externalTextFile?.provider, JSON.stringify(params?.externalTextFile?.path || [])]);

  useEffect(() => {
    if (!externalDirty && !workspaceNoteDirty) return;
    const beforeUnload = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ''; };
    window.addEventListener('beforeunload', beforeUnload);
    return () => window.removeEventListener('beforeunload', beforeUnload);
  }, [externalDirty, workspaceNoteDirty]);

  const refreshWorkspaceContent = useCallback(async (workspace: WorkspaceRecord | null) => {
    const generation = ++noteLoadGenerationRef.current;
    if (!workspace) {
      setNotes([]);
      setEvidence([]);
      setActiveNoteFile('');
      setNoteContent('');
      savedNoteContent.current = '';
      return;
    }
    setBusy(true);
    setError('');
    try {
      const [nextNotes, nextEvidence] = await Promise.all([
        listWorkspaceNotes(workspace),
        listWorkspaceEvidence(workspace),
      ]);
      const requested = params?.noteFileName;
      const chosen = (requested && nextNotes.find(note => note.fileName === requested)) || nextNotes.find(note => note.fileName === activeNoteFile) || nextNotes[0] || null;
      const loaded = chosen ? await loadWorkspaceNote(workspace, chosen) : null;
      if (generation !== noteLoadGenerationRef.current) return;
      setNotes(nextNotes);
      setEvidence(nextEvidence);
      setActiveNoteFile(chosen?.fileName || '');
      setNoteContent(loaded?.content || '');
      savedNoteContent.current = loaded?.content || '';
      setNoteSaving('idle');
      setDownloadDestinationState(getDownloadDestination());
    } catch (cause) {
      if (generation === noteLoadGenerationRef.current) {
        setError(cause instanceof Error ? cause.message : 'Falha ao abrir o workspace.');
      }
    } finally {
      if (generation === noteLoadGenerationRef.current) setBusy(false);
    }
  }, [activeNoteFile, params?.noteFileName]);

  useEffect(() => { void refreshWorkspaceContent(active); }, [active?.id]);
  useEffect(() => { setNoteHitIndex(0); setExternalHitIndex(0); }, [noteSearch]);

  useEffect(() => {
    if (externalFile || !active || !noteSearch.trim()) {
      setNoteSearchFiles([]);
      setNoteHits([]);
      setNoteSearchBusy(false);
      return;
    }
    let cancelled = false;
    setNoteSearchFiles([]);
    setNoteHits([]);
    const timer = window.setTimeout(() => {
      setNoteSearchBusy(true);
      void searchWorkspaceNotes(active, notes, noteSearch, {
        limit: MAX_VISIBLE_SEARCH_HITS,
        cancelled: () => cancelled,
        activeDocument: activeNoteFile ? { fileName: activeNoteFile, content: noteContent } : null,
      }).then(result => {
        if (cancelled) return;
        setNoteSearchFiles(result.fileNames);
        setNoteHits(result.hits);
      }).catch(cause => {
        if (!cancelled) setError(cause instanceof Error ? cause.message : 'Falha ao pesquisar Notes.');
      }).finally(() => {
        if (!cancelled) setNoteSearchBusy(false);
      });
    }, 180);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [active?.id, activeNoteFile, externalFile, noteContent, noteSearch, notes]);

  const persistDirtyWorkspaceNote = useCallback(async () => {
    if (externalFile || !active || !activeNoteFile || noteContent === savedNoteContent.current) return true;
    setNoteSaving('saving');
    setError('');
    try {
      const saved = await saveWorkspaceNote(active, { fileName: activeNoteFile, content: noteContent });
      savedNoteContent.current = saved.content;
      const meta = noteMetadata(saved);
      setNotes(current => current.map(note => note.fileName === saved.fileName ? meta : note));
      setNoteSaving('saved');
      return true;
    } catch (cause) {
      setNoteSaving('error');
      setError(cause instanceof Error ? cause.message : 'Falha ao salvar a nota antes de trocar de contexto.');
      return false;
    }
  }, [active, activeNoteFile, externalFile, noteContent]);

  const selectWorkspace = useCallback(async (workspace: WorkspaceRecord) => {
    setError(''); setNotice('');
    if (!(await persistDirtyWorkspaceNote())) return;
    setActiveId(workspace.id);
    if (workspace.status === 'archived') return;
    try { await activateWorkspace(workspace.id); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao ativar o workspace.'); }
  }, [persistDirtyWorkspaceNote]);

  const selectNote = useCallback(async (note: WorkflowNoteMeta) => {
    if (note.fileName === activeNoteFile && !externalFile) return;
    if (!active) return;
    if (externalDirty && !window.confirm(`Descartar alterações não salvas de “${externalFile?.name}”?`)) return;
    if (!(await persistDirtyWorkspaceNote())) return;
    const generation = ++noteLoadGenerationRef.current;
    setError('');
    try {
      const loaded = await loadWorkspaceNote(active, note);
      if (generation !== noteLoadGenerationRef.current) return;
      setExternalFile(null);
      setActiveNoteFile(loaded.fileName);
      setNoteContent(loaded.content);
      savedNoteContent.current = loaded.content;
      setNoteSaving('idle');
    } catch (cause) {
      if (generation === noteLoadGenerationRef.current) setError(cause instanceof Error ? cause.message : 'Falha ao carregar a nota.');
    }
  }, [active, activeNoteFile, externalDirty, externalFile, persistDirtyWorkspaceNote]);

  const saveActiveNote = useCallback(async () => {
    if (externalFile) {
      if (externalFile.content === externalFile.savedContent) return;
      const bytes = new TextEncoder().encode(externalFile.content).byteLength;
      if (bytes > MAX_NOTE_BYTES) { setError('Arquivo excede o limite de 2 MiB do editor rápido.'); return; }
      setNoteSaving('saving'); setError(''); setNotice('');
      try {
        await fileSourceFacade.writeText(externalFile.provider, externalFile.path, externalFile.name, externalFile.content, externalFile.mode);
        setExternalFile(current => current ? { ...current, savedContent: current.content } : current);
        setNoteSaving('saved');
        setNotice(`“${externalFile.name}” salvo em ${providerLabel(externalFile.provider)}.`);
      } catch (cause) {
        setNoteSaving('error');
        setError(cause instanceof Error ? cause.message : 'Falha ao salvar o arquivo.');
      }
      return;
    }
    await persistDirtyWorkspaceNote();
  }, [externalFile, persistDirtyWorkspaceNote]);

  const saveExternalAs = useCallback(async () => {
    if (!externalFile) return;
    const requested = window.prompt('Salvar como', externalFile.name);
    if (requested === null) return;
    const name = requested.normalize('NFKC').trim();
    if (workflowFileOpenMode(name, 'file', false) !== 'notes') {
      setError('Salvar Como aceita somente txt, md, json ou log. Scripts e executáveis continuam bloqueados.');
      return;
    }
    const bytes = new TextEncoder().encode(externalFile.content).byteLength;
    if (bytes > MAX_NOTE_BYTES) { setError('Arquivo excede o limite de 2 MiB do editor rápido.'); return; }
    setBusy(true); setError(''); setNotice('');
    try {
      const entries = await fileSourceFacade.list(externalFile.provider, externalFile.path, false);
      if (entries.some(entry => entry.name.toLocaleLowerCase('pt-BR') === name.toLocaleLowerCase('pt-BR'))) throw new Error(`“${name}” já existe. Salvar Como não sobrescreve arquivos.`);
      await fileSourceFacade.writeText(externalFile.provider, externalFile.path, name, externalFile.content, externalFile.mode);
      setExternalFile(current => current ? { ...current, name, savedContent: current.content } : current);
      setNoteSaving('saved');
      setNotice(`Nova cópia salva como “${name}”.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao salvar nova cópia.'); }
    finally { setBusy(false); }
  }, [externalFile]);

  const closeExternal = useCallback(() => {
    if (!externalFile) return;
    if (externalDirty && !window.confirm(`Fechar “${externalFile.name}” e descartar alterações não salvas?`)) return;
    setExternalFile(null);
    setNoteSaving('idle');
    setNoteSearch('');
  }, [externalDirty, externalFile]);

  // Workspace Notes retain bounded autosave. External real files are deliberately excluded:
  // they require explicit Save/Save As so a quick editor never silently changes a provider file.
  useEffect(() => {
    if (externalFile) return;
    const dirty = Boolean(active && activeNoteFile && noteContent !== savedNoteContent.current);
    if (!dirty) return;
    const timer = window.setTimeout(() => { void saveActiveNote(); }, 650);
    return () => window.clearTimeout(timer);
  }, [active?.id, activeNoteFile, externalFile, noteContent, saveActiveNote]);

  const addNote = useCallback(async () => {
    if (!active || busy || active.status === 'archived') return;
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const note = await createWorkspaceNote(active);
      noteLoadGenerationRef.current += 1;
      const meta = noteMetadata(note);
      setNotes(current => [meta, ...current.filter(item => item.fileName !== meta.fileName)]);
      setExternalFile(null);
      setActiveNoteFile(note.fileName);
      setNoteContent(note.content);
      savedNoteContent.current = note.content;
      setNoteSaving('idle');
      setTab('notes');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao criar nota.');
    } finally { setBusy(false); }
  }, [active, busy, persistDirtyWorkspaceNote]);

  const jumpToHit = useCallback(async (index: number) => {
    if (!noteHits.length || !active) return;
    const normalized = (index + noteHits.length) % noteHits.length;
    const hit = noteHits[normalized];
    const note = notes.find(item => item.fileName === hit.fileName);
    if (!note) return;
    if (note.fileName !== activeNoteFile) {
      if (!(await persistDirtyWorkspaceNote())) return;
      const generation = ++noteLoadGenerationRef.current;
      try {
        const loaded = await loadWorkspaceNote(active, note);
        if (generation !== noteLoadGenerationRef.current) return;
        setExternalFile(null);
        setActiveNoteFile(loaded.fileName);
        setNoteContent(loaded.content);
        savedNoteContent.current = loaded.content;
        setNoteSaving('idle');
      } catch (cause) {
        if (generation === noteLoadGenerationRef.current) setError(cause instanceof Error ? cause.message : 'Falha ao carregar resultado da pesquisa.');
        return;
      }
    }
    setNoteHitIndex(normalized);
    setPreviewMarkdown(false);
    window.requestAnimationFrame(() => {
      noteEditorRef.current?.focus();
      noteEditorRef.current?.setSelectionRange(hit.start, hit.end);
    });
  }, [active, activeNoteFile, noteHits, notes, persistDirtyWorkspaceNote]);

  const jumpExternalHit = useCallback((index: number) => {
    if (!externalHits.length) return;
    const normalized = (index + externalHits.length) % externalHits.length;
    const hit = externalHits[normalized];
    setExternalHitIndex(normalized);
    window.requestAnimationFrame(() => {
      noteEditorRef.current?.focus();
      noteEditorRef.current?.setSelectionRange(hit.start, hit.end);
    });
  }, [externalHits]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (tab !== 'notes') return;
      const key = event.key.toLowerCase();
      if (event.ctrlKey && event.shiftKey && key === 's' && externalFile) { event.preventDefault(); void saveExternalAs(); }
      else if (event.ctrlKey && key === 's') { event.preventDefault(); void saveActiveNote(); }
      else if (event.ctrlKey && key === 'n' && active && !externalFile) { event.preventDefault(); void addNote(); }
      else if (event.ctrlKey && key === 'f') { event.preventDefault(); noteSearchRef.current?.focus(); }
      else if (event.key === 'F3' && noteSearch.trim()) {
        event.preventDefault();
        if (externalFile) jumpExternalHit(externalHitIndex + (event.shiftKey ? -1 : 1));
        else void jumpToHit(noteHitIndex + (event.shiftKey ? -1 : 1));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, addNote, externalFile, externalHitIndex, jumpExternalHit, jumpToHit, noteHitIndex, noteSearch, saveActiveNote, saveExternalAs, tab]);

  const submitWorkspace = useCallback(async () => {
    if (!newName.trim()) { setError('Informe o nome do workspace.'); return; }
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      if (newProvider === 'windows') await fileSourceFacade.mountWindows();
      const workspace = await createWorkspace({ type: newType, name: newName, description: newDescription, client: newClient, tags: newTags.split(','), provider: newProvider, originPath: [] });
      setShowCreate(false);
      setNewName(''); setNewDescription(''); setNewClient(''); setNewTags('');
      refreshWorkspaces();
      setActiveId(workspace.id);
      setTransferProvider(workspace.provider);
      setTab('overview');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao criar workspace.');
    } finally { setBusy(false); }
  }, [newClient, newDescription, newName, newProvider, newTags, newType, persistDirtyWorkspaceNote, refreshWorkspaces]);

  const beginEdit = useCallback(() => {
    if (!active) return;
    setEditType(active.type);
    setEditName(active.name);
    setEditDescription(active.description);
    setEditClient(active.client);
    setEditTags(active.tags.join(', '));
    setShowEdit(true);
  }, [active]);

  const saveEdit = useCallback(async () => {
    if (!active || !editName.trim()) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const updated = await updateWorkspaceMetadata(active.id, { type: editType, name: editName, description: editDescription, client: editClient, tags: editTags.split(',') });
      setShowEdit(false);
      refreshWorkspaces();
      setActiveId(updated.id);
      setNotice('Workspace atualizado. A pasta física não foi recriada.');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao atualizar workspace.'); }
    finally { setBusy(false); }
  }, [active, editClient, editDescription, editName, editTags, editType, refreshWorkspaces]);

  const toggleArchive = useCallback(async () => {
    if (!active) return;
    const archiving = active.status !== 'archived';
    if (archiving && !window.confirm(`Arquivar “${active.name}”? Os arquivos não serão apagados.`)) return;
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      await archiveWorkspace(active.id, archiving);
      refreshWorkspaces();
      if (archiving) setShowArchived(true);
      setNotice(archiving ? 'Workspace arquivado sem apagar arquivos.' : 'Workspace reativado.');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao alterar status do workspace.'); }
    finally { setBusy(false); }
  }, [active, persistDirtyWorkspaceNote, refreshWorkspaces]);

  const duplicateActive = useCallback(async () => {
    if (!active || !window.confirm(`Duplicar “${active.name}” na mesma origem? Links simbólicos e itens acima dos limites serão rejeitados.`)) return;
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const duplicate = await duplicateWorkspace(active.id);
      refreshWorkspaces();
      setActiveId(duplicate.id);
      setTransferProvider(duplicate.provider);
      setTab('overview');
      setNotice('Workspace duplicado na mesma origem.');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao duplicar workspace.'); }
    finally { setBusy(false); }
  }, [active, persistDirtyWorkspaceNote, refreshWorkspaces]);

  const prepareProvider = useCallback(async (provider: WorkflowProvider) => {
    if (provider === 'windows') {
      const runtime = await fileSourceFacade.runtime('windows');
      if (!runtime.mounted) await fileSourceFacade.mountWindows();
    }
  }, []);

  const exportActive = useCallback(async () => {
    if (!active) return;
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const result = await downloadWorkspaceZip(active);
      setNotice(`Workspace ZIP exportado: ${result.entries} entrada(s), ${result.bytes} bytes · Notes + Evidence + Metadata.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao exportar Workspace.'); }
    finally { setBusy(false); }
  }, [active, persistDirtyWorkspaceNote]);

  const importWorkspace = useCallback(async (file: File) => {
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      await prepareProvider(transferProvider);
      const imported = await importWorkspaceFile(file, transferProvider);
      refreshWorkspaces();
      setActiveId(imported.id);
      setTab('overview');
      setNotice(`Workspace importado para ${providerLabel(imported.provider)}. Nenhum Workspace existente foi sobrescrito.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao importar Workspace.'); }
    finally {
      setBusy(false);
      if (workspaceImportRef.current) workspaceImportRef.current.value = '';
    }
  }, [persistDirtyWorkspaceNote, prepareProvider, refreshWorkspaces, transferProvider]);

  const moveActive = useCallback(async () => {
    if (!active || active.provider === transferProvider) return;
    if (!window.confirm(`Mover “${active.name}” para ${providerLabel(transferProvider)}? O CloudOS criará e verificará a nova cópia e depois arquivará a origem antiga; a origem não será apagada.`)) return;
    if (!(await persistDirtyWorkspaceNote())) return;
    setBusy(true); setError(''); setNotice('');
    try {
      await prepareProvider(transferProvider);
      const result = await moveWorkspaceSafely(active, transferProvider);
      refreshWorkspaces();
      setActiveId(result.workspace.id);
      setTab('overview');
      setNotice('Workspace movido com preservação: nova cópia ativa; origem antiga arquivada, não apagada.');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao mover Workspace.'); }
    finally { setBusy(false); }
  }, [active, persistDirtyWorkspaceNote, prepareProvider, refreshWorkspaces, transferProvider]);

  const addEvidenceText = useCallback(async () => {
    if (!active || !evidenceText.trim() || active.status === 'archived') return;
    setBusy(true); setError(''); setNotice('');
    try {
      await saveWorkspaceEvidenceText(active, evidenceKind, evidenceText);
      setEvidenceText('');
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao salvar evidência.'); }
    finally { setBusy(false); }
  }, [active, evidenceKind, evidenceText]);

  const addEvidenceFiles = useCallback(async (files: FileList | File[]) => {
    if (!active || files.length === 0 || active.status === 'archived') return;
    setBusy(true); setError(''); setNotice('');
    try {
      for (const file of Array.from(files)) await saveWorkspaceEvidenceFile(active, file);
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao anexar evidência.'); }
    finally { setBusy(false); if (evidenceInputRef.current) evidenceInputRef.current.value = ''; }
  }, [active]);

  const pasteScreenshot = useCallback(async () => {
    if (!active || active.status === 'archived') return;
    setBusy(true); setError(''); setNotice('');
    try {
      if (!navigator.clipboard?.read) throw new Error('Leitura de imagem do clipboard não está disponível nesta sessão.');
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const imageType = item.types.find(type => type.startsWith('image/'));
        if (!imageType) continue;
        const blob = await item.getType(imageType);
        const ext = imageType.split('/')[1]?.replace('jpeg', 'jpg') || 'png';
        const file = new File([blob], `captura-${new Date().toISOString().replace(/[:.]/g, '-')}.${ext}`, { type: imageType });
        await saveWorkspaceEvidenceFile(active, file);
        setEvidence(await listWorkspaceEvidence(active));
        return;
      }
      throw new Error('Nenhuma imagem encontrada no clipboard.');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao colar captura.'); }
    finally { setBusy(false); }
  }, [active]);

  const chooseDownloadDestination = useCallback((kind: 'workspace' | 'opfs' | 'windows' | 'wsl') => {
    try {
      const destination = kind === 'workspace'
        ? active && active.status !== 'archived' ? { kind: 'workspace' as const, workspaceId: active.id } : null
        : { kind } as const;
      if (!destination) throw new Error('Ative um workspace primeiro.');
      setDownloadDestination(destination);
      setDownloadDestinationState(destination);
      setNotice(`Destino de workflow: ${downloadDestinationLabel(destination)}.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Destino inválido.'); }
  }, [active]);

  const clipboardAction = useCallback(async (entry: ClipboardMetadata, action: 'copy' | 'paste') => {
    try {
      if (action === 'copy') await copyClipboardEntryToSystem(entry);
      else await pasteClipboardEntry(entry);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha no clipboard.'); }
  }, []);

  const renderExternalEditor = () => {
    if (!externalFile) return null;
    const hit = externalHits.length ? externalHits[Math.min(externalHitIndex, externalHits.length - 1)] : null;
    return <div className="workflow-notes ww-notes ww-notes--external">
      <section className="ww-note-editor ww-quick-editor">
        <div className="ww-note-head ww-editor-toolbar">
          <div><strong>{externalFile.name}</strong><span>{providerLabel(externalFile.provider)} · {externalDirty ? 'Arquivo modificado' : noteSaving === 'saving' ? 'Salvando…' : 'Salvo'}</span></div>
          <div className="ww-editor-actions"><button disabled={!externalDirty || busy} onClick={() => void saveActiveNote()}>Salvar</button><button disabled={busy} onClick={() => void saveExternalAs()}>Salvar como</button><button onClick={closeExternal}>Fechar</button></div>
        </div>
        <div className="ww-editor-search"><input ref={noteSearchRef} value={noteSearch} onChange={event => setNoteSearch(event.target.value)} placeholder="Pesquisar neste arquivo…" /><span>{noteSearch ? `${externalHits.length}${externalHits.length >= MAX_VISIBLE_SEARCH_HITS ? '+' : ''} resultado(s)` : 'Ctrl+F pesquisar'}</span><button disabled={!externalHits.length} onClick={() => jumpExternalHit(externalHitIndex - 1)}>↑ Anterior</button><button disabled={!externalHits.length} onClick={() => jumpExternalHit(externalHitIndex + 1)}>↓ Próximo</button></div>
        {hit && <button className="ww-current-hit" onClick={() => jumpExternalHit(externalHitIndex)}><HighlightedText value={hit.snippet} query={noteSearch} /></button>}
        <textarea ref={noteEditorRef} value={externalFile.content} onChange={event => { setExternalFile(current => current ? { ...current, content: event.target.value } : current); setNoteSaving('idle'); }} spellCheck={false} aria-label="Arquivo de texto no Notes" />
        <div className="ww-note-limit">Editor rápido: txt, md, json e log · máximo 2 MiB · Ctrl+S salva · Ctrl+Shift+S salva como · F3/Shift+F3 salta resultados. Arquivos reais não usam autosave; scripts, executáveis e symlinks não são abertos.</div>
      </section>
    </div>;
  };

  const renderNotes = () => {
    if (externalFile) return renderExternalEditor();
    if (!active) return <div className="ww-empty-small">Abra um Workspace ou um arquivo de texto compatível.</div>;
    return <div className="workflow-notes ww-notes">
      <aside>
        <div className="ww-note-tools"><input ref={noteSearchRef} value={noteSearch} onChange={event => setNoteSearch(event.target.value)} placeholder="Pesquisar título e conteúdo…" /><button disabled={active.status === 'archived'} onClick={() => void addNote()}>＋</button></div>
        <div className="ww-search-status"><span>{noteSearch ? noteSearchBusy ? 'Pesquisando conteúdo sob demanda…' : `${filteredNotes.length} nota(s) · ${noteHits.length}${noteHits.length >= MAX_VISIBLE_SEARCH_HITS ? '+' : ''} ocorrência(s)` : 'Metadata carregada · conteúdo somente da nota ativa'}</span><div><button disabled={!noteHits.length} onClick={() => void jumpToHit(noteHitIndex - 1)}>↑</button><button disabled={!noteHits.length} onClick={() => void jumpToHit(noteHitIndex + 1)}>↓</button></div></div>
        <div className="ww-search-limit">Pesquisa de conteúdo lê uma nota por vez e descarta o documento após extrair os resultados. Saltos limitados a {MAX_VISIBLE_SEARCH_HITS} ocorrências por busca; índice global continua limitado a {MAX_NOTE_INDEX_CONTENT_CHARS} caracteres por nota.</div>
        {filteredNotes.map(note => {
          const first = noteSearch ? noteHits.find(hit => hit.fileName === note.fileName) : null;
          return <button key={note.fileName} className={note.fileName === activeNoteFile ? 'active' : ''} onClick={() => void selectNote(note)}><strong><HighlightedText value={note.title} query={noteSearch} /></strong><small>{new Date(note.modified).toLocaleString()} · {note.size} bytes</small>{noteSearch && first && <em><HighlightedText value={first.snippet} query={noteSearch} /></em>}</button>;
        })}
      </aside>
      <section className="ww-note-editor">{activeNote ? <><div className="ww-note-head"><strong>{activeNote.title}.md</strong><span>{noteSaving === 'saving' ? 'Salvando…' : noteSaving === 'saved' ? 'Salvo' : noteSaving === 'error' ? 'Falha ao salvar' : noteContent !== savedNoteContent.current ? 'Modificado · autosave da nota' : 'Salvo'}</span><button onClick={() => setPreviewMarkdown(value => !value)}>{previewMarkdown ? 'Editar' : 'Preview'}</button></div>{previewMarkdown ? <MarkdownPreview value={noteContent} /> : <textarea ref={noteEditorRef} disabled={active.status === 'archived'} value={noteContent} onChange={event => setNoteContent(event.target.value)} spellCheck={false} aria-label="Nota Markdown" />}</> : <div className="ww-empty-small">Crie uma nota Markdown. Ctrl+N cria, Ctrl+S salva e Ctrl+F pesquisa.</div>}</section>
    </div>;
  };

  return <div className="workflow-workspace" data-workspace-id={active?.id || ''} data-workspace-status={active?.status || ''}>
    <aside className="ww-sidebar">
      <div className="ww-sidebar-head"><strong>Workspaces</strong><button onClick={() => setShowCreate(true)}>＋</button></div>
      <div className="ww-workspace-filter"><input value={workspaceSearch} onChange={event => setWorkspaceSearch(event.target.value)} placeholder="Pesquisar workspace…" /><label><input type="checkbox" checked={showArchived} onChange={event => setShowArchived(event.target.checked)} /> Arquivados</label></div>
      <div className="ww-workspace-list">
        {visibleWorkspaces.map(workspace => <button key={workspace.id} className={`${workspace.id === activeId ? 'active' : ''} ${workspace.status === 'archived' ? 'archived' : ''}`} onClick={() => void selectWorkspace(workspace)}>
          <span>{workspace.name}{workspace.status === 'archived' ? ' · Arquivado' : ''}</span><small>{WORKSPACE_TYPES.find(item => item.id === workspace.type)?.label} · {workspaceOriginLabel(workspace)}</small>{workspace.client && <small>Cliente: {workspace.client}</small>}
        </button>)}
        {!visibleWorkspaces.length && <p className="ww-empty-small">Nenhum workspace encontrado.</p>}
      </div>
      <button className="ww-new" onClick={() => setShowCreate(true)}>＋ Novo workspace</button>
    </aside>

    <section className="ww-main">
      {error && <div className="ww-error" role="alert"><span>{error}</span><button onClick={() => setError('')}>×</button></div>}
      {notice && <div className="ww-notice" role="status"><span>{notice}</span><button onClick={() => setNotice('')}>×</button></div>}
      {!active && !externalFile ? <div className="ww-empty"><h2>Workspace</h2><p>Crie um workspace para concentrar Notes, Downloads, Evidence, Reports, Files, Terminal e Browser.</p><button onClick={() => setShowCreate(true)}>Criar workspace</button></div> : <>
        <header className="ww-header">
          <div>{active ? <><small>{WORKSPACE_TYPES.find(item => item.id === active.type)?.label} · {active.status === 'archived' ? 'Arquivado' : 'Ativo'}</small><h2>{active.name}</h2><p>{active.description || 'Sem descrição.'}</p></> : <><small>Notes · editor rápido</small><h2>{externalFile?.name}</h2><p>Arquivo aberto diretamente do Files.</p></>}</div>
          {active && <div className="ww-quick-actions">
            <button onClick={beginEdit}>Renomear / editar</button>
            <button disabled={busy} onClick={() => void duplicateActive()}>Duplicar</button>
            <button disabled={busy} onClick={() => void toggleArchive()}>{active.status === 'archived' ? 'Reativar' : 'Arquivar'}</button>
            <button disabled={busy} onClick={() => void exportActive()}>Exportar</button>
            <select aria-label="Origem alvo para mover ou importar Workspace" value={transferProvider} onChange={event => setTransferProvider(event.target.value as WorkflowProvider)}><option value="opfs">OPFS</option><option value="windows">Windows</option><option value="wsl">Linux</option></select>
            <button disabled={busy || active.provider === transferProvider} title={active.provider === transferProvider ? 'Escolha outra origem.' : 'Copia para a nova origem e arquiva a antiga; não apaga a origem.'} onClick={() => void moveActive()}>Mover</button>
            <button disabled={busy} onClick={() => workspaceImportRef.current?.click()}>Importar</button>
            <input ref={workspaceImportRef} hidden type="file" accept="application/json,.json" onChange={event => event.target.files?.[0] && void importWorkspace(event.target.files[0])} />
            <button onClick={() => openWorkspaceFiles(active, 'Files')}>Files</button>
            <button onClick={() => openFilesAt(active.provider, [...active.root, 'Reports'])}>Reports</button>
            <button disabled={!terminalHereCapability(active.provider).supported} title={terminalHereCapability(active.provider).reason} onClick={() => { try { openWorkspaceTerminal(active); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Terminal aqui indisponível.'); } }}>Terminal</button>
            <button onClick={() => openExistingBrowser()}>Browser</button>
          </div>}
        </header>

        <div className="ww-permanent-destination"><small>Downloads do workflow</small><strong>{downloadDestinationLabel(downloadDestination)}</strong><span>O Browser nativo congelado não é redirecionado fisicamente por esta preferência.</span></div>

        <nav className="ww-tabs" aria-label="Workspace">
          {(['overview', 'notes', 'evidence', 'downloads', 'clipboard'] as WorkspaceTab[]).map(name => <button key={name} disabled={!active && name !== 'notes'} className={tab === name ? 'active' : ''} onClick={() => setTab(name)}>{name === 'overview' ? 'Visão geral' : name === 'notes' ? 'Notes' : name === 'evidence' ? 'Evidence' : name === 'downloads' ? 'Downloads' : 'Clipboard'}</button>)}
        </nav>

        <div className="ww-body">
          {tab === 'overview' && active && <div className="ww-overview">
            <section><h3>Estrutura</h3><div className="ww-folder-grid">{WORKSPACE_FOLDERS.map(folder => <button key={folder} onClick={() => openFilesAt(active.provider, [...active.root, folder])}>📁 {folder}</button>)}</div></section>
            <section className="ww-meta"><h3>workspace.json</h3><dl><dt>Nome</dt><dd>{active.name}</dd><dt>Cliente</dt><dd>{active.client || '—'}</dd><dt>Tipo</dt><dd>{WORKSPACE_TYPES.find(item => item.id === active.type)?.label}</dd><dt>Status</dt><dd>{active.status}</dd><dt>Tags</dt><dd>{active.tags.length ? active.tags.join(', ') : '—'}</dd><dt>Descrição</dt><dd>{active.description || '—'}</dd><dt>Data</dt><dd>{new Date(active.createdAt).toLocaleString()}</dd><dt>Último acesso</dt><dd>{new Date(active.lastAccessAt).toLocaleString()}</dd><dt>Última atividade</dt><dd>{new Date(active.lastActivityAt).toLocaleString()}</dd><dt>Origem</dt><dd>{workspaceOriginLabel(active)}</dd><dt>Pasta física</dt><dd>{active.root.join('/')}</dd></dl><p className="ww-note-limit">Renomear altera metadados sem mover a raiz física. Mover entre origens usa cópia validada + arquivamento da origem; não promete operação atômica e não apaga a origem antiga.</p><p className="ww-note-limit">Export/Import portátil: até {transferLimits.entries} itens, {Math.round(transferLimits.bytes / 1024 / 1024)} MiB agregados e {Math.round(transferLimits.fileBytes / 1024 / 1024)} MiB por arquivo. Symlinks são rejeitados.</p></section>
          </div>}

          {tab === 'notes' && renderNotes()}

          {tab === 'evidence' && active && <div className="ww-evidence">
            <div className="ww-evidence-compose"><select value={evidenceKind} onChange={event => setEvidenceKind(event.target.value as EvidenceKind)}><option value="note">Nota</option><option value="log">Log</option><option value="link">Link</option></select><textarea disabled={active.status === 'archived'} value={evidenceText} onChange={event => setEvidenceText(event.target.value)} placeholder={evidenceKind === 'link' ? 'https://…' : 'Conteúdo da evidência'} /><div><button disabled={active.status === 'archived'} onClick={() => void addEvidenceText()}>Salvar</button><button disabled={active.status === 'archived'} onClick={() => evidenceInputRef.current?.click()}>Anexar arquivo</button><button disabled={active.status === 'archived'} onClick={() => void pasteScreenshot()}>Colar captura</button><input ref={evidenceInputRef} hidden type="file" multiple onChange={event => event.target.files && void addEvidenceFiles(event.target.files)} /></div></div>
            <div className="ww-evidence-list">{evidence.map(entry => <div key={entry.name}><span>{entry.kind === 'directory' ? '📁' : '📎'}</span><strong>{entry.name}</strong><small>{entry.kind === 'file' ? `${entry.size} bytes` : 'Pasta'}</small></div>)}{!evidence.length && <p>Nenhuma evidência neste workspace.</p>}</div>
          </div>}

          {tab === 'downloads' && active && <div className="ww-downloads"><h3>Destino de downloads</h3><div className="ww-current-destination"><small>Destino atual</small><strong>{downloadDestinationLabel(downloadDestination)}</strong></div><p>Por padrão, quando não existe preferência salva, o destino é o Workspace ativo. A escolha abaixo é explícita, persistida no workflow e exibida permanentemente acima das abas.</p><div className="ww-destination-grid"><button className={downloadDestination.kind === 'workspace' ? 'active' : ''} onClick={() => chooseDownloadDestination('workspace')}>Workspace atual</button><button className={downloadDestination.kind === 'opfs' ? 'active' : ''} onClick={() => chooseDownloadDestination('opfs')}>OPFS</button><button className={downloadDestination.kind === 'windows' ? 'active' : ''} onClick={() => chooseDownloadDestination('windows')}>Windows grant</button><button className={downloadDestination.kind === 'wsl' ? 'active' : ''} onClick={() => chooseDownloadDestination('wsl')}>Linux Home</button></div><div className="ww-limitation"><strong>Limite do Release Freeze:</strong> o Browser nativo está congelado. Esta preferência organiza o destino do workflow, mas não intercepta nem redireciona fisicamente downloads do processo nativo.</div></div>}

          {tab === 'clipboard' && active && <div className="ww-clipboard"><div className="ww-clipboard-head"><span>{clipboardEntries.length}/30 entradas</span><button onClick={() => void clearClipboardHistory()}>Limpar</button></div>{clipboardEntries.map(entry => <div key={entry.id} className="ww-clipboard-entry"><button className={entry.favorite ? 'favorite active' : 'favorite'} onClick={() => { toggleClipboardFavorite(entry.id); setClipboardEntries(listClipboardEntries()); }}>★</button><div><strong>{entry.source}</strong><p>{entry.preview}</p><small>{entry.bytes} bytes · {new Date(entry.createdAt).toLocaleString()}</small></div><button onClick={() => void clipboardAction(entry, 'copy')}>Copiar</button><button onClick={() => void clipboardAction(entry, 'paste')}>Colar</button></div>)}{!clipboardEntries.length && <p>O histórico ignora senhas, JWT e padrões de secrets.</p>}</div>}
        </div>
      </>}
    </section>

    {showCreate && <div className="ww-modal" role="dialog" aria-modal="true"><section><h2>Novo workspace</h2><label>Tipo<select value={newType} onChange={event => setNewType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label><label>Nome<input autoFocus value={newName} onChange={event => setNewName(event.target.value)} /></label><label>Cliente<input value={newClient} onChange={event => setNewClient(event.target.value)} /></label><label>Tags<input value={newTags} onChange={event => setNewTags(event.target.value)} placeholder="produção, ticket-42" /></label><label>Descrição<textarea value={newDescription} onChange={event => setNewDescription(event.target.value)} /></label><label>Origem<select value={newProvider} onChange={event => setNewProvider(event.target.value as WorkflowProvider)}><option value="opfs">OPFS · CloudOS</option><option value="windows">Windows · pasta autorizada</option><option value="wsl">Linux · Home</option></select></label><p>{newProvider === 'windows' ? 'Ao confirmar, o seletor de pasta do Windows será aberto antes da criação.' : 'Nenhum banco real é usado.'}</p><footer><button onClick={() => setShowCreate(false)}>Cancelar</button><button disabled={busy} onClick={() => void submitWorkspace()}>{busy ? 'Criando…' : 'Criar workspace'}</button></footer></section></div>}

    {showEdit && active && <div className="ww-modal" role="dialog" aria-modal="true"><section><h2>Editar workspace</h2><label>Tipo<select value={editType} onChange={event => setEditType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label><label>Nome<input autoFocus value={editName} onChange={event => setEditName(event.target.value)} /></label><label>Cliente<input value={editClient} onChange={event => setEditClient(event.target.value)} /></label><label>Tags<input value={editTags} onChange={event => setEditTags(event.target.value)} /></label><label>Descrição<textarea value={editDescription} onChange={event => setEditDescription(event.target.value)} /></label><p>Renomear não move nem recria a pasta física do Workspace.</p><footer><button onClick={() => setShowEdit(false)}>Cancelar</button><button disabled={busy} onClick={() => void saveEdit()}>{busy ? 'Salvando…' : 'Salvar'}</button></footer></section></div>}
  </div>;
}
