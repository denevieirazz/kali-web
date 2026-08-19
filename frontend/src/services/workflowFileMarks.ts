import type { WorkflowProvider } from '../core/workflowCore.js';

const FILE_MARKS_KEY = 'cloudos.workflow.file-marks.v1';
const MAX_FILE_MARKS = 100;

export type WorkflowFileMark = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  favorite: boolean;
  pinned: boolean;
  updatedAt: string;
};

function storageAvailable() {
  return typeof localStorage !== 'undefined';
}

function safeSegment(value: unknown) {
  const text = typeof value === 'string' ? value.normalize('NFKC').trim() : '';
  if (!text || text === '.' || text === '..' || text.length > 140 || /[\/\\\u0000-\u001f]/.test(text)) return '';
  return text;
}

function normalizeMark(value: unknown): WorkflowFileMark | null {
  if (!value || typeof value !== 'object') return null;
  const raw = value as Partial<WorkflowFileMark>;
  if (raw.provider !== 'opfs' && raw.provider !== 'windows' && raw.provider !== 'wsl') return null;
  if (!Array.isArray(raw.path)) return null;
  const name = safeSegment(raw.name);
  if (!name) return null;
  const path: string[] = [];
  for (const part of raw.path.slice(0, 64)) {
    const safe = safeSegment(part);
    if (!safe) return null;
    path.push(safe);
  }
  const kind = raw.kind === 'directory' || raw.kind === 'symlink' ? raw.kind : 'file';
  const updatedAt = Number.isFinite(Date.parse(String(raw.updatedAt))) ? new Date(String(raw.updatedAt)).toISOString() : new Date(0).toISOString();
  return { provider: raw.provider, path, name, kind, favorite: Boolean(raw.favorite), pinned: Boolean(raw.pinned), updatedAt };
}

function keyOf(mark: Pick<WorkflowFileMark, 'provider' | 'path' | 'name'>) {
  return `${mark.provider}:${mark.path.join('/')}:${mark.name}`;
}

export function listFileMarks(filter: 'all' | 'favorites' | 'pinned' = 'all') {
  if (!storageAvailable()) return [] as WorkflowFileMark[];
  let raw: unknown = [];
  try { raw = JSON.parse(localStorage.getItem(FILE_MARKS_KEY) || '[]'); } catch { raw = []; }
  const marks = (Array.isArray(raw) ? raw : []).map(normalizeMark).filter((mark): mark is WorkflowFileMark => Boolean(mark));
  const visible = filter === 'favorites' ? marks.filter(mark => mark.favorite) : filter === 'pinned' ? marks.filter(mark => mark.pinned) : marks;
  return visible.sort((left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt)).slice(0, MAX_FILE_MARKS);
}

export function getFileMark(target: Pick<WorkflowFileMark, 'provider' | 'path' | 'name'>) {
  const key = keyOf(target);
  return listFileMarks().find(mark => keyOf(mark) === key) || null;
}

export function setFileMark(target: Pick<WorkflowFileMark, 'provider' | 'path' | 'name' | 'kind'>, patch: { favorite?: boolean; pinned?: boolean }) {
  if (!storageAvailable()) return null;
  const current = getFileMark(target);
  const normalized = normalizeMark({
    ...target,
    favorite: patch.favorite ?? current?.favorite ?? false,
    pinned: patch.pinned ?? current?.pinned ?? false,
    updatedAt: new Date().toISOString(),
  });
  if (!normalized) return null;
  const key = keyOf(normalized);
  const next = [normalized, ...listFileMarks().filter(mark => keyOf(mark) !== key)]
    .filter(mark => mark.favorite || mark.pinned)
    .slice(0, MAX_FILE_MARKS);
  localStorage.setItem(FILE_MARKS_KEY, JSON.stringify(next));
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
  return normalized;
}

export function renameFileMarkReference(target: Pick<WorkflowFileMark, 'provider' | 'path' | 'name'>, newName: string) {
  if (!storageAvailable()) return null;
  const safeName = safeSegment(newName);
  if (!safeName) return null;
  const marks = listFileMarks();
  const oldKey = keyOf(target);
  const current = marks.find(mark => keyOf(mark) === oldKey);
  if (!current) return null;
  const candidate = normalizeMark({ ...current, name: safeName, updatedAt: new Date().toISOString() });
  if (!candidate) return null;
  const newKey = keyOf(candidate);
  const collision = marks.find(mark => keyOf(mark) === newKey && keyOf(mark) !== oldKey);
  const renamed = normalizeMark({
    ...candidate,
    favorite: candidate.favorite || collision?.favorite || false,
    pinned: candidate.pinned || collision?.pinned || false,
  });
  if (!renamed) return null;
  const next = [renamed, ...marks.filter(mark => {
    const key = keyOf(mark);
    return key !== oldKey && key !== newKey;
  })].filter(mark => mark.favorite || mark.pinned).slice(0, MAX_FILE_MARKS);
  try { localStorage.setItem(FILE_MARKS_KEY, JSON.stringify(next)); } catch { return null; }
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:workflow-changed'));
  return renamed;
}
