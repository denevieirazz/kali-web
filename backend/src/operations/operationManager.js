import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config/index.js';

const operations = new Map();
const activeProcesses = new Map();
const activeManaged = new Map();
const cancellationRequests = new Set();
const MAX_LOG_LINES = 160;
const JOURNAL_PATH = path.join(config.dataDir, 'operations.json');

function safeOperationEnvironment() {
  return Object.fromEntries(Object.entries(process.env).filter(([key, value]) =>
    typeof value === 'string' && !/(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT)/i.test(key)
  ));
}

function persistOperations() {
  const temporary = `${JOURNAL_PATH}.${process.pid}.tmp`;
  const snapshot = [...operations.values()]
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
    .slice(0, 100);
  fs.mkdirSync(path.dirname(JOURNAL_PATH), { recursive: true });
  fs.writeFileSync(temporary, `${JSON.stringify(snapshot, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(temporary, JOURNAL_PATH);
}

function hydrateOperations() {
  try {
    const saved = JSON.parse(fs.readFileSync(JOURNAL_PATH, 'utf8'));
    if (!Array.isArray(saved)) return;
    for (const candidate of saved.slice(0, 100)) {
      if (!candidate?.id || !candidate?.createdAt || !Array.isArray(candidate.output)) continue;
      const operation = { ...candidate, output: candidate.output.slice(-MAX_LOG_LINES) };
      if (['queued', 'running', 'cancelling'].includes(operation.status)) {
        operation.status = 'failed';
        operation.step = 'interrupted';
        operation.message = 'O agente local foi reiniciado antes de concluir esta operação.';
        operation.errorCode = 'AGENT_RESTARTED';
        operation.finishedAt = new Date().toISOString();
        operation.updatedAt = operation.finishedAt;
      }
      operations.set(operation.id, operation);
    }
    persistOperations();
  } catch (error) {
    if (error.code !== 'ENOENT') {
      try { fs.renameSync(JOURNAL_PATH, `${JOURNAL_PATH}.corrupt-${Date.now()}`); } catch {}
    }
  }
}

hydrateOperations();

function publicOperation(operation) {
  if (!operation) return null;
  return { ...operation, output: [...operation.output] };
}

export function createOperation(type, target, message = 'Preparando operação...') {
  const now = new Date().toISOString();
  const operation = {
    id: randomUUID(),
    type,
    target: target || null,
    status: 'queued',
    progress: 0,
    step: 'queued',
    message,
    output: [],
    createdAt: now,
    updatedAt: now,
    finishedAt: null,
    exitCode: null,
    errorCode: null
  };
  operations.set(operation.id, operation);
  persistOperations();
  return publicOperation(operation);
}

export function updateOperation(id, updates) {
  const current = operations.get(id);
  if (!current) return null;
  const next = { ...updates };
  if (Object.hasOwn(next, 'progress')) {
    const numeric = Number(next.progress);
    next.progress = Number.isFinite(numeric) ? Math.max(0, Math.min(100, Math.round(numeric))) : current.progress;
  }
  Object.assign(current, next, { updatedAt: new Date().toISOString() });
  persistOperations();
  return publicOperation(current);
}

export function appendOperationOutput(id, text) {
  const current = operations.get(id);
  if (!current || !text) return;
  const cleanLines = String(text)
    .replace(/\0/g, '')
    .split(/\r\n|\n|\r/)
    .map((line) => line.trimEnd())
    .filter(Boolean);
  current.output.push(...cleanLines);
  if (current.output.length > MAX_LOG_LINES) current.output.splice(0, current.output.length - MAX_LOG_LINES);
  const percentages = cleanLines
    .flatMap((line) => [...line.matchAll(/(\d{1,3}(?:[.,]\d+)?)\s*%/g)])
    .map((match) => Number.parseFloat(match[1].replace(',', '.')))
    .filter((value) => Number.isFinite(value) && value >= 0 && value <= 100);
  if (percentages.length) current.progress = Math.max(current.progress, Math.min(95, Math.round(percentages.at(-1))));
  current.updatedAt = new Date().toISOString();
  persistOperations();
}

export function getOperation(id) {
  return publicOperation(operations.get(id));
}

export function listOperations() {
  return [...operations.values()]
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
    .slice(0, 50)
    .map(publicOperation);
}

export function getActiveOperation(types = []) {
  const acceptedTypes = new Set(types);
  const active = [...operations.values()].find((operation) =>
    ['queued', 'running', 'cancelling'].includes(operation.status) &&
    (!acceptedTypes.size || acceptedTypes.has(operation.type))
  );
  return publicOperation(active);
}

function decodeProcessChunk(chunk) {
  const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
  let zeroes = 0;
  for (let index = 1; index < Math.min(buffer.length, 120); index += 2) {
    if (buffer[index] === 0) zeroes += 1;
  }
  const likelyUtf16 = buffer.length > 3 && zeroes > Math.min(8, Math.floor(buffer.length / 8));
  return buffer.toString(likelyUtf16 ? 'utf16le' : 'utf8').replace(/^\uFEFF/, '');
}

export function runProcessOperation(operation, executable, args, options = {}) {
  const id = typeof operation === 'string' ? operation : operation.id;
  const existing = operations.get(id);
  if (!existing) throw new Error('Operação não encontrada.');

  updateOperation(id, {
    status: 'running',
    progress: Math.max(existing.progress, 2),
    step: options.step || 'running',
    message: options.message || 'Operação em andamento...'
  });

  let child;
  try {
    child = spawn(executable, args, {
      cwd: options.cwd,
      env: options.env || safeOperationEnvironment(),
      windowsHide: true,
      shell: false,
      stdio: ['ignore', 'pipe', 'pipe']
    });
  } catch (error) {
    updateOperation(id, {
      status: 'failed', step: 'failed', message: error.message,
      errorCode: error.code || 'SPAWN_FAILED', finishedAt: new Date().toISOString()
    });
    return publicOperation(operations.get(id));
  }

  activeProcesses.set(id, child);
  child.stdout?.on('data', (chunk) => appendOperationOutput(id, decodeProcessChunk(chunk)));
  child.stderr?.on('data', (chunk) => appendOperationOutput(id, decodeProcessChunk(chunk)));

  child.on('error', (error) => {
    activeProcesses.delete(id);
    updateOperation(id, {
      status: 'failed', step: 'failed', message: error.message,
      errorCode: error.code || 'PROCESS_ERROR', finishedAt: new Date().toISOString()
    });
  });

  child.on('close', async (exitCode, signal) => {
    activeProcesses.delete(id);
    if (cancellationRequests.delete(id)) {
      updateOperation(id, {
        status: 'cancelled', step: 'cancelled', message: 'Operação cancelada pelo usuário.',
        exitCode, progress: 0, finishedAt: new Date().toISOString()
      });
      return;
    }
    if (exitCode === 0) {
      try {
        await options.onSuccess?.();
        updateOperation(id, {
          status: 'completed', step: 'completed', message: options.successMessage || 'Operação concluída com sucesso.',
          progress: 100, exitCode, finishedAt: new Date().toISOString()
        });
      } catch (error) {
        updateOperation(id, {
          status: 'failed', step: 'verification_failed', message: error.message,
          errorCode: 'VERIFICATION_FAILED', exitCode, finishedAt: new Date().toISOString()
        });
      }
      return;
    }
    const latest = operations.get(id);
    const lastLine = latest?.output.at(-1);
    updateOperation(id, {
      status: 'failed', step: 'failed',
      message: lastLine || `O processo terminou com código ${exitCode ?? signal ?? 'desconhecido'}.`,
      errorCode: signal ? `SIGNAL_${signal}` : `EXIT_${exitCode}`,
      exitCode, finishedAt: new Date().toISOString()
    });
  });

  return publicOperation(operations.get(id));
}

export function runManagedOperation(operation, executor, options = {}) {
  const id = typeof operation === 'string' ? operation : operation.id;
  const existing = operations.get(id);
  if (!existing) throw new Error('Operação não encontrada.');
  if (activeManaged.has(id) || activeProcesses.has(id)) throw new Error('Operação já está em execução.');

  const controller = new AbortController();
  activeManaged.set(id, controller);
  updateOperation(id, {
    status: 'running',
    progress: Math.max(existing.progress, 1),
    step: options.step || 'running',
    message: options.message || 'Operação transacional em andamento...'
  });

  const context = {
    signal: controller.signal,
    update: (updates) => updateOperation(id, updates),
    appendOutput: (text) => appendOperationOutput(id, text),
    throwIfCancelled() {
      if (controller.signal.aborted) throw Object.assign(new Error('Operação cancelada pelo usuário.'), { code: 'OPERATION_CANCELLED' });
    }
  };

  const promise = Promise.resolve()
    .then(() => executor(context))
    .then(async (result) => {
      if (controller.signal.aborted || cancellationRequests.delete(id)) {
        await options.onCancelled?.(result);
        updateOperation(id, {
          status: 'cancelled', step: 'cancelled', message: 'Operação cancelada pelo usuário.',
          progress: 0, errorCode: null, finishedAt: new Date().toISOString()
        });
        return result;
      }
      await options.onSuccess?.(result);
      updateOperation(id, {
        status: 'completed', step: 'completed',
        message: options.successMessage || 'Operação concluída com sucesso.',
        progress: 100, errorCode: null, finishedAt: new Date().toISOString()
      });
      return result;
    })
    .catch(async (error) => {
      const cancelled = controller.signal.aborted || cancellationRequests.delete(id) || error?.code === 'OPERATION_CANCELLED' || error?.name === 'AbortError';
      if (cancelled) {
        try { await options.onCancelled?.(error); } catch {}
        updateOperation(id, {
          status: 'cancelled', step: 'cancelled', message: 'Operação cancelada pelo usuário.',
          progress: 0, errorCode: null, finishedAt: new Date().toISOString()
        });
        return null;
      }
      try { await options.onFailure?.(error); } catch {}
      updateOperation(id, {
        status: 'failed', step: 'failed',
        message: typeof error?.message === 'string' ? error.message.slice(0, 240) : 'A operação transacional falhou.',
        errorCode: typeof error?.code === 'string' ? error.code.slice(0, 64) : 'MANAGED_OPERATION_FAILED',
        finishedAt: new Date().toISOString()
      });
      return null;
    })
    .finally(() => {
      activeManaged.delete(id);
      cancellationRequests.delete(id);
    });

  return { operation: getOperation(id), promise };
}

export function cancelOperation(id) {
  const child = activeProcesses.get(id);
  const managed = activeManaged.get(id);
  const operation = operations.get(id);
  if (!operation) return { found: false, cancelled: false };
  if (!['queued', 'running', 'cancelling'].includes(operation.status)) {
    return { found: true, cancelled: false, operation: publicOperation(operation) };
  }

  if (managed) {
    cancellationRequests.add(id);
    updateOperation(id, { status: 'cancelling', step: 'cancelling', message: 'Solicitando cancelamento e rollback seguro...' });
    managed.abort();
    return { found: true, cancelled: true, operation: getOperation(id) };
  }

  if (child) {
    cancellationRequests.add(id);
    updateOperation(id, { status: 'cancelling', step: 'cancelling', message: 'Solicitando cancelamento seguro...' });
    child.kill('SIGTERM');
    return { found: true, cancelled: true, operation: getOperation(id) };
  }

  if (operation.status === 'queued') {
    updateOperation(id, {
      status: 'cancelled', step: 'cancelled', message: 'Operação cancelada antes de iniciar.',
      progress: 0, errorCode: null, finishedAt: new Date().toISOString()
    });
    return { found: true, cancelled: true, operation: getOperation(id) };
  }

  return { found: true, cancelled: false, operation: publicOperation(operation) };
}

export function resetOperationsForTests() {
  for (const child of activeProcesses.values()) child.kill('SIGTERM');
  for (const controller of activeManaged.values()) controller.abort();
  activeProcesses.clear();
  activeManaged.clear();
  cancellationRequests.clear();
  operations.clear();
  try { fs.unlinkSync(JOURNAL_PATH); } catch {}
}
