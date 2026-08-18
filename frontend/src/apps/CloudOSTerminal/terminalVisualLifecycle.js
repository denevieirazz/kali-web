export const TERMINAL_MIN_HOST_WIDTH = 24;
export const TERMINAL_MIN_HOST_HEIGHT = 24;

const defaultRequestFrame = callback => globalThis.requestAnimationFrame(callback);
const defaultCancelFrame = frame => globalThis.cancelAnimationFrame(frame);

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
