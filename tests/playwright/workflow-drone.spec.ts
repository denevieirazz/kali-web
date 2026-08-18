import { test, expect } from './fixtures/cloudos.fixture';
import { login } from './helpers/cloudos.ui';
import fs from 'node:fs';
import path from 'node:path';
import type { Locator, Page, WebSocket } from '@playwright/test';

type Severity = 'CRÍTICO' | 'ALTO' | 'MÉDIO' | 'BAIXO';
type Finding = {
  id: string;
  severity: Severity;
  category: string;
  title: string;
  evidence: string;
  screenshot?: string;
};
type Snapshot = {
  label: string;
  heapUsed: number | null;
  heapTotal: number | null;
  domNodes: number | null;
  jsEventListeners: number | null;
  documents: number | null;
  localStorageBytes: number;
  localStorageKeys: number;
  sessionStorageBytes: number;
  sessionStorageKeys: number;
  timeouts: number | null;
  intervals: number | null;
  resizeObservers: number | null;
  mutationObservers: number | null;
  windows: number;
  terminalTabs: number;
};

type DroneState = {
  findings: Finding[];
  snapshots: Snapshot[];
  sequence: number;
};

const ROOT = path.resolve(process.cwd(), 'test-results/drone');
const SHOTS = path.join(ROOT, 'screenshots');
const FINDINGS = path.join(ROOT, 'findings.json');
const SNAPSHOTS = path.join(ROOT, 'snapshots.json');

function ensureDirs() {
  fs.mkdirSync(SHOTS, { recursive: true });
}

function textOf(cause: unknown) {
  return cause instanceof Error ? (cause.stack || cause.message) : String(cause);
}

async function shot(page: Page, name: string) {
  ensureDirs();
  const file = path.join(SHOTS, `${Date.now()}-${name.replace(/[^a-z0-9_-]+/gi, '-').slice(0, 70)}.png`);
  await page.screenshot({ path: file, fullPage: true }).catch(() => undefined);
  return path.relative(process.cwd(), file).replace(/\\/g, '/');
}

async function addFinding(state: DroneState, page: Page, severity: Severity, category: string, title: string, evidence: string, screenshot = false) {
  const finding: Finding = {
    id: `DRONE-${String(++state.sequence).padStart(4, '0')}`,
    severity,
    category,
    title,
    evidence: evidence.slice(0, 12000),
  };
  if (screenshot) finding.screenshot = await shot(page, `${category}-${state.sequence}`);
  state.findings.push(finding);
}

async function installRuntimeProbe(page: Page) {
  await page.addInitScript(() => {
    const probe = {
      timeouts: new Set<number>(),
      intervals: new Set<number>(),
      resizeObservers: 0,
      mutationObservers: 0,
      unhandled: [] as string[],
    };
    const st = window.setTimeout.bind(window);
    const ct = window.clearTimeout.bind(window);
    const si = window.setInterval.bind(window);
    const ci = window.clearInterval.bind(window);
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      let id = 0;
      const wrapped = typeof handler === 'function'
        ? (...values: unknown[]) => { probe.timeouts.delete(id); return (handler as (...items: unknown[]) => unknown)(...values); }
        : handler;
      id = st(wrapped as TimerHandler, timeout, ...args);
      probe.timeouts.add(id);
      return id;
    }) as typeof window.setTimeout;
    window.clearTimeout = ((id?: number) => { if (typeof id === 'number') probe.timeouts.delete(id); return ct(id); }) as typeof window.clearTimeout;
    window.setInterval = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      const id = si(handler, timeout, ...args); probe.intervals.add(id); return id;
    }) as typeof window.setInterval;
    window.clearInterval = ((id?: number) => { if (typeof id === 'number') probe.intervals.delete(id); return ci(id); }) as typeof window.clearInterval;

    const RO = window.ResizeObserver;
    if (RO) {
      window.ResizeObserver = class extends RO {
        private tracked = true;
        constructor(callback: ResizeObserverCallback) { super(callback); probe.resizeObservers += 1; }
        disconnect() { if (this.tracked) { this.tracked = false; probe.resizeObservers = Math.max(0, probe.resizeObservers - 1); } return super.disconnect(); }
      };
    }
    const MO = window.MutationObserver;
    if (MO) {
      window.MutationObserver = class extends MO {
        private tracked = true;
        constructor(callback: MutationCallback) { super(callback); probe.mutationObservers += 1; }
        disconnect() { if (this.tracked) { this.tracked = false; probe.mutationObservers = Math.max(0, probe.mutationObservers - 1); } return super.disconnect(); }
      };
    }
    window.addEventListener('unhandledrejection', event => {
      const reason = event.reason;
      probe.unhandled.push(reason instanceof Error ? (reason.stack || reason.message) : String(reason));
    });
    Object.defineProperty(window, '__cloudosDroneProbe', { value: {
      snapshot: () => ({
        timeouts: probe.timeouts.size,
        intervals: probe.intervals.size,
        resizeObservers: probe.resizeObservers,
        mutationObservers: probe.mutationObservers,
        unhandled: [...probe.unhandled],
      }),
    } });
  });
}

function installNetworkCapture(page: Page, state: DroneState) {
  const seen = new Set<string>();
  const unique = (key: string) => {
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  };
  page.on('pageerror', error => {
    const evidence = error.stack || error.message;
    if (unique(`page:${evidence}`)) void addFinding(state, page, 'ALTO', 'runtime', 'pageerror', evidence, true);
  });
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const evidence = message.text();
    // Falhas HTTP já são capturadas com URL/status no evento response. Não
    // duplicar o mesmo 5xx como console.error sem contexto.
    if (/Failed to load resource: the server responded with a status of 5\d\d/i.test(evidence)) return;
    if (unique(`console:${evidence}`)) void addFinding(state, page, 'MÉDIO', 'runtime', 'console.error', evidence);
  });
  page.on('requestfailed', request => {
    const failure = request.failure();
    if (!failure || failure.errorText === 'net::ERR_ABORTED') return;
    const evidence = `${request.method()} ${request.url()} - ${failure.errorText}`;
    if (unique(`request:${evidence}`)) void addFinding(state, page, 'MÉDIO', 'network', 'fetch/request failure', evidence);
  });
  page.on('response', response => {
    if (response.status() < 500) return;
    const evidence = `${response.status()} ${response.request().method()} ${response.url()}`;
    const url = new URL(response.url());
    if (response.status() === 503 && url.pathname === '/api/wsl/distributions') {
      if (unique(`environment:${evidence}`)) void addFinding(state, page, 'BAIXO', 'environment', 'WSL indisponível no runner WebOnly', evidence);
      return;
    }
    if (unique(`http:${evidence}`)) void addFinding(state, page, 'ALTO', 'network', 'HTTP 5xx', evidence);
  });
  page.on('websocket', (socket: WebSocket) => {
    socket.on('socketerror', error => {
      const evidence = `${socket.url()} - ${String(error)}`;
      if (unique(`ws:${evidence}`)) void addFinding(state, page, 'MÉDIO', 'websocket', 'WebSocket failure', evidence);
    });
  });
}

async function snapshot(page: Page, state: DroneState, label: string) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('HeapProfiler.collectGarbage').catch(() => undefined);
  const heap = await cdp.send('Runtime.getHeapUsage').catch(() => null) as any;
  const dom = await cdp.send('Memory.getDOMCounters').catch(() => null) as any;
  await cdp.detach().catch(() => undefined);
  const browser = await page.evaluate(() => {
    const bytes = (storage: Storage) => {
      let total = 0;
      for (let i = 0; i < storage.length; i += 1) {
        const key = storage.key(i) || '';
        total += new TextEncoder().encode(key + (storage.getItem(key) || '')).byteLength;
      }
      return total;
    };
    const probe = (window as any).__cloudosDroneProbe?.snapshot?.() || {};
    return {
      localStorageBytes: bytes(localStorage),
      localStorageKeys: localStorage.length,
      sessionStorageBytes: bytes(sessionStorage),
      sessionStorageKeys: sessionStorage.length,
      timeouts: Number.isFinite(probe.timeouts) ? probe.timeouts : null,
      intervals: Number.isFinite(probe.intervals) ? probe.intervals : null,
      resizeObservers: Number.isFinite(probe.resizeObservers) ? probe.resizeObservers : null,
      mutationObservers: Number.isFinite(probe.mutationObservers) ? probe.mutationObservers : null,
      windows: document.querySelectorAll('.window').length,
      terminalTabs: document.querySelectorAll('.terminal-tab').length,
      unhandled: Array.isArray(probe.unhandled) ? probe.unhandled : [],
    };
  });
  for (const rejection of browser.unhandled) {
    if (!state.findings.some(item => item.category === 'runtime' && item.title === 'unhandled rejection' && item.evidence === rejection)) {
      await addFinding(state, page, 'ALTO', 'runtime', 'unhandled rejection', rejection, true);
    }
  }
  state.snapshots.push({
    label,
    heapUsed: heap?.usedSize ?? null,
    heapTotal: heap?.totalSize ?? null,
    domNodes: dom?.nodes ?? null,
    jsEventListeners: dom?.jsEventListeners ?? null,
    documents: dom?.documents ?? null,
    localStorageBytes: browser.localStorageBytes,
    localStorageKeys: browser.localStorageKeys,
    sessionStorageBytes: browser.sessionStorageBytes,
    sessionStorageKeys: browser.sessionStorageKeys,
    timeouts: browser.timeouts,
    intervals: browser.intervals,
    resizeObservers: browser.resizeObservers,
    mutationObservers: browser.mutationObservers,
    windows: browser.windows,
    terminalTabs: browser.terminalTabs,
  });
}

async function droneClick(page: Page, state: DroneState, locator: Locator, label: string) {
  try {
    await locator.scrollIntoViewIfNeeded();
    const obstruction = await locator.evaluate(element => {
      const rect = element.getBoundingClientRect();
      const x = Math.max(0, Math.min(innerWidth - 1, rect.left + rect.width / 2));
      const y = Math.max(0, Math.min(innerHeight - 1, rect.top + rect.height / 2));
      const top = document.elementFromPoint(x, y);
      if (!top || top === element || element.contains(top) || top.contains(element)) return null;
      const style = getComputedStyle(top);
      return {
        target: `${element.tagName.toLowerCase()}${element.className ? '.' + String(element.className).replace(/\s+/g, '.') : ''}`,
        blocker: `${top.tagName.toLowerCase()}${(top as HTMLElement).className ? '.' + String((top as HTMLElement).className).replace(/\s+/g, '.') : ''}`,
        blockerZ: style.zIndex,
        pointerEvents: style.pointerEvents,
      };
    });
    if (obstruction) {
      await addFinding(state, page, 'ALTO', 'ux', `Elemento coberto: ${label}`, JSON.stringify(obstruction), true);
    }
    await locator.click({ timeout: 6_000 });
    return true;
  } catch (cause) {
    const evidence = textOf(cause);
    const pointer = /intercepts pointer events|pointer|covered|obscur/i.test(evidence);
    await addFinding(state, page, pointer ? 'ALTO' : 'MÉDIO', 'ux', pointer ? `Pointer blocked: ${label}` : `Click falhou: ${label}`, evidence, true);
    return false;
  }
}

async function auditWindowStack(page: Page, state: DroneState) {
  const result = await page.evaluate(() => {
    const windows = Array.from(document.querySelectorAll<HTMLElement>('.window'));
    const visible = windows.filter(win => {
      const style = getComputedStyle(win);
      const rect = win.getBoundingClientRect();
      return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0 && rect.width > 0 && rect.height > 0;
    });
    const active = visible.filter(win => win.classList.contains('active'));
    return {
      visible: visible.length,
      active: active.length,
      activeZ: active.map(win => getComputedStyle(win).zIndex),
      maxZ: visible.reduce((max, win) => Math.max(max, Number.parseInt(getComputedStyle(win).zIndex || '0', 10) || 0), 0),
      activeMax: active.reduce((max, win) => Math.max(max, Number.parseInt(getComputedStyle(win).zIndex || '0', 10) || 0), 0),
    };
  });
  if (result.active > 1) await addFinding(state, page, 'MÉDIO', 'ux', 'Mais de uma janela ativa', JSON.stringify(result), true);
  if (result.active === 1 && result.activeMax < result.maxZ) await addFinding(state, page, 'ALTO', 'ux', 'Janela ativa abaixo de outra janela', JSON.stringify(result), true);
}

async function ensureWorkspace(page: Page, state: DroneState) {
  let workspace = page.locator('.workflow-workspace').last();
  if (!await workspace.isVisible().catch(() => false)) {
    await page.keyboard.press('Control+Alt+1');
    workspace = page.locator('.workflow-workspace').last();
    await expect(workspace).toBeVisible({ timeout: 12_000 });
  }
  const win = page.locator('.window:has(.workflow-workspace)').last();
  await win.click({ position: { x: 500, y: 80 } }).catch(() => undefined);
  await auditWindowStack(page, state);
  return workspace;
}

async function patrolWorkspace(page: Page, state: DroneState) {
  const workspace = await ensureWorkspace(page, state);
  const newButton = workspace.getByRole('button', { name: /Novo workspace/i });
  if (await newButton.isVisible().catch(() => false)) {
    if (await droneClick(page, state, newButton, 'Novo workspace')) {
      const modal = page.locator('.ww-modal').last();
      await expect(modal).toBeVisible();
      await modal.getByRole('textbox', { name: 'Nome', exact: true }).fill('Drone Audit Workspace');
      await modal.getByRole('textbox', { name: 'Cliente', exact: true }).fill('Drone');
      await droneClick(page, state, modal.getByRole('button', { name: /Criar workspace/i }), 'Criar workspace');
      await expect(modal).toHaveCount(0, { timeout: 12_000 }).catch(() => undefined);
    }
  }

  const notesTab = workspace.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true });
  if (await droneClick(page, state, notesTab, 'Notes')) {
    const add = workspace.locator('.ww-note-tools button').first();
    if (await add.isVisible().catch(() => false)) {
      await droneClick(page, state, add, 'Criar Note');
      const editor = workspace.locator('textarea[aria-label="Nota Markdown"]');
      if (await editor.isVisible().catch(() => false)) {
        await editor.fill('Drone audit note\nconteúdo persistente para caça de defeitos');
        await page.keyboard.press('Control+s');
      }
    }
  }

  const evidenceTab = workspace.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true });
  if (await droneClick(page, state, evidenceTab, 'Evidence')) {
    const evidenceArea = workspace.locator('textarea').last();
    if (await evidenceArea.isVisible().catch(() => false)) {
      await evidenceArea.fill('Drone evidence marker');
      const saveEvidence = workspace.getByRole('button', { name: /salvar|adicionar/i }).last();
      if (await saveEvidence.isVisible().catch(() => false)) await droneClick(page, state, saveEvidence, 'Salvar Evidence');
    }
  }

  const overview = workspace.locator('.ww-tabs').getByRole('button', { name: 'Visão geral', exact: true });
  await droneClick(page, state, overview, 'Visão geral');
  const exportButton = workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true });
  if (await exportButton.isVisible().catch(() => false)) {
    const waiting = page.waitForEvent('download', { timeout: 12_000 }).catch(() => null);
    await droneClick(page, state, exportButton, 'Exportar Workspace');
    const download = await waiting;
    if (!download) await addFinding(state, page, 'ALTO', 'workspace', 'Export não produziu download', 'O clique em Exportar não gerou evento download dentro de 12s.', true);
  }
  const importInput = workspace.locator('input[type="file"]').first();
  if (!await importInput.count()) await addFinding(state, page, 'BAIXO', 'workspace', 'Import input não localizado', 'A patrulha não encontrou input file no Workspace.');
}

async function waitForTerminalReady(terminal: Locator, expectedTabs?: number) {
  await expect(terminal).toBeVisible({ timeout: 12_000 });
  await expect(terminal).not.toHaveClass(/terminal-workspace--loading/, { timeout: 12_000 });
  if (typeof expectedTabs === 'number') {
    await expect(terminal.locator('.terminal-tab')).toHaveCount(expectedTabs, { timeout: 12_000 });
  } else {
    await expect.poll(() => terminal.locator('.terminal-tab').count(), { timeout: 12_000 }).toBeGreaterThan(0);
  }
}

async function patrolTerminal(page: Page, state: DroneState) {
  await page.keyboard.press('Control+Alt+3');
  const terminal = page.locator('.terminal-workspace').last();
  await waitForTerminalReady(terminal);
  const terminalWindow = page.locator('.window:has(.terminal-workspace)').last();
  await terminalWindow.click({ position: { x: 500, y: 80 } }).catch(() => undefined);
  await auditWindowStack(page, state);
  const initial = await terminal.locator('.terminal-tab').count();
  for (let i = 0; i < 3; i += 1) await page.keyboard.press('Control+t');
  await page.keyboard.press('Control+Tab');
  await page.keyboard.press('Control+Shift+Tab');
  await page.keyboard.press('Control+w');
  const beforeClose = await terminal.locator('.terminal-tab').count();
  if (beforeClose <= initial) await addFinding(state, page, 'ALTO', 'terminal', 'Tabs não foram criadas', `inicial=${initial} antesFechar=${beforeClose}`, true);
  const closeWindow = terminalWindow.getByRole('button', { name: /Fechar/i }).first();
  if (await closeWindow.isVisible().catch(() => false)) await droneClick(page, state, closeWindow, 'Fechar Terminal');
  else await page.keyboard.press('Control+Alt+w');
  await expect(terminal).toHaveCount(0, { timeout: 10_000 }).catch(() => undefined);
  await page.keyboard.press('Control+Alt+3');
  const restored = page.locator('.terminal-workspace').last();
  try {
    await waitForTerminalReady(restored, beforeClose);
  } catch (cause) {
    const restoredCount = await restored.locator('.terminal-tab').count().catch(() => 0);
    await addFinding(state, page, 'ALTO', 'terminal', 'Terminal tab restore divergente', `esperado=${beforeClose} recebido=${restoredCount}\n${textOf(cause)}`, true);
  }
}

async function patrolUX(page: Page, state: DroneState) {
  await auditWindowStack(page, state);
  const active = page.locator('.window.active').last();
  if (await active.count()) {
    const focus = await active.evaluate(element => ({
      activeElement: document.activeElement?.tagName || null,
      activeInside: Boolean(document.activeElement && element.contains(document.activeElement)),
      display: getComputedStyle(element).display,
      visibility: getComputedStyle(element).visibility,
    }));
    if (focus.display === 'none' || focus.visibility === 'hidden') await addFinding(state, page, 'ALTO', 'ux', 'Janela ativa oculta', JSON.stringify(focus), true);
  }
  const scrollIssues = await page.evaluate(() => Array.from(document.querySelectorAll<HTMLElement>('.window.active *')).filter(el => {
    const style = getComputedStyle(el);
    return el.scrollHeight > el.clientHeight + 20 && style.overflowY === 'hidden';
  }).slice(0, 10).map(el => ({ tag: el.tagName, cls: el.className, client: el.clientHeight, scroll: el.scrollHeight })));
  if (scrollIssues.length) await addFinding(state, page, 'BAIXO', 'ux', 'Conteúdo potencialmente sem scroll', JSON.stringify(scrollIssues));
}

async function patrolMemory(page: Page, state: DroneState) {
  await snapshot(page, state, 'baseline');
  for (let cycle = 0; cycle < 80; cycle += 1) {
    await page.keyboard.press(cycle % 2 ? 'Control+Alt+1' : 'Control+Alt+3');
    if (cycle % 8 === 0) await snapshot(page, state, `loop-${cycle}`);
  }
  await snapshot(page, state, 'final');
  const first = state.snapshots[0];
  const last = state.snapshots[state.snapshots.length - 1];
  if (first?.heapUsed && last?.heapUsed && last.heapUsed > first.heapUsed * 3 && last.heapUsed - first.heapUsed > 32 * 1024 * 1024) {
    await addFinding(state, page, 'ALTO', 'memory', 'Heap cresceu fortemente durante patrulha', `inicio=${first.heapUsed} final=${last.heapUsed}`, true);
  }
  if (first?.domNodes && last?.domNodes && last.domNodes > first.domNodes * 2 && last.domNodes - first.domNodes > 3000) {
    await addFinding(state, page, 'MÉDIO', 'memory', 'DOM cresceu fortemente durante patrulha', `inicio=${first.domNodes} final=${last.domNodes}`, true);
  }
  if (last && last.localStorageBytes > 4 * 1024 * 1024) await addFinding(state, page, 'MÉDIO', 'storage', 'localStorage acima de 4 MiB', String(last.localStorageBytes));
}

function persist(state: DroneState) {
  ensureDirs();
  fs.writeFileSync(FINDINGS, JSON.stringify(state.findings, null, 2), 'utf8');
  fs.writeFileSync(SNAPSHOTS, JSON.stringify(state.snapshots, null, 2), 'utf8');
}

test('Workflow Drone — patrulha automática de defeitos', async ({ page, cloudos }) => {
  const state: DroneState = { findings: [], snapshots: [], sequence: 0 };
  ensureDirs();
  await installRuntimeProbe(page);
  installNetworkCapture(page, state);
  try {
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
    await snapshot(page, state, 'boot');

    for (const [name, task] of [
      ['workspace', () => patrolWorkspace(page, state)],
      ['terminal', () => patrolTerminal(page, state)],
      ['ux', () => patrolUX(page, state)],
      ['memory', () => patrolMemory(page, state)],
    ] as const) {
      try {
        await task();
      } catch (cause) {
        await addFinding(state, page, 'ALTO', 'drone', `Patrulha ${name} interrompida`, textOf(cause), true);
      }
      persist(state);
    }
    await snapshot(page, state, 'shutdown-snapshot');
  } finally {
    persist(state);
  }
});
