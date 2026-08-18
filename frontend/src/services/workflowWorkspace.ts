import {
  WORKSPACE_FOLDERS,
  buildWorkspaceManifest,
  createWorkspaceRecord,
  matchesWorkflowQuery,
  normalizeWorkspaceRecord,
  sanitizeWorkspaceName,
  sanitizeWorkspaceTags,
  workspaceFolderName,
  workspaceSearchText,
  type WorkspaceRecord,
  type WorkspaceStatus,
  type WorkspaceType,
  type WorkflowProvider,
} from '../core/workflowCore.js';
import { fileSourceFacade, MAX_ASSISTED_TRANSFER_BYTES, type CloudFileEntry } from '../apps/CloudOSFiles/fileSourceFacade';

const WORKSPACES_KEY = 'cloudos.workflow.workspaces.v3';
const ACTIVE_WORKSPACE_KEY = 'cloudos.workflow.active-workspace.v3';
const NOTES_INDEX_KEY = 'cloudos.workflow.notes-index.v3';
const FILE_INDEX_KEY = 'cloudos.workflow.file-index.v3';
const DOWNLOAD_DESTINATION_KEY = 'cloudos.workflow.download-destination.v3';
export const MAX_WORKSPACES = 1000;
export const MAX_NOTE_BYTES = 2 * 1024 * 1024;
export const MAX_NOTE_INDEX_ENTRIES = 200;
export const MAX_NOTE_INDEX_CONTENT_CHARS = 8192;
const MAX_FILE_INDEX = 800;
const MAX_DUPLICATE_ENTRIES = 2000;
const MAX_DUPLICATE_BYTES = 1024 * 1024 * 1024;
const noteSaveChains = new Map<string, Promise<void>>();

export type { WorkspaceRecord, WorkspaceStatus, WorkspaceType, WorkflowProvider };

export type WorkflowNoteMeta = {
  workspaceId: string;
  fileName: string;
  title: string;
  modified: number;
  size: number;
};

export type WorkflowNoteContent = WorkflowNoteMeta & {
  content: string;
};

// Compatibility name used by lightweight consumers that only need note metadata.
export type WorkflowNote = WorkflowNoteMeta;

export type WorkflowNoteSearchHit = {
  fileName: string;
  start: number;
  end: number;
  snippet: string;
};

export type WorkflowNoteSearchResult = {
  fileNames: string[];
  hits: WorkflowNoteSearchHit[];
};

export type NoteIndexEntry = {
  workspaceId: string;
  fileName: string;
  title: string;
  searchText: string;
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
  }
  return output;
}

export function listWorkspaces() {
  return persistedWorkspaces().sort((left, right) => Date.parse(right.lastActivityAt) - Date.parse(left.lastActivityAt) || Date.parse(right.lastAccessAt) - Date.parse(left.lastAccessAt));
}

export function searchWorkspaces(query: string, includeArchived = true) {
  return listWorkspaces().filter(workspace => (includeArchived || workspace.status !== 'archived') && matchesWorkflowQuery(workspaceSearchText(workspace), query));
}

export function getWorkspace(id: string | null | undefined) {
  if (!id) return null;
  return persistedWorkspaces().find(item => item.id === id) || null;
}

export function getActiveWorkspace() {
  const id = storageAvailable() ? localStorage.getItem(ACTIVE_WORKSPACE_KEY) : null;
  const indexed = getWorkspace(id);
  if (indexed && indexed.status !== 'archived') return indexed;
  return listWorkspaces().find(item => item.status !== 'archived') || null;
}

function saveWorkspaceList(items: WorkspaceRecord[]) {
  // Never truncate an existing catalog. Capacity is enforced before admitting a new Workspace.
  writeJson(WORKSPACES_KEY, items);
  emitChanged();
}

function assertWorkspaceCapacityForCreate() {
  const count = persistedWorkspaces().length;
  if (count >= MAX_WORKSPACES) {
    throw new Error(`Limite de ${MAX_WORKSPACES} Workspaces atingido. Nenhum Workspace existente foi descartado.`);
  }
}

async function writeWorkspaceManifest(workspace: WorkspaceRecord) {
  const runtime = await fileSourceFacade.runtime(workspace.provider);
  if (!runtime.available || !runtime.mounted) throw new Error(`${runtime.label} não está disponível nesta sessão.`);
  await fileSourceFacade.writeText(workspace.provider, workspace.root, 'workspace.json', JSON.stringify(buildWorkspaceManifest(workspace), null, 2));
}

async function persistWorkspaceRecord(workspace: WorkspaceRecord, writeManifest = true) {
  const normalized = normalizeWorkspaceRecord(workspace);
  if (!normalized) throw new Error('Metadados do workspace foram rejeitados.');
  const items = persistedWorkspaces();
  const index = items.findIndex(item => item.id === normalized.id);
  if (index < 0) throw new Error('Workspace não encontrado.');
  if (writeManifest) await writeWorkspaceManifest(normalized);
  items[index] = normalized;
  saveWorkspaceList(items);
  return normalized;
}

export async function activateWorkspace(id: string) {
  const workspace = getWorkspace(id);
  if (!workspace) throw new Error('Workspace não encontrado.');
  if (workspace.status === 'archived') throw new Error('Workspace arquivado. Reative-o antes de usar.');
  if (storageAvailable()) localStorage.setItem(ACTIVE_WORKSPACE_KEY, workspace.id);
  await touchWorkspace(workspace.id, false);
  emitChanged();
  return getWorkspace(workspace.id) || workspace;
}

export async function touchWorkspace(id: string, activity = true) {
  const items = persistedWorkspaces();
  const index = items.findIndex(item => item.id === id);
  if (index < 0) return null;
  const now = new Date().toISOString();
  const updated: WorkspaceRecord = {
    ...items[index],
    lastAccessAt: now,
    lastActivityAt: activity ? now : items[index].lastActivityAt,
  };
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
  client?: string;
  tags?: string[];
  provider: WorkflowProvider;
  originPath?: string[];
}) {
  // Capacity is checked before any provider mount, directory or manifest is created.
  assertWorkspaceCapacityForCreate();

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
      client: input.client || '',
      tags: sanitizeWorkspaceTags(input.tags || []),
      provider: input.provider,
      root,
      originPath,
    });
    if (!workspace) throw new Error('Metadados do workspace foram rejeitados.');
    await fileSourceFacade.writeText(input.provider, root, 'workspace.json', JSON.stringify(buildWorkspaceManifest(workspace), null, 2));
    const items = [workspace, ...persistedWorkspaces().filter(item => item.id !== workspace.id)];
    if (items.length > MAX_WORKSPACES) {
      throw new Error(`Limite de ${MAX_WORKSPACES} Workspaces atingido durante a criação. Nenhum Workspace existente foi descartado.`);
    }
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

export async function updateWorkspaceMetadata(id: string, patch: {
  name?: string;
  description?: string;
  client?: string;
  tags?: string[];
  type?: WorkspaceType;
}) {
  const current = getWorkspace(id);
  if (!current) throw new Error('Workspace não encontrado.');
  const now = new Date().toISOString();
  const updated = normalizeWorkspaceRecord({
    ...current,
    ...(patch.name !== undefined ? { name: sanitizeWorkspaceName(patch.name) } : {}),
    ...(patch.description !== undefined ? { description: patch.description } : {}),
    ...(patch.client !== undefined ? { client: patch.client } : {}),
    ...(patch.tags !== undefined ? { tags: sanitizeWorkspaceTags(patch.tags) } : {}),
    ...(patch.type !== undefined ? { type: patch.type } : {}),
    lastAccessAt: now,
    lastActivityAt: now,
  });
  if (!updated) throw new Error('Metadados do workspace foram rejeitados.');
  // Rename is metadata-only by design: the physical root remains stable and no tree is recreated.
  return persistWorkspaceRecord(updated, true);
}

export async function renameWorkspace(id: string, name: string) {
  return updateWorkspaceMetadata(id, { name });
}

export async function archiveWorkspace(id: string, archived = true) {
  const current = getWorkspace(id);
  if (!current) throw new Error('Workspace não encontrado.');
  const now = new Date().toISOString();
  const updated = normalizeWorkspaceRecord({
    ...current,
    status: archived ? 'archived' : 'active',
    lastAccessAt: now,
    lastActivityAt: now,
  });
  if (!updated) throw new Error('Metadados do workspace foram rejeitados.');
  const saved = await persistWorkspaceRecord(updated, true);
  if (storageAvailable() && archived && localStorage.getItem(ACTIVE_WORKSPACE_KEY) === id) {
    localStorage.removeItem(ACTIVE_WORKSPACE_KEY);
  }
  emitChanged();
  return saved;
}

async function copyWorkspaceTree(
  source: WorkspaceRecord,
  destination: WorkspaceRecord,
  sourcePath: string[],
  destinationPath: string[],
  budget: { entries: number; bytes: number },
) {
  const entries = await fileSourceFacade.list(source.provider, sourcePath, false);
  for (const entry of entries) {
    if (entry.name === 'workspace.json' && sourcePath.length === source.root.length) continue;
    if (entry.symlink || entry.kind === 'symlink') throw new Error(`Duplicação interrompida: “${entry.name}” é link simbólico e não será seguido.`);
    budget.entries += 1;
    if (budget.entries > MAX_DUPLICATE_ENTRIES) throw new Error(`Workspace excede o limite de duplicação de ${MAX_DUPLICATE_ENTRIES} itens.`);
    if (entry.kind === 'directory') {
      const created = await fileSourceFacade.create(destination.provider, destinationPath, 'directory', entry.name);
      await copyWorkspaceTree(source, destination, [...sourcePath, entry.name], [...destinationPath, created], budget);
      continue;
    }
    budget.bytes += entry.size;
    if (entry.size > MAX_ASSISTED_TRANSFER_BYTES) throw new Error(`“${entry.name}” excede o limite de ${MAX_ASSISTED_TRANSFER_BYTES} bytes por arquivo.`);
    if (budget.bytes > MAX_DUPLICATE_BYTES) throw new Error(`Workspace excede o limite de duplicação de ${MAX_DUPLICATE_BYTES} bytes.`);
    const file = await fileSourceFacade.readFile(source.provider, sourcePath, entry, MAX_ASSISTED_TRANSFER_BYTES);
    await fileSourceFacade.writeFile(destination.provider, destinationPath, new File([file], entry.name, { type: file.type, lastModified: file.lastModified }), entry.mode);
  }
}

export async function duplicateWorkspace(id: string) {
  const source = getWorkspace(id);
  if (!source) throw new Error('Workspace não encontrado.');
  const runtime = await fileSourceFacade.runtime(source.provider);
  if (!runtime.available || !runtime.mounted) throw new Error(`${runtime.label} não está disponível para duplicação.`);
  const destination = await createWorkspace({
    type: source.type,
    name: `${source.name} — cópia`,
    description: source.description,
    client: source.client,
    tags: source.tags,
    provider: source.provider,
    originPath: source.originPath,
  });
  try {
    const budget = { entries: 0, bytes: 0 };
    for (const folder of WORKSPACE_FOLDERS) {
      await copyWorkspaceTree(source, destination, [...source.root, folder], [...destination.root, folder], budget);
    }
    await touchWorkspace(destination.id, true);
    return getWorkspace(destination.id) || destination;
  } catch (error) {
    removeWorkspaceFromIndex(destination.id);
    try {
      const parents = await fileSourceFacade.list(destination.provider, ['Workspaces'], false);
      const rootEntry = parents.find(entry => entry.name === destination.root[destination.root.length - 1]);
      if (rootEntry) await fileSourceFacade.trash(destination.provider, ['Workspaces'], rootEntry);
    } catch {
      // Fail closed: never hide the original error if cleanup cannot be completed.
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

function noteMeta(workspace: WorkspaceRecord, entry: CloudFileEntry): WorkflowNoteMeta {
  return {
    workspaceId: workspace.id,
    fileName: entry.name,
    title: noteTitle(entry.name),
    modified: entry.modified,
    size: entry.size,
  };
}

function validNoteEntry(entry: CloudFileEntry) {
  return entry.kind === 'file'
    && !entry.symlink
    && entry.name.toLowerCase().endsWith('.md')
    && entry.size <= MAX_NOTE_BYTES;
}

export async function listWorkspaceNotes(workspace: WorkspaceRecord): Promise<WorkflowNoteMeta[]> {
  const entries = await fileSourceFacade.list(workspace.provider, [...workspace.root, 'Notes'], false);
  return entries
    .filter(validNoteEntry)
    .map(entry => noteMeta(workspace, entry))
    .sort((left, right) => right.modified - left.modified || left.title.localeCompare(right.title));
}

export async function loadWorkspaceNote(workspace: WorkspaceRecord, note: WorkflowNoteMeta | string): Promise<WorkflowNoteContent> {
  const fileName = typeof note === 'string' ? note : note.fileName;
  const entries = await fileSourceFacade.list(workspace.provider, [...workspace.root, 'Notes'], false);
  const entry = entries.find(item => item.name === fileName);
  if (!entry || !validNoteEntry(entry)) throw new Error('Nota não encontrada, inválida ou acima do limite de 2 MiB.');
  const file = await fileSourceFacade.readFile(workspace.provider, [...workspace.root, 'Notes'], entry, MAX_NOTE_BYTES);
  const document: WorkflowNoteContent = {
    ...noteMeta(workspace, entry),
    content: await file.text(),
  };
  indexNotes([document]);
  return document;
}

function collectTextHits(fileName: string, text: string, query: string, limit: number): WorkflowNoteSearchHit[] {
  if (limit <= 0) return [];
  const needle = query.trim().toLocaleLowerCase('pt-BR');
  if (!needle) return [];
  const haystack = text.toLocaleLowerCase('pt-BR');
  const hits: WorkflowNoteSearchHit[] = [];
  let offset = 0;
  while (hits.length < limit) {
    const start = haystack.indexOf(needle, offset);
    if (start < 0) break;
    const end = start + needle.length;
    const snippetStart = Math.max(0, start - 45);
    const snippetEnd = Math.min(text.length, end + 70);
    hits.push({
      fileName,
      start,
      end,
      snippet: text.slice(snippetStart, snippetEnd).replace(/\s+/g, ' ').trim(),
    });
    offset = Math.max(end, start + 1);
  }
  return hits;
}

export async function searchWorkspaceNotes(
  workspace: WorkspaceRecord,
  notes: WorkflowNoteMeta[],
  query: string,
  options: {
    limit?: number;
    cancelled?: () => boolean;
    activeDocument?: { fileName: string; content: string } | null;
  } = {},
): Promise<WorkflowNoteSearchResult> {
  const needle = query.trim().toLocaleLowerCase('pt-BR');
  if (!needle) return { fileNames: [], hits: [] };

  const limit = Math.max(1, Math.min(1000, Math.floor(options.limit ?? 100)));
  const cancelled = options.cancelled || (() => false);
  const matched = new Set<string>();
  const hits: WorkflowNoteSearchHit[] = [];
  const entries = await fileSourceFacade.list(workspace.provider, [...workspace.root, 'Notes'], false);
  const byName = new Map(entries.filter(validNoteEntry).map(entry => [entry.name, entry]));

  for (const meta of notes) {
    if (cancelled()) break;
    const titleMatches = meta.title.toLocaleLowerCase('pt-BR').includes(needle);
    const activeOverride = options.activeDocument?.fileName === meta.fileName ? options.activeDocument.content : null;
    let content = activeOverride;

    if (content === null) {
      const entry = byName.get(meta.fileName);
      if (!entry) {
        if (titleMatches) matched.add(meta.fileName);
        continue;
      }
      const file = await fileSourceFacade.readFile(workspace.provider, [...workspace.root, 'Notes'], entry, MAX_NOTE_BYTES);
      if (cancelled()) break;
      content = await file.text();
    }

    if (cancelled()) break;
    const contentMatches = content.toLocaleLowerCase('pt-BR').includes(needle);
    if (titleMatches || contentMatches) matched.add(meta.fileName);
    if (contentMatches && hits.length < limit) {
      hits.push(...collectTextHits(meta.fileName, content, query, limit - hits.length));
    }
    content = '';
  }

  return { fileNames: [...matched], hits };
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
  const note: WorkflowNoteContent = {
    workspaceId: workspace.id,
    fileName,
    title: noteTitle(fileName),
    content,
    modified: Date.now(),
    size: new TextEncoder().encode(content).byteLength,
  };
  indexNotes([note]);
  await touchWorkspace(workspace.id, true);
  return note;
}

export async function saveWorkspaceNote(workspace: WorkspaceRecord, note: Pick<WorkflowNoteContent, 'fileName' | 'content'>) {
  if (!note.fileName.toLowerCase().endsWith('.md')) throw new Error('Notes aceita somente Markdown (.md).');
  const bytes = new TextEncoder().encode(note.content).byteLength;
  if (bytes > MAX_NOTE_BYTES) throw new Error('Nota excede o limite de 2 MiB.');

  const key = `${workspace.id}:${note.fileName}`;
  const previous = noteSaveChains.get(key) || Promise.resolve();
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const chain = previous.catch(() => undefined).then(() => gate);
  noteSaveChains.set(key, chain);

  await previous.catch(() => undefined);
  try {
    await fileSourceFacade.writeText(workspace.provider, [...workspace.root, 'Notes'], note.fileName, note.content);
    const indexed: WorkflowNoteContent = {
      workspaceId: workspace.id,
      fileName: note.fileName,
      title: noteTitle(note.fileName),
      content: note.content,
      modified: Date.now(),
      size: bytes,
    };
    indexNotes([indexed]);
    await touchWorkspace(workspace.id, true);
    return indexed;
  } finally {
    release();
    if (noteSaveChains.get(key) === chain) noteSaveChains.delete(key);
  }
}

function indexNotes(notes: WorkflowNoteContent[]) {
  const existing = listNoteIndex();
  const byKey = new Map(existing.map(item => [`${item.workspaceId}:${item.fileName}`, item]));
  for (const note of notes) {
    byKey.set(`${note.workspaceId}:${note.fileName}`, {
      workspaceId: note.workspaceId,
      fileName: note.fileName,
      title: note.title,
      searchText: note.content.slice(0, MAX_NOTE_INDEX_CONTENT_CHARS),
      updatedAt: new Date(note.modified || Date.now()).toISOString(),
    });
  }
  const next = [...byKey.values()]
    .sort((left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt))
    .slice(0, MAX_NOTE_INDEX_ENTRIES);
  if (JSON.stringify(next) === JSON.stringify(existing)) return;
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
      searchText: String(item.searchText || '').slice(0, MAX_NOTE_INDEX_CONTENT_CHARS),
      updatedAt: Number.isFinite(Date.parse(item.updatedAt)) ? new Date(item.updatedAt).toISOString() : new Date(0).toISOString(),
    }))
    .slice(0, MAX_NOTE_INDEX_ENTRIES);
}

export function searchNoteIndex(query: string) {
  return listNoteIndex().filter(note => matchesWorkflowQuery(`${note.title}\n${note.searchText}`, query));
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
  await touchWorkspace(workspace.id, true);
  return fileName;
}

export async function saveWorkspaceEvidenceFile(workspace: WorkspaceRecord, file: File) {
  const result = await fileSourceFacade.writeFile(workspace.provider, [...workspace.root, 'Evidence'], file);
  await touchWorkspace(workspace.id, true);
  return result;
}

export async function addFileToActiveWorkspaceEvidence(provider: WorkflowProvider, path: string[], name: string) {
  const workspace = getActiveWorkspace();
  if (!workspace) throw new Error('Ative um Workspace antes de adicionar evidência.');
  const sourceEntries = await fileSourceFacade.list(provider, path, false);
  const entry = sourceEntries.find(item => item.name === name);
  if (!entry || entry.kind !== 'file' || entry.symlink) throw new Error('A evidência deve ser um arquivo regular visível nesta origem.');
  if (entry.size > MAX_ASSISTED_TRANSFER_BYTES) throw new Error(`Arquivo excede o limite de evidência de ${MAX_ASSISTED_TRANSFER_BYTES} bytes.`);
  const destinationPath = [...workspace.root, 'Evidence'];
  const destinationEntries = await fileSourceFacade.list(workspace.provider, destinationPath, false);
  if (destinationEntries.some(item => item.name === entry.name)) throw new Error(`Evidence já contém “${entry.name}”. Nenhum arquivo foi sobrescrito.`);
  if (provider === workspace.provider) {
    const file = await fileSourceFacade.readFile(provider, path, entry, MAX_ASSISTED_TRANSFER_BYTES);
    await fileSourceFacade.writeFile(workspace.provider, destinationPath, new File([file], entry.name, { type: file.type, lastModified: file.lastModified }), entry.mode);
  } else {
    await fileSourceFacade.copyAcrossProviders(provider, path, entry, workspace.provider, destinationPath);
  }
  await touchWorkspace(workspace.id, true);
  return { workspace, name: entry.name };
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
  if (storageAvailable() && localStorage.getItem(DOWNLOAD_DESTINATION_KEY) === null) {
    const active = getActiveWorkspace();
    return active ? { kind: 'workspace', workspaceId: active.id } : { kind: 'opfs' };
  }
  const raw = safeJson<any>(DOWNLOAD_DESTINATION_KEY, null);
  if (raw?.kind === 'workspace' && typeof raw.workspaceId === 'string' && getWorkspace(raw.workspaceId)) return { kind: 'workspace', workspaceId: raw.workspaceId };
  if (['opfs', 'windows', 'wsl'].includes(raw?.kind)) return { kind: raw.kind } as DownloadDestination;
  const active = getActiveWorkspace();
  return active ? { kind: 'workspace', workspaceId: active.id } : { kind: 'opfs' };
}

export function downloadDestinationLabel(destination: DownloadDestination) {
  if (destination.kind === 'workspace') {
    const workspace = getWorkspace(destination.workspaceId);
    return workspace ? `Workspace “${workspace.name}” / Downloads` : 'Workspace indisponível';
  }
  if (destination.kind === 'windows') return 'Windows — pasta autorizada';
  if (destination.kind === 'wsl') return 'Linux — Home';
  return 'OPFS — CloudOS';
}

export function workspacePath(workspace: WorkspaceRecord, child: typeof WORKSPACE_FOLDERS[number]) {
  return [...workspace.root, child];
}

export function workspaceMatchesLocation(workspace: WorkspaceRecord, provider: WorkflowProvider, path: string[]) {
  return workspace.provider === provider && samePath(workspace.root, path);
}
