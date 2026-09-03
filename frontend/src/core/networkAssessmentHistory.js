export const NETWORK_ASSESSMENT_HISTORY_KEY = 'cloudos-network-assessment-history-v2';
export const MAX_NETWORK_ASSESSMENT_HISTORY = 20;

function cleanText(value, max = 160) {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max) : '';
}

function cleanPort(port) {
  const number = Number(port?.port);
  if (!Number.isInteger(number) || number < 1 || number > 65535) return null;
  return {
    port: number,
    protocol: cleanText(port?.protocol, 12),
    state: cleanText(port?.state, 20),
    service: cleanText(port?.service, 80),
    version: cleanText(port?.version, 160),
  };
}

function cleanHost(host) {
  const address = cleanText(host?.address, 64);
  if (!address) return null;
  return {
    address,
    hostname: cleanText(host?.hostname, 160),
    up: Boolean(host?.up),
    ports: Array.isArray(host?.ports) ? host.ports.map(cleanPort).filter(Boolean).slice(0, 128) : [],
  };
}

export function sanitizeNetworkAssessmentRecord(value) {
  if (!value || typeof value !== 'object') return null;
  const target = cleanText(value.target, 64);
  const preset = cleanText(value.preset, 32);
  if (!target || !preset) return null;
  return {
    id: cleanText(value.id, 80) || `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    target,
    preset,
    label: cleanText(value.label, 100),
    distribution: cleanText(value.distribution, 100),
    completedAt: cleanText(value.completedAt, 40) || new Date().toISOString(),
    durationMs: Number.isFinite(Number(value.durationMs)) ? Math.max(0, Math.min(Number(value.durationMs), 300000)) : null,
    highestSeverity: ['info', 'low', 'medium', 'high', 'critical'].includes(value.highestSeverity) ? value.highestSeverity : 'info',
    hosts: Array.isArray(value.hosts) ? value.hosts.map(cleanHost).filter(Boolean).slice(0, 256) : [],
  };
}

export function normalizeNetworkAssessmentHistory(value) {
  if (!Array.isArray(value)) return [];
  const result = [];
  const ids = new Set();
  for (const item of value) {
    const clean = sanitizeNetworkAssessmentRecord(item);
    if (!clean || ids.has(clean.id)) continue;
    ids.add(clean.id);
    result.push(clean);
    if (result.length >= MAX_NETWORK_ASSESSMENT_HISTORY) break;
  }
  return result;
}

export function appendNetworkAssessmentHistory(history, assessment) {
  const clean = sanitizeNetworkAssessmentRecord({
    ...assessment,
    id: `${Date.now()}-${cleanText(assessment?.preset, 24)}-${cleanText(assessment?.target, 48)}`,
    highestSeverity: assessment?.insights?.highestSeverity || assessment?.highestSeverity || 'info',
  });
  if (!clean) return normalizeNetworkAssessmentHistory(history);
  return normalizeNetworkAssessmentHistory([clean, ...normalizeNetworkAssessmentHistory(history)]);
}

function hostMap(record) {
  return new Map((record?.hosts || []).map(host => [host.address, host]));
}

function openPortSet(host) {
  return new Set((host?.ports || []).filter(port => port.state === 'open').map(port => `${port.port}/${port.protocol || 'tcp'}`));
}

export function diffNetworkAssessmentRecords(previousValue, currentValue) {
  const previous = sanitizeNetworkAssessmentRecord(previousValue);
  const current = sanitizeNetworkAssessmentRecord(currentValue);
  if (!previous || !current) return { comparable: false, addedHosts: [], removedHosts: [], changedHosts: [] };
  if (previous.target !== current.target || previous.preset !== current.preset) {
    return { comparable: false, addedHosts: [], removedHosts: [], changedHosts: [] };
  }

  const before = hostMap(previous);
  const after = hostMap(current);
  const addedHosts = [...after.keys()].filter(address => !before.has(address));
  const removedHosts = [...before.keys()].filter(address => !after.has(address));
  const changedHosts = [];

  for (const [address, host] of after) {
    const oldHost = before.get(address);
    if (!oldHost) continue;
    const oldPorts = openPortSet(oldHost);
    const newPorts = openPortSet(host);
    const openedPorts = [...newPorts].filter(port => !oldPorts.has(port)).sort();
    const closedPorts = [...oldPorts].filter(port => !newPorts.has(port)).sort();
    if (openedPorts.length || closedPorts.length || Boolean(oldHost.up) !== Boolean(host.up)) {
      changedHosts.push({ address, openedPorts, closedPorts, onlineChanged: Boolean(oldHost.up) !== Boolean(host.up), online: Boolean(host.up) });
    }
  }

  return { comparable: true, addedHosts, removedHosts, changedHosts };
}
