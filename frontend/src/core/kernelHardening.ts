import type { Process, ProcessPriority, UserProfile, WindowState } from '../types';
import legacyKernel, { type SystemResource } from './kernelLegacy';

type KernelInstance = typeof legacyKernel;

type KernelInternals = {
  _activeWindowId: string | null;
  _windows: Map<string, WindowState>;
  _resources: SystemResource;
  _user: UserProfile;
  _runQueues: Map<ProcessPriority, number[]>;
  _uptimeInterval: ReturnType<typeof setInterval> | null;
  _resourceInterval: ReturnType<typeof setInterval> | null;
  _emitWindowSnapshot: () => void;
  _persistSystemState: () => void;
};

const HARDENING_MARKER = '__cloudosCoreHardeningInstalled';
const SHELL_MEMORY_TARGETS: Readonly<Record<string, number>> = {
  'explorer.obx': 96,
  'dwm.obx': 72,
  'SearchHost.obx': 48,
};

function internalsOf(kernel: KernelInstance) {
  return kernel as unknown as KernelInternals;
}

function topUserWindow(windows: WindowState[]) {
  return windows
    .filter(window => !window.isSystem && !window.isMinimized)
    .sort((left, right) => right.zIndex - left.zIndex)[0];
}

/**
 * Repairs focus bookkeeping after system surfaces (Desktop/Taskbar) are opened
 * or a user process disappears. System surfaces must never become the active
 * application window.
 */
export function reconcileActiveWindow(kernel: KernelInstance = legacyKernel) {
  const internals = internalsOf(kernel);
  const windows = kernel.getWindows();
  const current = internals._activeWindowId
    ? windows.find(window => window.id === internals._activeWindowId)
    : undefined;
  const next = current && !current.isSystem && !current.isMinimized
    ? current
    : topUserWindow(windows);

  let changed = internals._activeWindowId !== (next?.id ?? null);

  for (const [id, window] of internals._windows.entries()) {
    const shouldBeActive = Boolean(next && !window.isSystem && id === next.id);
    if (window.isActive !== shouldBeActive) {
      internals._windows.set(id, { ...window, isActive: shouldBeActive });
      changed = true;
    }
  }

  internals._activeWindowId = next?.id ?? null;
  if (changed) internals._emitWindowSnapshot();
}

function stopUptimeCounter(kernel: KernelInstance) {
  const internals = internalsOf(kernel);
  if (internals._uptimeInterval) clearInterval(internals._uptimeInterval);
  internals._uptimeInterval = null;
}

function stopResourceLoop(kernel: KernelInstance) {
  const internals = internalsOf(kernel);
  if (internals._resourceInterval) clearInterval(internals._resourceInterval);
  internals._resourceInterval = null;
}

function clearRunQueues(kernel: KernelInstance) {
  for (const queue of internalsOf(kernel)._runQueues.values()) queue.length = 0;
}

function normalizeMemory(value: number) {
  return Number.isFinite(value) ? Math.max(0, value) : null;
}

function normalizeUser(profile: UserProfile): UserProfile {
  const username = profile.username.trim() || 'user';
  const displayName = profile.displayName.trim() || username;
  return {
    username,
    displayName,
    avatar: typeof profile.avatar === 'string' && profile.avatar.startsWith('data:image/') ? profile.avatar : '',
    isAdmin: profile.isAdmin === true,
    lastLogin: Number.isFinite(profile.lastLogin) ? profile.lastLogin : Date.now(),
  };
}

function sameUser(left: UserProfile, right: UserProfile) {
  return left.username === right.username
    && left.displayName === right.displayName
    && left.avatar === right.avatar
    && left.isAdmin === right.isAdmin
    && left.lastLogin === right.lastLogin;
}

/**
 * Narrow administrative bridge used while the monolithic legacy kernel is being
 * decomposed. React code never reaches into private kernel fields directly.
 */
export const kernelAdmin = {
  setUserProfile(profile: UserProfile) {
    const internals = internalsOf(legacyKernel);
    const next = normalizeUser(profile);
    if (sameUser(internals._user, next)) return;
    internals._user = next;
    internals._persistSystemState();
  },

  setTotalMemory(totalMemoryMb: number) {
    const next = Number.isFinite(totalMemoryMb) ? Math.floor(totalMemoryMb) : 0;
    if (next < 256) return false;
    const internals = internalsOf(legacyKernel);
    if (internals._resources.totalMemory === next) return true;
    internals._resources.totalMemory = next;
    legacyKernel.emit('memoryChange', { ...internals._resources });
    return true;
  },

  reconcileActiveWindow() {
    reconcileActiveWindow(legacyKernel);
  },
};

/**
 * Installs idempotent lifecycle/resource fixes around the legacy kernel. This is
 * deliberately centralized so each fix can later move into ProcessManager,
 * WindowManager and ResourceManager without changing application call sites.
 */
export function installKernelHardening(kernel: KernelInstance = legacyKernel) {
  const tagged = kernel as unknown as Record<string, unknown>;
  if (tagged[HARDENING_MARKER] === true) return kernel;
  tagged[HARDENING_MARKER] = true;

  const originalAllocateMemory = kernel.allocateMemory.bind(kernel);
  kernel.allocateMemory = ((amount: number, processName: string) => {
    const normalized = normalizeMemory(amount);
    if (normalized === null) {
      kernel.log('WARN', 'MemoryManager', `Rejected invalid memory allocation from ${processName}.`, 'INVALID_MEMORY_REQUEST');
      return false;
    }
    if (normalized === 0) return true;
    return originalAllocateMemory(normalized, processName);
  }) as KernelInstance['allocateMemory'];

  const originalFreeMemory = kernel.freeMemory.bind(kernel);
  kernel.freeMemory = ((amount: number) => {
    const normalized = normalizeMemory(amount);
    if (normalized === null || normalized === 0) return;
    originalFreeMemory(normalized);
  }) as KernelInstance['freeMemory'];

  const originalUpdateProcessMemory = kernel.updateProcessMemory.bind(kernel);
  kernel.updateProcessMemory = ((pid: number, memory: number) => {
    const process = kernel.getProcess(pid);
    const normalized = normalizeMemory(memory);
    if (!process || normalized === null) return;

    const delta = normalized - process.memoryUsage;
    if (delta > 0 && !kernel.allocateMemory(delta, process.name)) return;
    if (delta < 0) kernel.freeMemory(-delta);
    originalUpdateProcessMemory(pid, normalized);
  }) as KernelInstance['updateProcessMemory'];

  const originalOpenWindow = kernel.openWindow.bind(kernel);
  kernel.openWindow = ((config: Parameters<KernelInstance['openWindow']>[0]) => {
    const id = originalOpenWindow(config);
    reconcileActiveWindow(kernel);
    return id;
  }) as KernelInstance['openWindow'];

  const originalCloseWindow = kernel.closeWindow.bind(kernel);
  kernel.closeWindow = ((id: string) => {
    originalCloseWindow(id);
    reconcileActiveWindow(kernel);
  }) as KernelInstance['closeWindow'];

  const originalMinimizeWindow = kernel.minimizeWindow.bind(kernel);
  kernel.minimizeWindow = ((id: string) => {
    originalMinimizeWindow(id);
    reconcileActiveWindow(kernel);
  }) as KernelInstance['minimizeWindow'];

  const originalRestoreWindow = kernel.restoreWindow.bind(kernel);
  kernel.restoreWindow = ((id: string) => {
    originalRestoreWindow(id);
    reconcileActiveWindow(kernel);
  }) as KernelInstance['restoreWindow'];

  const originalFocusWindow = kernel.focusWindow.bind(kernel);
  kernel.focusWindow = ((id: string) => {
    const target = kernel.getWindow(id);
    if (!target || target.isSystem) return;
    originalFocusWindow(id);
    reconcileActiveWindow(kernel);
  }) as KernelInstance['focusWindow'];

  const originalTerminateProcess = kernel.terminateProcess.bind(kernel);
  kernel.terminateProcess = ((pid: number) => {
    originalTerminateProcess(pid);
    reconcileActiveWindow(kernel);
  }) as KernelInstance['terminateProcess'];

  const originalStartUptimeCounter = kernel.startUptimeCounter.bind(kernel);
  kernel.startUptimeCounter = (() => {
    stopUptimeCounter(kernel);
    originalStartUptimeCounter();
  }) as KernelInstance['startUptimeCounter'];

  const originalTriggerBSOD = kernel.triggerBSOD.bind(kernel);
  kernel.triggerBSOD = ((info: Parameters<KernelInstance['triggerBSOD']>[0]) => {
    originalTriggerBSOD(info);
    stopUptimeCounter(kernel);
    stopResourceLoop(kernel);
  }) as KernelInstance['triggerBSOD'];

  const originalReset = kernel.reset.bind(kernel);
  kernel.reset = (() => {
    kernel.stopScheduler();
    stopUptimeCounter(kernel);
    stopResourceLoop(kernel);
    clearRunQueues(kernel);
    originalReset();
    reconcileActiveWindow(kernel);
  }) as KernelInstance['reset'];

  const originalLoadShell = kernel.loadShell.bind(kernel);
  kernel.loadShell = (async () => {
    const beforePids = new Set(kernel.getProcesses().map((process: Process) => process.pid));
    const loaded = await originalLoadShell();
    if (!loaded) return false;

    const createdShellProcesses = kernel.getProcesses().filter(process =>
      !beforePids.has(process.pid) && Object.hasOwn(SHELL_MEMORY_TARGETS, process.name)
    );

    if (createdShellProcesses.length > 0) {
      // loadShell historically added fixed shell memory on top of createProcess(),
      // which had already allocated memory. Remove that duplicate accounting first.
      const duplicateMemory = createdShellProcesses.reduce(
        (total, process) => total + SHELL_MEMORY_TARGETS[process.name],
        0,
      );
      const internals = internalsOf(kernel);
      internals._resources.usedMemory = Math.max(0, internals._resources.usedMemory - duplicateMemory);

      for (const process of createdShellProcesses) {
        kernel.updateProcessMemory(process.pid, SHELL_MEMORY_TARGETS[process.name]);
      }
      kernel.emit('memoryChange', { ...internals._resources });
    }

    reconcileActiveWindow(kernel);
    return true;
  }) as KernelInstance['loadShell'];

  reconcileActiveWindow(kernel);
  return kernel;
}
