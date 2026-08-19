import { workflowFileOpenMode, type WorkflowProvider } from '../core/workflowCore.js';

const RECENT_FILES_KEY = 'cloudos.workflow.recent-files.v1';
const MAX_RECENT_FILES = 30;

export type WorkflowRecentFile = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
  openedAt: string;
  mode: 'notes' | 'viewer' | 'info';
};

function storageAvailable() {
  return typeof localStorage !== 'undefined';
}

function safeSegment(value: unknown) {
  const text = typeof value === 'string' ? value.normalize('NFKC').trim() : '';
  if (!text || text === '.' || text === '..' || text.length > 140 || /[\/\\\u0000-\u001f]/.test(text)) return '';
  return text;
}

function normalizeRecent(value: unknown): WorkflowRecentFile | null {
  if (!value || typeof value !== 'object') return null;
  const raw = value as Partial<WorkflowRecentFile>;
  if (raw.provider !== 'opfs' && raw.provider !== 'windows' && raw.provider !== 'wsl') return null;
  const name = safeSegment(raw.name);
  if (!name || !Array.isArray(raw.path)) return null;
  const path: string[] = [];
  for (const part of raw.path.slice(0, 64)) {
    const segment = safeSegment(part);
    if (!segment) return null;
    path.push(segment);
  }
  const mode = workflowFileOpenMode(name, 'file', false);
  const openedAt = Number.isFinite(Date.parse(String(raw.openedAt))) ? new Date(String(raw.openedAt)).toISOString() : new Date(0).toISOString();
  return { provider: raw.provider, path, name, openedAt, mode: mode === 'notes' || mode === 'viewer' ? mode : 'info' };
}

function keyOf(item: Pick<WorkflowRecentFile, 'provider' | 'path' | 'name'>) {
  return `${item.provider}:${item.path.join('/')}:${item.name}`;
}

export function listRecentFiles(kind: 'all' | 'documents' = 'all') {
  if (!storageAvailable()) return [] as WorkflowRecentFile[];
  let raw: unknown = [];
  try { raw = JSON.parse(localStorage.getItem(RECENT_FILES_KEY) || '[]'); } catch { raw = []; }
  const items = (Array.isArray(raw) ? raw : []).map(normalizeRecent).filter((item): item is WorkflowRecentFile => Boolean(item));
  const filtered = kind === 'documents' ? items.filter(item => item.mode === 'notes' || item.name.toLocaleLowerCase('pt-BR').endsWith('.pdf')) : items;
  return filtered.sort((left, right) => Date.parse(right.openedAt) - Date.parse(left.openedAt)).slice(0, MAX_RECENT_FILES);
}

export function recordRecentFile(input: { provider: WorkflowProvider; path: string[]; name: string }) {
  if (!storageAvailable()) return;
  const normalized = normalizeRecent({ ...input, openedAt: new Date().toISOString() });
  if (!normalized) return;
  const key = keyOf(normalized);
  const next = [normalized, ...listRecentFiles('all').filter(item => keyOf(item) !== key)].slice(0, MAX_RECENT_FILES);
  localStorage.setItem(RECENT_FILES_KEY, JSON.stringify(next));
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
}

export function renameRecentFileReference(target: Pick<WorkflowRecentFile, 'provider' | 'path' | 'name'>, newName: string) {
  if (!storageAvailable()) return null;
  const safeName = safeSegment(newName);
  if (!safeName) return null;
  const items = listRecentFiles('all');
  const oldKey = keyOf(target);
  const current = items.find(item => keyOf(item) === oldKey);
  if (!current) return null;
  const newKey = keyOf({ ...current, name: safeName });
  const collision = items.find(item => keyOf(item) === newKey && keyOf(item) !== oldKey);
  const openedAt = collision && Date.parse(collision.openedAt) > Date.parse(current.openedAt) ? collision.openedAt : current.openedAt;
  const renamed = normalizeRecent({ ...current, name: safeName, openedAt });
  if (!renamed) return null;
  const next = [renamed, ...items.filter(item => {
    const key = keyOf(item);
    return key !== oldKey && key !== newKey;
  })].slice(0, MAX_RECENT_FILES);
  try { localStorage.setItem(RECENT_FILES_KEY, JSON.stringify(next)); } catch { return null; }
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
  return renamed;
}

export function clearRecentFiles() {
  if (!storageAvailable()) return;
  localStorage.removeItem(RECENT_FILES_KEY);
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
}
