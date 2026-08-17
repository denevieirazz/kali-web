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
  saveWorkspaceEvidenceFile,
  saveWorkspaceEvidenceText,
  saveWorkspaceNote,
  setDownloadDestination,
  updateWorkspaceMetadata,
  type WorkflowNote,
  type WorkspaceRecord,
} from '../../services/workflowWorkspace';
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

type WorkspaceTab = 'overview' | 'notes' | 'evidence' | 'downloads' | 'clipboard';
type EvidenceKind = 'note' | 'log' | 'link';
type ExternalTextTarget = { provider: WorkflowProvider; path: string[]; name: string };
type ExternalTextState = ExternalTextTarget & { content: string; savedContent: string; mode?: number };
type WindowParams = { workspaceId?: string; noteFileName?: string; externalTextFile?: ExternalTextTarget };

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

function validExternalTarget(value: unknown): value is ExternalTextTarget {
  if (!value || typeof value !== 'object') return false;
  const target = value as ExternalTextTarget;
  return ['opfs', 'windows', 'wsl'].includes(target.provider)
    && Array.isArray(target.path)
    && target.path.every(part => typeof part === 'string' && Boolean(part))
    && typeof target.name === 'string'
    && workflowFileOpenMode(target.name, 'file', false) === 'notes';
}

export default function WorkflowWorkspace({ windowId }: { windowId: string }) {
  const params = useWindowManager(state => state.getWindow(windowId)?.params as WindowParams | undefined);
  const [workspaces, setWorkspaces] = useState<WorkspaceRecord[]>(listWorkspaces);
  const [activeId, setActiveId] = useState(() => params?.workspaceId || getActiveWorkspace()?.id || '');
  const [workspaceSearch, setWorkspaceSearch] = useState('');
  const [showArchived, setShowArchived] = useState(false);
  const [tab, setTab] = useState<WorkspaceTab>(params?.noteFileName || params?.externalTextFile ? 'notes' : 'overview');
  const [error, setError] = useState('');
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

  const [notes, setNotes] = useState<WorkflowNote[]>([]);
  const [activeNoteFile, setActiveNoteFile] = useState(params?.noteFileName || '');
  const [noteContent, setNoteContent] = useState('');
  const [noteSearch, setNoteSearch] = useState('');
  const [noteSaving, setNoteSaving] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [previewMarkdown, setPreviewMarkdown] = useState(false);
  const [externalFile, setExternalFile] = useState<ExternalTextState | null>(null);
  const savedNoteContent = useRef('');
  const noteSearchRef = useRef<HTMLInputElement>(null);

  const [evidence, setEvidence] = useState<any[]>([]);
  const [evidenceKind, setEvidenceKind] = useState<EvidenceKind>('note');
  const [evidenceText, setEvidenceText] = useState('');
  const evidenceInputRef = useRef<HTMLInputElement>(null);

  const [clipboardEntries, setClipboardEntries] = useState<ClipboardMetadata[]>(listClipboardEntries);
  const [downloadDestination, setDownloadDestinationState] = useState(getDownloadDestination);

  const active = useMemo(() => workspaces.find(item => item.id === activeId) || null, [activeId, workspaces]);
  const activeNote = useMemo(() => notes.find(note => note.fileName === activeNoteFile) || null, [activeNoteFile, notes]);
  const visibleWorkspaces = useMemo(() => workspaces.filter(workspace => (showArchived || workspace.status !== 'archived') && matchesWorkflowQuery(workspaceSearchText(workspace), workspaceSearch)), [showArchived, workspaceSearch, workspaces]);
  const filteredNotes = useMemo(() => notes.filter(note => matchesWorkflowQuery(`${note.title}\n${note.content}`, noteSearch)), [noteSearch, notes]);

  const refreshWorkspaces = useCallback(() => {
    const next = listWorkspaces();
    setWorkspaces(next);
    setActiveId(current => next.some(item => item.id === current) ? current : (getActiveWorkspace()?.id || next.find(item => item.status !== 'archived')?.id || next[0]?.id || ''));
  }, []);

  useEffect(() => {
    const changed = () => refreshWorkspaces();
    window.addEventListener('cloudos:workflow-changed', changed);
    return () => window.removeEventListener('cloudos:workflow-changed', changed);
  }, [refreshWorkspaces]);

  useEffect(() => {
    const changed = () => setClipboardEntries(listClipboardEntries());
    window.addEventListener('cloudos:clipboard-changed', changed);
    return () => window.removeEventListener('cloudos:clipboard-changed', changed);
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
    setBusy(true);
    setError('');
    void (async () => {
      try {
        const entries = await fileSourceFacade.list(raw.provider, raw.path, false);
        const entry = entries.find(item => item.name === raw.name);
        if (!entry || entry.kind !== 'file' || entry.symlink) throw new Error('Arquivo não encontrado ou não é um arquivo regular.');
        if (entry.size > MAX_NOTE_BYTES) throw new Error('Arquivo excede o limite de 2 MiB do Notes rápido.');
        const file = await fileSourceFacade.readFile(raw.provider, raw.path, entry, MAX_NOTE_BYTES);
        const content = await file.text();
        if (!cancelled) {
          setExternalFile({ ...raw, content, savedContent: content, mode: entry.mode });
          setTab('notes');
          setPreviewMarkdown(false);
        }
      } catch (cause) {
        if (!cancelled) setError(cause instanceof Error ? cause.message : 'Falha ao abrir o arquivo no Notes.');
      } finally {
        if (!cancelled) setBusy(false);
      }
    })();
    return () => { cancelled = true; };
  }, [params?.externalTextFile?.name, params?.externalTextFile?.provider, JSON.stringify(params?.externalTextFile?.path || [])]);

  const refreshWorkspaceContent = useCallback(async (workspace: WorkspaceRecord | null) => {
    if (!workspace) {
      setNotes([]);
      setEvidence([]);
      return;
    }
    setBusy(true);
    setError('');
    try {
      const [nextNotes, nextEvidence] = await Promise.all([
        listWorkspaceNotes(workspace),
        listWorkspaceEvidence(workspace),
      ]);
      setNotes(nextNotes);
      setEvidence(nextEvidence);
      const requested = params?.noteFileName;
      const chosen = (requested && nextNotes.find(note => note.fileName === requested)) || nextNotes.find(note => note.fileName === activeNoteFile) || nextNotes[0] || null;
      setActiveNoteFile(chosen?.fileName || '');
      setNoteContent(chosen?.content || '');
      savedNoteContent.current = chosen?.content || '';
      setNoteSaving('idle');
      setDownloadDestinationState(getDownloadDestination());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao abrir o workspace.');
    } finally {
      setBusy(false);
    }
  }, [activeNoteFile, params?.noteFileName]);

  useEffect(() => { void refreshWorkspaceContent(active); }, [active?.id]);

  const selectWorkspace = useCallback(async (workspace: WorkspaceRecord) => {
    setError('');
    setActiveId(workspace.id);
    if (workspace.status === 'archived') return;
    try { await activateWorkspace(workspace.id); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao ativar o workspace.'); }
  }, []);

  const selectNote = useCallback((note: WorkflowNote) => {
    setExternalFile(null);
    setActiveNoteFile(note.fileName);
    setNoteContent(note.content);
    savedNoteContent.current = note.content;
    setNoteSaving('idle');
  }, []);

  const saveActiveNote = useCallback(async () => {
    if (externalFile) {
      if (externalFile.content === externalFile.savedContent) return;
      const bytes = new TextEncoder().encode(externalFile.content).byteLength;
      if (bytes > MAX_NOTE_BYTES) { setError('Arquivo excede o limite de 2 MiB do Notes rápido.'); return; }
      setNoteSaving('saving');
      try {
        await fileSourceFacade.writeText(externalFile.provider, externalFile.path, externalFile.name, externalFile.content, externalFile.mode);
        setExternalFile(current => current ? { ...current, savedContent: current.content } : current);
        setNoteSaving('saved');
      } catch (cause) {
        setNoteSaving('error');
        setError(cause instanceof Error ? cause.message : 'Falha ao salvar o arquivo.');
      }
      return;
    }
    if (!active || !activeNoteFile || noteContent === savedNoteContent.current) return;
    setNoteSaving('saving');
    try {
      const saved = await saveWorkspaceNote(active, { fileName: activeNoteFile, content: noteContent });
      savedNoteContent.current = saved.content;
      setNotes(current => current.map(note => note.fileName === saved.fileName ? saved : note));
      setNoteSaving('saved');
    } catch (cause) {
      setNoteSaving('error');
      setError(cause instanceof Error ? cause.message : 'Falha ao salvar a nota.');
    }
  }, [active, activeNoteFile, externalFile, noteContent]);

  useEffect(() => {
    const dirty = externalFile ? externalFile.content !== externalFile.savedContent : Boolean(active && activeNoteFile && noteContent !== savedNoteContent.current);
    if (!dirty) return;
    const timer = window.setTimeout(() => { void saveActiveNote(); }, 650);
    return () => window.clearTimeout(timer);
  }, [active?.id, activeNoteFile, externalFile?.content, noteContent, saveActiveNote]);

  const addNote = useCallback(async () => {
    if (!active || busy || active.status === 'archived') return;
    setBusy(true);
    setError('');
    try {
      const note = await createWorkspaceNote(active);
      setNotes(current => [note, ...current]);
      selectNote(note);
      setTab('notes');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao criar nota.');
    } finally { setBusy(false); }
  }, [active, busy, selectNote]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (tab !== 'notes') return;
      if (event.ctrlKey && event.key.toLowerCase() === 's') { event.preventDefault(); void saveActiveNote(); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'n' && active && !externalFile) { event.preventDefault(); void addNote(); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'f' && active && !externalFile) { event.preventDefault(); noteSearchRef.current?.focus(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, addNote, externalFile, saveActiveNote, tab]);

  const submitWorkspace = useCallback(async () => {
    if (!newName.trim()) { setError('Informe o nome do workspace.'); return; }
    setBusy(true);
    setError('');
    try {
      if (newProvider === 'windows') await fileSourceFacade.mountWindows();
      const workspace = await createWorkspace({ type: newType, name: newName, description: newDescription, client: newClient, tags: newTags.split(','), provider: newProvider, originPath: [] });
      setShowCreate(false);
      setNewName(''); setNewDescription(''); setNewClient(''); setNewTags('');
      refreshWorkspaces();
      setActiveId(workspace.id);
      setTab('overview');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao criar workspace.');
    } finally { setBusy(false); }
  }, [newClient, newDescription, newName, newProvider, newTags, newType, refreshWorkspaces]);

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
    setBusy(true); setError('');
    try {
      const updated = await updateWorkspaceMetadata(active.id, { type: editType, name: editName, description: editDescription, client: editClient, tags: editTags.split(',') });
      setShowEdit(false);
      refreshWorkspaces();
      setActiveId(updated.id);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao atualizar workspace.'); }
    finally { setBusy(false); }
  }, [active, editClient, editDescription, editName, editTags, editType, refreshWorkspaces]);

  const toggleArchive = useCallback(async () => {
    if (!active) return;
    const archiving = active.status !== 'archived';
    if (archiving && !window.confirm(`Arquivar “${active.name}”? Os arquivos não serão apagados.`)) return;
    setBusy(true); setError('');
    try {
      await archiveWorkspace(active.id, archiving);
      refreshWorkspaces();
      if (archiving) setShowArchived(true);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao alterar status do workspace.'); }
    finally { setBusy(false); }
  }, [active, refreshWorkspaces]);

  const duplicateActive = useCallback(async () => {
    if (!active || !window.confirm(`Duplicar “${active.name}” na mesma origem? Links simbólicos e itens acima dos limites serão rejeitados.`)) return;
    setBusy(true); setError('');
    try {
      const duplicate = await duplicateWorkspace(active.id);
      refreshWorkspaces();
      setActiveId(duplicate.id);
      setTab('overview');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao duplicar workspace.'); }
    finally { setBusy(false); }
  }, [active, refreshWorkspaces]);

  const addEvidenceText = useCallback(async () => {
    if (!active || !evidenceText.trim() || active.status === 'archived') return;
    setBusy(true); setError('');
    try {
      await saveWorkspaceEvidenceText(active, evidenceKind, evidenceText);
      setEvidenceText('');
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao salvar evidência.'); }
    finally { setBusy(false); }
  }, [active, evidenceKind, evidenceText]);

  const addEvidenceFiles = useCallback(async (files: FileList | File[]) => {
    if (!active || files.length === 0 || active.status === 'archived') return;
    setBusy(true); setError('');
    try {
      for (const file of Array.from(files)) await saveWorkspaceEvidenceFile(active, file);
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao anexar evidência.'); }
    finally { setBusy(false); if (evidenceInputRef.current) evidenceInputRef.current.value = ''; }
  }, [active]);

  const pasteScreenshot = useCallback(async () => {
    if (!active || active.status === 'archived') return;
    setBusy(true); setError('');
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
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Destino inválido.'); }
  }, [active]);

  const clipboardAction = useCallback(async (entry: ClipboardMetadata, action: 'copy' | 'paste') => {
    try {
      if (action === 'copy') await copyClipboardEntryToSystem(entry);
      else await pasteClipboardEntry(entry);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha no clipboard.'); }
  }, []);

  const renderNotes = () => {
    if (externalFile) return <div className="workflow-notes ww-notes ww-notes--external">
      <section className="ww-note-editor">
        <div className="ww-note-head"><strong>{externalFile.name}</strong><span>{externalFile.provider.toUpperCase()} · arquivo externo · {noteSaving === 'saving' ? 'Salvando…' : noteSaving === 'saved' ? 'Salvo' : 'Autosave'}</span><button onClick={() => setExternalFile(null)}>Fechar arquivo</button></div>
        <textarea value={externalFile.content} onChange={event => setExternalFile(current => current ? { ...current, content: event.target.value } : current)} spellCheck={false} aria-label="Arquivo de texto no Notes" />
        <div className="ww-note-limit">Abertura segura: txt, md, json e log. Limite: 2 MiB. Scripts, executáveis e symlinks nunca são executados pelo Notes.</div>
      </section>
    </div>;
    if (!active) return <div className="ww-empty-small">Abra um Workspace ou um arquivo de texto compatível.</div>;
    return <div className="workflow-notes ww-notes">
      <aside><div className="ww-note-tools"><input ref={noteSearchRef} value={noteSearch} onChange={event => setNoteSearch(event.target.value)} placeholder="Pesquisar título e conteúdo…" /><button disabled={active.status === 'archived'} onClick={() => void addNote()}>＋</button></div><div className="ww-search-limit">Pesquisa instantânea no conteúdo carregado. Índice global: até {MAX_NOTE_INDEX_CONTENT_CHARS} caracteres por nota.</div>{filteredNotes.map(note => <button key={note.fileName} className={note.fileName === activeNoteFile ? 'active' : ''} onClick={() => selectNote(note)}><strong>{note.title}</strong><small>{new Date(note.modified).toLocaleString()}</small>{noteSearch && <em>{note.content.slice(0, 120).replace(/\s+/g, ' ')}</em>}</button>)}</aside>
      <section className="ww-note-editor">{activeNote ? <><div className="ww-note-head"><strong>{activeNote.title}.md</strong><span>{noteSaving === 'saving' ? 'Salvando…' : noteSaving === 'saved' ? 'Salvo' : noteSaving === 'error' ? 'Falha ao salvar' : 'Autosave'}</span><button onClick={() => setPreviewMarkdown(value => !value)}>{previewMarkdown ? 'Editar' : 'Preview'}</button></div>{previewMarkdown ? <MarkdownPreview value={noteContent} /> : <textarea disabled={active.status === 'archived'} value={noteContent} onChange={event => setNoteContent(event.target.value)} spellCheck={false} aria-label="Nota Markdown" />}</> : <div className="ww-empty-small">Crie uma nota Markdown. Ctrl+N cria, Ctrl+S salva e Ctrl+F pesquisa.</div>}</section>
    </div>;
  };

  return <div className="workflow-workspace">
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
      {!active && !externalFile ? <div className="ww-empty"><h2>Workspace</h2><p>Crie um workspace para concentrar Notes, Downloads, Evidence, Reports, Files, Terminal e Browser.</p><button onClick={() => setShowCreate(true)}>Criar workspace</button></div> : <>
        <header className="ww-header">
          <div>{active ? <><small>{WORKSPACE_TYPES.find(item => item.id === active.type)?.label} · {active.status === 'archived' ? 'Arquivado' : 'Ativo'}</small><h2>{active.name}</h2><p>{active.description || 'Sem descrição.'}</p></> : <><small>Notes</small><h2>{externalFile?.name}</h2><p>Arquivo aberto diretamente do Files.</p></>}</div>
          {active && <div className="ww-quick-actions">
            <button onClick={beginEdit}>Renomear / editar</button>
            <button disabled={busy} onClick={() => void duplicateActive()}>Duplicar</button>
            <button disabled={busy} onClick={() => void toggleArchive()}>{active.status === 'archived' ? 'Reativar' : 'Arquivar'}</button>
            <button onClick={() => openWorkspaceFiles(active, 'Files')}>Files</button>
            <button onClick={() => openFilesAt(active.provider, [...active.root, 'Reports'])}>Reports</button>
            <button disabled={!terminalHereCapability(active.provider).supported} title={terminalHereCapability(active.provider).reason} onClick={() => { try { openWorkspaceTerminal(active); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Terminal aqui indisponível.'); } }}>Terminal</button>
            <button onClick={() => openExistingBrowser()}>Browser</button>
          </div>}
        </header>

        <nav className="ww-tabs" aria-label="Workspace">
          {(['overview', 'notes', 'evidence', 'downloads', 'clipboard'] as WorkspaceTab[]).map(name => <button key={name} disabled={!active && name !== 'notes'} className={tab === name ? 'active' : ''} onClick={() => setTab(name)}>{name === 'overview' ? 'Visão geral' : name === 'notes' ? 'Notes' : name === 'evidence' ? 'Evidence' : name === 'downloads' ? 'Downloads' : 'Clipboard'}</button>)}
        </nav>

        <div className="ww-body">
          {tab === 'overview' && active && <div className="ww-overview">
            <section><h3>Estrutura</h3><div className="ww-folder-grid">{WORKSPACE_FOLDERS.map(folder => <button key={folder} onClick={() => openFilesAt(active.provider, [...active.root, folder])}>📁 {folder}</button>)}</div></section>
            <section className="ww-meta"><h3>workspace.json</h3><dl><dt>Nome</dt><dd>{active.name}</dd><dt>Cliente</dt><dd>{active.client || '—'}</dd><dt>Tipo</dt><dd>{WORKSPACE_TYPES.find(item => item.id === active.type)?.label}</dd><dt>Status</dt><dd>{active.status}</dd><dt>Tags</dt><dd>{active.tags.length ? active.tags.join(', ') : '—'}</dd><dt>Descrição</dt><dd>{active.description || '—'}</dd><dt>Data</dt><dd>{new Date(active.createdAt).toLocaleString()}</dd><dt>Último acesso</dt><dd>{new Date(active.lastAccessAt).toLocaleString()}</dd><dt>Última atividade</dt><dd>{new Date(active.lastActivityAt).toLocaleString()}</dd><dt>Origem</dt><dd>{workspaceOriginLabel(active)}</dd><dt>Pasta física</dt><dd>{active.root.join('/')}</dd></dl><p className="ww-note-limit">Renomear altera os metadados e o workspace.json; a raiz física permanece estável para não recriar nem mover a árvore.</p></section>
          </div>}

          {tab === 'notes' && renderNotes()}

          {tab === 'evidence' && active && <div className="ww-evidence">
            <div className="ww-evidence-compose"><select value={evidenceKind} onChange={event => setEvidenceKind(event.target.value as EvidenceKind)}><option value="note">Nota</option><option value="log">Log</option><option value="link">Link</option></select><textarea disabled={active.status === 'archived'} value={evidenceText} onChange={event => setEvidenceText(event.target.value)} placeholder={evidenceKind === 'link' ? 'https://…' : 'Conteúdo da evidência'} /><div><button disabled={active.status === 'archived'} onClick={() => void addEvidenceText()}>Salvar</button><button disabled={active.status === 'archived'} onClick={() => evidenceInputRef.current?.click()}>Anexar arquivo</button><button disabled={active.status === 'archived'} onClick={() => void pasteScreenshot()}>Colar captura</button><input ref={evidenceInputRef} hidden type="file" multiple onChange={event => event.target.files && void addEvidenceFiles(event.target.files)} /></div></div>
            <div className="ww-evidence-list">{evidence.map(entry => <div key={entry.name}><span>{entry.kind === 'directory' ? '📁' : '📎'}</span><strong>{entry.name}</strong><small>{entry.kind === 'file' ? `${entry.size} bytes` : 'Pasta'}</small></div>)}{!evidence.length && <p>Nenhuma evidência neste workspace.</p>}</div>
          </div>}

          {tab === 'downloads' && active && <div className="ww-downloads"><h3>Destino de downloads</h3><div className="ww-current-destination"><small>Destino atual</small><strong>{downloadDestinationLabel(downloadDestination)}</strong></div><p>Por padrão, quando não existe preferência salva, o destino é o Workspace ativo. A escolha abaixo é explícita e fica visível.</p><div className="ww-destination-grid"><button className={downloadDestination.kind === 'workspace' ? 'active' : ''} onClick={() => chooseDownloadDestination('workspace')}>Workspace atual</button><button className={downloadDestination.kind === 'opfs' ? 'active' : ''} onClick={() => chooseDownloadDestination('opfs')}>OPFS</button><button className={downloadDestination.kind === 'windows' ? 'active' : ''} onClick={() => chooseDownloadDestination('windows')}>Windows grant</button><button className={downloadDestination.kind === 'wsl' ? 'active' : ''} onClick={() => chooseDownloadDestination('wsl')}>Linux Home</button></div><div className="ww-limitation"><strong>Limite do Release Freeze:</strong> o Browser nativo está congelado. Esta preferência resolve a UX e o destino padrão no workflow, mas não intercepta nem redireciona downloads do processo nativo.</div></div>}

          {tab === 'clipboard' && active && <div className="ww-clipboard"><div className="ww-clipboard-head"><span>{clipboardEntries.length}/30 entradas</span><button onClick={() => void clearClipboardHistory()}>Limpar</button></div>{clipboardEntries.map(entry => <div key={entry.id} className="ww-clipboard-entry"><button className={entry.favorite ? 'favorite active' : 'favorite'} onClick={() => { toggleClipboardFavorite(entry.id); setClipboardEntries(listClipboardEntries()); }}>★</button><div><strong>{entry.source}</strong><p>{entry.preview}</p><small>{entry.bytes} bytes · {new Date(entry.createdAt).toLocaleString()}</small></div><button onClick={() => void clipboardAction(entry, 'copy')}>Copiar</button><button onClick={() => void clipboardAction(entry, 'paste')}>Colar</button></div>)}{!clipboardEntries.length && <p>O histórico ignora senhas, JWT e padrões de secrets.</p>}</div>}
        </div>
      </>}
    </section>

    {showCreate && <div className="ww-modal" role="dialog" aria-modal="true"><section><h2>Novo workspace</h2><label>Tipo<select value={newType} onChange={event => setNewType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label><label>Nome<input autoFocus value={newName} onChange={event => setNewName(event.target.value)} /></label><label>Cliente<input value={newClient} onChange={event => setNewClient(event.target.value)} /></label><label>Tags<input value={newTags} onChange={event => setNewTags(event.target.value)} placeholder="produção, ticket-42" /></label><label>Descrição<textarea value={newDescription} onChange={event => setNewDescription(event.target.value)} /></label><label>Origem<select value={newProvider} onChange={event => setNewProvider(event.target.value as WorkflowProvider)}><option value="opfs">OPFS · CloudOS</option><option value="windows">Windows · pasta autorizada</option><option value="wsl">Linux · Home</option></select></label><p>{newProvider === 'windows' ? 'Ao confirmar, o seletor de pasta do Windows será aberto antes da criação.' : 'Nenhum banco real é usado.'}</p><footer><button onClick={() => setShowCreate(false)}>Cancelar</button><button disabled={busy} onClick={() => void submitWorkspace()}>{busy ? 'Criando…' : 'Criar workspace'}</button></footer></section></div>}

    {showEdit && active && <div className="ww-modal" role="dialog" aria-modal="true"><section><h2>Editar workspace</h2><label>Tipo<select value={editType} onChange={event => setEditType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label><label>Nome<input autoFocus value={editName} onChange={event => setEditName(event.target.value)} /></label><label>Cliente<input value={editClient} onChange={event => setEditClient(event.target.value)} /></label><label>Tags<input value={editTags} onChange={event => setEditTags(event.target.value)} /></label><label>Descrição<textarea value={editDescription} onChange={event => setEditDescription(event.target.value)} /></label><p>Renomear não move nem recria a pasta física do Workspace.</p><footer><button onClick={() => setShowEdit(false)}>Cancelar</button><button disabled={busy} onClick={() => void saveEdit()}>{busy ? 'Salvando…' : 'Salvar'}</button></footer></section></div>}
  </div>;
}
