import { test, expect, type TestInfo } from '@playwright/test';
import { execFile, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { getFreePort } from './helpers/nativeBrowserServer';

const execFileAsync = promisify(execFile);
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Status = {
  closed: boolean;
  windowVisible: boolean;
  initializationStarted: boolean;
  webViewReady: boolean;
  initializationErrorCode?: string;
};

test.describe('Navegador CloudOS — lifecycle Windows', () => {
  test.skip(process.platform !== 'win32', 'Lifecycle nativo exige Windows.');
  test.describe.configure({ mode: 'serial', timeout: 90_000 });

  test('janela fica visível antes do CoreWebView2 e fecha durante inicialização', async ({}, testInfo) => {
    const harness = await startHarness(testInfo, ['--environment-delay-ms', '10000']);
    try {
      const beforeReady = await harness.waitForStatus((status) => status.windowVisible && status.initializationStarted && !status.webViewReady);
      expect(beforeReady.windowVisible).toBe(true);
      expect(beforeReady.webViewReady).toBe(false);

      const started = Date.now();
      await harness.sendControl('close-browser');
      await harness.waitForExit(5_000);
      expect(Date.now() - started).toBeLessThan(5_000);
    } finally {
      await harness.dispose();
    }
  });

  test('falha do environment permanece visível na BrowserWindow e não encerra Host', async ({}, testInfo) => {
    const harness = await startHarness(testInfo, ['--environment-fail']);
    try {
      const failed = await harness.waitForStatus((status) =>
        status.windowVisible && status.initializationErrorCode === 'BROWSER_WEBVIEW_INITIALIZATION_FAILED');
      expect(failed.webViewReady).toBe(false);
      expect(harness.process.exitCode).toBeNull();

      await harness.sendControl('close-browser');
      await harness.waitForExit(5_000);
    } finally {
      await harness.dispose();
    }
  });

  test('inicialização normal progride do loading visível para WebView2 pronto', async ({}, testInfo) => {
    const harness = await startHarness(testInfo, ['--environment-delay-ms', '1200']);
    try {
      const loading = await harness.waitForStatus((status) => status.windowVisible && status.initializationStarted && !status.webViewReady);
      expect(loading.initializationErrorCode).toBeUndefined();

      const ready = await harness.waitForStatus((status) => status.windowVisible && status.webViewReady, 30_000);
      expect(ready.initializationErrorCode).toBeUndefined();

      await harness.sendControl('close-browser');
      await harness.waitForExit(5_000);
    } finally {
      await harness.dispose();
    }
  });
});

async function startHarness(testInfo: TestInfo, extraArgs: string[]) {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'cloudos-browser-lifecycle-'));
  const readyFile = path.join(tempRoot, 'ready.txt');
  const controlFile = path.join(tempRoot, 'control.txt');
  const statusFile = path.join(tempRoot, 'status.json');
  const logFile = path.join(tempRoot, 'testhost.log');
  const debugPort = await getFreePort();
  let stdout = '';
  let stderr = '';
  const process = spawn('dotnet', [
    'run', '--project', 'desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj', '-c', 'Release', '--',
    '--debug-port', String(debugPort),
    '--root', tempRoot,
    '--ready-file', readyFile,
    '--control-file', controlFile,
    '--status-file', statusFile,
    '--log-file', logFile,
    ...extraArgs,
  ], { cwd: process.cwd(), windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  process.stdout?.on('data', (chunk) => { stdout += chunk.toString(); });
  process.stderr?.on('data', (chunk) => { stderr += chunk.toString(); });

  const startupDeadline = Date.now() + 45_000;
  while (!existsSync(readyFile)) {
    if (existsSync(readyFile + '.error')) {
      const error = await readFile(readyFile + '.error', 'utf8');
      await attachDiagnostics(testInfo, tempRoot, logFile, statusFile, stdout, stderr, `startup=${error}`);
      throw new Error(`Browser TestHost falhou antes de exibir a janela: ${error}`);
    }
    if (process.exitCode !== null) {
      await attachDiagnostics(testInfo, tempRoot, logFile, statusFile, stdout, stderr, `exit=${process.exitCode}`);
      throw new Error(`Browser TestHost encerrou com código ${process.exitCode}.`);
    }
    if (Date.now() > startupDeadline) {
      await attachDiagnostics(testInfo, tempRoot, logFile, statusFile, stdout, stderr, 'startup=timeout');
      throw new Error('BrowserWindow não ficou visível dentro do timeout do TestHost.');
    }
    await delay(100);
  }

  async function readStatus(): Promise<Status> {
    let lastError: unknown;
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        const parsed = JSON.parse(await readFile(statusFile, 'utf8')) as Record<string, unknown>;
        return {
          closed: parsed.closed === true,
          windowVisible: parsed.windowVisible === true,
          initializationStarted: parsed.initializationStarted === true,
          webViewReady: parsed.webViewReady === true,
          initializationErrorCode: typeof parsed.initializationErrorCode === 'string' ? parsed.initializationErrorCode : undefined,
        };
      } catch (error) {
        lastError = error;
        await delay(50);
      }
    }
    throw lastError instanceof Error ? lastError : new Error('Status do TestHost indisponível.');
  }

  async function waitForStatus(predicate: (status: Status) => boolean, timeoutMs = 15_000): Promise<Status> {
    const deadline = Date.now() + timeoutMs;
    let last: Status | undefined;
    while (Date.now() < deadline) {
      if (process.exitCode !== null) throw new Error(`TestHost encerrou antes do estado esperado: ${process.exitCode}.`);
      last = await readStatus();
      if (predicate(last)) return last;
      await delay(100);
    }
    throw new Error(`Estado esperado não ocorreu. Último estado: ${JSON.stringify(last)}`);
  }

  async function sendControl(command: string) {
    await writeFile(controlFile, command, 'utf8');
  }

  async function waitForExit(timeoutMs: number) {
    if (process.exitCode !== null) return;
    await Promise.race([
      new Promise<void>((resolve) => process.once('exit', () => resolve())),
      delay(timeoutMs).then(() => { throw new Error('TestHost não encerrou no prazo esperado.'); }),
    ]);
  }

  async function terminateOwnedProcess() {
    if (process.exitCode !== null) return;
    if (!process.pid) throw new Error('PID criado pelo teste não está disponível.');
    try {
      await execFileAsync('taskkill', ['/PID', String(process.pid), '/T', '/F'], { windowsHide: true });
    } catch (error) {
      if (process.exitCode === null)
        throw new Error(`Falha ao encerrar o PID ${process.pid}: ${error instanceof Error ? error.message : String(error)}`);
    }
    await waitForExit(10_000);
  }

  async function dispose() {
    try {
      await terminateOwnedProcess();
    } catch (error) {
      await attachDiagnostics(testInfo, tempRoot, logFile, statusFile, stdout, stderr, `teardown=${error instanceof Error ? error.message : String(error)}`);
      throw error;
    } finally {
      for (let attempt = 0; attempt < 8; attempt++) {
        try {
          await rm(tempRoot, { recursive: true, force: true });
        } catch (error) {
          if (attempt === 7) throw error;
        }
        if (!existsSync(tempRoot)) break;
        await delay(200 * (attempt + 1));
      }
      if (existsSync(tempRoot)) throw new Error('UDF temporário permaneceu após teardown do TestHost.');
    }
  }

  return { process, readStatus, waitForStatus, sendControl, waitForExit, dispose };
}

async function attachDiagnostics(
  testInfo: TestInfo,
  tempRoot: string,
  logFile: string,
  statusFile: string,
  stdout: string,
  stderr: string,
  reason: string,
) {
  const chunks = [reason];
  if (existsSync(logFile)) chunks.push(await readFile(logFile, 'utf8'));
  if (existsSync(statusFile)) chunks.push(await readFile(statusFile, 'utf8'));
  chunks.push(stdout, stderr);
  let sanitized = chunks.join('\n');
  sanitized = sanitized.replaceAll(tempRoot, '<temp>');
  sanitized = sanitized.replace(/(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\s*[:=]\s*|\s+)[^\s,;]+/gi, '$1=<redacted>');
  await testInfo.attach('native-browser-lifecycle.log', {
    body: Buffer.from(sanitized.slice(0, 128_000)),
    contentType: 'text/plain',
  });
}
