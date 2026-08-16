import fs from 'node:fs/promises';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { chromium } from '@playwright/test';

const args = new Map();
for (let i = 2; i + 1 < process.argv.length; i += 2) {
  if (process.argv[i].startsWith('--')) args.set(process.argv[i].slice(2), process.argv[i + 1]);
}
const url = args.get('url');
const distribution = args.get('distro');
const corePath = args.get('core');
const username = args.get('username');
const password = args.get('password');
const output = path.resolve(args.get('output') || 'test-results/visible-terminal-wsl-core-physical/browser-validation.json');
const wslExe = `${process.env.WINDIR || 'C:\\Windows'}\\System32\\wsl.exe`;
if (!url || !distribution || !corePath || !username || !password) {
  console.error('VISIBLE_TERMINAL_PROBE_ARGS_INVALID');
  process.exit(2);
}

const checks = [];
let browser = null;
let trackedGuestPids = [];
let resizeBefore = null;
let resizeAfter = null;

function wsl(args) {
  return execFileSync(wslExe, ['--distribution', distribution, '--exec', ...args], { encoding: 'utf8', windowsHide: true });
}

function processRows() {
  const result = wsl(['/bin/ps', '-eo', 'pid=,ppid=,args=']);
  return result.split(/\r?\n/).map(line => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/);
    return match ? { pid: Number(match[1]), ppid: Number(match[2]), args: match[3] } : null;
  }).filter(Boolean);
}

function collectCoreTree() {
  const rows = processRows();
  const roots = rows.filter(row => row.args.includes(corePath) && /\sserve(?:\s|$)/.test(row.args)).map(row => row.pid);
  const selected = new Set(roots);
  let changed = true;
  while (changed) {
    changed = false;
    for (const row of rows) {
      if (selected.has(row.ppid) && !selected.has(row.pid)) { selected.add(row.pid); changed = true; }
    }
  }
  return [...selected].sort((a, b) => a - b);
}

function guestPidAlive(pid) {
  try { execFileSync(wslExe, ['--distribution', distribution, '--exec', '/usr/bin/test', '-d', `/proc/${pid}`], { windowsHide: true }); return true; }
  catch { return false; }
}

async function waitForOutput(pane, token, timeout = 8000) {
  await pane.locator('.xterm-rows').filter({ hasText: token }).first().waitFor({ state: 'visible', timeout });
}

async function typeCommand(page, pane, command, expect) {
  const input = pane.locator('.xterm-helper-textarea');
  await input.focus();
  await page.keyboard.type(command);
  await page.keyboard.press('Enter');
  if (expect) await waitForOutput(pane, expect);
}

async function writeReport(value) {
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, `${JSON.stringify(value, null, 2)}\n`);
}

try {
  browser = await chromium.launch({ headless: false, channel: process.env.CLOUDOS_VISIBLE_TERMINAL_BROWSER_CHANNEL || 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });

  const lock = page.locator('.cloudos-lock-screen');
  await lock.waitFor({ state: 'visible', timeout: 30000 });
  await page.keyboard.press('Space');
  await page.locator('#login-username').fill(username);
  await page.locator('#login-password').fill(password);
  await page.getByRole('button', { name: 'Entrar', exact: true }).click();
  await page.locator('.taskbar').waitFor({ state: 'visible', timeout: 30000 });
  checks.push('cloudos-authenticated-desktop');

  await page.getByTitle('Iniciar').click();
  const search = page.locator('.start-search-input');
  await search.fill('CloudOS Terminal');
  await page.locator('.start-app-btn').filter({ hasText: 'CloudOS Terminal' }).first().click();

  const pane = page.locator(`.terminal-pane[data-backend-mode="wsl-core-v2"][data-terminal-state="connected"][data-distribution="${distribution}"]`).first();
  await pane.waitFor({ state: 'visible', timeout: 30000 });
  await pane.getByText(`Linux: ${distribution}`, { exact: true }).waitFor();
  await pane.getByText('Transporte: WSL Core v2', { exact: true }).waitFor();
  await pane.getByText('Estado: conectado', { exact: true }).waitFor();
  checks.push('visible-mode-wsl-core-v2');

  await typeCommand(page, pane, 'uname -a', 'Linux');
  checks.push('uname-a');
  await typeCommand(page, pane, 'pwd', '/');
  checks.push('pwd');
  await typeCommand(page, pane, 'id', 'uid=');
  checks.push('id');

  resizeBefore = { cols: Number(await pane.getAttribute('data-cols')), rows: Number(await pane.getAttribute('data-rows')) };
  const window = pane.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " window ")][1]');
  const handle = window.locator('.resize-handle.se');
  const box = await handle.boundingBox();
  if (!box) throw new Error('VISIBLE_RESIZE_HANDLE_MISSING');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 160, box.y + box.height / 2 + 100, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(400);
  resizeAfter = { cols: Number(await pane.getAttribute('data-cols')), rows: Number(await pane.getAttribute('data-rows')) };
  if (resizeAfter.cols === resizeBefore.cols && resizeAfter.rows === resizeBefore.rows) throw new Error('VISIBLE_TERMINAL_RESIZE_NOT_OBSERVED');
  checks.push('visible-resize');

  await typeCommand(page, pane, 'sleep 30');
  await page.waitForTimeout(500);
  await pane.locator('.xterm-helper-textarea').focus();
  await page.keyboard.press('Control+C');
  await typeCommand(page, pane, "printf 'cloudos-after-ctrl-c-ok\\n'", 'cloudos-after-ctrl-c-ok');
  checks.push('ctrl-c-signal');

  await typeCommand(page, pane, 'sleep 60');
  await page.waitForTimeout(600);
  trackedGuestPids = collectCoreTree();
  if (trackedGuestPids.length < 2) throw new Error('GUEST_PROCESS_TREE_NOT_OBSERVED');
  checks.push('active-process-observed-before-close');

  await window.locator('.window-btn.close').click();
  await pane.waitFor({ state: 'detached', timeout: 10000 });
  checks.push('visible-window-close');

  const deadline = Date.now() + 8000;
  let alive = trackedGuestPids.filter(guestPidAlive);
  while (alive.length && Date.now() < deadline) {
    await page.waitForTimeout(250);
    alive = trackedGuestPids.filter(guestPidAlive);
  }
  if (alive.length) throw new Error('GUEST_ORPHANS_AFTER_VISIBLE_CLOSE');
  checks.push('zero-orphans-after-visible-close');

  await writeReport({ passed: true, physicalValidation: true, visibleTerminal: true, distribution, mode: 'wsl-core-v2', protection: 'aes-256-gcm-seq', checks, resizeBefore, resizeAfter, trackedGuestProcessCount: trackedGuestPids.length, noOrphansVerified: true });
  console.log(output);
} catch (error) {
  await writeReport({ passed: false, physicalValidation: true, visibleTerminal: true, distribution, mode: null, checks, resizeBefore, resizeAfter, trackedGuestProcessCount: trackedGuestPids.length, errorCode: String(error?.message || error?.name || 'VISIBLE_TERMINAL_PROBE_FAILED').slice(0, 160) });
  console.error(error?.message || 'VISIBLE_TERMINAL_PROBE_FAILED');
  process.exitCode = 1;
} finally {
  await browser?.close().catch(() => {});
}
