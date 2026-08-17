import { useCallback, useEffect, useMemo, useState } from 'react';
import { terminalHereCapability, workflowFileOpenMode, type WorkflowProvider } from '../../core/workflowCore.js';
import { clearRecentFiles, listRecentFiles, recordRecentFile, type WorkflowRecentFile } from '../../services/workflowRecentFiles';
import { addFileToActiveWorkspaceEvidence, downloadDestinationLabel, getDownloadDestination } from '../../services/workflowWorkspace';
import { openFilesAt, openTerminalHere, openTextFileInNotes } from '../../services/workflowLaunch';
import './FilesWorkflowBridge.css';
import './FilesWorkflowBridge36.css';

type FilesContext = { provider: WorkflowProvider; path: string[]; inTrash: boolean };
type FilesSelection = FilesContext & {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  symlink: boolean;
};

function parseProvider(root: HTMLElement): WorkflowProvider | null {
  const value = root.dataset.filesSource;
  return value === 'opfs' || value === 'windows' || value === 'wsl' ? value : null;
}

function parsePath(root: HTMLElement) {
  const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('.cf-address button'));
  if (buttons.some(button => /lixeira/i.test(button.textContent || ''))) return [];
  return buttons.slice(1).map(button => (button.textContent || '').trim().replace(/^\/\s*/, '')).filter(Boolean);
}

function contextFromRoot(root: HTMLElement): FilesContext | null {
  const provider = parseProvider(root);
  if (!provider) return null;
  return {
    provider,
    path: parsePath(root),
    inTrash: /lixeira/i.test(root.querySelector('.cf-address')?.textContent || ''),
  };
}

function selectionFromTarget(target: EventTarget | null): FilesSelection | null {
  if (!(target instanceof Element)) return null;
  const item = target.closest<HTMLElement>('.cf-item');
  const root = item?.closest<HTMLElement>('.cf-root');
  if (!item || !root) return null;
  const context = contextFromRoot(root);
  if (!context) return null;
  const kindRaw = item.dataset.fileKind;
  const kind = kindRaw === 'directory' || kindRaw === 'symlink' ? kindRaw : 'file';
  const name = item.querySelector<HTMLElement>('.cf-name')?.textContent?.trim() || '';
  if (!name) return null;
  return {
    ...context,
    name,
    kind,
    symlink: kind === 'symlink' || item.classList.contains('cf-item--symlink'),
  };
}

function originLabel(provider: WorkflowProvider) {
  if (provider === 'windows') return 'Windows';
  if (provider === 'wsl') return 'Linux';
  return 'OPFS';
}

function originDetail(provider: WorkflowProvider) {
  if (provider === 'windows') return 'pasta autorizada';
  if (provider === 'wsl') return 'Home';
  return 'CloudOS';
}

function trashText(provider: WorkflowProvider) {
  if (provider === 'windows') return 'Lixeira CloudOS dentro da pasta Windows autorizada. Não é a Lixeira do Windows; restauração usa metadata do próprio CloudOS.';
  if (provider === 'wsl') return 'Lixeira gerenciada pelo CloudOS no Linux Home. Restauração só aparece quando o provider retorna um identificador válido.';
  return 'Lixeira transacional do OPFS privado do CloudOS, com restauração suportada pelo provider.';
}

function visibleFilesRoot() {
  const roots = Array.from(document.querySelectorAll<HTMLElement>('.cf-root[data-files-source]'));
  return [...roots].reverse().find(root => root.getClientRects().length > 0) || roots.at(-1) || null;
}

function RecentRow({ file, label }: { file: WorkflowRecentFile; label: string }) {
  return <button className="wf-files-recent-row" type="button" onClick={() => openFilesAt(file.provider, file.path, file.name)} title={`${originLabel(file.provider)} · /${file.path.join('/')}`}>
    <span>{file.mode === 'notes' ? '✎' : file.mode === 'viewer' ? '◫' : 'ℹ'}</span>
    <div><strong>{file.name}</strong><small>{label} · {originLabel(file.provider)} · {file.path.length ? `/${file.path.join('/')}` : '/'}</small></div>
  </button>;
}

export default function FilesWorkflowBridge() {
  const [context, setContext] = useState<FilesContext | null>(null);
  const [selection, setSelection] = useState<FilesSelection | null>(null);
  const [message, setMessage] = useState('');
  const [revision, setRevision] = useState(0);
  const [showRecent, setShowRecent] = useState(false);

  useEffect(() => {
    const syncContext = (preferred?: HTMLElement | null) => {
      const root = preferred || visibleFilesRoot();
      const next = root ? contextFromRoot(root) : null;
      setContext(current => current?.provider === next?.provider && current?.inTrash === next?.inTrash && JSON.stringify(current?.path || []) === JSON.stringify(next?.path || []) ? current : next);
      if (!next) setSelection(null);
    };
    syncContext();
    const observer = new MutationObserver(() => syncContext());
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-files-source'] });

    const onWorkflowChanged = () => setRevision(value => value + 1);
    window.addEventListener('cloudos:workflow-changed', onWorkflowChanged);

    const onClick = (event: MouseEvent) => {
      const element = event.target instanceof Element ? event.target : null;
      const root = element?.closest<HTMLElement>('.cf-root');
      if (root) syncContext(root);
      const next = selectionFromTarget(event.target);
      if (next) {
        setSelection(next);
        setMessage('');
      } else if (element && !element.closest('.wf-files-bridge') && !root) {
        setSelection(null);
      }
    };
    const onDoubleClick = (event: MouseEvent) => {
      const next = selectionFromTarget(event.target);
      if (!next || next.inTrash || next.symlink || next.kind !== 'file') return;
      recordRecentFile({ provider: next.provider, path: next.path, name: next.name });
      setSelection(next);
      const mode = workflowFileOpenMode(next.name, next.kind, next.symlink);
      if (mode !== 'notes') return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      try {
        openTextFileInNotes({ provider: next.provider, path: next.path, name: next.name });
      } catch (cause) {
        setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir no Notes.');
      }
    };
    document.addEventListener('click', onClick, true);
    document.addEventListener('dblclick', onDoubleClick, true);
    return () => {
      observer.disconnect();
      window.removeEventListener('cloudos:workflow-changed', onWorkflowChanged);
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('dblclick', onDoubleClick, true);
    };
  }, []);

  const activeContext = selection || context;
  const openMode = useMemo(() => selection ? workflowFileOpenMode(selection.name, selection.kind, selection.symlink) : 'info', [selection]);
  const terminal = useMemo(() => activeContext ? terminalHereCapability(activeContext.provider) : null, [activeContext]);
  const recent = useMemo(() => { void revision; return listRecentFiles('all').slice(0, 6); }, [revision]);
  const documents = useMemo(() => { void revision; return listRecentFiles('documents').slice(0, 6); }, [revision]);
  const destination = useMemo(() => { void revision; return getDownloadDestination(); }, [revision]);

  const navigateBreadcrumb = useCallback((index: number) => {
    const root = visibleFilesRoot();
    if (!root) return;
    const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('.cf-address button'));
    const target = index < 0 ? buttons[0] : buttons[index + 1];
    target?.click();
  }, []);

  const openTerminal = useCallback(() => {
    if (!activeContext) return;
    const path = selection?.kind === 'directory' && !selection.symlink ? [...selection.path, selection.name] : activeContext.path;
    try { openTerminalHere(activeContext.provider, path); }
    catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Terminal indisponível nesta origem.'); }
  }, [activeContext, selection]);

  const openNotes = useCallback(() => {
    if (!selection || openMode !== 'notes' || selection.inTrash) return;
    try {
      recordRecentFile({ provider: selection.provider, path: selection.path, name: selection.name });
      openTextFileInNotes({ provider: selection.provider, path: selection.path, name: selection.name });
    } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir no Notes.'); }
  }, [openMode, selection]);

  const addEvidence = useCallback(async () => {
    if (!selection || selection.kind !== 'file' || selection.symlink || selection.inTrash) return;
    if (!window.confirm(`Adicionar “${selection.name}” à Evidence do Workspace ativo? O original será preservado.`)) return;
    setMessage('');
    try {
      const result = await addFileToActiveWorkspaceEvidence(selection.provider, selection.path, selection.name);
      setMessage(`Adicionado à Evidence de “${result.workspace.name}”.`);
    } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao adicionar à Evidence.'); }
  }, [selection]);

  if (!activeContext) return null;

  const contextName = selection?.name || (activeContext.inTrash ? 'Lixeira' : activeContext.path.at(-1) || 'Raiz');
  return <aside className="wf-files-bridge wf-files-bridge--36" aria-label="Contexto e ações rápidas do Files">
    <div className="wf-files-context">
      <span className="wf-files-origin">{originLabel(activeContext.provider)}</span>
      <div><strong>{contextName}</strong><small>{originDetail(activeContext.provider)} · {activeContext.inTrash ? 'Lixeira' : selection ? openMode === 'notes' ? 'Abre em Notes' : openMode === 'viewer' ? 'Abre no Viewer' : selection.kind === 'directory' ? 'Pasta' : 'Informações' : 'Origem ativa'}</small></div>
      {selection ? <button onClick={() => setSelection(null)} aria-label="Limpar seleção contextual">×</button> : <span />}
    </div>

    {!activeContext.inTrash && <nav className="wf-files-breadcrumbs" aria-label="Breadcrumb unificado do Files">
      <button type="button" onClick={() => navigateBreadcrumb(-1)}>{originLabel(activeContext.provider)}</button>
      {activeContext.path.map((part, index) => <span key={`${part}-${index}`}><b>›</b><button type="button" onClick={() => navigateBreadcrumb(index)}>{part}</button></span>)}
    </nav>}

    <div className="wf-files-destination" aria-label="Destino atual de downloads">
      <div><small>Destino atual de downloads</small><strong>{downloadDestinationLabel(destination)}</strong></div>
      <span>Preferência do workflow. O Browser nativo congelado ainda não suporta redirecionamento físico por esta escolha.</span>
    </div>

    {activeContext.inTrash ? <p className="wf-files-trash-note"><strong>{originLabel(activeContext.provider)}:</strong> {trashText(activeContext.provider)}</p> : <div className="wf-files-actions">
      <button disabled={!terminal?.supported} title={terminal?.reason} onClick={openTerminal}>Abrir no Terminal</button>
      <button disabled={!selection || openMode !== 'notes'} title={!selection || openMode !== 'notes' ? 'Selecione txt, md, json ou log para abrir no Notes.' : ''} onClick={openNotes}>Abrir em Notes</button>
      <button disabled={!selection || selection.kind !== 'file' || selection.symlink} onClick={() => void addEvidence()}>Adicionar à Evidence</button>
      <button type="button" className={showRecent ? 'is-active' : ''} onClick={() => setShowRecent(value => !value)}>Recentes</button>
    </div>}

    {showRecent && <section className="wf-files-recents" aria-label="Arquivos recentes">
      <header><div><strong>Abrir recente</strong><small>Somente itens realmente abertos pelo Files nesta sessão/histórico local.</small></div><button type="button" disabled={!recent.length} onClick={() => { clearRecentFiles(); setRevision(value => value + 1); }}>Limpar</button></header>
      <div className="wf-files-recent-columns">
        <div><h4>Recentes</h4>{recent.map(file => <RecentRow key={`all:${file.provider}:${file.path.join('/')}:${file.name}`} file={file} label={new Date(file.openedAt).toLocaleString()} />)}{!recent.length && <p>Nenhum arquivo aberto recentemente.</p>}</div>
        <div><h4>Documentos recentes</h4>{documents.map(file => <RecentRow key={`doc:${file.provider}:${file.path.join('/')}:${file.name}`} file={file} label="Documento" />)}{!documents.length && <p>Nenhum documento recente.</p>}</div>
      </div>
    </section>}

    <div className="wf-files-shortcuts"><span><kbd>Enter</kbd> abrir</span><span><kbd>F2</kbd> renomear</span><span><kbd>Del</kbd> lixeira/excluir</span><span><kbd>Ctrl+C/X/V</kbd> arquivo</span><span><kbd>Ctrl+Alt+T</kbd> Terminal aqui</span></div>
    {message && <p className="wf-files-message">{message}</p>}
  </aside>;
}
