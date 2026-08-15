export const SYSTEM_CENTER_HISTORY_LIMIT = 60;

export function clampPercent(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return Math.max(0, Math.min(100, numeric));
}

export function memoryPercent(resources) {
  const total = Number(resources?.totalMemory) || 0;
  const used = Number(resources?.usedMemory) || 0;
  return total > 0 ? clampPercent((used / total) * 100) : 0;
}

export function diskPercent(resources) {
  const total = Number(resources?.totalDisk) || 0;
  const used = Number(resources?.usedDisk) || 0;
  return total > 0 ? clampPercent((used / total) * 100) : 0;
}

export function appendHistory(history, value, limit = SYSTEM_CENTER_HISTORY_LIMIT) {
  const safeLimit = Math.max(1, Math.min(600, Number(limit) || SYSTEM_CENTER_HISTORY_LIMIT));
  return [...(Array.isArray(history) ? history : []), clampPercent(value)].slice(-safeLimit);
}

export function isSystemProcess(process) {
  const pid = Number(process?.pid);
  return Number.isFinite(pid) && pid >= 0 && pid < 100;
}

export function healthSummary({ processes = [], services = [], drivers = [], resources = {} } = {}) {
  const failedServices = services.filter(service => service?.status === 'failed');
  const failedDrivers = drivers.filter(driver => driver?.status === 'failed' || driver?.status === 'not_found');
  const memory = memoryPercent(resources);
  const cpu = clampPercent(resources?.cpuUsage);
  const suspended = processes.filter(process => process?.status === 'suspended' || process?.state === 'BLOCKED').length;
  const alerts = [];

  if (failedServices.length) alerts.push(`${failedServices.length} serviço(s) com falha`);
  if (failedDrivers.length) alerts.push(`${failedDrivers.length} driver(s) com falha`);
  if (memory >= 90) alerts.push(`memória em ${Math.round(memory)}%`);
  if (cpu >= 95) alerts.push(`CPU em ${Math.round(cpu)}%`);

  return {
    status: alerts.length ? 'attention' : 'healthy',
    alerts,
    failedServices: failedServices.length,
    failedDrivers: failedDrivers.length,
    suspended,
    memory,
    cpu,
  };
}

export function sortProcesses(processes, field = 'memory') {
  const list = Array.isArray(processes) ? [...processes] : [];
  if (field === 'cpu') return list.sort((a, b) => (Number(b?.cpuUsage) || 0) - (Number(a?.cpuUsage) || 0));
  if (field === 'pid') return list.sort((a, b) => (Number(a?.pid) || 0) - (Number(b?.pid) || 0));
  if (field === 'name') return list.sort((a, b) => String(a?.title || a?.name || '').localeCompare(String(b?.title || b?.name || ''), undefined, { sensitivity: 'base' }));
  return list.sort((a, b) => (Number(b?.memoryUsage) || 0) - (Number(a?.memoryUsage) || 0));
}
