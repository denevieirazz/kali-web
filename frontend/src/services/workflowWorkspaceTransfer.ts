import { WORKSPACE_FOLDERS, type WorkflowProvider } from '../core/workflowCore.js';
import { fileSourceFacade, type CloudFileEntry } from '../apps/CloudOSFiles/fileSourceFacade';
import {
  activateWorkspace,
  archiveWorkspace,
  createWorkspace,
  getWorkspace,
  removeWorkspaceFromIndex,
  type WorkspaceRecord,
  type WorkspaceType,
} from './workflowWorkspace';

export const WORKSPACE_EXPORT_SCHEMA = 'cloudos-workspace-export/v1';
export const MAX_WORKSPACE_EXPORT_ENTRIES = 2000;
export const MAX_WORKSPACE_EXPORT_BYTES = 64 * 1024 * 1024;
export const MAX_WORKSPACE_EXPORT_FILE_BYTES = 16 * 1024 * 1024;
export const MAX_WORKSPACE_IMPORT_JSON_BYTES = 96 * 1024 * 1024;

type PortableWorkspaceEntry = {
  path: string[];
  kind: 'directory' | 'file';
  contentBase64?: string;
  type?: string;
  modified?: number;
  mode?: number;
};

type PortableWorkspace = {
  schema: typeof WORKSPACE_EXPORT_SCHEMA;
  exportedAt: string;
  workspace: {
    name: string;
    description: string;
    client: string;
    tags: string[];
    type: WorkspaceType;
  };
  entries: PortableWorkspaceEntry[];
};

function safeSegment(value: unknown) {
  const text = typeof value === 'string' ? value.normalize('NFKC').trim() : '';
  if (!text || text === '.' || text === '..' || text.length > 140 || /[\/\\\u0000-\u001f]/.test(text)) return '';
  return text;
}

function safeRelativePath(value: unknown) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 64) return null;
  const path: string[] = [];
  for (const raw of value) {
    const segment = safeSegment(raw);
    if (!segment) return null;
    path.push(segment);
  }
  return path;
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  const chunk = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + chunk)));
  }
  return btoa(binary);
}

function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function portableName(name: string) {
  return name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80) || 'workspace';
}

async function collectTree(
  workspace: WorkspaceRecord,
  relativePath: string[],
  output: PortableWorkspaceEntry[],
  budget: { entries: number; bytes: number },
) {
  const sourcePath = [...workspace.root, ...relativePath];
  const entries = await fileSourceFacade.list(workspace.provider, sourcePath, false);
  for (const entry of entries) {
    if (relativePath.length === 0 && entry.name === 'workspace.json') continue;
    if (entry.symlink || entry.kind === 'symlink') throw new Error(`Exportação interrompida: “${entry.name}” é link simbólico e não será seguido.`);
    budget.entries += 1;
    if (budget.entries > MAX_WORKSPACE_EXPORT_ENTRIES) throw new Error(`Workspace excede o limite de exportação de ${MAX_WORKSPACE_EXPORT_ENTRIES} itens.`);
    const path = [...relativePath, entry.name];
    if (entry.kind === 'directory') {
      output.push({ path, kind: 'directory' });
      await collectTree(workspace, path, output, budget);
      continue;
    }
    if (entry.size > MAX_WORKSPACE_EXPORT_FILE_BYTES) throw new Error(`“${entry.name}” excede o limite de ${MAX_WORKSPACE_EXPORT_FILE_BYTES} bytes por arquivo para exportação portátil.`);
    budget.bytes += entry.size;
    if (budget.bytes > MAX_WORKSPACE_EXPORT_BYTES) throw new Error(`Workspace excede o limite agregado de ${MAX_WORKSPACE_EXPORT_BYTES} bytes para exportação portátil.`);
    const file = await fileSourceFacade.readFile(workspace.provider, sourcePath, entry, MAX_WORKSPACE_EXPORT_FILE_BYTES);
    output.push({
      path,
      kind: 'file',
      contentBase64: bytesToBase64(new Uint8Array(await file.arrayBuffer())),
      type: file.type || undefined,
      modified: file.lastModified || entry.modified,
      mode: entry.mode,
    });
  }
}

export async function buildWorkspaceExport(workspace: WorkspaceRecord): Promise<PortableWorkspace> {
  const current = getWorkspace(workspace.id);
  if (!current) throw new Error('Workspace não encontrado.');
  const runtime = await fileSourceFacade.runtime(current.provider);
  if (!runtime.available || !runtime.mounted) throw new Error(`${runtime.label} não está disponível para exportação.`);
  const entries: PortableWorkspaceEntry[] = [];
  await collectTree(current, [], entries, { entries: 0, bytes: 0 });
  return {
    schema: WORKSPACE_EXPORT_SCHEMA,
    exportedAt: new Date().toISOString(),
    workspace: {
      name: current.name,
      description: current.description,
      client: current.client,
      tags: [...current.tags],
      type: current.type,
    },
    entries,
  };
}

export async function downloadWorkspaceExport(workspace: WorkspaceRecord) {
  const bundle = await buildWorkspaceExport(workspace);
  const blob = new Blob([JSON.stringify(bundle)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `${portableName(workspace.name)}.cloudos-workspace.json`;
  anchor.rel = 'noopener';
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
  return { bytes: blob.size, entries: bundle.entries.length };
}

function validateBundle(value: unknown): PortableWorkspace {
  if (!value || typeof value !== 'object') throw new Error('Bundle de Workspace inválido.');
  const raw = value as Partial<PortableWorkspace>;
  if (raw.schema !== WORKSPACE_EXPORT_SCHEMA) throw new Error('Formato de Workspace não suportado.');
  if (!raw.workspace || typeof raw.workspace !== 'object' || !Array.isArray(raw.entries)) throw new Error('Bundle de Workspace incompleto.');
  if (raw.entries.length > MAX_WORKSPACE_EXPORT_ENTRIES) throw new Error(`Importação excede ${MAX_WORKSPACE_EXPORT_ENTRIES} itens.`);
  const type = ['client', 'project', 'ticket', 'lab', 'custom'].includes(raw.workspace.type as string) ? raw.workspace.type as WorkspaceType : 'custom';
  const seen = new Set<string>();
  let estimatedBytes = 0;
  const entries: PortableWorkspaceEntry[] = raw.entries.map(item => {
    const path = safeRelativePath(item?.path);
    if (!path || path[0] === 'workspace.json') throw new Error('Bundle contém caminho inválido.');
    const key = path.join('/');
    if (seen.has(key)) throw new Error(`Bundle contém caminho duplicado: ${key}.`);
    seen.add(key);
    if (item?.kind !== 'directory' && item?.kind !== 'file') throw new Error(`Tipo de item inválido em ${key}.`);
    if (item.kind === 'file') {
      if (typeof item.contentBase64 !== 'string') throw new Error(`Conteúdo ausente em ${key}.`);
      estimatedBytes += Math.floor(item.contentBase64.length * 0.75);
      if (estimatedBytes > MAX_WORKSPACE_EXPORT_BYTES) throw new Error(`Importação excede ${MAX_WORKSPACE_EXPORT_BYTES} bytes agregados.`);
    }
    return {
      path,
      kind: item.kind,
      ...(item.kind === 'file' ? {
        contentBase64: item.contentBase64,
        type: typeof item.type === 'string' ? item.type.slice(0, 120) : undefined,
        modified: Number(item.modified) || undefined,
        mode: Number.isSafeInteger(item.mode) ? item.mode : undefined,
      } : {}),
    };
  });
  return {
    schema: WORKSPACE_EXPORT_SCHEMA,
    exportedAt: Number.isFinite(Date.parse(String(raw.exportedAt))) ? new Date(String(raw.exportedAt)).toISOString() : new Date(0).toISOString(),
    workspace: {
      name: portableName(String(raw.workspace.name || 'Workspace importado')),
      description: String(raw.workspace.description || '').slice(0, 1000),
      client: String(raw.workspace.client || '').slice(0, 120),
      tags: Array.isArray(raw.workspace.tags) ? raw.workspace.tags.map(String).slice(0, 12) : [],
      type,
    },
    entries,
  };
}

async function ensureDirectory(provider: WorkflowProvider, path: string[], name: string) {
  const entries = await fileSourceFacade.list(provider, path, false);
  const existing = entries.find(entry => entry.name === name);
  if (existing) {
    if (existing.kind !== 'directory' || existing.symlink) throw new Error(`“${name}” existe e não é uma pasta regular.`);
    return existing.name;
  }
  return fileSourceFacade.create(provider, path, 'directory', name);
}

async function cleanupImportedWorkspace(workspace: WorkspaceRecord) {
  removeWorkspaceFromIndex(workspace.id);
  try {
    const parents = await fileSourceFacade.list(workspace.provider, ['Workspaces'], false);
    const rootName = workspace.root.at(-1);
    const rootEntry = parents.find(entry => entry.name === rootName);
    if (rootEntry && rootEntry.kind === 'directory' && !rootEntry.symlink) await fileSourceFacade.trash(workspace.provider, ['Workspaces'], rootEntry);
  } catch {
    // Preserve the import failure. Partial data remains visible for manual recovery if cleanup fails.
  }
}

export async function importWorkspaceBundle(bundleValue: unknown, provider: WorkflowProvider) {
  const bundle = validateBundle(bundleValue);
  const workspace = await createWorkspace({
    type: bundle.workspace.type,
    name: bundle.workspace.name,
    description: bundle.workspace.description,
    client: bundle.workspace.client,
    tags: bundle.workspace.tags,
    provider,
    originPath: [],
  });
  try {
    const directories = bundle.entries.filter(entry => entry.kind === 'directory').sort((left, right) => left.path.length - right.path.length);
    for (const entry of directories) {
      const parent = [...workspace.root, ...entry.path.slice(0, -1)];
      await ensureDirectory(provider, parent, entry.path.at(-1)!);
    }
    for (const entry of bundle.entries.filter(item => item.kind === 'file')) {
      const parent = [...workspace.root, ...entry.path.slice(0, -1)];
      for (let index = 0; index < entry.path.length - 1; index += 1) {
        await ensureDirectory(provider, [...workspace.root, ...entry.path.slice(0, index)], entry.path[index]);
      }
      const name = entry.path.at(-1)!;
      const existing = await fileSourceFacade.list(provider, parent, false);
      if (existing.some(item => item.name === name)) throw new Error(`Importação não sobrescreve “${entry.path.join('/')}”.`);
      const bytes = base64ToBytes(entry.contentBase64 || '');
      if (bytes.byteLength > MAX_WORKSPACE_EXPORT_FILE_BYTES) throw new Error(`“${name}” excede o limite por arquivo.`);
      const file = new File([bytes], name, { type: entry.type || '', lastModified: entry.modified || Date.now() });
      await fileSourceFacade.writeFile(provider, parent, file, entry.mode);
    }
    await activateWorkspace(workspace.id);
    return workspace;
  } catch (error) {
    await cleanupImportedWorkspace(workspace);
    throw error;
  }
}

export async function importWorkspaceFile(file: File, provider: WorkflowProvider) {
  if (file.size > MAX_WORKSPACE_IMPORT_JSON_BYTES) throw new Error(`Bundle excede o limite de ${MAX_WORKSPACE_IMPORT_JSON_BYTES} bytes.`);
  let parsed: unknown;
  try { parsed = JSON.parse(await file.text()); }
  catch { throw new Error('Arquivo de importação não contém JSON válido.'); }
  return importWorkspaceBundle(parsed, provider);
}

export async function moveWorkspaceSafely(workspace: WorkspaceRecord, provider: WorkflowProvider) {
  if (provider === workspace.provider) throw new Error('Escolha uma origem diferente para mover o Workspace.');
  const bundle = await buildWorkspaceExport(workspace);
  const moved = await importWorkspaceBundle(bundle, provider);
  try {
    await archiveWorkspace(workspace.id, true);
  } catch (error) {
    throw new Error(`A cópia foi criada em ${provider}, mas o Workspace original não pôde ser arquivado. Os dois permanecem preservados. ${error instanceof Error ? error.message : ''}`.trim());
  }
  return { workspace: moved, sourceArchived: true, sourceDeleted: false };
}

export function workspaceTransferLimits() {
  return {
    entries: MAX_WORKSPACE_EXPORT_ENTRIES,
    bytes: MAX_WORKSPACE_EXPORT_BYTES,
    fileBytes: MAX_WORKSPACE_EXPORT_FILE_BYTES,
    importJsonBytes: MAX_WORKSPACE_IMPORT_JSON_BYTES,
    standardFolders: [...WORKSPACE_FOLDERS],
  };
}
