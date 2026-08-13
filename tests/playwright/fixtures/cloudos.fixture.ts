import { test as base, expect } from '@playwright/test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, ChildProcess, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { installBrowserErrorGuards } from '../helpers/cloudos.ui';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '../../../');

export interface CloudOSAdminResult {
  token: string;
  user: {
    id: string;
    username: string;
    display_name: string;
    role: string;
  };
  recoveryCode: string;
}

export interface CloudOSFixture {
  baseURL: string;
  createAdmin: () => Promise<CloudOSAdminResult>;
  stop: () => Promise<void>;
}

function processExited(child: ChildProcess): boolean {
  return child.exitCode !== null || child.signalCode !== null;
}

function waitForProcessExit(child: ChildProcess, timeoutMs: number): Promise<boolean> {
  if (processExited(child)) return Promise.resolve(true);

  return new Promise((resolve) => {
    let settled = false;
    let timer: NodeJS.Timeout | null = null;
    const finish = (exited: boolean) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      child.off('exit', onExit);
      resolve(exited);
    };
    const onExit = () => finish(true);
    child.once('exit', onExit);
    timer = setTimeout(() => finish(processExited(child)), timeoutMs);
  });
}

function forceKillProcessTree(pid: number): void {
  if (process.platform === 'win32') {
    execFileSync('taskkill.exe', ['/F', '/T', '/PID', String(pid)], {
      stdio: 'ignore',
      windowsHide: true
    });
    return;
  }
  process.kill(pid, 'SIGKILL');
}

async function stopChildProcess(child: ChildProcess): Promise<void> {
  if (processExited(child)) return;

  if (!child.pid) {
    if (await waitForProcessExit(child, 2_000)) return;
    throw new Error('O processo temporario do backend nao recebeu PID nem confirmou encerramento.');
  }

  try {
    child.kill();
  } catch {}
  if (await waitForProcessExit(child, 3_000)) return;

  try {
    forceKillProcessTree(child.pid);
  } catch {
    if (processExited(child)) return;
  }
  if (!await waitForProcessExit(child, 5_000)) {
    throw new Error(`O backend temporario (PID ${child.pid}) permaneceu ativo apos o cleanup.`);
  }
}

export const test = base.extend<{ cloudos: CloudOSFixture; browserDiagnostics: void }>({
  cloudos: async ({}, use, testInfo) => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-pw-test-'));
    const runtimeDir = path.join(tempDir, 'runtime');
    const dataDir = path.join(tempDir, 'data');
    fs.mkdirSync(runtimeDir, { recursive: true });
    fs.mkdirSync(dataDir, { recursive: true });

    const frontendDist = path.resolve(rootDir, 'frontend/dist');
    const serverScript = path.resolve(rootDir, 'backend/src/server.js');

    const cleanEnv: NodeJS.ProcessEnv = { ...process.env };
    delete cleanEnv.DATABASE_PATH;
    delete cleanEnv.CLOUDOS_NATIVE_HOST;
    delete cleanEnv.CLOUDOS_SUPERVISOR_TOKEN;
    delete cleanEnv.CLOUDOS_HOST_LEASE_PIPE;
    delete cleanEnv.CLOUDOS_HOST_LEASE_TOKEN;
    delete cleanEnv.CLOUDOS_RUN_ID;
    delete cleanEnv.CLOUDOS_PARENT_PID;

    const childEnv: NodeJS.ProcessEnv = {
      ...cleanEnv,
      NODE_ENV: 'test',
      PORT: '0',
      HOST: '127.0.0.1',
      DATABASE_PATH: path.join(dataDir, 'cloudos.json'),
      CLOUDOS_TEST_ROOT: tempDir,
      CLOUDOS_RUNTIME_DIR: runtimeDir,
      CLOUDOS_DATA_DIR: dataDir,
      CLOUDOS_FRONTEND_DIST: frontendDist,
      CLOUDOS_NATIVE_HOST: '0',
      CLOUDOS_SUPERVISOR_TOKEN: '',
      CLOUDOS_HOST_LEASE_PIPE: '',
      CLOUDOS_HOST_LEASE_TOKEN: '',
      CLOUDOS_RUN_ID: '',
      CLOUDOS_PARENT_PID: '',
      JWT_SECRET: 'cloudos-playwright-characterization-only'
    };

    let backendStdout = '';
    let backendStderr = '';
    let backendSpawnError = '';

    const backendProcess: ChildProcess = spawn(process.execPath, [serverScript], {
      cwd: rootDir,
      env: childEnv,
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false
    });
    backendProcess.once('error', (error) => {
      backendSpawnError = error.message;
    });
    backendProcess.stdout?.on('data', (data) => {
      backendStdout += data.toString();
    });
    backendProcess.stderr?.on('data', (data) => {
      backendStderr += data.toString();
    });

    let stopped = false;
    const stopBackend = async () => {
      if (stopped) return;
      stopped = true;
      await stopChildProcess(backendProcess);
    };

    try {
      const runtimePortFile = path.join(runtimeDir, 'backend-port.json');
      const startTime = Date.now();
      let port = 0;

      while (Date.now() - startTime < 20_000) {
        if (fs.existsSync(runtimePortFile)) {
          try {
            const content = JSON.parse(fs.readFileSync(runtimePortFile, 'utf8'));
            if (content && typeof content.backendPort === 'number' && content.backendPort > 0) {
              port = content.backendPort;
              break;
            }
          } catch {}
        }
        if (backendSpawnError || processExited(backendProcess)) break;
        await new Promise(resolve => setTimeout(resolve, 100));
      }

      if (!port || backendSpawnError || processExited(backendProcess)) {
        const spawnMessage = backendSpawnError ? ` Erro de spawn: ${backendSpawnError}.` : '';
        throw new Error(`Falha ao iniciar backend CloudOS temporario.${spawnMessage} Codigo de saida: ${backendProcess.exitCode}. Stderr: ${backendStderr}\nStdout: ${backendStdout}`);
      }

      const baseURL = `http://127.0.0.1:${port}`;
      let healthy = false;
      for (let attempt = 0; attempt < 30; attempt += 1) {
        try {
          const response = await fetch(`${baseURL}/api/health`);
          if (response.ok) {
            healthy = true;
            break;
          }
        } catch {}
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      if (!healthy) {
        throw new Error(`Backend CloudOS em ${baseURL} nao respondeu ao health check. Stderr: ${backendStderr}\nStdout: ${backendStdout}`);
      }

      const createAdmin = async (): Promise<CloudOSAdminResult> => {
        const response = await fetch(`${baseURL}/api/setup/admin`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            displayName: 'Playwright Admin',
            username: 'playwright.admin',
            password: 'CloudOS-Test-2026!',
            confirmPassword: 'CloudOS-Test-2026!'
          })
        });
        if (response.status !== 201) {
          const body = await response.text();
          throw new Error(`createAdmin() falhou com status ${response.status}: ${body}`);
        }
        return await response.json() as CloudOSAdminResult;
      };

      await use({
        baseURL,
        createAdmin,
        stop: stopBackend
      });
    } finally {
      if (testInfo.status !== testInfo.expectedStatus) {
        await testInfo.attach('backend-stdout.log', {
          body: backendStdout,
          contentType: 'text/plain'
        });
        await testInfo.attach('backend-stderr.log', {
          body: backendStderr,
          contentType: 'text/plain'
        });
      }

      let cleanupError: unknown;
      try {
        await stopBackend();
      } catch (error) {
        cleanupError = error;
      }

      if (!cleanupError) {
        fs.rmSync(tempDir, { recursive: true, force: true });
        if (fs.existsSync(tempDir)) {
          cleanupError = new Error(`O diretorio temporario permaneceu apos o cleanup: ${tempDir}`);
        }
      }

      if (cleanupError) throw cleanupError;
    }
  },
  browserDiagnostics: [async ({ page, cloudos }, use) => {
    void cloudos;
    const guards = installBrowserErrorGuards(page);
    try {
      await use();
    } finally {
      guards.assertNoErrors();
    }
  }, { auto: true }]
});

export { expect };
