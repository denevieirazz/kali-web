export const WSL_CORE_MODE = 'wsl-core-v2';
export const LEGACY_MODE = 'legacy-pty';
export const EMULATOR_MODE = 'emulator';
export const WSL_CORE_PROTOCOL = 2;
export const WSL_CORE_PROTECTION = 'aes-256-gcm-seq';

const MAX_ERROR = 240;
const VALID_STATES = new Set(['connecting', 'connected', 'closing', 'closed', 'failed', 'legacy-fallback']);

function isOpen(socket) {
  return socket?.readyState === 1;
}

function clamp(value, min, max, fallback) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? Math.max(min, Math.min(max, parsed)) : fallback;
}

export function sanitizeTerminalError(value) {
  let text = String(value ?? 'Falha no Terminal.')
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ')
    .replace(/(?:127\.0\.0\.1|localhost):\d{1,5}/gi, 'agente local')
    .replace(/\b(?:pid|port|porta)\s*[=:]?\s*\d+\b/gi, '[detalhe interno]')
    .replace(/\b(?:secret|token|nonce|password|credential)\s*[=:]\s*[^\s,;]+/gi, '$1=[redigido]')
    .replace(/\b(?:[A-Fa-f0-9]{48,}|[A-Za-z0-9+/]{48,}={0,2})\b/g, '[redigido]')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) text = 'Falha no Terminal.';
  return text.slice(0, MAX_ERROR);
}

function statusLabel(state, profile, distribution, mode, detail = '') {
  const distro = distribution || 'Linux';
  if (state === 'connecting') return profile === 'wsl' ? `Conectando ao Linux · ${distro}` : 'Conectando ao PowerShell';
  if (state === 'connected' && mode === WSL_CORE_MODE) return `WSL Core v2 · ${distro}`;
  if (state === 'legacy-fallback') return `Fallback legado · ${distro}`;
  if (state === 'connected') return profile === 'wsl' ? `WSL · ${distro}` : 'PowerShell · Windows';
  if (state === 'closing') return 'Encerrando sessão…';
  if (state === 'closed') return 'Sessão encerrada';
  if (state === 'failed') return detail ? sanitizeTerminalError(detail) : 'Falha na sessão';
  return state;
}

function makeStatus(state, profile, distribution, mode, detail) {
  if (!VALID_STATES.has(state)) throw new TypeError(`Invalid terminal state: ${state}`);
  return { state, label: statusLabel(state, profile, distribution, mode, detail), mode: mode || null };
}

function attach(socket, type, handler) {
  socket.addEventListener(type, handler);
  return () => socket.removeEventListener(type, handler);
}

function parseMessage(event) {
  try {
    return JSON.parse(String(event?.data ?? ''));
  } catch {
    return null;
  }
}

export function createTerminalTransport({
  socket,
  profile,
  distribution = '',
  initialCols = 100,
  initialRows = 28,
  onOutput = () => {},
  onStatus = () => {},
  onExit = () => {},
  onNotice = () => {},
} = {}) {
  if (!socket || typeof socket.addEventListener !== 'function' || typeof socket.send !== 'function') {
    throw new TypeError('A WebSocket-like transport is required.');
  }
  if (profile !== 'wsl' && profile !== 'powershell') throw new TypeError('Invalid terminal profile.');

  let disposed = false;
  let closing = false;
  let ready = false;
  let startSent = false;
  let backendMode = null;
  let latestResize = {
    cols: clamp(initialCols, 20, 300, 100),
    rows: clamp(initialRows, 5, 120, 28),
  };
  let startResize = null;
  let currentStatus = makeStatus('connecting', profile, distribution, null);
  const removers = [];

  const emitStatus = (state, detail = '') => {
    if (disposed) return;
    currentStatus = makeStatus(state, profile, distribution, backendMode, detail);
    onStatus(currentStatus);
  };

  const send = (payload) => {
    if (disposed || !isOpen(socket)) return false;
    socket.send(JSON.stringify(payload));
    return true;
  };

  const fail = (message) => {
    if (disposed) return;
    ready = false;
    const clean = sanitizeTerminalError(message);
    emitStatus('failed', clean);
    onNotice({ tone: 'error', message: clean });
  };

  const flushResize = () => {
    if (!ready || !isOpen(socket)) return false;
    if (startResize && startResize.cols === latestResize.cols && startResize.rows === latestResize.rows) return true;
    const sent = send({ type: 'resize', cols: latestResize.cols, rows: latestResize.rows });
    if (sent) startResize = { ...latestResize };
    return sent;
  };

  const handleOpen = () => {
    if (disposed || startSent) return;
    startSent = true;
    startResize = { ...latestResize };
    send({
      type: 'start',
      profile,
      distribution: profile === 'wsl' ? distribution : undefined,
      cols: latestResize.cols,
      rows: latestResize.rows,
    });
    emitStatus('connecting');
  };

  const handleMessage = (event) => {
    if (disposed) return;
    const message = parseMessage(event);
    if (!message || typeof message.type !== 'string') {
      fail('Resposta inválida do Terminal.');
      return;
    }

    if (message.type === 'backend') {
      const mode = typeof message.mode === 'string' ? message.mode : '';
      if (profile === 'wsl' && mode === WSL_CORE_MODE) {
        if (message.protocol !== WSL_CORE_PROTOCOL || message.protection !== WSL_CORE_PROTECTION) {
          fail('O Terminal recusou um backend WSL Core incompatível.');
          try { socket.close(1011, 'Backend incompatível'); } catch {}
          return;
        }
        backendMode = mode;
        ready = true;
        emitStatus('connected');
        flushResize();
        return;
      }
      if (mode === LEGACY_MODE || mode === EMULATOR_MODE) {
        backendMode = mode;
        ready = true;
        emitStatus(profile === 'wsl' ? 'legacy-fallback' : 'connected');
        flushResize();
        return;
      }
      fail('O Terminal recebeu um modo de backend não reconhecido.');
      return;
    }

    if (message.type === 'output') {
      if (typeof message.data === 'string') onOutput(message.data);
      return;
    }
    if (message.type === 'warning') {
      onNotice({ tone: 'warning', message: sanitizeTerminalError(message.data ?? 'Aviso do Terminal.') });
      return;
    }
    if (message.type === 'error') {
      fail(message.data ?? 'Falha ao iniciar o Terminal.');
      return;
    }
    if (message.type === 'exit') {
      ready = false;
      if (!closing) emitStatus('closing');
      emitStatus('closed');
      onExit({ exitCode: message.exitCode ?? null, signal: typeof message.signal === 'string' ? message.signal : '' });
      return;
    }
  };

  const handleError = () => {
    if (!disposed && currentStatus.state !== 'failed') fail('Falha na conexão do Terminal.');
  };

  const handleClose = () => {
    if (disposed) return;
    ready = false;
    if (currentStatus.state === 'failed') return;
    if (closing) emitStatus('closed');
    else if (!backendMode) fail('A conexão foi encerrada antes da sessão ficar pronta.');
    else emitStatus('closed');
  };

  removers.push(attach(socket, 'open', handleOpen));
  removers.push(attach(socket, 'message', handleMessage));
  removers.push(attach(socket, 'error', handleError));
  removers.push(attach(socket, 'close', handleClose));
  onStatus(currentStatus);

  return {
    get snapshot() {
      return {
        state: currentStatus.state,
        label: currentStatus.label,
        mode: backendMode,
        ready,
        cols: latestResize.cols,
        rows: latestResize.rows,
      };
    },
    input(data) {
      if (!ready || !isOpen(socket) || typeof data !== 'string') return false;
      if (data === '\x03') return send({ type: 'signal', signal: 'interrupt' });
      return send({ type: 'input', data });
    },
    resize(cols, rows) {
      latestResize = {
        cols: clamp(cols, 20, 300, latestResize.cols),
        rows: clamp(rows, 5, 120, latestResize.rows),
      };
      if (!ready) return false;
      return flushResize();
    },
    signal(signal) {
      if (!ready || !['interrupt', 'terminate', 'hangup'].includes(String(signal))) return false;
      return send({ type: 'signal', signal: String(signal) });
    },
    close() {
      if (disposed || closing) return;
      closing = true;
      emitStatus('closing');
      if (ready && isOpen(socket)) send({ type: 'close' });
      try { socket.close(1000, 'Terminal fechado'); } catch {}
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const remove of removers.splice(0)) remove();
      try {
        if (isOpen(socket)) {
          if (ready) socket.send(JSON.stringify({ type: 'close' }));
          socket.close(1000, 'Terminal desmontado');
        }
      } catch {}
      ready = false;
    },
  };
}
