import { test, expect } from './fixtures/cloudos.fixture';
import { login, waitForDesktop } from './helpers/cloudos.ui';
import fs from 'node:fs';
import path from 'node:path';

type Status = 'PASSOU' | 'FALHOU' | 'ALERTA';
type MissionResult = {
  id: number;
  name: string;
  status: Status;
  durationMs: number;
  details: string[];
  alerts: string[];
  error?: string;
  screenshot?: string;
};
type RuntimeSnapshot = {
  mission: number;
  label: string;
  heapUsed: number | null;
  heapTotal: number | null;
  nodes: number | null;
  jsEventListeners: number | null;
  localStorageBytes: number;
  localStorageKeys: number;
  timeoutCount: number | null;
  intervalCount: number | null;
  resizeObservers: number | null;
  mutationObservers: number | null;
  windows: number;
};

const ROOT = path.resolve(process.cwd(), 'test-results/human-simulation');
const SHOTS = path.join(ROOT, 'screenshots');
const RESULTS = path.join(ROOT, 'v2-results');
const REPORT = path.resolve(process.cwd(), 'HUMAN_SIMULATION_REPORT.md');
const RUN_TOKEN = 'HUMAN-V2-7B5D8F2B';

function missionFile(id: number) { return path.join(RESULTS, `mission-${id}.json`); }
function snapshotFile(id: number) { return path.join(RESULTS, `mission-${id}-snapshots.json`); }
function errorText(cause: unknown) { return cause instanceof Error ? (cause.stack || cause.message) : String(cause); }
function escapeCell(value: string) { return value.replace(/\|/g, '\\|').replace(/\r?\n/g, ' '); }
function humanBytes(value: number | null) {
  if (value === null) return 'n/d';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  return `${(value / 1024 / 1024).toFixed(1)} MiB`;
}

function writeResult(result: MissionResult) {
  fs.mkdirSync(RESULTS, { recursive: true });
  fs.writeFileSync(missionFile(result.id), JSON.stringify(result, null, 2), 'utf8');
}

async function installProbe(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    const state = { timeouts: new Set<number>(), intervals: new Set<number>(), resizeObservers: 0, mutationObservers: 0 };
    const st = window.setTimeout.bind(window);
    const ct = window.clearTimeout.bind(window);
    const si = window.setInterval.bind(window);
    const ci = window.clearInterval.bind(window);
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      let id = 0;
      if (typeof handler === 'function') {
        const wrapped = (...values: unknown[]) => {
          state.timeouts.delete(id);
          return (handler as (...items: unknown[]) => unknown)(...values);
        };
        id = st(wrapped as TimerHandler, timeout, ...args);
      } else id = st(handler, timeout, ...args);
      state.timeouts.add(id);
      return id;
    }) as typeof window.setTimeout;
    window.clearTimeout = ((id?: number) => { if (typeof id === 'number') state.timeouts.delete(id); return ct(id); }) as typeof window.clearTimeout;
    window.setInterval = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      const id = si(handler, timeout, ...args); state.intervals.add(id); return id;
    }) as typeof window.setInterval;
    window.clearInterval = ((id?: number) => { if (typeof id === 'number') state.intervals.delete(id); return ci(id); }) as typeof window.clearInterval;

    const RO = window.ResizeObserver;
    if (RO) {
      window.ResizeObserver = class extends RO {
        private tracked = true;
        constructor(callback: ResizeObserverCallback) { super(callback); state.resizeObservers += 1; }
        disconnect() { if (this.tracked) { this.tracked = false; state.resizeObservers = Math.max(0, state.resizeObservers - 1); } return super.disconnect(); }
      };
    }
    const MO = window.MutationObserver;
    if (MO) {
      window.MutationObserver = class extends MO {
        private tracked = true;
        constructor(callback: MutationCallback) { super(callback); state.mutationObservers += 1; }
        disconnect() { if (this.tracked) { this.tracked = false; state.mutationObservers = Math.max(0, state.mutationObservers - 1); } return super.disconnect(); }
      };
    }
    Object.defineProperty(window, '__cloudosHumanProbeV2', { value: { snapshot: () => ({
      timeoutCount: state.timeouts.size,
      intervalCount: state.intervals.size,
      resizeObservers: state.resizeObservers,
      mutationObservers: state.mutationObservers,
    }) } });
  });
}

async function boot(page: import('@playwright/test').Page, cloudos: any) {
  await installProbe(page);
  await cloudos.createAdmin();
  await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
  await expect(page.locator('.desktop')).toBeVisible();
}

async function ensureWorkspace(page: import('@playwright/test').Page) {
  let workspace = page.locator('.workflow-workspace').last();
  if (!await workspace.isVisible().catch(() => false)) {
    await page.keyboard.press('Control+Alt+1');
    workspace = page.locator('.workflow-workspace').last();
    await expect(workspace).toBeVisible({ timeout: 15_000 });
  }
  await workspace.click({ position: { x: 650, y: 120 } }).catch(() => undefined);
  return workspace;
}

async function createWorkspace(page: import('@playwright/test').Page, name: string) {
  const workspace = await ensureWorkspace(page);
  await workspace.getByRole('button', { name: /Novo workspace/i }).click();
  const modal = page.locator('.ww-modal').last();
  await expect(modal).toBeVisible();
  await modal.getByRole('textbox', { name: 'Nome', exact: true }).fill(name);
  await modal.getByRole('textbox', { name: 'Cliente', exact: true }).fill(`Cliente ${name}`);
  await modal.getByRole('textbox', { name: 'Descrição', exact: true }).fill(`Simulação humana ${name}`);
  await modal.getByRole('button', { name: /Criar workspace/i }).click();
  await expect(modal).toHaveCount(0, { timeout: 15_000 });
  await expect(workspace.locator('.ww-header h2')).toHaveText(name, { timeout: 15_000 });
  return workspace;
}

async function notesTab(page: import('@playwright/test').Page) {
  const workspace = await ensureWorkspace(page);
  await workspace.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
  await expect(workspace.locator('.ww-notes')).toBeVisible();
  return workspace;
}

async function createNote(page: import('@playwright/test').Page) {
  const workspace = await notesTab(page);
  const rows = workspace.locator('.ww-notes aside > button');
  const before = await rows.count();
  await workspace.locator('.ww-note-tools button').click();
  await expect(rows).toHaveCount(before + 1, { timeout: 10_000 });
  await expect(workspace.locator('textarea[aria-label="Nota Markdown"]')).toBeVisible();
  return workspace;
}

async function ensureFiles(page: import('@playwright/test').Page) {
  let files = page.locator('.cf-root').last();
  let filesWindow = page.locator('.window:has(.cf-root)').last();
  if (await files.isVisible().catch(() => false) && await filesWindow.evaluate(element => element.classList.contains('active')).catch(() => false)) {
    return files;
  }

  const workspace = await ensureWorkspace(page);
  const workspaceWindow = page.locator('.window:has(.workflow-workspace)').last();
  if (!await workspaceWindow.evaluate(element => element.classList.contains('active')).catch(() => false)) {
    await page.keyboard.press('Control+Alt+1');
    await expect(workspaceWindow).toHaveClass(/active/, { timeout: 10_000 });
  }

  await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Files', exact: true }).click();
  files = page.locator('.cf-root').last();
  filesWindow = page.locator('.window:has(.cf-root)').last();
  await expect(files).toBeVisible({ timeout: 15_000 });
  await expect(filesWindow).toHaveClass(/active/, { timeout: 10_000 });
  return files;
}

async function createFile(page: import('@playwright/test').Page, name: string) {
  const files = await ensureFiles(page);
  await files.getByRole('button', { name: /＋ Arquivo/ }).click();
  const modal = page.locator('.cf-modal').last();
  await expect(modal).toBeVisible();
  await modal.locator('.cf-dialog-input').fill(name);
  await modal.getByRole('button', { name: 'Confirmar', exact: true }).click();
  await expect(modal).toHaveCount(0, { timeout: 10_000 });
  await expect(files.locator('.cf-item', { hasText: name })).toBeVisible({ timeout: 10_000 });
}

async function ensureTerminal(page: import('@playwright/test').Page) {
  let terminal = page.locator('.terminal-workspace').last();
  if (!await terminal.isVisible().catch(() => false)) {
    await page.keyboard.press('Control+Alt+3');
    terminal = page.locator('.terminal-workspace').last();
    await expect(terminal).toBeVisible({ timeout: 15_000 });
  }
  await terminal.click({ position: { x: 700, y: 130 } }).catch(() => undefined);
  return terminal;
}

async function runtimeSnapshot(page: import('@playwright/test').Page, mission: number, label: string): Promise<RuntimeSnapshot> {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('HeapProfiler.collectGarbage').catch(() => undefined);
  const heap = await cdp.send('Runtime.getHeapUsage').catch(() => null) as any;
  const dom = await cdp.send('Memory.getDOMCounters').catch(() => null) as any;
  await cdp.detach().catch(() => undefined);
  const browser = await page.evaluate(() => {
    const probe = (window as any).__cloudosHumanProbeV2?.snapshot?.() || {};
    let localStorageBytes = 0;
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i) || '';
      localStorageBytes += new TextEncoder().encode(key + (localStorage.getItem(key) || '')).byteLength;
    }
    return {
      localStorageBytes,
      localStorageKeys: localStorage.length,
      windows: document.querySelectorAll('.window').length,
      timeoutCount: Number.isFinite(probe.timeoutCount) ? probe.timeoutCount : null,
      intervalCount: Number.isFinite(probe.intervalCount) ? probe.intervalCount : null,
      resizeObservers: Number.isFinite(probe.resizeObservers) ? probe.resizeObservers : null,
      mutationObservers: Number.isFinite(probe.mutationObservers) ? probe.mutationObservers : null,
    };
  });
  return { mission, label, heapUsed: heap?.usedSize ?? null, heapTotal: heap?.totalSize ?? null, nodes: dom?.nodes ?? null, jsEventListeners: dom?.jsEventListeners ?? null, ...browser };
}

async function runMission(
  id: number,
  name: string,
  page: import('@playwright/test').Page,
  body: (details: string[], alerts: string[]) => Promise<void>,
) {
  const started = Date.now();
  const details: string[] = [];
  const alerts: string[] = [];
  let result: MissionResult;
  try {
    await body(details, alerts);
    const shot = path.join(SHOTS, `mission-${id}-pass.png`);
    await page.screenshot({ path: shot, fullPage: true });
    result = { id, name, status: alerts.length ? 'ALERTA' : 'PASSOU', durationMs: Date.now() - started, details, alerts, screenshot: path.relative(process.cwd(), shot).replace(/\\/g, '/') };
  } catch (cause) {
    const shot = path.join(SHOTS, `mission-${id}-failure.png`);
    await page.screenshot({ path: shot, fullPage: true }).catch(() => undefined);
    result = { id, name, status: 'FALHOU', durationMs: Date.now() - started, details, alerts, error: errorText(cause), screenshot: path.relative(process.cwd(), shot).replace(/\\/g, '/') };
  }
  writeResult(result);
  if (result.status === 'FALHOU') throw new Error(`Missão ${id} falhou: ${result.error}`);
}

function buildReport() {
  const results: MissionResult[] = [];
  const snapshots: RuntimeSnapshot[] = [];
  for (let id = 1; id <= 6; id += 1) {
    if (fs.existsSync(missionFile(id))) results.push(JSON.parse(fs.readFileSync(missionFile(id), 'utf8')));
    else results.push({ id, name: `MISSÃO ${id}`, status: 'FALHOU', durationMs: 0, details: [], alerts: [], error: 'A missão terminou sem produzir resultado (timeout/crash/aborto do runner).' });
    if (fs.existsSync(snapshotFile(id))) snapshots.push(...JSON.parse(fs.readFileSync(snapshotFile(id), 'utf8')));
  }
  const failed = results.filter(item => item.status === 'FALHOU').length;
  const alerted = results.filter(item => item.status === 'ALERTA').length;
  const lines = [
    '# HUMAN_SIMULATION_REPORT.md', '',
    '## CloudOS Workflow — Human User Simulation v2', '',
    '**Branch:** `stabilization/cloudos-workflow-batch-4`  ',
    `**Commit executado:** \`${process.env.GITHUB_SHA || 'local'}\`  `,
    `**Resultado:** ${failed ? `${failed} missão(ões) FALHOU` : alerted ? `${alerted} missão(ões) com ALERTA` : 'todas as missões PASSARAM'}`, '',
    '> Execução Playwright real contra frontend compilado + backend temporário CloudOS. Operações funcionais são UI/teclado; CDP/page.evaluate são usados somente para telemetria.', '',
    '| Missão | Status | Duração |', '|---|---|---:|',
    ...results.map(item => `| ${item.id}. ${escapeCell(item.name)} | **${item.status}** | ${(item.durationMs / 1000).toFixed(1)} s |`), ''
  ];
  for (const item of results) {
    lines.push(`## Missão ${item.id} — ${item.name}`, '', `**${item.status}**`, '');
    item.details.forEach(detail => lines.push(`- ${detail}`));
    item.alerts.forEach(alert => lines.push(`- **ALERTA:** ${alert}`));
    if (item.error) lines.push('', '```text', item.error.slice(0, 12000), '```');
    if (item.screenshot) lines.push('', `Screenshot: \`${item.screenshot}\``);
    lines.push('');
  }
  lines.push('## Telemetria', '', '| Missão/Ponto | Heap | DOM nodes | JS listeners | localStorage | timers | intervals | ResizeObserver | MutationObserver | janelas |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  snapshots.forEach(item => lines.push(`| ${item.mission}/${item.label} | ${humanBytes(item.heapUsed)} | ${item.nodes ?? 'n/d'} | ${item.jsEventListeners ?? 'n/d'} | ${humanBytes(item.localStorageBytes)} | ${item.timeoutCount ?? 'n/d'} | ${item.intervalCount ?? 'n/d'} | ${item.resizeObservers ?? 'n/d'} | ${item.mutationObservers ?? 'n/d'} | ${item.windows} |`));
  fs.writeFileSync(REPORT, lines.join('\n'), 'utf8');
  fs.writeFileSync(path.join(ROOT, 'human-simulation-v2.json'), JSON.stringify({ results, snapshots }, null, 2), 'utf8');
}

test.describe('Workflow Human User Simulation v2', () => {
  test.beforeAll(() => {
    fs.rmSync(RESULTS, { recursive: true, force: true });
    fs.mkdirSync(RESULTS, { recursive: true });
    fs.mkdirSync(SHOTS, { recursive: true });
  });
  test.afterAll(() => buildReport());

  test('1 CLIENTE NOVO', async ({ page, cloudos }) => {
    test.setTimeout(5 * 60_000);
    await boot(page, cloudos);
    await runMission(1, 'CLIENTE NOVO', page, async (details) => {
      const workspace = await createWorkspace(page, 'Cliente Humano 001');
      details.push('Workspace criado pela UI.');
      await createNote(page);
      const editor = workspace.locator('textarea[aria-label="Nota Markdown"]');
      await editor.fill(`# Cliente\n\n${RUN_TOKEN}\nconteúdo inicial`);
      await page.keyboard.press('Control+s');
      await expect(workspace.locator('.ww-note-head')).toContainText('Salvo');
      await editor.fill(`# Cliente\n\n${RUN_TOKEN}\nconteúdo inicial\nedição posterior preservada`);
      await page.keyboard.press('Control+s');
      await expect(workspace.locator('.ww-note-head')).toContainText('Salvo');
      details.push('Note criada, salva e editada.');
      await workspace.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
      await workspace.locator('.ww-evidence-compose textarea').fill('Evidence criada pelo usuário simulado.');
      await workspace.locator('.ww-evidence-compose').getByRole('button', { name: 'Salvar', exact: true }).click();
      await expect(workspace.locator('.ww-evidence-list')).not.toContainText('Nenhuma evidência');
      details.push('Evidence criada.');
      const downloadEvent = page.waitForEvent('download', { timeout: 20_000 });
      await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true }).click();
      const download = await downloadEvent;
      expect(download.suggestedFilename()).toMatch(/\.cloudos-workspace\.zip$/);
      details.push(`Export ZIP real: ${download.suggestedFilename()}.`);
      await page.locator('.window:has(.workflow-workspace)').last().locator('button.window-btn.close').click();
      await page.keyboard.press('Control+Alt+1');
      await expect(page.locator('.workflow-workspace')).toBeVisible();
      await page.reload({ waitUntil: 'domcontentloaded' });
      if (!await page.locator('.desktop').isVisible().catch(() => false)) await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
      else await waitForDesktop(page);
      const reopened = await ensureWorkspace(page);
      await expect(reopened.locator('.ww-workspace-list')).toContainText('Cliente Humano 001');
      await reopened.locator('.ww-workspace-list button', { hasText: 'Cliente Humano 001' }).click();
      await reopened.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
      await expect(reopened.locator('textarea[aria-label="Nota Markdown"]')).toHaveValue(/edição posterior preservada/);
      await reopened.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
      await expect(reopened.locator('.ww-evidence-list')).not.toContainText('Nenhuma evidência');
      details.push('Persistência e contexto confirmados após fechar/reabrir/reload.');
    });
  });

  test('2 DIA DE TRABALHO', async ({ page, cloudos }) => {
    test.setTimeout(8 * 60_000);
    await boot(page, cloudos);
    await createWorkspace(page, 'Dia de Trabalho');
    await runMission(2, 'DIA DE TRABALHO', page, async (details, alerts) => {
      const latencies: number[] = [];
      for (let index = 0; index < 240; index += 1) {
        const begin = Date.now();
        const op = index % 6;
        if (op === 0) {
          await page.keyboard.press('Alt+Space');
          await expect(page.locator('.wf-launcher')).toBeVisible({ timeout: 4_000 });
          await page.keyboard.press('Escape');
        } else if (op === 1) {
          await page.keyboard.press('Control+Alt+V');
          const panel = page.locator('.wf-clipboard-panel');
          await expect(panel).toBeVisible({ timeout: 4_000 });
          await panel.locator('header button').click();
        } else if (op === 2) {
          await page.keyboard.press('Control+Alt+1');
          await ensureWorkspace(page);
        } else if (op === 3) {
          await page.keyboard.press('Control+Alt+2');
          const workspace = await ensureWorkspace(page);
          await workspace.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
        } else if (op === 4) {
          const workspace = await ensureWorkspace(page);
          await workspace.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
        } else {
          const workspace = await ensureWorkspace(page);
          await workspace.locator('.ww-tabs').getByRole('button', { name: 'Clipboard', exact: true }).click();
        }
        latencies.push(Date.now() - begin);
        if (index % 40 === 0) await expect(page.locator('.desktop')).toBeVisible();
      }
      const sorted = [...latencies].sort((a, b) => a - b);
      const p95 = sorted[Math.floor(sorted.length * .95)] || 0;
      const max = sorted.at(-1) || 0;
      details.push(`240 operações UI/teclado concluídas; p95=${p95}ms, máximo=${max}ms.`);
      if (p95 > 1000) alerts.push(`p95 acima de 1s: ${p95}ms.`);
    });
  });

  test('3 FILES', async ({ page, cloudos }) => {
    test.setTimeout(6 * 60_000);
    await boot(page, cloudos);
    await createWorkspace(page, 'Files Humano');
    await runMission(3, 'FILES', page, async (details, alerts) => {
      for (const name of ['cliente.txt', 'dados.json', 'registro.log', 'leia-me.md']) await createFile(page, name);
      details.push('txt/md/json/log criados pela UI.');
      for (const name of ['cliente.txt', 'dados.json', 'registro.log', 'leia-me.md']) {
        const files = await ensureFiles(page);
        await files.locator('.cf-item', { hasText: name }).first().dblclick();
        const quick = page.locator('.ww-quick-editor').last();
        await expect(quick).toBeVisible({ timeout: 10_000 });
        await expect(quick.locator('.ww-note-head')).toContainText(name);
        await quick.getByRole('button', { name: 'Fechar', exact: true }).click();
      }
      details.push('Associação de arquivo abriu os quatro tipos no Notes.');
      const files = await ensureFiles(page);
      const row = files.locator('.cf-item', { hasText: 'cliente.txt' }).first();
      await row.click();
      const shelf = page.locator('.wb4-files');
      await expect(shelf).toBeVisible();
      await shelf.getByRole('button', { name: /Favorito/ }).click();
      await shelf.getByRole('button', { name: /Fixar/ }).click();
      await expect(shelf).toContainText('cliente.txt');
      const bridge = page.locator('.wf-files-bridge');
      await bridge.getByRole('button', { name: 'Recentes', exact: true }).click();
      await expect(bridge.locator('.wf-files-recents')).toContainText('cliente.txt');
      await row.getByRole('button', { name: 'Renomear', exact: true }).click();
      const modal = page.locator('.cf-modal').last();
      await modal.locator('.cf-dialog-input').fill('cliente-renomeado.txt');
      await modal.getByRole('button', { name: 'Confirmar', exact: true }).click();
      await expect(files.locator('.cf-item', { hasText: 'cliente-renomeado.txt' })).toBeVisible();
      const stale = (await shelf.getByText('cliente.txt', { exact: true }).count()) + (await bridge.locator('.wf-files-recents').getByText('cliente.txt', { exact: true }).count());
      if (stale) alerts.push('Referência stale reproduzida após rename em Favoritos/Fixados/Recentes.');
      details.push('Favoritos, Fixados e Recentes exercitados; rename verificado contra stale references.');
    });
  });

  test('4 TERMINAL', async ({ page, cloudos }) => {
    test.setTimeout(5 * 60_000);
    await boot(page, cloudos);
    await runMission(4, 'TERMINAL', page, async (details, alerts) => {
      let terminal = await ensureTerminal(page);
      const tabs = terminal.locator('.terminal-tab');
      const initial = await tabs.count();
      for (let i = 0; i < 3; i += 1) await page.keyboard.press('Control+t');
      await expect(tabs).toHaveCount(Math.min(8, initial + 3));
      const created = await tabs.count();
      const activeIdBefore = await terminal.locator('.terminal-tab.is-active').getAttribute('class');
      const activeIndexBefore = await terminal.locator('.terminal-tab').evaluateAll(items => items.findIndex(item => item.classList.contains('is-active')));
      await page.keyboard.press('Control+Tab');
      const activeIndexAfter = await terminal.locator('.terminal-tab').evaluateAll(items => items.findIndex(item => item.classList.contains('is-active')));
      await page.keyboard.press('Control+Shift+Tab');
      const activeIndexBack = await terminal.locator('.terminal-tab').evaluateAll(items => items.findIndex(item => item.classList.contains('is-active')));
      if (created > 1 && activeIndexAfter === activeIndexBefore) alerts.push('Ctrl+Tab não mudou o índice da aba ativa.');
      expect(activeIndexBack).toBe(activeIndexBefore);
      await page.keyboard.press('Control+w');
      await expect(tabs).toHaveCount(Math.max(1, created - 1));
      const persistedBefore = await page.evaluate(() => localStorage.getItem('cloudos_terminal_workspace_v1'));
      expect(persistedBefore).toBeTruthy();
      const expectedCount = await tabs.count();
      await page.locator('.window:has(.terminal-workspace)').last().locator('button.window-btn.close').click();
      terminal = await ensureTerminal(page);
      await expect(terminal.locator('.terminal-tab')).toHaveCount(expectedCount);
      const persistedAfter = await page.evaluate(() => localStorage.getItem('cloudos_terminal_workspace_v1'));
      expect(persistedAfter).toBe(persistedBefore);
      details.push(`${created} abas exercitadas; Ctrl+T/Ctrl+W/Ctrl+Tab/Ctrl+Shift+Tab e restauração validados.`);
      void activeIdBefore;
    });
  });

  test('5 LONG SESSION', async ({ page, cloudos }) => {
    test.setTimeout(8 * 60_000);
    await boot(page, cloudos);
    await createWorkspace(page, 'Long Session');
    await runMission(5, 'LONG SESSION', page, async (details, alerts) => {
      const snapshots: RuntimeSnapshot[] = [];
      snapshots.push(await runtimeSnapshot(page, 5, 'baseline'));
      const checkpoints = [{ label: '1h', loops: 150 }, { label: '2h', loops: 300 }, { label: '4h', loops: 600 }, { label: '8h', loops: 1200 }];
      let done = 0;
      for (const checkpoint of checkpoints) {
        while (done < checkpoint.loops) {
          const op = done % 5;
          if (op === 0) { await page.keyboard.press('Alt+Space'); await expect(page.locator('.wf-launcher')).toBeVisible({ timeout: 3_000 }); await page.keyboard.press('Escape'); }
          else if (op === 1) { const ws = await ensureWorkspace(page); await ws.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click(); }
          else if (op === 2) { const ws = await ensureWorkspace(page); await ws.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click(); }
          else if (op === 3) { await page.keyboard.press('Control+Alt+V'); const panel = page.locator('.wf-clipboard-panel'); await expect(panel).toBeVisible({ timeout: 3_000 }); await panel.locator('header button').click(); }
          else { await page.keyboard.press('Control+Alt+1'); await ensureWorkspace(page); }
          done += 1;
        }
        snapshots.push(await runtimeSnapshot(page, 5, checkpoint.label));
      }
      fs.writeFileSync(snapshotFile(5), JSON.stringify(snapshots, null, 2));
      const first = snapshots[0], last = snapshots.at(-1)!;
      if (first.heapUsed && last.heapUsed && last.heapUsed > first.heapUsed * 3) alerts.push(`Heap cresceu >3x: ${humanBytes(first.heapUsed)} → ${humanBytes(last.heapUsed)}.`);
      if (first.jsEventListeners !== null && last.jsEventListeners !== null && last.jsEventListeners > first.jsEventListeners + 200) alerts.push(`JS listeners cresceram +${last.jsEventListeners - first.jsEventListeners}.`);
      if (first.resizeObservers !== null && last.resizeObservers !== null && last.resizeObservers > first.resizeObservers + 20) alerts.push('ResizeObservers cresceram continuamente.');
      if (first.mutationObservers !== null && last.mutationObservers !== null && last.mutationObservers > first.mutationObservers + 20) alerts.push('MutationObservers cresceram continuamente.');
      details.push('Horizontes 1h/2h/4h/8h simulados por 150/300/600/1200 operações determinísticas com snapshots de heap/listeners/timers/observers/localStorage.');
    });
  });

  test('6 STRESS 100 Workspaces 500 1000 Notes', async ({ page, cloudos }) => {
    test.setTimeout(20 * 60_000);
    await boot(page, cloudos);
    await createWorkspace(page, 'Stress Workspace 001');
    await runMission(6, 'STRESS — 100 Workspaces / 500 / 1000 Notes', page, async (details, alerts) => {
      const snapshots: RuntimeSnapshot[] = [await runtimeSnapshot(page, 6, 'start')];
      for (let i = 2; i <= 100; i += 1) await createWorkspace(page, `Stress Workspace ${String(i).padStart(3, '0')}`);
      const workspace = await ensureWorkspace(page);
      await expect(workspace.locator('.ww-workspace-list > button')).toHaveCount(100, { timeout: 20_000 });
      snapshots.push(await runtimeSnapshot(page, 6, '100-workspaces'));
      details.push('100 Workspaces criados pela UI e todos preservados no catálogo visual.');

      await notesTab(page);
      const rows = workspace.locator('.ww-notes aside > button');
      for (let i = 1; i <= 1000; i += 1) {
        const before = await rows.count();
        await workspace.locator('.ww-note-tools button').click();
        await expect(rows).toHaveCount(before + 1, { timeout: 10_000 });
        if (i === 500 || i === 1000) {
          const editor = workspace.locator('textarea[aria-label="Nota Markdown"]');
          await editor.fill(`${RUN_TOKEN}-${i}`);
          await page.keyboard.press('Control+s');
          await expect(workspace.locator('.ww-note-head')).toContainText('Salvo');
          const search = workspace.locator('.ww-note-tools input');
          await search.fill(`${RUN_TOKEN}-${i}`);
          await expect(workspace.locator('.ww-search-status')).toContainText('1 nota', { timeout: 30_000 });
          await search.fill('');
          snapshots.push(await runtimeSnapshot(page, 6, `${i}-notes`));
        }
      }
      expect(await rows.count()).toBe(1000);
      const first = rows.first();
      const last = rows.last();
      await first.click();
      await expect(first).toHaveClass(/active/);
      await last.click();
      await expect(last).toHaveClass(/active/);
      const editor = workspace.locator('textarea[aria-label="Nota Markdown"]');
      await editor.fill(`${RUN_TOKEN}-1000-editado`);
      await page.keyboard.press('Control+s');
      const downloadEvent = page.waitForEvent('download', { timeout: 60_000 });
      await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true }).click();
      const download = await downloadEvent;
      expect(download.suggestedFilename()).toMatch(/\.cloudos-workspace\.zip$/);
      snapshots.push(await runtimeSnapshot(page, 6, 'after-export'));
      fs.writeFileSync(snapshotFile(6), JSON.stringify(snapshots, null, 2));
      const startHeap = snapshots[0].heapUsed, endHeap = snapshots.at(-1)!.heapUsed;
      if (startHeap && endHeap && endHeap > startHeap * 8) alerts.push(`Heap após stress >8x baseline: ${humanBytes(startHeap)} → ${humanBytes(endHeap)}.`);
      details.push('500 e 1000 Notes alcançadas pela UI; busca de conteúdo, troca, edição e export ZIP executados.');
    });
  });
});
