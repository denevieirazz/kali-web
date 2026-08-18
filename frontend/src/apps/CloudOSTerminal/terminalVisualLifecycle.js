export const TERMINAL_MIN_HOST_WIDTH = 24;
export const TERMINAL_MIN_HOST_HEIGHT = 24;

const defaultRequestFrame = callback => globalThis.requestAnimationFrame(callback);
const defaultCancelFrame = frame => globalThis.cancelAnimationFrame(frame);
const defaultScheduleTask = callback => globalThis.setTimeout(callback, 0);

export function hasUsableTerminalGeometry(host) {
  if (!host || host.isConnected === false) return false;
  const width = Number(host.clientWidth || host.getBoundingClientRect?.().width || 0);
  const height = Number(host.clientHeight || host.getBoundingClientRect?.().height || 0);
  return Number.isFinite(width) && Number.isFinite(height) && width >= TERMINAL_MIN_HOST_WIDTH && height >= TERMINAL_MIN_HOST_HEIGHT;
}

export function sanitizeTerminalLifecycleError(error) {
  const message = typeof error?.message === 'string' && error.message.trim()
    ? error.message
    : 'Falha ao preparar a área visual do Terminal.';
  return message.replace(/(?:token|secret|password|authorization)\s*[:=]\s*\S+/gi, '[redacted]').slice(0, 220);
}

export class TerminalFrameScheduler {
  constructor({ requestFrame = defaultRequestFrame, cancelFrame = defaultCancelFrame, task }) {
    this.requestFrame = requestFrame;
    this.cancelFrame = cancelFrame;
    this.task = task;
    this.frame = null;
    this.disposed = false;
  }

  schedule() {
    if (this.disposed || this.frame !== null) return;
    this.frame = this.requestFrame(() => {
      this.frame = null;
      if (!this.disposed) this.task();
    });
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    if (this.frame !== null) this.cancelFrame(this.frame);
    this.frame = null;
  }
}

// xterm 5.x agenda trabalho do viewport em task + animation frame durante open/refresh.
// Ao remover rapidamente uma aba, destruir o renderer no mesmo cleanup pode deixar
// callbacks internos já enfileirados acessando um render service descartado. O
// transporte/observers são encerrados imediatamente pelo caller; somente o dispose
// visual é postergado por uma task e um frame para drenar o trabalho já pendente.
export function disposeTerminalAfterViewportSettles(terminal, {
  scheduleTask = defaultScheduleTask,
  requestFrame = defaultRequestFrame,
} = {}) {
  if (!terminal || typeof terminal.dispose !== 'function') return;
  scheduleTask(() => {
    requestFrame(() => {
      try { terminal.dispose(); } catch { /* boundary de teardown idempotente */ }
    });
  });
}

export function waitForTerminalGeometry(host, { requestFrame = defaultRequestFrame, maxFrames = 90, cancelled = () => false } = {}) {
  return new Promise(resolve => {
    let frames = 0;
    const check = () => {
      if (cancelled()) return resolve(false);
      if (hasUsableTerminalGeometry(host)) return resolve(true);
      frames += 1;
      if (frames >= maxFrames) return resolve(false);
      requestFrame(check);
    };
    check();
  });
}
