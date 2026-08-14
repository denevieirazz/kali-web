import { test, expect, chromium, type Browser, type BrowserContext, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { getFreePort, startNativeBrowserServer } from './helpers/nativeBrowserServer';

test.describe('Navegador CloudOS — WebView2 real', () => {
  test.skip(process.platform !== 'win32', 'WebView2 real exige Windows.');
  test.describe.configure({ mode: 'serial', timeout: 120_000 });

  let testServer: Awaited<ReturnType<typeof startNativeBrowserServer>>;
  let host: ChildProcess;
  let browser: Browser;
  let context: BrowserContext;
  let page: Page;
  let tempRoot: string;

  test.beforeAll(async () => {
    testServer = await startNativeBrowserServer();
    const debugPort = await getFreePort();
    tempRoot = await mkdtemp(path.join(os.tmpdir(), 'cloudos-native-browser-'));
    const readyFile = path.join(tempRoot, 'ready.txt');
    host = spawn('dotnet', [
      'run', '--project', 'desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj', '-c', 'Release', '--',
      '--debug-port', String(debugPort),
      '--root', tempRoot,
      '--ready-file', readyFile,
      '--backend-origin', 'http://127.0.0.1:65534/',
      '--url', `${testServer.origin}/xfo-deny`,
    ], { cwd: process.cwd(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });

    const deadline = Date.now() + 90_000;
    while (!existsSync(readyFile)) {
      if (existsSync(readyFile + '.error')) throw new Error(await readFile(readyFile + '.error', 'utf8'));
      if (host.exitCode !== null) throw new Error(`Browser test host encerrou com código ${host.exitCode}.`);
      if (Date.now() > deadline) throw new Error('Browser test host não ficou pronto.');
      await new Promise((resolve) => setTimeout(resolve, 250));
    }

    let lastError: unknown;
    while (Date.now() < deadline) {
      try {
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
        break;
      } catch (error) {
        lastError = error;
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    }
    if (!browser!) throw lastError instanceof Error ? lastError : new Error('Não foi possível conectar ao CDP WebView2.');
    context = browser.contexts()[0];
    page = context.pages()[0];
    await page.waitForLoadState('domcontentloaded');
  });

  test.afterAll(async () => {
    try { await browser?.close(); } catch {}
    if (host && host.exitCode === null) host.kill();
    await testServer?.close();
    if (tempRoot) await rm(tempRoot, { recursive: true, force: true });
  });

  test('X-Frame-Options DENY carrega como documento top-level', async () => {
    await expect(page.locator('#xfo')).toHaveText('XFO top-level carregado');
  });

  test("CSP frame-ancestors 'none' carrega como documento top-level", async () => {
    await page.goto(`${testServer.origin}/csp-deny`);
    await expect(page.locator('#csp')).toHaveText('CSP top-level carregado');
  });

  test('site externo não recebe bridge, nonce ou runtime CloudOS', async () => {
    await page.goto(`${testServer.origin}/probe`);
    const isolation = await page.evaluate(() => ({
      webMessage: typeof (window as any).chrome?.webview?.postMessage,
      nonce: typeof (window as any).__cloudosNativeNonce,
      runtime: typeof (window as any).__CLOUDOS_RUNTIME__,
    }));
    expect(isolation.webMessage).not.toBe('function');
    expect(isolation.nonce).toBe('undefined');
    expect(isolation.runtime).toBe('undefined');
  });

  test('window.open cria nova aba WebView2 e não janela Edge externa', async () => {
    await page.goto(`${testServer.origin}/popup`);
    const previousCount = context.pages().length;
    await page.locator('#popup').click();
    await expect.poll(() => context.pages().length).toBe(previousCount + 1);
    const popup = context.pages().at(-1)!;
    await expect(popup.locator('#child')).toHaveText('Popup em aba');
  });

  test('cookies são compartilhados entre abas do profile Browser', async () => {
    await page.goto(`${testServer.origin}/cookie`);
    const other = context.pages().find((candidate) => candidate !== page) ?? page;
    await other.goto(`${testServer.origin}/probe`);
    expect(await other.evaluate(() => document.cookie)).toContain('cloudos_browser_test=shared');
  });

  test('origem cloudos.local e file:// são bloqueados', async () => {
    await page.goto(`${testServer.origin}/probe`);
    const before = page.url();
    await page.goto('https://cloudos.local/').catch(() => undefined);
    expect(page.url()).toBe(before);
    await page.goto('file:///C:/Windows/win.ini').catch(() => undefined);
    expect(page.url()).toBe(before);
  });
});
