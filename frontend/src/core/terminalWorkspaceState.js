export const MAX_TERMINAL_TABS = 8;
export const TERMINAL_WORKSPACE_STORAGE_KEY = 'cloudos_terminal_workspace_v1';

const VALID_PROFILES = new Set(['powershell', 'wsl']);

function safeId(value) {
  if (typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value)) return value;
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `terminal-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function safeDistribution(value) {
  return typeof value === 'string' ? value.trim().slice(0, 120) : '';
}

function safeInitialDirectory(value, profile) {
  if (profile !== 'wsl' || !value || typeof value !== 'object' || value.provider !== 'wsl' || !Array.isArray(value.path)) return undefined;
  const path = [];
  for (const raw of value.path) {
    if (path.length >= 64) break;
    const segment = typeof raw === 'string' ? raw : '';
    if (!segment || segment.length > 120 || /[\u0000\r\n]/.test(segment) || segment === '.' || segment === '..') return undefined;
    path.push(segment);
  }
  return { provider: 'wsl', path };
}

function normalizeTab(value, fallback = {}) {
  const source = value && typeof value === 'object' ? value : {};
  const profile = VALID_PROFILES.has(source.profile) ? source.profile : (VALID_PROFILES.has(fallback.profile) ? fallback.profile : 'powershell');
  const distribution = profile === 'wsl' ? safeDistribution(source.distribution || fallback.distribution) : '';
  const initialDirectory = safeInitialDirectory(source.initialDirectory || fallback.initialDirectory, profile);
  return { id: safeId(source.id), profile, distribution, ...(initialDirectory ? { initialDirectory } : {}) };
}

export function createTerminalTab(profile = 'powershell', distribution = '', id, initialDirectory) {
  return normalizeTab({ id, profile, distribution, initialDirectory });
}

export function normalizeTerminalWorkspace(value, fallbackTab = createTerminalTab()) {
  const source = value && typeof value === 'object' ? value : {};
  const incoming = Array.isArray(source.tabs) ? source.tabs : [];
  const seen = new Set();
  const tabs = [];

  for (const candidate of incoming) {
    if (tabs.length >= MAX_TERMINAL_TABS) break;
    const tab = normalizeTab(candidate, fallbackTab);
    if (seen.has(tab.id)) tab.id = safeId();
    seen.add(tab.id);
    tabs.push(tab);
  }

  if (tabs.length === 0) tabs.push(normalizeTab(fallbackTab));

  const activeId = tabs.some(tab => tab.id === source.activeId) ? source.activeId : tabs[0].id;
  const splitId = tabs.some(tab => tab.id === source.splitId && tab.id !== activeId) ? source.splitId : null;
  return { tabs, activeId, splitId };
}

export function addTerminalTab(workspace, tab) {
  const current = normalizeTerminalWorkspace(workspace, tab);
  if (current.tabs.length >= MAX_TERMINAL_TABS) return current;
  const nextTab = normalizeTab(tab);
  if (current.tabs.some(item => item.id === nextTab.id)) nextTab.id = safeId();
  return { tabs: [...current.tabs, nextTab], activeId: nextTab.id, splitId: current.splitId };
}

export function updateTerminalTab(workspace, tabId, updates) {
  const current = normalizeTerminalWorkspace(workspace);
  return {
    ...current,
    tabs: current.tabs.map(tab => tab.id === tabId ? normalizeTab({ ...tab, ...updates, id: tab.id }, tab) : tab),
  };
}

export function closeTerminalTab(workspace, tabId, fallbackTab = createTerminalTab()) {
  const current = normalizeTerminalWorkspace(workspace, fallbackTab);
  const index = current.tabs.findIndex(tab => tab.id === tabId);
  if (index === -1) return current;

  const tabs = current.tabs.filter(tab => tab.id !== tabId);
  if (tabs.length === 0) {
    const fallback = normalizeTab(fallbackTab);
    return { tabs: [fallback], activeId: fallback.id, splitId: null };
  }

  const activeId = current.activeId === tabId ? tabs[Math.min(index, tabs.length - 1)].id : current.activeId;
  const splitId = current.splitId === tabId || current.splitId === activeId ? null : current.splitId;
  return { tabs, activeId, splitId };
}

export function activateTerminalTab(workspace, tabId) {
  const current = normalizeTerminalWorkspace(workspace);
  if (!current.tabs.some(tab => tab.id === tabId)) return current;
  return { ...current, activeId: tabId, splitId: current.splitId === tabId ? null : current.splitId };
}

export function toggleTerminalSplit(workspace) {
  const current = normalizeTerminalWorkspace(workspace);
  if (current.splitId) return { ...current, splitId: null };
  const secondary = current.tabs.find(tab => tab.id !== current.activeId);
  return { ...current, splitId: secondary?.id ?? null };
}

export function cycleTerminalTab(workspace, direction = 1) {
  const current = normalizeTerminalWorkspace(workspace);
  if (current.tabs.length < 2) return current;
  const index = current.tabs.findIndex(tab => tab.id === current.activeId);
  const offset = direction < 0 ? -1 : 1;
  const nextIndex = (index + offset + current.tabs.length) % current.tabs.length;
  return activateTerminalTab(current, current.tabs[nextIndex].id);
}

export function serializableTerminalWorkspace(workspace) {
  const current = normalizeTerminalWorkspace(workspace);
  return {
    tabs: current.tabs.map(({ id, profile, distribution }) => ({ id, profile, distribution })),
    activeId: current.activeId,
    splitId: current.splitId,
  };
}
