export const SECURITY_WORKSPACE_STORAGE_KEY = 'cloudos_security_workspace_v1';
export const MAX_SCOPE_ASSETS = 50;

function safeText(value, maxLength) {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, maxLength) : '';
}

function validIpv4(value) {
  const parts = value.split('.');
  return parts.length === 4 && parts.every(part => /^\d{1,3}$/.test(part) && Number(part) <= 255);
}

function validHostname(value) {
  if (value.length > 253 || value.includes('..')) return false;
  return value.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label));
}

export function normalizeScopeAsset(value) {
  const input = safeText(value, 512);
  if (!input || /\s/.test(input)) return null;

  if (/^https?:\/\//i.test(input)) {
    try {
      const url = new URL(input);
      if (url.username || url.password || !['http:', 'https:'].includes(url.protocol)) return null;
      if (!validHostname(url.hostname) && !validIpv4(url.hostname)) return null;
      url.hash = '';
      return url.href.slice(0, 512);
    } catch {
      return null;
    }
  }

  const cidr = input.match(/^(.+)\/(\d{1,2})$/);
  if (cidr && validIpv4(cidr[1])) {
    const prefix = Number(cidr[2]);
    return prefix >= 0 && prefix <= 32 ? `${cidr[1]}/${prefix}` : null;
  }

  if (validIpv4(input) || validHostname(input)) return input.toLowerCase();
  return null;
}

export function normalizeSecurityWorkspace(value) {
  const source = value && typeof value === 'object' ? value : {};
  const projectName = safeText(source.projectName, 120) || 'Projeto autorizado';
  const notes = safeText(source.notes, 1000);
  const scopes = [];
  const seen = new Set();
  for (const candidate of Array.isArray(source.scopes) ? source.scopes : []) {
    if (scopes.length >= MAX_SCOPE_ASSETS) break;
    const normalized = normalizeScopeAsset(candidate);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    scopes.push(normalized);
  }
  const activeScope = scopes.includes(source.activeScope) ? source.activeScope : (scopes[0] || null);
  return { projectName, notes, scopes, activeScope };
}

export function addScopeAsset(workspace, value) {
  const current = normalizeSecurityWorkspace(workspace);
  const normalized = normalizeScopeAsset(value);
  if (!normalized) return { workspace: current, added: false, reason: 'Alvo inválido. Use domínio, IPv4, CIDR IPv4 ou URL HTTP/HTTPS.' };
  if (current.scopes.includes(normalized)) return { workspace: current, added: false, reason: 'Alvo já está no escopo.' };
  if (current.scopes.length >= MAX_SCOPE_ASSETS) return { workspace: current, added: false, reason: 'Limite de escopo atingido.' };
  return {
    workspace: { ...current, scopes: [...current.scopes, normalized], activeScope: current.activeScope || normalized },
    added: true,
    reason: ''
  };
}

export function removeScopeAsset(workspace, value) {
  const current = normalizeSecurityWorkspace(workspace);
  const scopes = current.scopes.filter(scope => scope !== value);
  return { ...current, scopes, activeScope: current.activeScope === value ? (scopes[0] || null) : current.activeScope };
}

export function selectScopeAsset(workspace, value) {
  const current = normalizeSecurityWorkspace(workspace);
  return current.scopes.includes(value) ? { ...current, activeScope: value } : current;
}
