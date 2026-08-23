import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { classifyPreview } from '../../core/filePreviewPolicy.js';
import { WORKSPACE_TYPES, terminalHereCapability, type WorkspaceType } from '../../core/workflowCore.js';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useWindowManager } from '../../stores/windowManager';
import { addClipboardText } from '../../services/workflowClipboard';
import { openTerminalHere, openWorkspace } from '../../services/workflowLaunch';
import { openFile } from '../../services/fileLauncher';
import { getFileIconForExtension } from '../../services/mimeRegistry';
import {
  createWorkspace,
  getActiveWorkspace,
  indexFiles,
  listWorkspaces,
  type WorkspaceRecord,
} from '../../services/workflowWorkspace';
import FilePreviewPanel from './FilePreviewPanel';
import FileVisual from './FileVisual';
import { formatBytes, type StorageInfo } from './opfsFileService';
import {
  fileSourceFacade,
  type CloudClipboardEntry,
  type CloudFileEntry,
  type SourceRuntime,
} from './fileSourceFacade';
import { sourceLabel, type FileSourceKind } from './fileSourcePolicy';
import type { FileOperation } from './wslFileSource';
import './CloudOSFiles.css';
import './CloudOSFiles.real.css';
import './CloudOSFiles.visual.css';

type ViewMode = 'files' | 'trash';
type SortField = 'name' | 'modified' | 'size';
type LayoutMode = 'grid' | 'list';
type DialogType = 'create-file' | 'create-folder' | 'rename' | 'confirm-delete' | 'confirm-empty-trash' | 'workspace' | null;
type DialogState = { type: DialogType; title?: string; message?: string; entry?: CloudFileEntry };
type EditorState = { name: string; content: string; mode?: number } | null;
type ActiveOperation = { source: 'windows' | 'wsl'; id?: string; status: string; progress: number; message: string };
type LaunchParams = { workflowSource?: FileSourceKind; workflowPath?: string[]; workflowSelectName?: string };

const MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024;
const delay = (ms: number) => new Promise(resolve => window.setTimeout(resolve, ms));

function isTypingTarget(target: EventTarget | null) {
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || (target instanceof HTMLElement && target.isContentEditable);
}

function validSource(value: unknown): value is FileSourceKind {
  return value === 'opfs' || value === 'windows' || value === 'wsl';
}

function storageDescription(source: FileSourceKind, runtime: SourceRuntime, storage: StorageInfo | null) {
  if (source === 'opfs') return {
    title: 'CloudOS Home (Início)',
    type: 'Armazenamento Híbrido Unificado (Downloads, Documentos, Projetos, Workspace)',
    persistence: 'Persiste no CloudOS Home',
    permission: 'Acesso padrão e integrado para todos os aplicativos',
    capacity: storage ? `${formatBytes(storage.used)} usados de ${formatBytes(storage.quota)} de quota reportada` : 'Capacidade dinâmica do CloudOS',
  };
  if (source === 'windows') return {
    title: 'Pasta Windows autorizada',
    type: 'File System Access API',
    persistence: 'Grant mantido somente durante esta sessão do Files',
    permission: runtime.mounted ? 'Pasta escolhida explicitamente pelo usuário' : 'Sem pasta autorizada nesta sessão',
    capacity: 'Capacidade física não inferida pelo CloudOS',
  };
  return {
    title: 'Linux Home',
    type: 'Filesystem POSIX via WSL Core v2',
    persistence: 'Persiste dentro da distribuição WSL selecionada',
    permission: runtime.available ? 'Raiz confinada ao Home do usuário do core' : 'Linux Files indisponível',
    capacity: 'Capacidade física não inferida nesta fase',
  };
}

export default function CloudOSFiles({ windowId }: { windowId?: string }) {
  const [launchParams] = useState<LaunchParams>(() => {
    const win = windowId ? useWindowManager.getState().getWindow(windowId) : undefined;
    const raw = (win?.params || {}) as LaunchParams;
    return {
      workflowSource: validSource(raw.workflowSource) ? raw.workflowSource : undefined,
      workflowPath: Array.isArray(raw.workflowPath) ? raw.workflowPath.filter((part): part is string => typeof part === 'string' && Boolean(part)) : undefined,
      workflowSelectName: typeof raw.workflowSelectName === 'string' ? raw.workflowSelectName : undefined,
    };
  });
  const initialSource = launchParams.workflowSource || 'opfs';
  const [source, setSource] = useState<FileSourceKind>('opfs');
  const [runtime, setRuntime] = useState<SourceRuntime>({ source: initialSource, label: sourceLabel(initialSource), mounted: initialSource === 'opfs', available: initialSource === 'opfs', detail: '' });
  const [entries, setEntries] = useState<CloudFileEntry[]>([]);
  const [currentPath, setCurrentPath] = useState<string[]>(launchParams.workflowPath || []);
  const [viewMode, setViewMode] = useState<ViewMode>('files');
  const [layoutMode, setLayoutMode] = useState<LayoutMode>('grid');
  const [selectedName, setSelectedName] = useState<string | null>(launchParams.workflowSelectName || null);
  const [previewFile, setPreviewFile] = useState<File | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [clipboard, setClipboard] = useState<CloudClipboardEntry | null>(null);
  const [storageInfo, setStorageInfo] = useState<StorageInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isDragging, setIsDragging] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [editor, setEditor] = useState<EditorState>(null);
  const [dialog, setDialog] = useState<DialogState>({ type: null });
  const [dialogInputValue, setDialogInputValue] = useState('');
  const [workspaceDescription, setWorkspaceDescription] = useState('');
  const [workspaceType, setWorkspaceType] = useState<WorkspaceType>('client');
  const [workspaces, setWorkspaces] = useState<WorkspaceRecord[]>(listWorkspaces);
  const [activeOperation, setActiveOperation] = useState<ActiveOperation | null>(null);
  const uploadInputRef = useRef<HTMLInputElement>(null);
  const directoryGeneration = useRef(0);
  const previewGeneration = useRef(0);
  const operationController = useRef<AbortController | null>(null);
  const activeOperationRef = useRef<ActiveOperation | null>(null);
  const pendingSelectRef = useRef(launchParams.workflowSelectName || '');
  const launchAppliedRef = useRef(false);
  const { openContextMenu } = useContextMenuStore();

  useEffect(() => {
    if (launchAppliedRef.current) return;
    launchAppliedRef.current = true;
    if (launchParams.workflowSource && launchParams.workflowSource !== 'opfs') setSource(launchParams.workflowSource);
  }, [launchParams.workflowSource]);

  useEffect(() => { activeOperationRef.current = activeOperation; }, [activeOperation]);
  useEffect(() => {
    const onChanged = () => setWorkspaces(listWorkspaces());
    window.addEventListener('cloudos:workflow-changed', onChanged);
    return () => window.removeEventListener('cloudos:workflow-changed', onChanged);
  }, []);

  const selectedEntry = useMemo(() => entries.find(entry => entry.name === selectedName) ?? null, [entries, selectedName]);
  const storage = useMemo(() => storageDescription(source, runtime, storageInfo), [runtime, source, storageInfo]);
  const terminalCapability = useMemo(() => terminalHereCapability(source), [source]);

  const loadDirectory = useCallback(async () => {
    const generation = ++directoryGeneration.current;
    setIsLoading(true);
    setErrorMessage('');
    try {
      const nextRuntime = await fileSourceFacade.runtime(source);
      if (generation !== directoryGeneration.current) return;
      setRuntime(nextRuntime);
      if (!nextRuntime.available || !nextRuntime.mounted) {
        setEntries([]);
        setStorageInfo(null);
        if (source === 'windows' && !nextRuntime.mounted) setErrorMessage('Selecione explicitamente uma pasta do Windows para conceder acesso.');
        else if (source === 'wsl') setErrorMessage(nextRuntime.detail || 'Linux Files indisponível.');
        return;
      }
      const [nextEntries, estimate] = await Promise.all([
        fileSourceFacade.list(source, currentPath, viewMode === 'trash'),
        fileSourceFacade.storage(source),
      ]);
      if (generation !== directoryGeneration.current) return;
      setEntries(nextEntries);
      setStorageInfo(estimate);
      if (viewMode === 'files') indexFiles(source, currentPath, nextEntries);
      const requested = pendingSelectRef.current;
      if (requested && nextEntries.some(entry => entry.name === requested)) {
        setSelectedName(requested);
        pendingSelectRef.current = '';
      } else setSelectedName(null);
      setPreviewFile(null);
      setPreviewLoading(false);
    } catch (error) {
      if (generation !== directoryGeneration.current) return;
      setEntries([]);
      setStorageInfo(null);
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao acessar a origem de arquivos.');
    } finally {
      if (generation === directoryGeneration.current) setIsLoading(false);
    }
  }, [currentPath, source, viewMode]);

  useEffect(() => { void loadDirectory(); }, [loadDirectory]);

  useEffect(() => () => {
    operationController.current?.abort();
    const operation = activeOperationRef.current;
    if (operation?.source === 'wsl' && operation.id && ['queued', 'running', 'cancelling'].includes(operation.status)) {
      void fileSourceFacade.cancelWslOperation(operation.id).catch(() => undefined);
    }
  }, []);

  const changeSource = useCallback(async (next: FileSourceKind) => {
    if (next === source && (next !== 'windows' || runtime.mounted)) return;
    if (next === 'windows' && !runtime.mounted) {
      try {
        await fileSourceFacade.mountWindows();
      } catch (error) {
        setErrorMessage(error instanceof Error ? error.message : 'A seleção da pasta do Windows foi cancelada.');
        return;
      }
    }
    operationController.current?.abort();
    setActiveOperation(null);
    setErrorMessage('');
    setSource(next);
    setCurrentPath([]);
    setViewMode('files');
    setSelectedName(null);
    setPreviewFile(null);
    setClipboard(null);
  }, [runtime.mounted, source]);

  const visibleEntries = useMemo(() => {
    const query = searchQuery.trim().toLocaleLowerCase();
    return entries
      .filter(entry => !query || (entry.originalName || entry.name).toLocaleLowerCase().includes(query))
      .sort((left, right) => {
        if (left.kind !== right.kind) {
          if (left.kind === 'directory') return -1;
          if (right.kind === 'directory') return 1;
          if (left.kind === 'symlink') return 1;
          if (right.kind === 'symlink') return -1;
        }
        if (sortField === 'size') return right.size - left.size;
        if (sortField === 'modified') return right.modified - left.modified;
        return (left.originalName || left.name).localeCompare(right.originalName || right.name, undefined, { sensitivity: 'base' });
      });
  }, [entries, searchQuery, sortField]);

  const selectEntry = useCallback(async (entry: CloudFileEntry) => {
    setSelectedName(entry.name);
    const generation = ++previewGeneration.current;
    setPreviewFile(null);
    if (entry.kind !== 'file' || entry.symlink || (viewMode === 'trash' && source !== 'opfs')) {
      setPreviewLoading(false);
      return;
    }
    const policy = classifyPreview({ name: entry.originalName || entry.name, size: entry.size });
    if (!policy.allowed) { setPreviewLoading(false); return; }
    setPreviewLoading(true);
    try {
      const file = await fileSourceFacade.readFile(source, currentPath, entry, policy.limit);
      if (generation === previewGeneration.current) setPreviewFile(file);
    } catch (error) {
      if (generation === previewGeneration.current) setErrorMessage(error instanceof Error ? error.message : 'Não foi possível carregar o preview deste arquivo.');
    } finally {
      if (generation === previewGeneration.current) setPreviewLoading(false);
    }
  }, [currentPath, source, viewMode]);

  const handleLaunchFile = useCallback(async (entry: CloudFileEntry, openWith = false) => {
    if (entry.kind !== 'file' || entry.symlink) return;
    const fullPath = source === 'opfs'
      ? `~/${currentPath.length ? `${currentPath.join('/')}/` : ''}${entry.name}`
      : source === 'wsl'
      ? `/${currentPath.length ? `${currentPath.join('/')}/` : ''}${entry.name}`
      : `/mnt/c/${currentPath.length ? `${currentPath.join('/')}/` : ''}${entry.name}`;

    let fileContent: string | undefined;
    if (source === 'opfs' && entry.size < 4 * 1024 * 1024) {
      try {
        const file = await fileSourceFacade.readFile(source, currentPath, entry, 4 * 1024 * 1024);
        fileContent = await file.text();
      } catch {}
    }

    openFile({
      filePath: fullPath,
      fileName: entry.name,
      fileContent,
      openWith,
    });
  }, [currentPath, source]);

  const openEntry = useCallback(async (entry: CloudFileEntry) => {
    if (entry.kind === 'symlink' || entry.symlink) { await selectEntry(entry); return; }
    if (entry.kind === 'directory' && viewMode === 'files') { setCurrentPath(path => [...path, entry.name]); return; }
    await selectEntry(entry);
    await handleLaunchFile(entry, false);
  }, [handleLaunchFile, selectEntry, viewMode]);

  const downloadEntry = useCallback(async (entry: CloudFileEntry) => {
    if (entry.kind !== 'file' || entry.symlink || (viewMode === 'trash' && source !== 'opfs')) return;
    try {
      const file = await fileSourceFacade.readFile(source, currentPath, entry, MAX_DOWNLOAD_BYTES);
      const url = URL.createObjectURL(file);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = entry.originalName || entry.name;
      anchor.rel = 'noopener';
      anchor.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 0);
    } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao preparar a cópia para download.'); }
  }, [currentPath, source, viewMode]);

  const openEditor = useCallback(async (entry: CloudFileEntry) => {
    if (entry.kind !== 'file' || entry.symlink || viewMode === 'trash') return;
    try {
      if (entry.size > 2 * 1024 * 1024) throw new Error('Arquivo grande demais para o editor rápido.');
      const file = await fileSourceFacade.readFile(source, currentPath, entry, 2 * 1024 * 1024);
      setEditor({ name: entry.name, content: await file.text(), mode: entry.mode });
    } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao abrir o editor.'); }
  }, [currentPath, source, viewMode]);

  const saveEditor = useCallback(async () => {
    if (!editor) return;
    setIsLoading(true);
    try { await fileSourceFacade.writeText(source, currentPath, editor.name, editor.content, editor.mode); setEditor(null); await loadDirectory(); }
    catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao salvar o arquivo.'); }
    finally { setIsLoading(false); }
  }, [currentPath, editor, loadDirectory, source]);

  const monitorWslOperation = useCallback(async (operation: FileOperation) => {
    setActiveOperation({ source: 'wsl', id: operation.id, status: operation.status, progress: operation.progress, message: operation.message });
    while (true) {
      const current = await fileSourceFacade.getWslOperation(operation.id);
      setActiveOperation({ source: 'wsl', id: current.id, status: current.status, progress: current.progress, message: current.message });
      if (['completed', 'failed', 'cancelled'].includes(current.status)) {
        if (current.status === 'failed') throw new Error(current.message || current.errorCode || 'A operação Linux falhou.');
        return current;
      }
      await delay(350);
    }
  }, []);

  const pasteClipboard = useCallback(async () => {
    if (!clipboard || viewMode !== 'files' || activeOperation) return;
    const controller = new AbortController();
    operationController.current = controller;
    setErrorMessage('');
    if (source === 'windows') setActiveOperation({ source: 'windows', status: 'running', progress: 0, message: 'Preparando operação Windows...' });
    try {
      const result = await fileSourceFacade.paste(source, clipboard, currentPath, {
        signal: controller.signal,
        onProgress: value => {
          const progress = value.totalBytes > 0 ? Math.round((value.copiedBytes / value.totalBytes) * 100) : Math.round((value.entriesDone / Math.max(1, value.totalEntries)) * 100);
          setActiveOperation({ source: 'windows', status: 'running', progress: Math.max(0, Math.min(99, progress)), message: `Copiando ${value.current}...` });
        },
      });
      if (result.operation) await monitorWslOperation(result.operation);
      else if (source === 'windows') setActiveOperation({ source: 'windows', status: 'completed', progress: 100, message: 'Operação concluída.' });
      if (clipboard.action === 'cut' && result.moved) setClipboard(null);
      await loadDirectory();
    } catch (error) {
      setErrorMessage(controller.signal.aborted ? 'Operação cancelada e destino parcial revertido.' : error instanceof Error ? error.message : 'Falha ao colar o item.');
    } finally {
      operationController.current = null;
      window.setTimeout(() => setActiveOperation(current => current?.status === 'completed' || current?.status === 'cancelled' ? null : current), 700);
    }
  }, [activeOperation, clipboard, currentPath, loadDirectory, monitorWslOperation, source, viewMode]);

  const cancelActiveOperation = useCallback(async () => {
    const current = activeOperationRef.current;
    if (!current) return;
    setActiveOperation({ ...current, status: 'cancelling', message: 'Cancelando e revertendo destino parcial...' });
    if (current.source === 'windows') operationController.current?.abort();
    else if (current.id) {
      try { await fileSourceFacade.cancelWslOperation(current.id); }
      catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao solicitar cancelamento.'); }
    }
  }, []);

  const handleUpload = useCallback(async (files: FileList | File[]) => {
    if (source !== 'opfs') { setErrorMessage('Envio direto continua restrito ao armazenamento local; use as pontes assistidas para trocar de origem.'); return; }
    if (viewMode !== 'files' || files.length === 0) return;
    setIsLoading(true);
    try { await fileSourceFacade.upload(source, currentPath, Array.from(files)); await loadDirectory(); }
    catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao enviar arquivos.'); }
    finally { setIsLoading(false); if (uploadInputRef.current) uploadInputRef.current.value = ''; }
  }, [currentPath, loadDirectory, source, viewMode]);

  const rememberFileCopy = useCallback((entry: CloudFileEntry) => {
    if (entry.kind !== 'file' || entry.symlink) return;
    const descriptor = `${source}:${currentPath.length ? `/${currentPath.join('/')}/` : '/'}${entry.name}`;
    void addClipboardText(descriptor, 'Files').catch(() => undefined);
  }, [currentPath, source]);

  const requestRename = useCallback((entry: CloudFileEntry) => {
    if (viewMode !== 'files' || entry.symlink || entry.kind === 'symlink') return;
    setDialogInputValue(entry.name); setDialog({ type: 'rename', title: 'Renomear item', entry });
  }, [viewMode]);

  const requestDelete = useCallback((entry: CloudFileEntry) => {
    if (entry.symlink || entry.kind === 'symlink') { setErrorMessage('Links simbólicos são somente metadados; o CloudOS não segue nem altera o link.'); return; }
    setDialog({ type: 'confirm-delete', entry, title: viewMode === 'trash' ? 'Excluir permanentemente' : 'Mover para a Lixeira', message: viewMode === 'trash' ? `Apagar definitivamente “${entry.originalName || entry.name}”?` : `Mover “${entry.name}” para a lixeira transacional desta origem?` });
  }, [viewMode]);

  const restoreEntry = useCallback(async (entry: CloudFileEntry) => {
    setIsLoading(true);
    try { await fileSourceFacade.restore(source, entry); await loadDirectory(); }
    catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao restaurar o item.'); }
    finally { setIsLoading(false); }
  }, [loadDirectory, source]);

  const launchTerminalAt = useCallback((entry?: CloudFileEntry) => {
    const path = entry?.kind === 'directory' && !entry.symlink ? [...currentPath, entry.name] : [...currentPath];
    try { openTerminalHere(source, path); }
    catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Terminal aqui indisponível nesta origem.'); }
  }, [currentPath, source]);

  const copyToDestination = useCallback(async (entry: CloudFileEntry, destination: FileSourceKind, destinationPath: string[], label: string) => {
    if (entry.kind !== 'file' || entry.symlink) { setErrorMessage('A ponte assistida copia somente arquivos regulares nesta fase.'); return; }
    if (!window.confirm(`Copiar “${entry.name}” para ${label}? O CloudOS não moverá nem sobrescreverá o arquivo de origem.`)) return;
    setIsLoading(true); setErrorMessage('');
    try {
      if (destination === 'windows') {
        const windowsRuntime = await fileSourceFacade.runtime('windows');
        if (!windowsRuntime.mounted) await fileSourceFacade.mountWindows();
      }
      if (destination === source) {
        const existing = await fileSourceFacade.list(destination, destinationPath, false);
        if (existing.some(candidate => candidate.name === entry.name)) throw new Error(`O destino já contém “${entry.name}”. Nenhum arquivo foi sobrescrito.`);
        const controller = new AbortController();
        const result = await fileSourceFacade.paste(source, { entry, action: 'copy', source, sourcePath: [...currentPath] }, destinationPath, { signal: controller.signal });
        if (result.operation) await monitorWslOperation(result.operation);
      } else {
        await fileSourceFacade.copyAcrossProviders(source, currentPath, entry, destination, destinationPath);
      }
      setErrorMessage(`Cópia confirmada para ${label}.`);
    } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha na cópia assistida.'); }
    finally { setIsLoading(false); }
  }, [currentPath, monitorWslOperation, source]);

  const sendToLinux = useCallback((entry: CloudFileEntry) => copyToDestination(entry, 'wsl', [], 'Linux Home'), [copyToDestination]);
  const sendToWindows = useCallback((entry: CloudFileEntry) => copyToDestination(entry, 'windows', [], 'Windows grant'), [copyToDestination]);
  const copyToWorkspace = useCallback(async (entry: CloudFileEntry) => {
    const workspace = getActiveWorkspace();
    if (!workspace) { setErrorMessage('Ative ou crie um Workspace antes de copiar para ele.'); return; }
    await copyToDestination(entry, workspace.provider, [...workspace.root, 'Files'], `Workspace “${workspace.name}”`);
  }, [copyToDestination]);

  const saveWorkspace = useCallback(async () => {
    const name = dialogInputValue.trim();
    if (!name) { setErrorMessage('Informe um nome para o workspace.'); return; }
    setIsLoading(true); setErrorMessage('');
    try {
      const workspace = await createWorkspace({ type: workspaceType, name, description: workspaceDescription, provider: source, originPath: currentPath });
      setWorkspaces(listWorkspaces());
      setDialog({ type: null }); setDialogInputValue(''); setWorkspaceDescription('');
      openWorkspace(workspace.id);
      await loadDirectory();
    } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao criar o workspace.'); }
    finally { setIsLoading(false); }
  }, [currentPath, dialogInputValue, loadDirectory, source, workspaceDescription, workspaceType]);

  const confirmDialog = useCallback(async () => {
    if (!dialog.type) return;
    if (dialog.type === 'workspace') { await saveWorkspace(); return; }
    setIsLoading(true); setErrorMessage('');
    try {
      if (dialog.type === 'create-file') await fileSourceFacade.create(source, currentPath, 'file', dialogInputValue);
      else if (dialog.type === 'create-folder') await fileSourceFacade.create(source, currentPath, 'directory', dialogInputValue);
      else if (dialog.type === 'rename' && dialog.entry) await fileSourceFacade.rename(source, currentPath, dialog.entry, dialogInputValue);
      else if (dialog.type === 'confirm-delete' && dialog.entry) {
        if (viewMode === 'trash') await fileSourceFacade.deleteTrash(source, dialog.entry); else await fileSourceFacade.trash(source, currentPath, dialog.entry);
      } else if (dialog.type === 'confirm-empty-trash') await fileSourceFacade.emptyTrash(source);
      setDialog({ type: null }); setDialogInputValue(''); await loadDirectory();
    } catch (error) { setErrorMessage(error instanceof Error ? error.message : 'Falha ao realizar a operação.'); }
    finally { setIsLoading(false); }
  }, [currentPath, dialog, dialogInputValue, loadDirectory, saveWorkspace, source, viewMode]);

  const openEntryContextMenu = useCallback((event: React.MouseEvent, entry: CloudFileEntry) => {
    event.preventDefault(); event.stopPropagation();
    setSelectedName(entry.name);
    const symlink = entry.kind === 'symlink' || entry.symlink;
    openContextMenu(event.clientX, event.clientY, [
      {
        id: 'open',
        label: symlink ? 'Detalhes' : entry.kind === 'directory' ? 'Abrir pasta' : 'Abrir',
        icon: '⚡',
        onClick: () => {
          if (entry.kind === 'directory') void openEntry(entry);
          else handleLaunchFile(entry, false);
        }
      },
      ...(entry.kind === 'file' && !symlink ? [
        { id: 'open-with', label: 'Abrir com...', icon: '🗂️', onClick: () => handleLaunchFile(entry, true) },
        { id: 'preview-pane', label: 'Visualizar (Preview)', icon: '👁️', onClick: () => void selectEntry(entry) },
      ] : []),
      { id: 'terminal-here', label: 'Abrir Terminal aqui', shortcut: 'Ctrl+Alt+T', onClick: () => launchTerminalAt(entry) },
      { id: 'sep-workflow', label: '', separator: true },
      { id: 'send-linux', label: 'Enviar para Linux', disabled: source === 'wsl' || entry.kind !== 'file' || Boolean(symlink), onClick: () => void sendToLinux(entry) },
      { id: 'send-windows', label: 'Enviar para Windows', disabled: source === 'windows' || entry.kind !== 'file' || Boolean(symlink), onClick: () => void sendToWindows(entry) },
      { id: 'copy-workspace', label: 'Copiar para Workspace', disabled: entry.kind !== 'file' || Boolean(symlink), onClick: () => void copyToWorkspace(entry) },
      { id: 'sep-file', label: '', separator: true },
      { id: 'copy', label: 'Copiar', shortcut: 'Ctrl+C', disabled: Boolean(symlink), onClick: () => { setClipboard({ entry, action: 'copy', source, sourcePath: [...currentPath] }); rememberFileCopy(entry); } },
      { id: 'rename', label: 'Renomear', shortcut: 'F2', disabled: Boolean(symlink), onClick: () => requestRename(entry) },
      { id: 'delete', label: 'Excluir', shortcut: 'Delete', disabled: Boolean(symlink), onClick: () => requestDelete(entry) },
    ]);
  }, [copyToWorkspace, currentPath, handleLaunchFile, launchTerminalAt, openContextMenu, openEntry, rememberFileCopy, requestDelete, requestRename, selectEntry, sendToLinux, sendToWindows, source]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (windowId && useWindowManager.getState().activeWindowId !== windowId) return;
      if (isTypingTarget(event.target) || editor || dialog.type) return;
      if (event.key === 'Escape') { setSelectedName(null); setPreviewFile(null); }
      else if (event.ctrlKey && event.altKey && event.key.toLowerCase() === 't' && viewMode === 'files') { event.preventDefault(); launchTerminalAt(selectedEntry || undefined); }
      else if (event.key === 'Delete' && selectedEntry) { event.preventDefault(); requestDelete(selectedEntry); }
      else if (event.key === 'F2' && selectedEntry && viewMode === 'files') { event.preventDefault(); requestRename(selectedEntry); }
      else if (event.key === 'Enter' && selectedEntry) { event.preventDefault(); void openEntry(selectedEntry); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'c' && selectedEntry && viewMode === 'files' && !selectedEntry.symlink) { event.preventDefault(); setClipboard({ entry: selectedEntry, action: 'copy', source, sourcePath: [...currentPath] }); rememberFileCopy(selectedEntry); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'x' && selectedEntry && viewMode === 'files' && !selectedEntry.symlink) { event.preventDefault(); setClipboard({ entry: selectedEntry, action: 'cut', source, sourcePath: [...currentPath] }); }
      else if (event.ctrlKey && event.key.toLowerCase() === 'v' && clipboard && viewMode === 'files') { event.preventDefault(); void pasteClipboard(); }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [clipboard, currentPath, dialog.type, editor, launchTerminalAt, openEntry, pasteClipboard, rememberFileCopy, requestDelete, requestRename, selectedEntry, source, viewMode, windowId]);

  const pathPrefix = source === 'opfs' ? '🏠 ~/' : source === 'windows' ? '🪟 /mnt/c' : '🐧 /';

  return (
    <div className="cf-root" data-files-source={source} data-files-actor="user-ui" data-files-layout={layoutMode}>
      <header className="cf-toolbar">
        <select className="cf-source-select" value={source} onChange={event => void changeSource(event.target.value as FileSourceKind)} aria-label="Origem de arquivos">
          <option value="opfs">🏠 CloudOS Home (~/)</option>
          <option value="wsl">🐧 Linux RootFS (/)</option>
          <option value="windows">🪟 Windows Drives (/mnt/c)</option>
        </select>
        <button className="cf-btn" onClick={() => setCurrentPath(path => path.slice(0, -1))} disabled={!currentPath.length || viewMode === 'trash'} title="Pasta anterior">←</button>
        <button className="cf-btn" onClick={() => void loadDirectory()} title="Atualizar">↻</button>
        <div className="cf-toolbar-divider" />
        {viewMode === 'files' ? <>
          <button className="cf-btn primary-btn" disabled={!runtime.mounted} onClick={() => { setDialogInputValue('Novo Documento.txt'); setDialog({ type: 'create-file', title: 'Criar arquivo' }); }}>＋ Arquivo</button>
          <button className="cf-btn" disabled={!runtime.mounted} onClick={() => { setDialogInputValue('Nova Pasta'); setDialog({ type: 'create-folder', title: 'Criar pasta' }); }}>＋ Pasta</button>
          <button className="cf-btn" disabled={source !== 'opfs'} onClick={() => uploadInputRef.current?.click()}>↑ Enviar</button>
          <input ref={uploadInputRef} hidden multiple type="file" onChange={event => event.target.files && void handleUpload(event.target.files)} />
          {clipboard && <button className="cf-btn paste-btn" disabled={clipboard.source !== source || Boolean(activeOperation)} onClick={() => void pasteClipboard()}>📋 Colar</button>}
          <button className="cf-btn" onClick={() => launchTerminalAt()} title={terminalCapability.supported ? 'Abrir Terminal nesta pasta (Ctrl+Alt+T)' : terminalCapability.reason}>⌨ Terminal aqui</button>
          <button className="cf-btn" disabled={!runtime.mounted} onClick={() => { setViewMode('trash'); setCurrentPath([]); }}>🗑️ Lixeira</button>
          <button className="cf-btn" onClick={() => { setDialogInputValue('Meu workspace'); setDialog({ type: 'workspace', title: 'Criar workspace' }); }}>Workspace</button>
          {source === 'windows' && runtime.mounted && <button className="cf-btn" onClick={() => { fileSourceFacade.unmountWindows(); setSource('opfs'); setCurrentPath([]); setClipboard(null); }}>Desconectar Windows</button>}
        </> : <>
          <button className="cf-btn primary-btn" onClick={() => { setViewMode('files'); setCurrentPath([]); }}>📁 Arquivos</button>
          <button className="cf-btn danger-btn" disabled={!entries.length} onClick={() => setDialog({ type: 'confirm-empty-trash', title: 'Esvaziar Lixeira', message: 'Apagar permanentemente todos os itens da lixeira desta origem?' })}>🗑️ Esvaziar</button>
        </>}
        <nav className="cf-address" aria-label="Caminho">
          <button className={!currentPath.length && viewMode === 'files' ? 'active-breadcrumb' : ''} onClick={() => { setViewMode('files'); setCurrentPath([]); }}>{pathPrefix}</button>
          {viewMode === 'trash' ? <button className="active-breadcrumb">/ 🗑️ Lixeira</button> : currentPath.map((part, index) => <button key={`${part}-${index}`} className={index === currentPath.length - 1 ? 'active-breadcrumb' : ''} onClick={() => setCurrentPath(currentPath.slice(0, index + 1))}>/ {part}</button>)}
        </nav>
        <input className="cf-search" value={searchQuery} onChange={event => setSearchQuery(event.target.value)} placeholder="Pesquisar…" aria-label="Pesquisar arquivos" />
        <select className="cf-sort-select" value={sortField} onChange={event => setSortField(event.target.value as SortField)} aria-label="Ordenar por"><option value="name">Nome</option><option value="modified">Modificado</option><option value="size">Tamanho</option></select>
        <div className="cf-view-toggle" aria-label="Modo de visualização"><button className={layoutMode === 'grid' ? 'active' : ''} onClick={() => setLayoutMode('grid')} aria-label="Grade">▦</button><button className={layoutMode === 'list' ? 'active' : ''} onClick={() => setLayoutMode('list')} aria-label="Lista">☷</button></div>
      </header>

      {errorMessage && <div className="cf-error" role="alert"><span>⚠️ {errorMessage}</span><button onClick={() => setErrorMessage('')}>×</button></div>}
      {activeOperation && <div className="cf-real-operation" data-operation-status={activeOperation.status}><div><strong>{activeOperation.message}</strong><span>{activeOperation.progress}%</span></div><progress max={100} value={activeOperation.progress} />{['queued', 'running', 'cancelling'].includes(activeOperation.status) && <button className="cf-btn danger-btn" disabled={activeOperation.status === 'cancelling'} onClick={() => void cancelActiveOperation()}>{activeOperation.status === 'cancelling' ? 'Revertendo…' : 'Cancelar'}</button>}</div>}

      <section className="cf-storage-strip" data-storage-provider={source}>
        <div><small>CloudOS Storage</small><strong>{storage.title}</strong></div>
        <span><b>Tipo:</b> {storage.type}</span><span><b>Persistência:</b> {storage.persistence}</span><span><b>Permissão:</b> {storage.permission}</span><span><b>Capacidade:</b> {storage.capacity}</span>
        {source === 'windows' && !runtime.mounted && <button className="cf-btn primary-btn" onClick={() => void changeSource('windows')}>Selecionar pasta do Windows</button>}
        {source === 'wsl' && runtime.available && <span className="cf-real-badge">WSL Core v2</span>}
      </section>

      <div className="cf-workspace">
        <main className={`cf-content ${isDragging ? 'is-dragging' : ''}`} onDragOver={event => { if (viewMode === 'files' && source === 'opfs') { event.preventDefault(); setIsDragging(true); } }} onDragLeave={() => setIsDragging(false)} onDrop={event => { event.preventDefault(); setIsDragging(false); if (viewMode === 'files' && source === 'opfs' && event.dataTransfer.files.length) void handleUpload(event.dataTransfer.files); }}>
          {isDragging && <div className="cf-drop-overlay">Solte os arquivos no armazenamento local do navegador</div>}
          {isLoading ? <div className="cf-empty"><div className="cf-spinner" /><span>Processando {sourceLabel(source)}…</span></div> : visibleEntries.length ? (
            <div className={layoutMode === 'grid' ? 'cf-grid cf-grid--visual' : 'cf-list'} role="list" data-files-view={layoutMode}>
              {visibleEntries.map(entry => {
                const selected = selectedName === entry.name;
                const symlink = entry.kind === 'symlink' || entry.symlink;
                return <article key={`${entry.name}-${entry.trashId || ''}`} className={`cf-item ${selected ? 'selected' : ''} ${symlink ? 'cf-item--symlink' : ''}`} onClick={() => void selectEntry(entry)} onDoubleClick={() => void openEntry(entry)} onContextMenu={event => openEntryContextMenu(event, entry)} onKeyDown={event => { if (event.key === 'Enter') void openEntry(entry); }} role="listitem" tabIndex={0} data-file-kind={entry.kind}>
                  <FileVisual entry={entry} source={source} path={currentPath} fromTrash={viewMode === 'trash'} compact={layoutMode === 'list'} />
                  <div className="cf-item-main"><strong className="cf-name" title={entry.originalName || entry.name}>{entry.originalName || entry.name}</strong><small className="cf-size">{symlink ? 'Link não seguido' : entry.kind === 'directory' ? 'Pasta' : formatBytes(entry.size)}{source === 'wsl' && entry.mode !== undefined ? ` · 0${entry.mode.toString(8)}` : ''}</small></div>
                  <div className="cf-actions">{viewMode === 'files' ? <>
                    <button onClick={event => { event.stopPropagation(); void openEntry(entry); }}>{symlink ? 'Detalhes' : entry.kind === 'directory' ? 'Abrir' : 'Preview'}</button>
                    {entry.kind === 'file' && !symlink && <button onClick={event => { event.stopPropagation(); void downloadEntry(entry); }}>Baixar</button>}
                    <button disabled={Boolean(symlink)} onClick={event => { event.stopPropagation(); setClipboard({ entry, action: 'copy', source, sourcePath: [...currentPath] }); rememberFileCopy(entry); }}>Copiar</button>
                    <button disabled={Boolean(symlink)} onClick={event => { event.stopPropagation(); setClipboard({ entry, action: 'cut', source, sourcePath: [...currentPath] }); }}>Recortar</button>
                    <button disabled={Boolean(symlink)} onClick={event => { event.stopPropagation(); requestRename(entry); }}>Renomear</button>
                    <button disabled={Boolean(symlink)} className="danger" onClick={event => { event.stopPropagation(); requestDelete(entry); }}>Excluir</button>
                  </> : <><button className="primary" onClick={event => { event.stopPropagation(); void restoreEntry(entry); }}>Restaurar</button>{entry.kind === 'file' && source === 'opfs' && <button onClick={event => { event.stopPropagation(); void selectEntry(entry); }}>Preview</button>}<button className="danger" onClick={event => { event.stopPropagation(); requestDelete(entry); }}>Apagar</button></>}</div>
                </article>;
              })}
            </div>
          ) : <div className="cf-empty"><strong>{viewMode === 'trash' ? 'Lixeira vazia' : 'Pasta vazia'}</strong><small>{runtime.mounted ? 'Nenhum item nesta origem.' : 'Conceda acesso explícito para continuar.'}</small></div>}
        </main>
        <FilePreviewPanel entry={selectedEntry} file={previewFile} loading={previewLoading} onClose={() => { setSelectedName(null); setPreviewFile(null); }} onEdit={() => selectedEntry && void openEditor(selectedEntry)} onDownload={() => selectedEntry && void downloadEntry(selectedEntry)} />
      </div>

      <footer className="cf-status"><span>{visibleEntries.length} item(ns){clipboard ? ` · ${clipboard.action === 'cut' ? 'recortado' : 'copiado'}: ${clipboard.entry.name}` : ''}</span><span>{runtime.detail} · {workspaces.filter(item => item.provider === source).length} workspace(s)</span></footer>

      {editor && <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="editor-title"><section className="cf-modal-card"><header className="cf-modal-header"><strong id="editor-title">📝 {editor.name}</strong><button className="cf-modal-close" onClick={() => setEditor(null)}>✕</button></header><textarea className="cf-modal-textarea" value={editor.content} onChange={event => setEditor({ ...editor, content: event.target.value })} aria-label="Conteúdo do arquivo" /><footer className="cf-modal-footer"><button className="cf-btn" onClick={() => setEditor(null)}>Cancelar</button><button className="cf-btn primary-btn" onClick={() => void saveEditor()}>Salvar alterações</button></footer></section></div>}

      {dialog.type && <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><section className="cf-dialog-box"><h2 className="cf-dialog-title" id="dialog-title">{dialog.title}</h2>{dialog.message && <p className="cf-dialog-message">{dialog.message}</p>}
        {(dialog.type === 'create-file' || dialog.type === 'create-folder' || dialog.type === 'rename' || dialog.type === 'workspace') && <input className="cf-dialog-input" autoFocus value={dialogInputValue} onChange={event => setDialogInputValue(event.target.value)} onKeyDown={event => { if (event.key === 'Enter' && dialog.type !== 'workspace') void confirmDialog(); }} placeholder={dialog.type === 'workspace' ? 'Nome do workspace' : undefined} />}
        {dialog.type === 'workspace' && <><select className="cf-dialog-input" value={workspaceType} onChange={event => setWorkspaceType(event.target.value as WorkspaceType)}>{WORKSPACE_TYPES.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select><textarea className="cf-dialog-input" value={workspaceDescription} onChange={event => setWorkspaceDescription(event.target.value)} placeholder="Descrição" /><p className="cf-dialog-message">Provider: {storage.title}. Origem registrada: {currentPath.join('/') || '/'}. Serão criadas as pastas Notes, Downloads, Evidence, Reports, Files, Terminal e Browser, além de workspace.json. Nenhum banco real é usado.</p></>}
        <div className="cf-dialog-actions"><button className="cf-btn" onClick={() => { setDialog({ type: null }); setDialogInputValue(''); }}>Cancelar</button><button className={`cf-btn ${dialog.type?.includes('delete') || dialog.type === 'confirm-empty-trash' ? 'danger-btn' : 'primary-btn'}`} onClick={() => void confirmDialog()}>Confirmar</button></div></section></div>}
    </div>
  );
}