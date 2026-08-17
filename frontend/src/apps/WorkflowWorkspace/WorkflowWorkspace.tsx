import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { WORKSPACE_FOLDERS, WORKSPACE_TYPES, matchesWorkflowQuery, terminalHereCapability, type WorkspaceType, type WorkflowProvider } from '../../core/workflowCore.js';
import { useWindowManager } from '../../stores/windowManager';
import { fileSourceFacade } from '../CloudOSFiles/fileSourceFacade';
import {
  activateWorkspace,
  createWorkspace,
  createWorkspaceNote,
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
  if (workspace.provider === 'opfs') return 'CloudOS local (OPFS)';
  if (workspace.provider === 'windows') return 'Windows grant';
  return 'Linux Home';
}

export default function WorkflowWorkspace({ windowId }: { windowId: string }) {
  const params = useWindowManager(state => state.getWindow(windowId)?.params as { workspaceId?: string; noteFileName?: string } | undefined);
  const [workspaces, setWorkspaces] = useState<WorkspaceRecord[]>(listWorkspaces);
  const [activeId, setActiveId] = useState(() => params?.workspaceId || getActiveWorkspace()?.id || '');
  const [tab, setTab] = useState<WorkspaceTab>(params?.noteFileName ? 'notes' : 'overview');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [newType, setNewType] = useState<WorkspaceType>('client');
  const [newProvider, setNewProvider] = useState<WorkflowProvider>('opfs');
  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');

  const [notes, setNotes] = useState<WorkflowNote[]>([]);
  const [activeNoteFile, setActiveNoteFile] = useState(params?.noteFileName || '');
  const [noteContent, setNoteContent] = useState('');
  const [noteSearch, setNoteSearch] = useState('');
  const [noteSaving, setNoteSaving] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [previewMarkdown, setPreviewMarkdown] = useState(false);
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
  const filteredNotes = useMemo(() => notes.filter(note => matchesWorkflowQuery(`${note.title}\n${note.content}`, noteSearch)), [noteSearch, notes]);

  const refreshWorkspaces = useCallback(() => {
    const next = listWorkspaces();
    setWorkspaces(next);
    setActiveId(current => next.some(item => item.id === current) ? current : (getActiveWorkspace()?.id || next[0]?.id || ''));
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
      void activateWorkspace(target.id).catch(() => undefined);
    }
  }, [params?.workspaceId]);

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
    try { await activateWorkspace(workspace.id); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao ativar o workspace.'); }
  }, []);

  const selectNote = useCallback((note: WorkflowNote) => {
    setActiveNoteFile(note.fileName);
    setNoteContent(note.content);
    savedNoteContent.current = note.content;
    setNoteSaving('idle');
  }, []);

  const saveActiveNote = useCallback(async () => {
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
  }, [active, activeNoteFile, noteContent]);

  useEffect(() => {
    if (!active || !activeNoteFile || noteContent === savedNoteContent.current) return;
    const timer = window.setTimeout(() => { void saveActiveNote(); }, 650);
    return () => window.clearTimeout(timer);
  }, [active?.id, activeNoteFile, noteContent, saveActiveNote]);

  const addNote = useCallback(async () => {
    if (!active || busy) return;
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
      if (tab !== 'notes' || !active) return;
      if (event.ctrlKey && event.key.toLowerCase() === 's') { event.preventDefault(); void saveActiveNote(); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'n') { event.preventDefault(); void addNote(); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'f') { event.preventDefault(); noteSearchRef.current?.focus(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, addNote, saveActiveNote, tab]);

  const submitWorkspace = useCallback(async () => {
    if (!newName.trim()) { setError('Informe o nome do workspace.'); return; }
    setBusy(true);
    setError('');
    try {
      if (newProvider === 'windows') await fileSourceFacade.mountWindows();
      const workspace = await createWorkspace({ type: newType, name: newName, description: newDescription, provider: newProvider, originPath: [] });
      setShowCreate(false);
      setNewName('');
      setNewDescription('');
      refreshWorkspaces();
      setActiveId(workspace.id);
      setTab('overview');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao criar workspace.');
    } finally { setBusy(false); }
  }, [newDescription, newName, newProvider, newType, refreshWorkspaces]);

  const addEvidenceText = useCallback(async () => {
    if (!active || !evidenceText.trim()) return;
    setBusy(true);
    setError('');
    try {
      await saveWorkspaceEvidenceText(active, evidenceKind, evidenceText);
      setEvidenceText('');
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao salvar evidência.'); }
    finally { setBusy(false); }
  }, [active, evidenceKind, evidenceText]);

  const addEvidenceFiles = useCallback(async (files: FileList | File[]) => {
    if (!active || files.length === 0) return;
    setBusy(true);
    setError('');
    try {
      for (const file of Array.from(files)) await saveWorkspaceEvidenceFile(active, file);
      setEvidence(await listWorkspaceEvidence(active));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Falha ao anexar evidência.'); }
    finally { setBusy(false); if (evidenceInputRef.current) evidenceInputRef.current.value = ''; }
  }, [active]);

  const pasteScreenshot = useCallback(async () => {
    if (!active) return;
    setBusy(true);
    setError('');
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
        ? active ? { kind: 'workspace' as const, workspaceId: active.id } : null
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

  return <div className="workflow-workspace">
    <aside className="ww-sidebar">
      <div className="ww-sidebar-head"><strong>Workspaces</strong><button onClick={() => setShowCreate(true)}>＋</button></div>
      <div className="ww-workspace-list">
        {workspaces.map(workspace => <button key={workspace.id} className={workspace.id === activeId ? 'active' : ''} onClick={() => void selectWorkspace(workspace)}>
          <span>{workspace.name}</span><small>{WORKSPACE_TYPES.find(item => item.id === workspace.type)?.label} · {workspaceOriginLabel(workspace)}</small>
        </button>)}
        {!workspaces.length && <p className="ww-empty-small">Nenhum workspace criado.</p>}
      </div>
      <button className="ww-new" onClick={() => setShowCreate(true)}>＋ Novo workspace</button>
    </aside>

    <section className="ww-main">
      {error && <div className="ww-error" role="alert"><span>{error}</span><button onClick={() => setError('')}>×</button></div>}
      {!active ? <div className="ww-empty"><h2>Workspace</h2><p>Crie um workspace para concentrar Notes, Downloads, Evidence, Reports, Files, Terminal e Browser.</p><button onClick={() => setShowCreate(true)}>Criar workspace</button></div> : <>
        <header className="ww-header">
          <div><small>{WORKSPACE_TYPES.find(item => item.id === active.type)?.label}</small><h2>{active.name}</h2><p>{active.description || 'Sem descrição.'}</p></div>
          <div className="ww-quick-actions">
            <button onClick={() => openWorkspaceFiles(active, 'Files')}>Files</button>
            <button onClick={() => openFilesAt(active.provider, [...active.root, 'Reports'])}>Reports</button>
            <button disabled={!terminalHereCapability(active.provider).supported} title={terminalHereCapability(active.provider).reason} onClick={() => { try { openWorkspaceTerminal(active); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Terminal aqui indisponível.'); } }}>Terminal</button>
            <button onClick={() => openExistingBrowser()}>Browser</button>
          </div>
        </header>

        <nav className="ww-tabs" aria-label="Workspace">
          {(['overview', 'notes', 'evidence', 'downloads', 'clipboard'] as WorkspaceTab[]).map(name => <button key={name} className={tab === name ? 'active' : ''} onClick={() => setTab(name)}>{name === 'overview' ? 'Visão geral' : name === 'notes' ? 'Notes' : name === 'evidence' ? 'Evidence' : name === 'downloads' ? 'Downloads' : 'Clipboard'}</button>)}
        </nav>

        <div className="ww-body">
          {tab === 'overview' && <div className="ww-overview">
            <section><h3>Estrutura</h3><div className="ww-folder-grid">{WORKSPACE_FOLDERS.map(folder => <button key={folder} onClick={() => openFilesAt(active.provider, [...active.root, folder])}>📁 {folder}</button>)}</div></section>
            <section className="ww-meta"><h3>workspace.json</h3><dl><dt>Nome</dt><dd>{active.name}</dd><dt>Descrição</dt><dd>{active.description || '—'}</dd><dt>Data</dt><dd>{new Date(active.createdAt).toLocaleString()}</dd><dt>Último acesso</dt><dd>{new Date(active.lastAccessAt).toLocaleString()}</dd><dt>Origem</dt><dd>{workspaceOriginLabel(active)}</dd></dl></section>
          </div>}

          {tab === 'notes' && <div className="workflow-notes ww-notes">
            <aside><div className="ww-note-tools"><input ref={noteSearchRef} value={noteSearch} onChange={event => setNoteSearch(event.target.value)} placeholder="Pesquisar notas…" /><button onClick={() => void addNote()}>＋</button></div>{filteredNotes.map(note => <button key={note.fileName} className={note.fileName === activeNoteFile ? 'active' : ''} onClick={() => selectNote(note)}><strong>{note.title}</strong><small>{new Date(note.modified).toLocaleString()}</small></button>)}</aside>
            <section className="ww-note-editor">{activeNote ? <><div className="ww-note-head"><strong>{activeNote.title}.md</strong><span>{noteSaving === 'saving' ? 'Salvando…' : noteSaving === 'saved' ? 'Salvo' : noteSaving === 'error' ? 'Falha ao salvar' : 'Autosave'}</span><button onClick={() => setPreviewMarkdown(value => !value)}>{previewMarkdown ? 'Editar' : 'Preview'}</button></div>{previewMarkdown ? <MarkdownPreview value={noteContent} /> : <textarea value={noteContent} onChange={event => setNoteContent(event.target.value)} spellCheck={false} aria-label="Nota Markdown" />}</> : <div className="ww-empty-small">Crie uma nota Markdown. Ctrl+N cria, Ctrl+S salva e Ctrl+F pesquisa.</div>}</section>
          </div>}

          {tab === 'evidence' && <div className="ww-evidence">
            <div className="ww-evidence-compose"><select value={evidenceKind} onChange={event => setEvidenceKind(event.target.value as EvidenceKind)}><option value="note">Nota</option><option value="log">Log</option><option value="link">Link</option></select><textarea value={evidenceText} onChange={event => setEvidenceText(event.target.value)} placeholder={evidenceKind === 'link' ? 'https://…' : 'Conteúdo da evidência'} /><div><button onClick={() => void addEvidenceText()}>Salvar</button><button onClick={() => evidenceInputRef.current?.click()}>Anexar arquivo</button><button onClick={() => void pasteScreenshot()}>Colar captura</button><input ref={evidenceInputRef} hidden type="file" multiple onChange={event => event.target.files && void addEvidenceFiles(event.target.files)} /></div></div>
            <div className="ww-evidence-list">{evidence.map(entry => <div key={entry.name}><span>{entry.kind === 'directory' ? '📁' : '📎'}</span><strong>{entry.name}</strong><small>{entry.kind === 'file' ? `${entry.size} bytes` : 'Pasta'}</small></div>)}{!evidence.length && <p>Nenhuma evidência neste workspace.</p>}</div>
          </div>}

          {tab === 'downloads' && <div className="ww-downloads"><h3>Destino explícito de downloads</h3><p>O Batch 3 registra a escolha sem mover arquivos automaticamente.</p><div className="ww-destination-grid"><button className={downloadDestination.kind === 'workspace' ? 'active' : ''} onClick={() => chooseDownloadDestination('workspace')}>Workspace atual</button><button className={downloadDestination.kind === 'opfs' ? 'active' : ''} onClick={() => chooseDownloadDestination('opfs')}>OPFS</button><button className={downloadDestination.kind === 'windows' ? 'active' : ''} onClick={() => chooseDownloadDestination('windows')}>Windows grant</button><button className={downloadDestination.kind === 'wsl' ? 'active' : ''} onClick={() => chooseDownloadDestination('wsl')}>Linux Home</button></div><div className="ww-limitation"><strong>Limite do Release Freeze:</strong> o Browser nativo está congelado. Esta preferência fica pronta no workflow, mas não é injetada no processo nativo até existir autorização explícita para tocar essa integração.</div></div>}

          {tab === 'clipboard' && <div className="ww-clipboard"><div className="ww-clipboard-head"><span>{clipboardEntries.length}/30 entradas</span><button onClick={() => void clearClipboardHistory()}>Limpar</button></div>{clipboardEntries.map(entry => <div key={entry.id} className="ww-clipboard-entry"><button className={entry.favorite ? 'favorite active' : 'favorite'} onClick={() => { toggleClipboardFavorite(entry.id); setClipboardEntries(listClipboardEntries()); }}>★</button><div><strong>{entry.source}</strong><p>{entry.preview}</p><small>{entry.bytes} bytes · {new Date(entry.createdAt).toLocaleString()}</small></div><button onClick={() => void clipboardAction(entry, 'copy')}>Copiar</button><button onClick={() => void clipboardAction(entry, 'paste')}>Colar</button></div>)}{!clipboardEntries.length && <p>O histórico ignora senhas, JWT e padrões de secrets.</p>}</div>}
        </div>
      </>}
    </section>

    {showCreate && <div className="ww-modal" role="dialog" aria-modal="true"><section><h2>Novo workspace</h2><label>Tipo<select value={newType} onChange={event => setNewType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label><label>Nome<input autoFocus value={newName} onChange={event => setNewName(event.target.value)} /></label><label>Descrição<textarea value={newDescription} onChange={event => setNewDescription(event.target.value)} /></label><label>Origem<select value={newProvider} onChange={event => setNewProvider(event.target.value as WorkflowProvider)}><option value="opfs">CloudOS local (OPFS)</option><option value="windows">Windows grant</option><option value="wsl">Linux Home</option></select></label><p>{newProvider === 'windows' ? 'Ao confirmar, o seletor de pasta do Windows será aberto antes da criação.' : 'Nenhum banco real é usado.'}</p><footer><button onClick={() => setShowCreate(false)}>Cancelar</button><button disabled={busy} onClick={() => void submitWorkspace()}>{busy ? 'Criando…' : 'Criar workspace'}</button></footer></section></div>}
  </div>;
}
