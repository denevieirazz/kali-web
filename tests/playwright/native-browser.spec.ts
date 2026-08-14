import { test, expect, chromium, type Browser, type BrowserContext, type Page, type TestInfo } from '@playwright/test';
import { execFile, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { getFreePort, startNativeBrowserServer } from './helpers/nativeBrowserServer';

const execFileAsync = promisify(execFile);
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

test.describe('Navegador CloudOS — WebView2 real', () => {
  test.skip(process.platform !== 'win32', 'WebView2 real exige Windows.');
  test.describe.configure({ mode: 'serial', timeout: 150_000 });
  test.use({ trace: 'off' });

  let testServer: Awaited<ReturnType<typeof startNativeBrowserServer>>;
  let host: ChildProcess | undefined;
  let browser: Browser | undefined;
  let context: BrowserContext | undefined;
  let page: Page | undefined;
  let tempRoot = '';
  let readyFile = '';
  let controlFile = '';
  let statusFile = '';
  let logFile = '';
  let stdout = '';
  let stderr = '';
  const traceSteps: string[] = [];

  const record = (message: string) => traceSteps.push(`${new Date().toISOString()} ${message}`);

  test.beforeAll(async ({}, testInfo) => {
    try {
      testServer = await startNativeBrowserServer();
      const debugPort = await getFreePort();
      tempRoot = await mkdtemp(path.join(os.tmpdir(), 'cloudos-native-browser-'));
      readyFile = path.join(tempRoot, 'ready.txt');
      controlFile = path.join(tempRoot, 'control.txt');
      statusFile = path.join(tempRoot, 'status.json');
      logFile = path.join(tempRoot, 'testhost.log');
      record('test server started');

      host = spawn('dotnet', [
        'run', '--project', 'desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj', '-c', 'Release', '--',
        '--debug-port', String(debugPort),
        '--root', tempRoot,
        '--ready-file', readyFile,
        '--control-file', controlFile,
        '--status-file', statusFile,
        '--log-file', logFile,
        '--backend-origin', `${testServer.backendOrigin}/`,
        '--url', `${testServer.origin}/xfo-deny`,
      ], { cwd: process.cwd(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      host.stdout?.on('data', (chunk) => { stdout += chunk.toString(); });
      host.stderr?.on('data', (chunk) => { stderr += chunk.toString(); });
      record(`test host spawned pid=${host.pid ?? 'unknown'}`);

      const deadline = Date.now() + 90_000;
      while (!existsSync(readyFile)) {
        if (existsSync(readyFile + '.error')) throw new Error(await readFile(readyFile + '.error', 'utf8'));
        if (host.exitCode !== null) throw new Error(`Browser test host encerrou com código ${host.exitCode}.`);
        if (Date.now() > deadline) throw new Error('Browser test host não ficou pronto.');
        await delay(250);
      }
      record('test host ready');

      let lastError: unknown;
      while (Date.now() < deadline) {
        try {
          browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
          break;
        } catch (error) {
          lastError = error;
          await delay(250);
        }
      }
      if (!browser) throw lastError instanceof Error ? lastError : new Error('Não foi possível conectar ao CDP WebView2.');
      context = browser.contexts()[0];
      page = context?.pages()[0];
      if (!context || !page) throw new Error('WebView2 não expôs contexto/página ao CDP de teste.');
      await page.waitForLoadState('domcontentloaded');
      record('CDP connected');
    } catch (error) {
      await attachDiagnostics(testInfo, error instanceof Error ? error.message : String(error));
      throw error;
    }
  });

  test.afterEach(async ({}, testInfo) => {
    if (testInfo.status !== testInfo.expectedStatus)
      await attachDiagnostics(testInfo, `status=${testInfo.status}`);
  });

  test.afterAll(async ({}, testInfo) => {
    let teardownError: Error | undefined;
    try {
      if (browser?.isConnected()) {
        try { await browser.close(); }
        catch (error) { record(`CDP close failed ${error instanceof Error ? error.name : 'Error'}`); }
      }
      await terminateOwnedHost();
      if (testServer) await testServer.close();
      await removeTempRoot();
    } catch (error) {
      teardownError = error instanceof Error ? error : new Error(String(error));
      await attachDiagnostics(testInfo, `teardown=${teardownError.message}`);
    }
    if (teardownError) throw teardownError;
  });

  test('X-Frame-Options DENY e CSP frame-ancestors none carregam como top-level', async () => {
    const current = mustPage();
    await expect(current.locator('#xfo')).toHaveText('XFO top-level carregado');
    record('XFO top-level accepted');
    await current.goto(`${testServer.origin}/csp-deny`);
    await expect(current.locator('#csp')).toHaveText('CSP top-level carregado');
    record('CSP top-level accepted');
  });

  test('site externo não recebe bridge, nonce, runtime nem host object CloudOS', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/probe`);
    const isolation = await current.evaluate(() => ({
      webMessage: typeof (window as any).chrome?.webview?.postMessage,
      nonce: typeof (window as any).__cloudosNativeNonce,
      runtime: typeof (window as any).__CLOUDOS_RUNTIME__,
    }));
    expect(isolation.webMessage).not.toBe('function');
    expect(isolation.nonce).toBe('undefined');
    expect(isolation.runtime).toBe('undefined');
    record('bridge nonce runtime absent');
  });

  test('window.open cria nova aba WebView2 e cookies são compartilhados somente no profile Browser', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/popup`);
    const previousCount = mustContext().pages().length;
    await current.locator('#popup').click();
    await expect.poll(() => mustContext().pages().length).toBe(previousCount + 1);
    const popup = mustContext().pages().at(-1)!;
    await expect(popup.locator('#child')).toHaveText('Popup em aba');
    record('popup became WebView tab');

    await current.goto(`${testServer.origin}/cookie`);
    await popup.goto(`${testServer.origin}/probe`);
    expect(await popup.evaluate(() => document.cookie)).toContain('cloudos_browser_test=shared');
    record('browser profile cookie shared between tabs');
  });

  test('redirect e fetch não alcançam origens CloudOS internas; websocket externo é rejeitado', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/probe`);
    await current.goto(`${testServer.origin}/redirect-shell`).catch(() => undefined);
    expect(current.url()).not.toContain('cloudos.local');
    record('redirect to shell blocked');

    const httpBeforeRedirect = testServer.getBackendHttpHits();
    await current.goto(`${testServer.origin}/redirect-backend`).catch(() => undefined);
    expect(testServer.getBackendHttpHits()).toBe(httpBeforeRedirect);
    record('redirect to backend blocked before request');

    await current.goto(`${testServer.origin}/network-probe`);
    const httpBeforeFetch = testServer.getBackendHttpHits();
    const fetchResult = await current.evaluate(async () => {
      try {
        const response = await fetch((window as any).backendOrigin + '/fetch-probe');
        return { resolved: true, status: response.status };
      } catch {
        return { resolved: false, status: 0 };
      }
    });
    expect(testServer.getBackendHttpHits()).toBe(httpBeforeFetch);
    expect(fetchResult.resolved ? fetchResult.status : 403).toBe(403);
    record('fetch to backend intercepted');

    const upgradeBefore = testServer.getBackendUpgradeHits();
    const websocketResult = await current.evaluate(async () => await new Promise<string>((resolve) => {
      const socket = new WebSocket((window as any).backendWsOrigin + '/ws/terminal');
      const timer = window.setTimeout(() => { socket.close(); resolve('timeout'); }, 3000);
      socket.onopen = () => { window.clearTimeout(timer); socket.close(); resolve('open'); };
      socket.onerror = () => { window.clearTimeout(timer); resolve('error'); };
      socket.onclose = () => { window.clearTimeout(timer); resolve('closed'); };
    }));
    expect(websocketResult).not.toBe('open');
    expect(testServer.getBackendUpgradeHits()).toBe(upgradeBefore + 1);
    record('websocket backend probe rejected by backend boundary');
  });

  test('file e CloudOS shell permanecem bloqueados por navegação', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/probe`);
    await current.goto('file:///C:/Windows/win.ini').catch(() => undefined);
    expect(current.url()).not.toMatch(/^file:/i);
    await current.goto('https://cloudos.local/').catch(() => undefined);
    expect(current.url()).not.toContain('cloudos.local');
    record('file and shell top-level blocked');
  });

  test('dois downloads podem ser cancelados em lote', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/downloads`);
    await current.evaluate(() => {
      (document.querySelector('#download-one') as HTMLAnchorElement).click();
      (document.querySelector('#download-two') as HTMLAnchorElement).click();
    });
    await expect.poll(async () => (await readStatus()).activeDownloadCount).toBe(2);
    expect(testServer.getStartedDownloads()).toBeGreaterThanOrEqual(2);
    record('two downloads active');

    await sendControl('cancel-downloads');
    await expect.poll(async () => (await readStatus()).activeDownloadCount).toBe(0);
    await expect.poll(() => testServer.getAbortedDownloads()).toBeGreaterThanOrEqual(2);
    record('multiple downloads cancelled');
  });

  test('renderer recupera uma vez e segunda falha em 30s encerra o loop', async () => {
    const current = mustPage();
    await current.goto(`${testServer.origin}/probe`);
    const logicalUrl = current.url();
    const session = await mustContext().newCDPSession(current);
    await session.send('Page.crash').catch(() => undefined);
    record('first renderer crash requested');

    await expect.poll(() => mustContext().pages().filter(candidate => !candidate.isClosed() && candidate.url() === logicalUrl).length).toBeGreaterThanOrEqual(1);
    const replacement = mustContext().pages().find(candidate => !candidate.isClosed() && candidate.url() === logicalUrl);
    if (!replacement) throw new Error('A primeira recuperação do renderer não criou uma aba utilizável.');
    await replacement.waitForLoadState('domcontentloaded').catch(() => undefined);
    const secondSession = await mustContext().newCDPSession(replacement);
    await secondSession.send('Page.crash').catch(() => undefined);
    record('second renderer crash requested');

    await expect.poll(async () => (await readStatus()).activeErrorCode).toBe('RENDERER_CRASHED');
    record('crash loop stopped');
  });

  test('fechar Browser com download ativo cancela transferência e encerra TestHost sem deixar temp root', async () => {
    const live = mustContext().pages().find(candidate => !candidate.isClosed());
    if (!live) throw new Error('Nenhuma aba WebView2 permaneceu disponível para o teste de encerramento.');
    await live.goto(`${testServer.origin}/downloads`);
    await live.evaluate(() => (document.querySelector('#download-one') as HTMLAnchorElement).click());
    await expect.poll(async () => (await readStatus()).activeDownloadCount).toBeGreaterThanOrEqual(1);
    record('download active before close');

    await sendControl('close-browser');
    await waitForHostExit(15_000);
    await expect.poll(() => testServer.getAbortedDownloads()).toBeGreaterThanOrEqual(3);
    record('browser close cancelled download and host exited');
  });

  function mustPage(): Page {
    if (!page || page.isClosed()) {
      const live = context?.pages().find(candidate => !candidate.isClosed());
      if (!live) throw new Error('Página WebView2 indisponível.');
      page = live;
    }
    return page;
  }

  function mustContext(): BrowserContext {
    if (!context) throw new Error('Contexto WebView2 indisponível.');
    return context;
  }

  async function sendControl(command: string) {
    if (!controlFile) throw new Error('Control file não configurado.');
    await writeFile(controlFile, command, 'utf8');
    record(`control ${command}`);
  }

  async function readStatus(): Promise<{ activeDownloadCount: number; activeErrorCode?: string; closed: boolean }> {
    let lastError: unknown;
    for (let attempt = 0; attempt < 10; attempt++) {
      try {
        const raw = await readFile(statusFile, 'utf8');
        const parsed = JSON.parse(raw) as { ActiveDownloadCount?: number; activeDownloadCount?: number; ActiveErrorCode?: string; activeErrorCode?: string; closed?: boolean };
        return {
          activeDownloadCount: parsed.activeDownloadCount ?? parsed.ActiveDownloadCount ?? 0,
          activeErrorCode: parsed.activeErrorCode ?? parsed.ActiveErrorCode,
          closed: parsed.closed === true,
        };
      } catch (error) {
        lastError = error;
        await delay(50);
      }
    }
    throw lastError instanceof Error ? lastError : new Error('Status do TestHost indisponível.');
  }

  async function waitForHostExit(timeoutMs: number) {
    if (!host || host.exitCode !== null) return;
    await Promise.race([
      new Promise<void>((resolve) => host!.once('exit', () => resolve())),
      delay(timeoutMs).then(() => { throw new Error('TestHost não encerrou dentro do timeout.'); }),
    ]);
  }

  async function terminateOwnedHost() {
    if (!host || host.exitCode !== null) return;
    if (!host.pid) throw new Error('PID do TestHost criado pelo teste não está disponível.');
    record(`taskkill owned pid=${host.pid}`);
    try {
      await execFileAsync('taskkill', ['/PID', String(host.pid), '/T', '/F'], { windowsHide: true });
    } catch (error) {
      if (host.exitCode === null)
        throw new Error(`Falha ao encerrar PID de teste ${host.pid}: ${error instanceof Error ? error.message : String(error)}`);
    }
    await waitForHostExit(10_000);
  }

  async function removeTempRoot() {
    if (!tempRoot) return;
    for (let attempt = 0; attempt < 8; attempt++) {
      await rm(tempRoot, { recursive: true, force: true }).catch(() => undefined);
      if (!existsSync(tempRoot)) return;
      await delay(250 * (attempt + 1));
    }
    throw new Error('UDF temporário do Browser permaneceu bloqueado após o encerramento do TestHost.');
  }

  function sanitize(value: string): string {
    let output = value;
    if (tempRoot) output = output.replaceAll(tempRoot, '<temp>');
    output = output.replace(/(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\s*[:=]\s*|\s+)[^\s,;]+/gi, '$1=<redacted>');
    return output.slice(0, 65_536);
  }

  async function attachDiagnostics(testInfo: TestInfo, reason: string) {
    const sections = [`reason=${sanitize(reason)}`, ...traceSteps.map(sanitize)];
    if (logFile && existsSync(logFile)) {
      try { sections.push('--- testhost ---', sanitize(await readFile(logFile, 'utf8'))); }
      catch (error) { sections.push(`testhost-read-error=${error instanceof Error ? error.name : 'Error'}`); }
    }
    if (stdout) sections.push('--- stdout ---', sanitize(stdout));
    if (stderr) sections.push('--- stderr ---', sanitize(stderr));
    await testInfo.attach('native-browser-sanitized-trace.txt', {
      body: Buffer.from(sections.join('\n'), 'utf8'),
      contentType: 'text/plain',
    });

    const live = context?.pages().find(candidate => !candidate.isClosed());
    if (live) {
      try {
        await testInfo.attach('native-browser-failure.png', {
          body: await live.screenshot({ type: 'png' }),
          contentType: 'image/png',
        });
      } catch (error) {
        sections.push(`screenshot-error=${error instanceof Error ? error.name : 'Error'}`);
      }
    }
  }
});
