import {
  WORKSPACE_FOLDERS,
  buildWorkspaceManifest,
  createWorkspaceRecord,
  normalizeWorkspaceRecord,
  sanitizeWorkspaceName,
  workspaceFolderName,
  type WorkspaceRecord,
  type WorkspaceType,
  type WorkflowProvider,
} from '../core/workflowCore.js';
import { fileSourceFacade, type CloudFileEntry } from '../apps/CloudOSFiles/fileSourceFacade';

const WORKSPACES_KEY = 'cloudos.workflow.workspaces.v3';
const ACTIVE_WORKSPACE_KEY = 'cloudos.workflow.active-workspace.v3';
const NOTES_INDEX_KEY = 'cloudos.workflow.notes-index.v3';
const FILE_INDEX_KEY = 'cloudos.workflow.file-index.v3';
const DOWNLOAD_DESTINATION_KEY = 'cloudos.workflow.download-destination.v3';
const MAX_WORKSPACES = 100;
const MAX_NOTE_BYTES = 2 * 1024 * 1024;
const MAX_FILE_INDEX = 800;

export type { WorkspaceRecord, WorkspaceType, WorkflowProvider };

export type WorkflowNote = {
  workspaceId: string;
  fileName: string;
  title: string;
  content: string;
  modified: number;
};

export type NoteIndexEntry = {
  workspaceId: string;
  fileName: string;
  title: string;
  updatedAt: string;
};

export type IndexedFile = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
  kind: CloudFileEntry['kind'];
  modified: number;
};

export type DownloadDestination =
  | { kind: 'workspace'; workspaceId: string }
  | { kind: 'opfs' }
  | { kind: 'windows' }
  | { kind: 'wsl' };

function storageAvailable() {
  return typeof localStorage !== 'undefined';
}

function emitChanged() {
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
}

function safeJson<T>(key: string, fallback: T): T {
  if (!storageAvailable()) return fallback;
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || 'null');
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function writeJson(key: string, value: unknown) {
  if (!storageAvailable()) return;
  localStorage.setItem(key, JSON.stringify(value));
}

function samePath(left: string[], right: string[]) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

async function ensureDirectory(provider: WorkflowProvider, path: string[], name: string) {
  const entries = await fileSourceFacade.list(provider, path, false);
  const existing = entries.find(entry => entry.name === name);
  if (existing) {
    if (existing.kind !== 'directory') throw new Error(`“${name}” já existe e não é uma pasta.`);
    return name;
  }
  return await fileSourceFacade.create(provider, path, 'directory', name);
}

function persistedWorkspaces() {
  const raw = safeJson<unknown[]>(WORKSPACES_KEY, []);
  const output: WorkspaceRecord[] = [];
  for (const candidate of Array.isArray(raw) ? raw : []) {
    const normalized = normalizeWorkspaceRecord(candidate);
    if (normalized) output.push(normalized);
    if (output.length >= MAX_WORKSPACES) break;
  }
  return output;
}

export function listWorkspaces() {
  return persistedWorkspaces().sort((left, right) => Date.parse(right.lastAccessAt) - Date.parse(left.lastAccessAt));
}

export function getWorkspace(id: string | null | undefined) {
  if (!id) return null;
  return persistedWorkspaces().find(item => item.id === id) || null;
}

export function getActiveWorkspace() {
  const id = storageAvailable() ? localStorage.getItem(ACTIVE_WORKSPACE_KEY) : null;
  return getWorkspace(id) || listWorkspaces()[0] || null;
}

function saveWorkspaceList(items: WorkspaceRecord[]) {
  writeJson(WORKSPACES_KEY, items.slice(0, MAX_WORKSPACES));
  emitChanged();
}

export async function activateWorkspace(id: string) {
  const workspace = getWorkspace(id);
  if (!workspace) throw new Error('Workspace não encontrado.');
  if (storageAvailable()) localStorage.setItem(ACTIVE_WORKSPACE_KEY, workspace.id);
  await touchWorkspace(workspace.id);
  emitChanged();
  return getWorkspace(workspace.id) || workspace;
}

export async function touchWorkspace(id: string) {
  const items = persistedWorkspaces();
  const index = items.findIndex(item => item.id === id);
  if (index < 0) return null;
  const updated: WorkspaceRecord = { ...items[index], lastAccessAt: new Date().toISOString() };
  items[index] = updated;
  saveWorkspaceList(items);
  try {
    const runtime = await fileSourceFacade.runtime(updated.provider);
    if (runtime.available && runtime.mounted) {
      await fileSourceFacade.writeText(updated.provider, updated.root, 'workspace.json', JSON.stringify(buildWorkspaceManifest(updated), null, 2));
    }
  } catch {
    // A metadata touch must not request a new Windows grant or change runtime state.
  }
  return updated;
}

export async function createWorkspace(input: {
  type: WorkspaceType;
  name: string;
  description?: string;
  provider: WorkflowProvider;
  originPath?: string[];
}) {
  const runtime = await fileSourceFacade.runtime(input.provider);
  if (!runtime.available || !runtime.mounted) {
    throw new Error(input.provider === 'windows'
      ? 'Selecione uma pasta do Windows antes de criar o workspace.'
      : `${runtime.label} não está disponível nesta sessão.`);
  }

  const id = crypto.randomUUID();
  const name = sanitizeWorkspaceName(input.name);
  const originPath = Array.isArray(input.originPath) ? [...input.originPath] : [];
  await ensureDirectory(input.provider, [], 'Workspaces');
  const folder = workspaceFolderName(name, id);
  const rootName = await fileSourceFacade.create(input.provider, ['Workspaces'], 'directory', folder);
  const root = ['Workspaces', rootName];
  let rootEntry: CloudFileEntry | null = null;

  try {
    for (const child of WORKSPACE_FOLDERS) await ensureDirectory(input.provider, root, child);
    const workspace = createWorkspaceRecord({
      id,
      type: input.type,
      name,
      description: input.description || '',
      provider: input.provider,
      root,
      originPath,
    });
    if (!workspace) throw new Error('Metadados do workspace foram rejeitados.');
    await fileSourceFacade.writeText(input.provider, root, 'workspace.json', JSON.stringify(buildWorkspaceManifest(workspace), null, 2));
    const items = [workspace, ...persistedWorkspaces().filter(item => item.id !== workspace.id)].slice(0, MAX_WORKSPACES);
    saveWorkspaceList(items);
    if (storageAvailable()) localStorage.setItem(ACTIVE_WORKSPACE_KEY, workspace.id);
    emitChanged();
    return workspace;
  } catch (error) {
    try {
      const parentEntries = await fileSourceFacade.list(input.provider, ['Workspaces'], false);
      rootEntry = parentEntries.find(entry => entry.name === rootName) || null;
      if (rootEntry) await fileSourceFacade.trash(input.provider, ['Workspaces'], rootEntry);
    } catch {
      // Preserve the original failure. A partial workspace remains visible for manual recovery if rollback fails.
    }
    throw error;
  }
}

export function removeWorkspaceFromIndex(id: string) {
  const items = persistedWorkspaces().filter(item => item.id !== id);
  saveWorkspaceList(items);
  if (storageAvailable() && localStorage.getItem(ACTIVE_WORKSPACE_KEY) === id) localStorage.removeItem(ACTIVE_WORKSPACE_KEY);
  const notes = listNoteIndex().filter(item => item.workspaceId !== id);
  writeJson(NOTES_INDEX_KEY, notes);
  emitChanged();
}

function noteTitle(fileName: string) {
  return fileName.replace(/\.md$/i, '').replace(/[-_]+/g, ' ').trim() || 'Nota';
}

export async function listWorkspaceNotes(workspace: WorkspaceRecord): Promise<WorkflowNote[]> {
  const entries = await fileSourceFacade.list(workspace.provider, [...workspace.root, 'Notes'], false);
  const notes: WorkflowNote[] = [];
  for (const entry of entries) {
    if (entry.kind !== 'file' || entry.symlink || !entry.name.toLowerCase().endsWith('.md') || entry.size > MAX_NOTE_BYTES) continue;
    try {
      const file = await fileSourceFacade.readFile(workspace.provider, [...workspace.root, 'Notes'], entry, MAX_NOTE_BYTES);
      notes.push({
        workspaceId: workspace.id,
        fileName: entry.name,
        title: noteTitle(entry.name),
        content: await file.text(),
        modified: entry.modified,
      });
    } catch {
      // One damaged note must not hide the rest of the workspace.
    }
  }
  notes.sort((left, right) => right.modified - left.modified || left.title.localeCompare(right.title));
  indexNotes(notes);
  return notes;
}

function sanitizeNoteFileName(title: string) {
  const base = sanitizeWorkspaceName(title).replace(/\.[^.]+$/g, '').slice(0, 72) || 'Nota';
  return `${base}.md`;
}

export async function createWorkspaceNote(workspace: WorkspaceRecord, title = 'Nova Nota') {
  const requested = sanitizeNoteFileName(title);
  const fileName = await fileSourceFacade.create(workspace.provider, [...workspace.root, 'Notes'], 'file', requested);
  const content = `# ${noteTitle(fileName)}\n\n`;
  await fileSourceFacade.writeText(workspace.provider, [...workspace.root, 'Notes'], fileName, content);
  const note: WorkflowNote = { workspaceId: workspace.id, fileName, title: noteTitle(fileName), content, modified: Date.now() };
  indexNotes([note]);
  await touchWorkspace(workspace.id);
  return note;
}

export async function saveWorkspaceNote(workspace: WorkspaceRecord, note: Pick<WorkflowNote, 'fileName' | 'content'>) {
  if (!note.fileName.toLowerCase().endsWith('.md')) throw new Error('Notes aceita somente Markdown (.md).');
  const bytes = new TextEncoder().encode(note.content).byteLength;
  if (bytes > MAX_NOTE_BYTES) throw new Error('Nota excede o limite de 2 MiB.');
  await fileSourceFacade.writeText(workspace.provider, [...workspace.root, 'Notes'], note.fileName, note.content);
  const indexed: WorkflowNote = {
    workspaceId: workspace.id,
    fileName: note.fileName,
    title: noteTitle(note.fileName),
    content: note.content,
    modified: Date.now(),
  };
  indexNotes([indexed]);
  await touchWorkspace(workspace.id);
  return indexed;
}

function indexNotes(notes: WorkflowNote[]) {
  const existing = listNoteIndex();
  const byKey = new Map(existing.map(item => [`${item.workspaceId}:${item.fileName}`, item]));
  for (const note of notes) {
    byKey.set(`${note.workspaceId}:${note.fileName}`, {
      workspaceId: note.workspaceId,
      fileName: note.fileName,
      title: note.title,
      updatedAt: new Date(note.modified || Date.now()).toISOString(),
    });
  }
  const next = [...byKey.values()]
    .sort((left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt))
    .slice(0, 500);
  writeJson(NOTES_INDEX_KEY, next);
  emitChanged();
}

export function listNoteIndex(): NoteIndexEntry[] {
  const raw = safeJson<unknown[]>(NOTES_INDEX_KEY, []);
  return (Array.isArray(raw) ? raw : [])
    .filter((item: any) => item && typeof item.workspaceId === 'string' && typeof item.fileName === 'string' && typeof item.title === 'string')
    .map((item: any) => ({
      workspaceId: item.workspaceId,
      fileName: item.fileName,
      title: item.title.slice(0, 120),
      updatedAt: Number.isFinite(Date.parse(item.updatedAt)) ? new Date(item.updatedAt).toISOString() : new Date(0).toISOString(),
    }));
}

export async function listWorkspaceEvidence(workspace: WorkspaceRecord) {
  return fileSourceFacade.list(workspace.provider, [...workspace.root, 'Evidence'], false);
}

export async function saveWorkspaceEvidenceText(workspace: WorkspaceRecord, kind: 'note' | 'log' | 'link', value: string) {
  const text = String(value || '').trim();
  if (!text) throw new Error('Informe o conteúdo da evidência.');
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const extension = kind === 'log' ? 'log' : 'md';
  const requested = `${kind}-${stamp}.${extension}`;
  const fileName = await fileSourceFacade.create(workspace.provider, [...workspace.root, 'Evidence'], 'file', requested);
  const body = kind === 'link'
    ? `# Link\n\n${text}\n\nRegistrado em ${new Date().toISOString()}\n`
    : kind === 'note'
      ? `# Nota de evidência\n\n${text}\n`
      : text;
  await fileSourceFacade.writeText(workspace.provider, [...workspace.root, 'Evidence'], fileName, body);
  await touchWorkspace(workspace.id);
  return fileName;
}

export async function saveWorkspaceEvidenceFile(workspace: WorkspaceRecord, file: File) {
  const result = await fileSourceFacade.writeFile(workspace.provider, [...workspace.root, 'Evidence'], file);
  await touchWorkspace(workspace.id);
  return result;
}

export function indexFiles(provider: WorkflowProvider, path: string[], entries: CloudFileEntry[]) {
  const existing = listIndexedFiles();
  const currentPrefix = `${provider}:${path.join('/')}:`;
  const retained = existing.filter(item => !`${item.provider}:${item.path.join('/')}:`.startsWith(currentPrefix));
  const incoming: IndexedFile[] = entries.slice(0, 300).map(entry => ({
    provider,
    path: [...path],
    name: entry.name,
    kind: entry.kind,
    modified: entry.modified,
  }));
  writeJson(FILE_INDEX_KEY, [...incoming, ...retained].slice(0, MAX_FILE_INDEX));
  emitChanged();
}

export function listIndexedFiles(): IndexedFile[] {
  const raw = safeJson<unknown[]>(FILE_INDEX_KEY, []);
  const output: IndexedFile[] = [];
  for (const item of Array.isArray(raw) ? raw : []) {
    const provider = (item as any)?.provider;
    if (!['opfs', 'windows', 'wsl'].includes(provider)) continue;
    if (typeof (item as any)?.name !== 'string' || !Array.isArray((item as any)?.path)) continue;
    output.push({
      provider,
      path: (item as any).path.map(String).slice(0, 64),
      name: (item as any).name.slice(0, 140),
      kind: ['file', 'directory', 'symlink'].includes((item as any).kind) ? (item as any).kind : 'file',
      modified: Number((item as any).modified) || 0,
    });
    if (output.length >= MAX_FILE_INDEX) break;
  }
  return output;
}

export function setDownloadDestination(destination: DownloadDestination) {
  if (destination.kind === 'workspace' && !getWorkspace(destination.workspaceId)) throw new Error('Workspace de download não encontrado.');
  writeJson(DOWNLOAD_DESTINATION_KEY, destination);
  emitChanged();
}

export function getDownloadDestination(): DownloadDestination {
  const raw = safeJson<any>(DOWNLOAD_DESTINATION_KEY, { kind: 'opfs' });
  if (raw?.kind === 'workspace' && typeof raw.workspaceId === 'string' && getWorkspace(raw.workspaceId)) return { kind: 'workspace', workspaceId: raw.workspaceId };
  if (['opfs', 'windows', 'wsl'].includes(raw?.kind)) return { kind: raw.kind } as DownloadDestination;
  return { kind: 'opfs' };
}

export function workspacePath(workspace: WorkspaceRecord, child: typeof WORKSPACE_FOLDERS[number]) {
  return [...workspace.root, child];
}

export function workspaceMatchesLocation(workspace: WorkspaceRecord, provider: WorkflowProvider, path: string[]) {
  return workspace.provider === provider && samePath(workspace.root, path);
}
