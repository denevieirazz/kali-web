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
  label: string;
  heapUsed: number | null;
  heapTotal: number | null;
  documents: number | null;
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

const REPORT_ROOT = path.resolve(process.cwd(), 'test-results/human-simulation');
const SCREENSHOT_ROOT = path.join(REPORT_ROOT, 'screenshots');
const REPORT_FILE = path.resolve(process.cwd(), 'HUMAN_SIMULATION_REPORT.md');
const REPORT_JSON = path.join(REPORT_ROOT, 'human-simulation.json');
const CLIENT_WORKSPACE = 'Cliente Humano 001';
const UNIQUE_TEXT = 'SIM-HUMAN-UNIQUE-7B5D8F2B';

function escapeCell(value: string) {
  return value.replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function bytes(value: number | null) {
  if (value === null) return 'n/d';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  return `${(value / 1024 / 1024).toFixed(1)} MiB`;
}

async function installLongRunProbe(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    const probe = {
      timeouts: new Set<number>(),
      intervals: new Set<number>(),
      resizeObservers: 0,
      mutationObservers: 0,
    };

    const nativeSetTimeout = window.setTimeout.bind(window);
    const nativeClearTimeout = window.clearTimeout.bind(window);
    const nativeSetInterval = window.setInterval.bind(window);
    const nativeClearInterval = window.clearInterval.bind(window);

    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      let id = 0;
      if (typeof handler === 'function') {
        const wrapped = (...callbackArgs: unknown[]) => {
          probe.timeouts.delete(id);
          return (handler as (...values: unknown[]) => unknown)(...callbackArgs);
        };
        id = nativeSetTimeout(wrapped as TimerHandler, timeout, ...args);
      } else {
        id = nativeSetTimeout(handler, timeout, ...args);
      }
      probe.timeouts.add(id);
      return id;
    }) as typeof window.setTimeout;

    window.clearTimeout = ((id?: number) => {
      if (typeof id === 'number') probe.timeouts.delete(id);
      return nativeClearTimeout(id);
    }) as typeof window.clearTimeout;

    window.setInterval = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      const id = nativeSetInterval(handler, timeout, ...args);
      probe.intervals.add(id);
      return id;
    }) as typeof window.setInterval;

    window.clearInterval = ((id?: number) => {
      if (typeof id === 'number') probe.intervals.delete(id);
      return nativeClearInterval(id);
    }) as typeof window.clearInterval;

    const NativeResizeObserver = window.ResizeObserver;
    if (NativeResizeObserver) {
      window.ResizeObserver = class TrackedResizeObserver extends NativeResizeObserver {
        private __trackedDisconnected = false;
        constructor(callback: ResizeObserverCallback) {
          super(callback);
          probe.resizeObservers += 1;
        }
        disconnect() {
          if (!this.__trackedDisconnected) {
            this.__trackedDisconnected = true;
            probe.resizeObservers = Math.max(0, probe.resizeObservers - 1);
          }
          return super.disconnect();
        }
      };
    }

    const NativeMutationObserver = window.MutationObserver;
    if (NativeMutationObserver) {
      window.MutationObserver = class TrackedMutationObserver extends NativeMutationObserver {
        private __trackedDisconnected = false;
        constructor(callback: MutationCallback) {
          super(callback);
          probe.mutationObservers += 1;
        }
        disconnect() {
          if (!this.__trackedDisconnected) {
            this.__trackedDisconnected = true;
            probe.mutationObservers = Math.max(0, probe.mutationObservers - 1);
          }
          return super.disconnect();
        }
      };
    }

    Object.defineProperty(window, '__cloudosHumanProbe', {
      configurable: false,
      enumerable: false,
      value: {
        snapshot: () => ({
          timeoutCount: probe.timeouts.size,
          intervalCount: probe.intervals.size,
          resizeObservers: probe.resizeObservers,
          mutationObservers: probe.mutationObservers,
        }),
      },
    });
  });
}

async function ensureWorkspace(page: import('@playwright/test').Page) {
  const workspace = page.locator('.workflow-workspace').last();
  if (await workspace.isVisible().catch(() => false)) {
    await workspace.click({ position: { x: 500, y: 120 } }).catch(() => undefined);
    return workspace;
  }
  await page.keyboard.press('Control+Alt+1');
  await expect(workspace).toBeVisible({ timeout: 15_000 });
  return workspace;
}

async function ensureFiles(page: import('@playwright/test').Page) {
  const files = page.locator('.cf-root').last();
  if (await files.isVisible().catch(() => false)) {
    await files.click({ position: { x: 600, y: 140 } });
    return files;
  }
  const workspace = await ensureWorkspace(page);
  await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Files', exact: true }).click();
  await expect(files).toBeVisible({ timeout: 15_000 });
  return files;
}

async function ensureTerminal(page: import('@playwright/test').Page) {
  const terminal = page.locator('.terminal-workspace').last();
  if (await terminal.isVisible().catch(() => false)) {
    await terminal.click({ position: { x: 600, y: 120 } });
    return terminal;
  }
  await page.keyboard.press('Control+Alt+3');
  await expect(terminal).toBeVisible({ timeout: 15_000 });
  return terminal;
}

async function createWorkspaceViaUI(page: import('@playwright/test').Page, name: string) {
  const workspace = await ensureWorkspace(page);
  await workspace.getByRole('button', { name: /Novo workspace/i }).click();
  const modal = page.locator('.ww-modal').last();
  await expect(modal).toBeVisible();
  await modal.getByLabel('Nome').fill(name);
  await modal.getByLabel('Cliente').fill(`Cliente ${name}`);
  await modal.getByLabel('Descrição').fill(`Criado pelo simulador humano: ${name}`);
  await modal.getByRole('button', { name: /Criar workspace/i }).click();
  await expect(modal).toHaveCount(0, { timeout: 15_000 });
  await expect(workspace.locator('.ww-header h2')).toHaveText(name, { timeout: 15_000 });
}

async function openNotesTab(page: import('@playwright/test').Page) {
  const workspace = await ensureWorkspace(page);
  await workspace.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
  await expect(workspace.locator('.ww-notes')).toBeVisible();
  return workspace;
}

async function createNoteViaUI(page: import('@playwright/test').Page) {
  const workspace = await openNotesTab(page);
  const header = workspace.locator('.ww-note-head strong');
  const before = await header.textContent().catch(() => '');
  await workspace.locator('.ww-note-tools button').click();
  await expect.poll(async () => (await header.textContent().catch(() => '')) || '', { timeout: 10_000 })
    .not.toBe(before || '');
  return workspace;
}

async function createFileViaUI(page: import('@playwright/test').Page, name: string) {
  const files = await ensureFiles(page);
  await files.getByRole('button', { name: /Arquivo/, exact: false }).first().click();
  const modal = page.locator('.cf-modal').last();
  await expect(modal).toBeVisible();
  await modal.locator('.cf-dialog-input').fill(name);
  await modal.getByRole('button', { name: 'Confirmar', exact: true }).click();
  await expect(modal).toHaveCount(0, { timeout: 10_000 });
  await expect(files.locator('.cf-item', { hasText: name })).toBeVisible({ timeout: 10_000 });
}

async function snapshotRuntime(
  page: import('@playwright/test').Page,
  cdp: import('@playwright/test').CDPSession,
  label: string,
): Promise<RuntimeSnapshot> {
  await cdp.send('HeapProfiler.collectGarbage').catch(() => undefined);
  const heap = await cdp.send('Runtime.getHeapUsage').catch(() => null) as any;
  const dom = await cdp.send('Memory.getDOMCounters').catch(() => null) as any;
  const browser = await page.evaluate(() => {
    const values = Object.keys(localStorage).map(key => `${key}:${localStorage.getItem(key) || ''}`);
    const probe = (window as any).__cloudosHumanProbe?.snapshot?.() || {};
    return {
      localStorageBytes: new TextEncoder().encode(values.join('\n')).byteLength,
      localStorageKeys: localStorage.length,
      windows: document.querySelectorAll('.window').length,
      timeoutCount: Number.isFinite(probe.timeoutCount) ? probe.timeoutCount : null,
      intervalCount: Number.isFinite(probe.intervalCount) ? probe.intervalCount : null,
      resizeObservers: Number.isFinite(probe.resizeObservers) ? probe.resizeObservers : null,
      mutationObservers: Number.isFinite(probe.mutationObservers) ? probe.mutationObservers : null,
    };
  });
  return {
    label,
    heapUsed: heap?.usedSize ?? null,
    heapTotal: heap?.totalSize ?? null,
    documents: dom?.documents ?? null,
    nodes: dom?.nodes ?? null,
    jsEventListeners: dom?.jsEventListeners ?? null,
    ...browser,
  };
}

function renderReport(results: MissionResult[], snapshots: RuntimeSnapshot[], startedAt: string, finishedAt: string) {
  const failed = results.filter(item => item.status === 'FALHOU').length;
  const alerts = results.filter(item => item.status === 'ALERTA').length;
  const lines = [
    '# HUMAN_SIMULATION_REPORT.md',
    '',
    '## CloudOS Workflow — Human User Simulation',
    '',
    `**Branch:** \`stabilization/cloudos-workflow-batch-4\`  `,
    `**Commit executado:** \`${process.env.GITHUB_SHA || 'execução local'}\`  `,
    `**Início:** ${startedAt}  `,
    `**Fim:** ${finishedAt}  `,
    `**Resultado:** ${failed ? `${failed} missão(ões) FALHOU` : alerts ? `${alerts} missão(ões) com ALERTA; nenhuma falha fatal` : 'todas as missões PASSARAM'}`,
    '',
    '> Esta suíte usa Playwright contra o frontend compilado servido pelo backend CloudOS temporário. As operações funcionais são executadas pela UI e por teclado real do browser automation. Apenas telemetria é coletada por CDP/page.evaluate.',
    '',
    '## Resumo',
    '',
    '| Missão | Status | Duração |',
    '|---|---|---:|',
    ...results.map(item => `| ${item.id}. ${escapeCell(item.name)} | **${item.status}** | ${(item.durationMs / 1000).toFixed(1)} s |`),
    '',
  ];

  for (const result of results) {
    lines.push(`## Missão ${result.id} — ${result.name}`, '', `**${result.status}**`, '');
    for (const detail of result.details) lines.push(`- ${detail}`);
    for (const alert of result.alerts) lines.push(`- **ALERTA:** ${alert}`);
    if (result.error) lines.push('', '```text', result.error.slice(0, 12_000), '```');
    if (result.screenshot) lines.push('', `Screenshot: \`${result.screenshot}\``);
    lines.push('');
  }

  lines.push('## Telemetria de sessão longa', '', '| Ponto | Heap usada | Heap total | DOM nodes | JS listeners | localStorage | timers | intervals | ResizeObserver | MutationObserver | janelas |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (const item of snapshots) {
    lines.push(`| ${item.label} | ${bytes(item.heapUsed)} | ${bytes(item.heapTotal)} | ${item.nodes ?? 'n/d'} | ${item.jsEventListeners ?? 'n/d'} | ${bytes(item.localStorageBytes)} | ${item.timeoutCount ?? 'n/d'} | ${item.intervalCount ?? 'n/d'} | ${item.resizeObservers ?? 'n/d'} | ${item.mutationObservers ?? 'n/d'} | ${item.windows} |`);
  }
  lines.push('', '## Critério', '', '- **PASSOU:** fluxo concluído e invariantes funcionais preservadas.', '- **ALERTA:** fluxo concluiu, mas foi observado comportamento de escala/stale/pressão que merece revisão.', '- **FALHOU:** operação real não concluiu, perdeu persistência/integridade ou gerou exceção impeditiva.', '');
  return lines.join('\n');
}

test.describe('Workflow Human User Simulation', () => {
  test('simula cliente, dia de trabalho, Files, Terminal, sessão longa e stress', async ({ page, cloudos }, testInfo) => {
    test.setTimeout(35 * 60_000);
    fs.mkdirSync(SCREENSHOT_ROOT, { recursive: true });
    const startedAt = new Date().toISOString();
    const results: MissionResult[] = [];
    const snapshots: RuntimeSnapshot[] = [];

    await installLongRunProbe(page);
    await cloudos.createAdmin();
    await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');

    const cdp = await page.context().newCDPSession(page);
    await cdp.send('HeapProfiler.enable').catch(() => undefined);

    const mission = async (id: number, name: string, run: (details: string[], alerts: string[]) => Promise<void>) => {
      const begin = Date.now();
      const details: string[] = [];
      const alerts: string[] = [];
      let status: Status = 'PASSOU';
      let error = '';
      let screenshot = '';
      try {
        await run(details, alerts);
        if (alerts.length) status = 'ALERTA';
      } catch (cause) {
        status = 'FALHOU';
        error = cause instanceof Error ? (cause.stack || cause.message) : String(cause);
        const screenshotPath = path.join(SCREENSHOT_ROOT, `mission-${id}-failure.png`);
        await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => undefined);
        screenshot = path.relative(process.cwd(), screenshotPath).replace(/\\/g, '/');
      }
      results.push({ id, name, status, durationMs: Date.now() - begin, details, alerts, error: error || undefined, screenshot: screenshot || undefined });
    };

    await mission(1, 'CLIENTE NOVO', async (details) => {
      await ensureWorkspace(page);
      await createWorkspaceViaUI(page, CLIENT_WORKSPACE);
      details.push('Workspace criado pela UI.');

      const workspace = await createNoteViaUI(page);
      const noteEditor = workspace.locator('textarea[aria-label="Nota Markdown"]');
      const firstContent = `# Relatório do cliente\n\n${UNIQUE_TEXT}\nConteúdo inicial criado pela simulação humana.`;
      await noteEditor.fill(firstContent);
      await page.keyboard.press('Control+s');
      await expect(workspace.locator('.ww-note-head')).toContainText('Salvo', { timeout: 10_000 });
      await noteEditor.fill(`${firstContent}\nEdição humana posterior preservada.`);
      await page.keyboard.press('Control+s');
      await expect(workspace.locator('.ww-note-head')).toContainText('Salvo', { timeout: 10_000 });
      details.push('Nota criada, salva, editada e salva novamente.');

      await workspace.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
      await workspace.locator('.ww-evidence-compose textarea').fill('Evidence da sessão humana — integridade do cliente.');
      await workspace.locator('.ww-evidence-compose').getByRole('button', { name: 'Salvar', exact: true }).click();
      await expect(workspace.locator('.ww-evidence-list')).toContainText('note-', { timeout: 10_000 });
      details.push('Evidence textual criada pela UI.');

      const downloadPromise = page.waitForEvent('download', { timeout: 15_000 });
      await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true }).click();
      const download = await downloadPromise;
      const downloadPath = await download.path();
      expect(download.suggestedFilename()).toMatch(/\.cloudos-workspace\.zip$/);
      if (downloadPath) expect(fs.statSync(downloadPath).size).toBeGreaterThan(0);
      details.push(`ZIP exportado: ${download.suggestedFilename()}.`);

      const wsWindow = page.locator('.window:has(.workflow-workspace)').last();
      await wsWindow.locator('button.window-btn.close').click();
      await expect(page.locator('.workflow-workspace')).toHaveCount(0);
      await page.keyboard.press('Control+Alt+1');
      await expect(page.locator('.workflow-workspace')).toBeVisible({ timeout: 10_000 });

      await page.reload({ waitUntil: 'domcontentloaded' });
      const desktopReady = await page.locator('.desktop').isVisible({ timeout: 7_000 }).catch(() => false);
      if (!desktopReady) await login(page, cloudos.baseURL, 'playwright.admin', 'CloudOS-Test-2026!');
      else await waitForDesktop(page);
      const reopened = await ensureWorkspace(page);
      await expect(reopened.locator('.ww-workspace-list')).toContainText(CLIENT_WORKSPACE);
      await reopened.locator('.ww-workspace-list button', { hasText: CLIENT_WORKSPACE }).click();
      await reopened.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
      await expect(reopened.locator('textarea[aria-label="Nota Markdown"]')).toHaveValue(/Edição humana posterior preservada/);
      await reopened.locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true }).click();
      await expect(reopened.locator('.ww-evidence-list')).toContainText('note-');
      details.push('Persistência confirmada após fechar, reabrir e recarregar a sessão.');

      const screenshotPath = path.join(SCREENSHOT_ROOT, 'mission-1-client-reopened.png');
      await page.screenshot({ path: screenshotPath, fullPage: true });
    });

    await mission(2, 'DIA DE TRABALHO', async (details, alerts) => {
      const latencies: number[] = [];
      const operations = 240;
      for (let index = 0; index < operations; index += 1) {
        const start = performance.now();
        const op = index % 6;
        if (op === 0) {
          await page.keyboard.press('Alt+Space');
          await expect(page.locator('.wf-launcher')).toBeVisible({ timeout: 3_000 });
          await page.keyboard.press('Escape');
        } else if (op === 1) {
          await page.keyboard.press('Control+Alt+V');
          await expect(page.locator('.wf-clipboard-panel')).toBeVisible({ timeout: 3_000 });
          await page.keyboard.press('Escape');
        } else if (op === 2) {
          await page.keyboard.press('Control+Alt+1');
        } else if (op === 3) {
          await page.keyboard.press('Control+Alt+2');
        } else if (op === 4) {
          const workspace = await ensureWorkspace(page);
          await workspace.locator('.ww-tabs').getByRole('button', { name: index % 12 === 4 ? 'Evidence' : 'Notes', exact: true }).click();
        } else {
          const workspace = await ensureWorkspace(page);
          await workspace.locator('.ww-tabs').getByRole('button', { name: 'Clipboard', exact: true }).click();
        }
        latencies.push(performance.now() - start);
        if (index % 40 === 0) await expect(page.locator('.desktop')).toBeVisible();
      }
      const sorted = [...latencies].sort((a, b) => a - b);
      const p95 = sorted[Math.floor(sorted.length * 0.95)] || 0;
      const max = sorted.at(-1) || 0;
      details.push(`${operations} operações reais de teclado/UI concluídas; p95=${p95.toFixed(1)}ms, máximo=${max.toFixed(1)}ms.`);
      if (p95 > 1000) alerts.push(`Latência p95 do fluxo diário acima de 1s (${p95.toFixed(1)}ms).`);
    });

    await mission(3, 'FILES', async (details, alerts) => {
      await ensureWorkspace(page);
      const files = await ensureFiles(page);
      for (const name of ['cliente.txt', 'dados.json', 'registro.log', 'leia-me.md']) {
        if (!(await files.locator('.cf-item', { hasText: name }).count())) await createFileViaUI(page, name);
      }
      details.push('txt, json, log e md criados pela UI do Files.');

      for (const name of ['cliente.txt', 'dados.json', 'registro.log', 'leia-me.md']) {
        const activeFiles = await ensureFiles(page);
        const row = activeFiles.locator('.cf-item', { hasText: name }).first();
        await row.dblclick();
        const quickEditor = page.locator('.ww-quick-editor').last();
        await expect(quickEditor).toBeVisible({ timeout: 10_000 });
        await expect(quickEditor).toContainText(name);
        await quickEditor.getByRole('button', { name: 'Fechar', exact: true }).click();
      }
      details.push('Associação txt/md/json/log → Notes validada por duplo clique real.');

      const activeFiles = await ensureFiles(page);
      const marked = activeFiles.locator('.cf-item', { hasText: 'cliente.txt' }).first();
      await marked.click();
      const shelf = page.locator('.wb4-files');
      await expect(shelf).toBeVisible();
      await shelf.getByRole('button', { name: /Favorito/ }).click();
      await shelf.getByRole('button', { name: /Fixar/ }).click();
      await expect(shelf).toContainText('cliente.txt');
      details.push('Favorito e Fixado persistidos no shelf de acesso rápido.');

      const bridge = page.locator('.wf-files-bridge');
      await bridge.getByRole('button', { name: 'Recentes', exact: true }).click();
      const recent = bridge.locator('.wf-files-recents');
      await expect(recent).toContainText('cliente.txt');
      await expect(recent).toContainText('dados.json');
      await expect(recent).toContainText('registro.log');
      await expect(recent).toContainText('leia-me.md');
      details.push('Recentes registrou os quatro documentos realmente abertos.');

      await marked.click();
      await marked.getByRole('button', { name: 'Renomear', exact: true }).click();
      const rename = page.locator('.cf-modal').last();
      await rename.locator('.cf-dialog-input').fill('cliente-renomeado.txt');
      await rename.getByRole('button', { name: 'Confirmar', exact: true }).click();
      await expect(activeFiles.locator('.cf-item', { hasText: 'cliente-renomeado.txt' })).toBeVisible();
      const staleFavorite = await shelf.getByText('cliente.txt', { exact: true }).count();
      const staleRecent = await recent.getByText('cliente.txt', { exact: true }).count();
      if (staleFavorite || staleRecent) alerts.push('Rename mantém referência stale em Favoritos/Fixados e/ou Recentes; comportamento conhecido foi reproduzido por uso real.');
    });

    await mission(4, 'TERMINAL', async (details, alerts) => {
      const terminal = await ensureTerminal(page);
      const tabs = terminal.locator('.terminal-tab');
      const initial = await tabs.count();
      for (let i = 0; i < 3; i += 1) await page.keyboard.press('Control+t');
      await expect(tabs).toHaveCount(Math.min(initial + 3, 8), { timeout: 10_000 });
      const afterCreate = await tabs.count();
      const activeBefore = await terminal.locator('.terminal-tab.is-active .terminal-tab__title').textContent();
      await page.keyboard.press('Control+Tab');
      const activeAfter = await terminal.locator('.terminal-tab.is-active .terminal-tab__title').textContent();
      await page.keyboard.press('Control+Shift+Tab');
      const activeBack = await terminal.locator('.terminal-tab.is-active .terminal-tab__title').textContent();
      if (afterCreate > 1 && activeBefore === activeAfter) alerts.push('Ctrl+Tab não alterou o título da aba ativa; revisar foco/ciclo se as abas tiverem títulos iguais.');
      expect(activeBack).toBe(activeBefore);
      await page.keyboard.press('Control+w');
      await expect(tabs).toHaveCount(Math.max(1, afterCreate - 1));

      const savedBefore = await page.evaluate(() => localStorage.getItem('cloudos.terminal.workspace.v1') || localStorage.getItem('cloudos.terminal.workspace.v2') || Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)).find(key => key?.includes('terminal') && key?.includes('workspace')) || '');
      const wsWindow = page.locator('.window:has(.terminal-workspace)').last();
      await wsWindow.locator('button.window-btn.close').click();
      await page.keyboard.press('Control+Alt+3');
      const reopened = await ensureTerminal(page);
      await expect(reopened.locator('.terminal-tab')).toHaveCount(Math.max(1, afterCreate - 1));
      const savedAfter = await page.evaluate(() => localStorage.getItem('cloudos.terminal.workspace.v1') || localStorage.getItem('cloudos.terminal.workspace.v2') || Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)).find(key => key?.includes('terminal') && key?.includes('workspace')) || '');
      expect(savedAfter).toBe(savedBefore);
      await expect(reopened.locator('.terminal-tab.is-active [role="tab"]')).toHaveAttribute('aria-selected', 'true');
      details.push(`Abas: ${initial} → ${afterCreate} → ${Math.max(1, afterCreate - 1)}; criação, remoção, ciclo, restauração e foco validados.`);
    });

    await mission(5, 'LONG SESSION', async (details, alerts) => {
      snapshots.push(await snapshotRuntime(page, cdp, 'baseline'));
      const phases = [
        { label: '1h-simulada', cycles: 60 },
        { label: '2h-simuladas', cycles: 120 },
        { label: '4h-simuladas', cycles: 240 },
        { label: '8h-simuladas', cycles: 480 },
      ];
      for (const phase of phases) {
        for (let index = 0; index < phase.cycles; index += 1) {
          const op = index % 5;
          if (op === 0) { await page.keyboard.press('Alt+Space'); await page.keyboard.press('Escape'); }
          else if (op === 1) { await page.keyboard.press('Control+Alt+V'); await page.keyboard.press('Escape'); }
          else if (op === 2) await page.keyboard.press('Control+Alt+1');
          else if (op === 3) await page.keyboard.press('Control+Alt+2');
          else {
            await ensureWorkspace(page);
            const activeWorkspace = page.locator('.workflow-workspace').last();
            await activeWorkspace.locator('.ww-tabs').getByRole('button', { name: index % 10 === 4 ? 'Evidence' : 'Notes', exact: true }).click();
          }
        }
        snapshots.push(await snapshotRuntime(page, cdp, phase.label));
      }

      const baseline = snapshots.find(item => item.label === 'baseline')!;
      const final = snapshots.find(item => item.label === '8h-simuladas')!;
      details.push('900 ciclos determinísticos executados nos horizontes 1h/2h/4h/8h simulados.');
      details.push(`Heap após GC: ${bytes(baseline.heapUsed)} → ${bytes(final.heapUsed)}; listeners: ${baseline.jsEventListeners} → ${final.jsEventListeners}; localStorage: ${bytes(baseline.localStorageBytes)} → ${bytes(final.localStorageBytes)}.`);
      if (baseline.heapUsed !== null && final.heapUsed !== null && final.heapUsed > baseline.heapUsed + 64 * 1024 * 1024 && final.heapUsed > baseline.heapUsed * 2) {
        alerts.push(`Heap cresceu mais de 64 MiB e 2x após GC (${bytes(baseline.heapUsed)} → ${bytes(final.heapUsed)}).`);
      }
      if (baseline.jsEventListeners !== null && final.jsEventListeners !== null && final.jsEventListeners > baseline.jsEventListeners + 100) {
        alerts.push(`JS event listeners cresceram +${final.jsEventListeners - baseline.jsEventListeners} após ciclos.`);
      }
      if (baseline.resizeObservers !== null && final.resizeObservers !== null && final.resizeObservers > baseline.resizeObservers + 10) alerts.push('ResizeObservers ativos cresceram sem retornar ao patamar inicial.');
      if (baseline.mutationObservers !== null && final.mutationObservers !== null && final.mutationObservers > baseline.mutationObservers + 10) alerts.push('MutationObservers ativos cresceram sem retornar ao patamar inicial.');
      if (final.localStorageBytes > baseline.localStorageBytes + 2 * 1024 * 1024) alerts.push('localStorage cresceu mais de 2 MiB durante os ciclos determinísticos.');
      const screenshotPath = path.join(SCREENSHOT_ROOT, 'mission-5-8h-simulated.png');
      await page.screenshot({ path: screenshotPath, fullPage: true });
    });

    await mission(6, 'STRESS — 100 Workspaces / 500 / 1000 Notes', async (details, alerts) => {
      const workspace = await ensureWorkspace(page);
      const currentWorkspaceButtons = workspace.locator('.ww-workspace-list button');
      let workspaceCount = await currentWorkspaceButtons.count();
      const workspaceStart = Date.now();
      for (let index = workspaceCount; index < 100; index += 1) {
        await createWorkspaceViaUI(page, `Stress Workspace ${String(index + 1).padStart(3, '0')}`);
      }
      workspaceCount = await currentWorkspaceButtons.count();
      expect(workspaceCount).toBeGreaterThanOrEqual(100);
      details.push(`Catálogo atingiu ${workspaceCount} Workspaces pela UI em ${((Date.now() - workspaceStart) / 1000).toFixed(1)}s; nenhum truncamento observado até 100.`);

      await workspace.locator('.ww-workspace-list button', { hasText: CLIENT_WORKSPACE }).click();
      await workspace.locator('.ww-tabs').getByRole('button', { name: 'Notes', exact: true }).click();
      const notesList = workspace.locator('.ww-notes > aside > button');
      const addButton = workspace.locator('.ww-note-tools button');
      const noteHeader = workspace.locator('.ww-note-head strong');
      let noteCount = await notesList.count();

      const createUntil = async (target: number) => {
        const started = Date.now();
        while (noteCount < target) {
          const before = await noteHeader.textContent().catch(() => '');
          await addButton.click();
          await expect.poll(async () => (await noteHeader.textContent().catch(() => '')) || '', { timeout: 10_000 }).not.toBe(before || '');
          noteCount += 1;
        }
        return Date.now() - started;
      };

      const to500 = await createUntil(500);
      const snapshot500 = await snapshotRuntime(page, cdp, 'stress-500-notes');
      snapshots.push(snapshot500);
      const searchInput = workspace.locator('.ww-note-tools input');
      const search500Start = Date.now();
      await searchInput.fill(UNIQUE_TEXT);
      await expect(workspace.locator('.ww-search-status')).not.toContainText('Pesquisando conteúdo sob demanda…', { timeout: 120_000 });
      const search500Ms = Date.now() - search500Start;
      await expect(workspace.locator('.ww-search-status')).toContainText('1 nota(s)');
      await searchInput.fill('');
      details.push(`500 Notes criadas em ${(to500 / 1000).toFixed(1)}s; busca completa em ${(search500Ms / 1000).toFixed(2)}s; heap=${bytes(snapshot500.heapUsed)}.`);

      const to1000 = await createUntil(1000);
      const snapshot1000 = await snapshotRuntime(page, cdp, 'stress-1000-notes');
      snapshots.push(snapshot1000);
      const search1000Start = Date.now();
      await searchInput.fill(UNIQUE_TEXT);
      await expect(workspace.locator('.ww-search-status')).not.toContainText('Pesquisando conteúdo sob demanda…', { timeout: 180_000 });
      const search1000Ms = Date.now() - search1000Start;
      await expect(workspace.locator('.ww-search-status')).toContainText('1 nota(s)');
      details.push(`1000 Notes alcançadas; últimas 500 em ${(to1000 / 1000).toFixed(1)}s; busca completa em ${(search1000Ms / 1000).toFixed(2)}s; heap=${bytes(snapshot1000.heapUsed)}.`);

      if (search1000Ms > 30_000) alerts.push(`Busca em 1000 Notes levou ${(search1000Ms / 1000).toFixed(1)}s — gargalo de I/O O(N) reproduzido.`);
      if (snapshot500.heapUsed !== null && snapshot1000.heapUsed !== null && snapshot1000.heapUsed > snapshot500.heapUsed + 128 * 1024 * 1024) alerts.push('Heap cresceu >128 MiB entre 500 e 1000 Notes mesmo após GC; revisar custo de DOM/metadata.');

      await searchInput.fill('');
      const firstClientNote = workspace.locator('.ww-notes > aside > button').filter({ hasText: 'Relatório do cliente' }).first();
      if (await firstClientNote.count()) await firstClientNote.click();
      const editor = workspace.locator('textarea[aria-label="Nota Markdown"]');
      const content = await editor.inputValue();
      await editor.fill(`${content}\nEdição após stress 1000 Notes.`);
      await page.keyboard.press('Control+s');
      await expect(workspace.locator('.ww-note-head')).toContainText('Salvo', { timeout: 15_000 });

      const downloadPromise = page.waitForEvent('download', { timeout: 60_000 });
      await workspace.locator('.ww-quick-actions').getByRole('button', { name: 'Exportar', exact: true }).click();
      const download = await downloadPromise;
      const downloadPath = await download.path();
      const size = downloadPath ? fs.statSync(downloadPath).size : 0;
      expect(size).toBeGreaterThan(0);
      details.push(`Edição pós-stress salva e ZIP de ${bytes(size)} exportado com ~1000 notas.`);

      const screenshotPath = path.join(SCREENSHOT_ROOT, 'mission-6-stress-1000-notes.png');
      await page.screenshot({ path: screenshotPath, fullPage: true });
    });

    const finishedAt = new Date().toISOString();
    const report = renderReport(results, snapshots, startedAt, finishedAt);
    fs.mkdirSync(REPORT_ROOT, { recursive: true });
    fs.writeFileSync(REPORT_FILE, report, 'utf8');
    fs.writeFileSync(REPORT_JSON, JSON.stringify({ startedAt, finishedAt, results, snapshots }, null, 2), 'utf8');
    await testInfo.attach('HUMAN_SIMULATION_REPORT.md', { body: Buffer.from(report), contentType: 'text/markdown' });
    await testInfo.attach('human-simulation.json', { body: Buffer.from(JSON.stringify({ results, snapshots }, null, 2)), contentType: 'application/json' });

    const failures = results.filter(item => item.status === 'FALHOU');
    if (failures.length) {
      throw new Error(`Human simulation encontrou ${failures.length} missão(ões) com falha: ${failures.map(item => `${item.id}:${item.name}`).join(', ')}`);
    }
  });
});
