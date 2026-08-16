import { apiClient } from '../../services/apiClient';
import { appendFilePath, normalizeFilePath, USER_FILE_ACTOR } from './fileSourcePolicy';

export type WslFileEntry = {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  size: number;
  mode: number;
  modified: number;
  uid: number;
  gid: number;
  symlink: boolean;
  source: 'wsl';
  trashId?: string;
  originalPath?: string[];
  originalName?: string;
  deletedAt?: number;
};

export type WslFilesStatus = {
  enabled: boolean;
  available: boolean;
  distribution: string | null;
  wsl2: boolean;
  protocol: number;
  protection: string;
  source: 'wsl';
  mode: 'wsl-core-v2';
  reason?: string;
  root?: { root: string; rootLabel: string; user: string; readOnly: boolean; trash: boolean; pathPolicy: string };
};

export type FileOperation = {
  id: string;
  type: string;
  status: 'queued' | 'running' | 'cancelling' | 'cancelled' | 'completed' | 'failed';
  progress: number;
  step: string;
  message: string;
  errorCode: string | null;
  output: string[];
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

function normalizeEntry(raw: any): WslFileEntry | null {
  if (!raw || typeof raw.name !== 'string' || !['file', 'directory', 'symlink'].includes(raw.kind)) return null;
  return {
    name: raw.name,
    kind: raw.kind,
    size: Number.isFinite(Number(raw.size)) ? Math.max(0, Number(raw.size)) : 0,
    mode: Number.isSafeInteger(Number(raw.mode)) ? Number(raw.mode) : 0,
    modified: parseTime(raw.modifiedAt),
    uid: Number.isSafeInteger(Number(raw.uid)) ? Number(raw.uid) : -1,
    gid: Number.isSafeInteger(Number(raw.gid)) ? Number(raw.gid) : -1,
    symlink: raw.symlink === true || raw.kind === 'symlink',
    source: 'wsl',
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

export const wslFileSource = {
  status: () => apiClient<WslFilesStatus>('/api/files/wsl/status', jsonOptions()),

  async list(path: string[]): Promise<WslFileEntry[]> {
    const safePath = normalizeFilePath(path);
    const result = await apiClient<{ entries?: unknown[] }>('/api/files/wsl/list', jsonOptions({ path: safePath }));
    return (result.entries || []).map(normalizeEntry).filter((entry): entry is WslFileEntry => Boolean(entry));
  },

  async readFile(path: string[], name: string, maximumBytes: number): Promise<File> {
    const fullPath = appendFilePath(path, name);
    const chunks: Uint8Array[] = [];
    let offset = 0;
    let totalSize = -1;
    while (true) {
      const result = await apiClient<{ data: string; bytes: number; eof: boolean; size: number }>('/api/files/wsl/read', jsonOptions({ path: fullPath, offset, limit: 256 * 1024 }, 20000));
      if (!Number.isSafeInteger(result.bytes) || result.bytes < 0 || typeof result.data !== 'string') throw new Error('Bloco Linux inválido.');
      if (totalSize < 0) totalSize = Math.max(0, Number(result.size) || 0);
      if (totalSize > maximumBytes) throw new Error(`Arquivo excede o limite permitido de ${maximumBytes} bytes.`);
      const bytes = base64ToBytes(result.data);
      if (bytes.length !== result.bytes) throw new Error('Bloco Linux inconsistente.');
      chunks.push(bytes);
      offset += result.bytes;
      if (offset > maximumBytes) throw new Error(`Arquivo excede o limite permitido de ${maximumBytes} bytes.`);
      if (result.eof) break;
      if (result.bytes === 0) throw new Error('Leitura Linux não avançou.');
    }
    return new File(chunks, name, { lastModified: Date.now() });
  },

  async writeText(path: string[], name: string, content: string, mode = 0o600) {
    const fullPath = appendFilePath(path, name);
    const bytes = new TextEncoder().encode(content);
    let offset = 0;
    if (bytes.length === 0) {
      await apiClient('/api/files/wsl/write', jsonOptions({ confirmed: true, path: fullPath, offset: 0, data: '', truncate: true, mode }));
      return;
    }
    while (offset < bytes.length) {
      const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 256 * 1024));
      await apiClient('/api/files/wsl/write', jsonOptions({ confirmed: true, path: fullPath, offset, data: bytesToBase64(chunk), truncate: offset === 0, mode }, 20000));
      offset += chunk.length;
    }
  },

  mkdir: (path: string[], name: string) => apiClient('/api/files/wsl/mkdir', jsonOptions({ confirmed: true, path: appendFilePath(path, name), mode: 0o700 })),

  move: (path: string[], name: string, destinationPath: string[], destinationName: string) => apiClient('/api/files/wsl/move', jsonOptions({
    confirmed: true,
    source: appendFilePath(path, name),
    destination: appendFilePath(destinationPath, destinationName),
  })),

  async copy(path: string[], name: string, destinationPath: string[], destinationName: string): Promise<FileOperation> {
    const result = await apiClient<{ operation: FileOperation }>('/api/files/wsl/copy', jsonOptions({
      confirmed: true,
      source: appendFilePath(path, name),
      destination: appendFilePath(destinationPath, destinationName),
    }));
    return result.operation;
  },

  trash: (path: string[], name: string) => apiClient('/api/files/wsl/trash', jsonOptions({ confirmed: true, path: appendFilePath(path, name) })),

  async listTrash(): Promise<WslFileEntry[]> {
    const result = await apiClient<{ entries?: any[] }>('/api/files/wsl/trash/list', jsonOptions({}));
    return (result.entries || []).map(raw => {
      if (!raw || typeof raw.id !== 'string' || typeof raw.originalName !== 'string') return null;
      return {
        name: raw.storedName || raw.id,
        kind: raw.kind === 'directory' ? 'directory' : 'file',
        size: Math.max(0, Number(raw.size) || 0),
        mode: Number(raw.mode) || 0,
        modified: parseTime(raw.deletedAt),
        uid: -1,
        gid: -1,
        symlink: false,
        source: 'wsl' as const,
        trashId: raw.id,
        originalPath: Array.isArray(raw.originalPath) ? raw.originalPath.map(String) : [],
        originalName: raw.originalName,
        deletedAt: parseTime(raw.deletedAt),
      } satisfies WslFileEntry;
    }).filter((entry): entry is WslFileEntry => Boolean(entry));
  },

  restoreTrash: (id: string) => apiClient('/api/files/wsl/trash/restore', jsonOptions({ confirmed: true, id })),
  deleteTrash: (id: string) => apiClient('/api/files/wsl/trash/delete', jsonOptions({ confirmed: true, id })),

  getOperation: (id: string) => apiClient<FileOperation>(`/api/operations/${encodeURIComponent(id)}`),
  cancelOperation: (id: string) => apiClient<FileOperation>(`/api/operations/${encodeURIComponent(id)}/cancel`, { method: 'POST', body: JSON.stringify({}) }),
};
