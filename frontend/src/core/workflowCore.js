export const WORKSPACE_TYPES = Object.freeze([
  { id: 'client', label: 'Cliente' },
  { id: 'project', label: 'Projeto' },
  { id: 'ticket', label: 'Ticket' },
  { id: 'lab', label: 'Laboratório' },
  { id: 'custom', label: 'Personalizado' },
]);

export const WORKSPACE_FOLDERS = Object.freeze([
  'Notes',
  'Downloads',
  'Evidence',
  'Reports',
  'Files',
  'Terminal',
  'Browser',
]);

export const MAX_CLIPBOARD_ITEMS = 30;
export const MAX_CLIPBOARD_ITEM_BYTES = 5 * 1024 * 1024;
export const MAX_WORKSPACE_DESCRIPTION = 1000;
export const MAX_WORKSPACE_TAGS = 12;
export const MAX_WORKSPACE_TAG_LENGTH = 32;
export const MIN_VIEWER_ZOOM = 0.25;
export const MAX_VIEWER_ZOOM = 4;
export const VIEWER_ZOOM_STEP = 0.25;

const VALID_WORKSPACE_TYPES = new Set(WORKSPACE_TYPES.map(item => item.id));
const VALID_PROVIDERS = new Set(['opfs', 'windows', 'wsl']);
const VALID_WORKSPACE_STATUS = new Set(['active', 'archived']);
const NOTES_EXTENSIONS = new Set(['txt', 'md', 'json', 'log']);
const VIEWER_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'webp', 'pdf']);
const JWT = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/;
const PEM = /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/i;
const AUTH_BEARER = /\b(?:authorization\s*:\s*bearer|bearer)\s+[A-Za-z0-9._~+\/-]{12,}/i;
const ASSIGNED_SECRET = /\b(?:password|passwd|senha|secret|client_secret|api[_-]?key|access[_-]?token|refresh[_-]?token|jwt|credential)\b\s*[:=]\s*["']?[^\s"';,]{6,}/i;
const URL_CREDENTIAL = /\b[a-z][a-z0-9+.-]*:\/\/[^\s/:@]+:[^\s/@]{4,}@/i;
const HIGH_ENTROPY_TOKEN = /\b(?:AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{24,})\b/;

export function workspaceTypeLabel(type) {
  return WORKSPACE_TYPES.find(item => item.id === type)?.label || 'Personalizado';
}

export function sanitizeWorkspaceName(value) {
  const text = String(value ?? '')
    .normalize('NFKC')
    .trim()
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-')
    .replace(/\s+/g, ' ')
    .replace(/[. ]+$/g, '')
    .slice(0, 80);
  return text || 'Workspace';
}

export function sanitizeWorkspaceTags(value) {
  const source = Array.isArray(value) ? value : String(value ?? '').split(',');
  const output = [];
  const seen = new Set();
  for (const raw of source) {
    const tag = String(raw ?? '')
      .normalize('NFKC')
      .trim()
      .replace(/[\u0000-\u001f]/g, '')
      .replace(/\s+/g, ' ')
      .slice(0, MAX_WORKSPACE_TAG_LENGTH);
    const key = tag.toLocaleLowerCase('pt-BR');
    if (!tag || seen.has(key)) continue;
    seen.add(key);
    output.push(tag);
    if (output.length >= MAX_WORKSPACE_TAGS) break;
  }
  return output;
}

export function workspaceFolderName(name, id) {
  const slug = sanitizeWorkspaceName(name)
    .toLocaleLowerCase('pt-BR')
    .replace(/[^a-z0-9\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48) || 'workspace';
  const suffix = String(id || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 8) || 'local';
  return `${slug}-${suffix}`;
}

export function normalizeWorkspaceRecord(value) {
  if (!value || typeof value !== 'object') return null;
  const type = VALID_WORKSPACE_TYPES.has(value.type) ? value.type : 'custom';
  const provider = VALID_PROVIDERS.has(value.provider) ? value.provider : null;
  const id = typeof value.id === 'string' && /^[a-zA-Z0-9-]{8,80}$/.test(value.id) ? value.id : '';
  const name = sanitizeWorkspaceName(value.name);
  const root = Array.isArray(value.root) ? value.root.map(String).filter(Boolean).slice(0, 64) : [];
  if (!provider || !id || root.length === 0) return null;
  const createdAt = Number.isFinite(Date.parse(value.createdAt)) ? new Date(value.createdAt).toISOString() : new Date(0).toISOString();
  const lastAccessAt = Number.isFinite(Date.parse(value.lastAccessAt)) ? new Date(value.lastAccessAt).toISOString() : createdAt;
  const lastActivityAt = Number.isFinite(Date.parse(value.lastActivityAt)) ? new Date(value.lastActivityAt).toISOString() : lastAccessAt;
  return {
    id,
    type,
    name,
    description: String(value.description ?? '').trim().slice(0, MAX_WORKSPACE_DESCRIPTION),
    client: String(value.client ?? '').normalize('NFKC').trim().replace(/[\u0000-\u001f]/g, '').slice(0, 120),
    tags: sanitizeWorkspaceTags(value.tags),
    status: VALID_WORKSPACE_STATUS.has(value.status) ? value.status : 'active',
    provider,
    root,
    originPath: Array.isArray(value.originPath) ? value.originPath.map(String).filter(Boolean).slice(0, 64) : [],
    createdAt,
    lastAccessAt,
    lastActivityAt,
  };
}

export function createWorkspaceRecord({ id, type, name, description = '', client = '', tags = [], status = 'active', provider, root, originPath = [], now = new Date().toISOString() }) {
  return normalizeWorkspaceRecord({ id, type, name, description, client, tags, status, provider, root, originPath, createdAt: now, lastAccessAt: now, lastActivityAt: now });
}

export function buildWorkspaceManifest(workspace) {
  const normalized = normalizeWorkspaceRecord(workspace);
  if (!normalized) throw new TypeError('Workspace inválido.');
  return {
    versao: 1,
    id: normalized.id,
    tipo: workspaceTypeLabel(normalized.type),
    nome: normalized.name,
    descricao: normalized.description,
    cliente: normalized.client,
    tags: [...normalized.tags],
    status: normalized.status,
    data: normalized.createdAt,
    ultimoAcesso: normalized.lastAccessAt,
    ultimaAtividade: normalized.lastActivityAt,
    origem: {
      provider: normalized.provider,
      caminhoInicial: normalized.originPath,
    },
    estrutura: [...WORKSPACE_FOLDERS],
  };
}

export function workspaceSearchText(workspace) {
  const normalized = normalizeWorkspaceRecord(workspace);
  if (!normalized) return '';
  return [
    normalized.name,
    normalized.description,
    normalized.client,
    normalized.type,
    workspaceTypeLabel(normalized.type),
    normalized.status,
    normalized.provider,
    ...normalized.tags,
  ].join(' ');
}

export function workflowFileOpenMode(name, kind = 'file', symlink = false) {
  if (symlink || kind === 'symlink') return 'info';
  if (kind === 'directory') return 'directory';
  if (kind !== 'file') return 'info';
  const match = String(name ?? '').toLocaleLowerCase('pt-BR').match(/\.([^.]+)$/);
  const extension = match?.[1] || '';
  if (NOTES_EXTENSIONS.has(extension)) return 'notes';
  if (VIEWER_EXTENSIONS.has(extension)) return 'viewer';
  return 'info';
}

export function normalizeViewerZoom(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 1;
  return Math.min(MAX_VIEWER_ZOOM, Math.max(MIN_VIEWER_ZOOM, Math.round(numeric * 100) / 100));
}

export function stepViewerZoom(current, direction) {
  const delta = Number(direction) < 0 ? -VIEWER_ZOOM_STEP : VIEWER_ZOOM_STEP;
  return normalizeViewerZoom(Number(current) + delta);
}

export function looksSensitiveText(value) {
  const text = String(value ?? '');
  if (!text) return false;
  return JWT.test(text)
    || PEM.test(text)
    || AUTH_BEARER.test(text)
    || ASSIGNED_SECRET.test(text)
    || URL_CREDENTIAL.test(text)
    || HIGH_ENTROPY_TOKEN.test(text);
}

export function clipboardTextPolicy(value) {
  const text = String(value ?? '');
  const bytes = new TextEncoder().encode(text).byteLength;
  if (!text.trim()) return { allowed: false, reason: 'empty', bytes };
  if (bytes > MAX_CLIPBOARD_ITEM_BYTES) return { allowed: false, reason: 'too-large', bytes };
  if (looksSensitiveText(text)) return { allowed: false, reason: 'sensitive', bytes };
  return { allowed: true, reason: 'ok', bytes };
}

export function normalizeClipboardMetadata(entries) {
  const source = Array.isArray(entries) ? entries : [];
  const seen = new Set();
  const output = [];
  for (const raw of source) {
    if (!raw || typeof raw !== 'object') continue;
    const id = typeof raw.id === 'string' && /^[a-zA-Z0-9-]{8,100}$/.test(raw.id) ? raw.id : '';
    if (!id || seen.has(id)) continue;
    const bytes = Number(raw.bytes);
    if (!Number.isFinite(bytes) || bytes < 0 || bytes > MAX_CLIPBOARD_ITEM_BYTES) continue;
    seen.add(id);
    output.push({
      id,
      source: String(raw.source || 'CloudOS').slice(0, 40),
      createdAt: Number.isFinite(Date.parse(raw.createdAt)) ? new Date(raw.createdAt).toISOString() : new Date(0).toISOString(),
      bytes,
      preview: String(raw.preview || '').replace(/[\u0000-\u001f]/g, ' ').slice(0, 180),
      favorite: raw.favorite === true,
      fileName: typeof raw.fileName === 'string' ? raw.fileName.slice(0, 140) : `${id}.txt`,
    });
    if (output.length >= MAX_CLIPBOARD_ITEMS) break;
  }
  return output;
}

export function terminalHereCapability(provider) {
  if (provider === 'wsl') return { supported: true, profile: 'wsl', reason: '' };
  if (provider === 'windows') return {
    supported: false,
    profile: 'powershell',
    reason: 'O grant do navegador não expõe o caminho físico da pasta Windows ao Terminal.',
  };
  return {
    supported: false,
    profile: 'powershell',
    reason: 'OPFS é armazenamento privado do navegador e não possui caminho de sistema operacional.',
  };
}

function shellQuoteSegment(value) {
  const segment = String(value ?? '');
  if (!segment || segment.length > 120 || /[\u0000\r\n]/.test(segment) || segment === '.' || segment === '..') {
    throw new TypeError('Segmento Linux inválido.');
  }
  return `'${segment.replaceAll("'", `'"'"'`)}'`;
}

export function buildWslCdCommand(path) {
  const safe = Array.isArray(path) ? path : [];
  if (safe.length > 64) throw new TypeError('Caminho Linux longo demais.');
  if (safe.length === 0) return 'cd -- "$HOME"';
  return `cd -- "$HOME"/${safe.map(shellQuoteSegment).join('/')}`;
}

export function snapBounds(side, viewportWidth, viewportHeight, reservedTop = 0, reservedBottom = 48) {
  if (!['left', 'right'].includes(side)) throw new TypeError('Lado de snap inválido.');
  const width = Math.max(320, Math.floor(Number(viewportWidth) || 0));
  const height = Math.max(240, Math.floor(Number(viewportHeight) || 0));
  const top = Math.max(0, Math.floor(Number(reservedTop) || 0));
  const bottom = Math.max(0, Math.floor(Number(reservedBottom) || 0));
  const usableHeight = Math.max(200, height - top - bottom);
  const leftWidth = Math.floor(width / 2);
  const rightWidth = width - leftWidth;
  return side === 'left'
    ? { x: 0, y: top, width: leftWidth, height: usableHeight }
    : { x: leftWidth, y: top, width: rightWidth, height: usableHeight };
}

export function matchesWorkflowQuery(value, query) {
  const needle = String(query ?? '').trim().toLocaleLowerCase('pt-BR');
  if (!needle) return true;
  return String(value ?? '').toLocaleLowerCase('pt-BR').includes(needle);
}
