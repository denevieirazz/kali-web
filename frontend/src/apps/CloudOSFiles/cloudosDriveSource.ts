import { apiClient } from '../../services/apiClient';
import { appendFilePath, normalizeFilePath, USER_FILE_ACTOR } from './fileSourcePolicy';

export type CloudOsDriveEntry = {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  size: number;
  modified: number;
  symlink: boolean;
  source: 'cloudos';
  trashId?: string;
  originalPath?: string[];
  originalName?: string;
  deletedAt?: number;
};

export type CloudOsDriveStatus = {
  source: 'cloudos';
  mode: 'cloudos-drive-v1';
  available: boolean;
  mounted: boolean;
  rootLabel: string;
  directories: string[];
  capacity: { total: number; free: number } | null;
};

const actorHeaders = { 'X-CloudOS-File-Actor': USER_FILE_ACTOR };
const jsonOptions = (body?: unknown, timeoutMs = 15000) => ({
  method: body === undefined ? 'GET' : 'POST',
  headers: actorHeaders,
  body: body === undefined ? undefined : JSON.stringify(body),
  timeoutMs,
});

function parseTime(value: unknown) {
  const timestamp = typeof value === 'string' ? Date.parse(value) : Number.NaN;
  return Number.isFinite(timestamp) ? timestamp : 0;
}

function normalizeEntry(raw: any): CloudOsDriveEntry | null {
  if (!raw || typeof raw.name !== 'string' || !['file', 'directory', 'symlink'].includes(raw.kind)) return null;
  return {
    name: raw.name,
    kind: raw.kind,
    size: Number.isFinite(Number(raw.size)) ? Math.max(0, Number(raw.size)) : 0,
    modified: parseTime(raw.modifiedAt),
    symlink: raw.symlink === true || raw.kind === 'symlink',
    source: 'cloudos',
  };
}

function normalizeTrashEntry(raw: any): CloudOsDriveEntry | null {
  if (!raw || typeof raw.id !== 'string' || typeof raw.originalName !== 'string') return null;
  const kind: CloudOsDriveEntry['kind'] = raw.kind === 'directory' ? 'directory' : 'file';
  return {
    name: typeof raw.storedName === 'string' && raw.storedName ? raw.storedName : raw.id,
    kind,
    size: Math.max(0, Number(raw.size) || 0),
    modified: parseTime(raw.deletedAt),
    symlink: false,
    source: 'cloudos',
    trashId: raw.id,
    originalPath: Array.isArray(raw.originalPath) ? raw.originalPath.map(String) : [],
    originalName: raw.originalName,
    deletedAt: parseTime(raw.deletedAt),
  };
}

function bytesToBase64(bytes: Uint8Array) {
  let output = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    output += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(output);
}

function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

async function writeBytes(path: string[], name: string, bytes: Uint8Array) {
  const fullPath = appendFilePath(path, name);
  let offset = 0;
  if (bytes.length === 0) {
    await apiClient('/api/files/cloudos/write', jsonOptions({ confirmed: true, path: fullPath, offset: 0, data: '', truncate: true }));
    return;
  }
  while (offset < bytes.length) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 256 * 1024));
    await apiClient('/api/files/cloudos/write', jsonOptions({
      confirmed: true,
      path: fullPath,
      offset,
      data: bytesToBase64(chunk),
      truncate: offset === 0,
    }, 20000));
    offset += chunk.length;
  }
}

export const cloudosDriveSource = {
  status: () => apiClient<CloudOsDriveStatus>('/api/files/cloudos/status', jsonOptions()),

  async list(path: string[]): Promise<CloudOsDriveEntry[]> {
    const safePath = normalizeFilePath(path);
    const result = await apiClient<{ entries?: unknown[] }>('/api/files/cloudos/list', jsonOptions({ path: safePath }));
    return (result.entries || []).map(normalizeEntry).filter((entry): entry is CloudOsDriveEntry => entry !== null);
  },

  async readFile(path: string[], name: string, maximumBytes: number): Promise<File> {
    const fullPath = appendFilePath(path, name);
    const chunks: Uint8Array[] = [];
    let offset = 0;
    let totalSize = -1;
    while (true) {
      const result = await apiClient<{ data: string; bytes: number; eof: boolean; size: number }>('/api/files/cloudos/read', jsonOptions({
        path: fullPath,
        offset,
        limit: 256 * 1024,
      }, 20000));
      if (!Number.isSafeInteger(result.bytes) || result.bytes < 0 || typeof result.data !== 'string') throw new Error('Bloco CloudOS Drive inválido.');
      if (totalSize < 0) totalSize = Math.max(0, Number(result.size) || 0);
      if (totalSize > maximumBytes) throw new Error(`Arquivo excede o limite permitido de ${maximumBytes} bytes.`);
      const bytes = base64ToBytes(result.data);
      if (bytes.length !== result.bytes) throw new Error('Bloco CloudOS Drive inconsistente.');
      chunks.push(bytes);
      offset += result.bytes;
      if (offset > maximumBytes) throw new Error(`Arquivo excede o limite permitido de ${maximumBytes} bytes.`);
      if (result.eof) break;
      if (result.bytes === 0) throw new Error('Leitura CloudOS Drive não avançou.');
    }
    return new File(chunks, name, { lastModified: Date.now() });
  },

  async writeText(path: string[], name: string, content: string) {
    await writeBytes(path, name, new TextEncoder().encode(content));
  },

  async writeFile(path: string[], file: File) {
    const safeName = normalizeFilePath([file.name])[0];
    await writeBytes(path, safeName, new Uint8Array(await file.arrayBuffer()));
    return safeName;
  },

  mkdir: (path: string[], name: string) => apiClient('/api/files/cloudos/mkdir', jsonOptions({ confirmed: true, path: appendFilePath(path, name) })),

  move: (path: string[], name: string, destinationPath: string[], destinationName: string) => apiClient('/api/files/cloudos/move', jsonOptions({
    confirmed: true,
    source: appendFilePath(path, name),
    destination: appendFilePath(destinationPath, destinationName),
  })),

  copy: (path: string[], name: string, destinationPath: string[], destinationName: string) => apiClient('/api/files/cloudos/copy', jsonOptions({
    confirmed: true,
    source: appendFilePath(path, name),
    destination: appendFilePath(destinationPath, destinationName),
  })),

  trash: (path: string[], name: string) => apiClient('/api/files/cloudos/trash', jsonOptions({ confirmed: true, path: appendFilePath(path, name) })),

  async listTrash(): Promise<CloudOsDriveEntry[]> {
    const result = await apiClient<{ entries?: unknown[] }>('/api/files/cloudos/trash/list', jsonOptions({}));
    return (result.entries || []).map(normalizeTrashEntry).filter((entry): entry is CloudOsDriveEntry => entry !== null);
  },

  restoreTrash: (id: string) => apiClient('/api/files/cloudos/trash/restore', jsonOptions({ confirmed: true, id })),
  deleteTrash: (id: string) => apiClient('/api/files/cloudos/trash/delete', jsonOptions({ confirmed: true, id })),
  emptyTrash: () => apiClient('/api/files/cloudos/trash/empty', jsonOptions({ confirmed: true })),
};
