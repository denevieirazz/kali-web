import net from 'node:net';

export const HOST_LEASE_PROTOCOL = 1;
export const HOST_LEASE_HANDSHAKE_TYPE = 'cloudos-runtime-lease';
export const HOST_LEASE_ACCEPTED_TYPE = 'cloudos-runtime-lease-accepted';
const PIPE_NAME_PATTERN = /^CloudOS\.Runtime\.Lease\.[A-F0-9]{48}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAXIMUM_ACK_BYTES = 4096;

function parsePositiveInteger(value) {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function isCanonicalLeaseToken(token) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9+/]{64}$/.test(token)) return false;
  try {
    const decoded = Buffer.from(token, 'base64');
    return decoded.length === 48 && decoded.toString('base64') === token;
  } catch {
    return false;
  }
}

/**
 * Returns null for the regular browser/dev server. Native mode is fail-closed:
 * a missing or malformed lease prevents the privileged local agent starting.
 */
export function readHostLeaseConfig(environment = process.env) {
  if (environment.CLOUDOS_NATIVE_HOST !== '1') return null;

  const pipeName = environment.CLOUDOS_HOST_LEASE_PIPE;
  const token = environment.CLOUDOS_HOST_LEASE_TOKEN;
  const runId = environment.CLOUDOS_RUN_ID;
  const hostPid = parsePositiveInteger(environment.CLOUDOS_PARENT_PID);

  if (!PIPE_NAME_PATTERN.test(String(pipeName || ''))) {
    throw new Error('CLOUDOS_HOST_LEASE_PIPE ausente ou inválido.');
  }
  if (!isCanonicalLeaseToken(token)) {
    throw new Error('CLOUDOS_HOST_LEASE_TOKEN ausente ou inválido.');
  }
  if (typeof runId !== 'string' || !UUID_PATTERN.test(runId)) {
    throw new Error('CLOUDOS_RUN_ID ausente ou inválido para a lease.');
  }
  if (hostPid === null) {
    throw new Error('CLOUDOS_PARENT_PID ausente ou inválido para a lease.');
  }

  return Object.freeze({ pipeName, token, runId, hostPid });
}

export function createHostLeaseHandshake(config, pid = process.pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new TypeError('PID inválido para a lease.');
  return `${JSON.stringify({
    protocol: HOST_LEASE_PROTOCOL,
    type: HOST_LEASE_HANDSHAKE_TYPE,
    pid,
    runId: config.runId,
    token: config.token
  })}\n`;
}

export function parseHostLeaseAcknowledgement(line, config) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    throw new Error('A confirmação da lease não contém JSON válido.');
  }

  if (message?.protocol !== HOST_LEASE_PROTOCOL ||
      message?.type !== HOST_LEASE_ACCEPTED_TYPE ||
      message?.runId !== config.runId ||
      message?.hostPid !== config.hostPid) {
    throw new Error('A confirmação da lease não corresponde ao host esperado.');
  }
  return Object.freeze({ protocol: message.protocol, hostPid: message.hostPid, runId: message.runId });
}

function pipePath(pipeName) {
  return `\\\\.\\pipe\\${pipeName}`;
}

/**
 * Connects and authenticates the backend to its exact parent host. The returned
 * socket remains referenced deliberately: its close event is the host-death
 * signal. `onLost` is invoked at most once and never for an intentional close.
 */
export function connectHostLease(config, {
  pid = process.pid,
  timeoutMs = 30_000,
  onLost = () => {}
} = {}) {
  if (!config) throw new TypeError('Configuração da lease é obrigatória.');

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ path: pipePath(config.pipeName) });
    let acknowledgement = '';
    let accepted = false;
    let settled = false;
    let intentionalClose = false;
    let lossReported = false;

    const timeout = setTimeout(() => {
      fail(new Error('Tempo limite excedido ao autenticar a lease do host.'));
    }, timeoutMs);

    function clearHandshakeTimeout() {
      clearTimeout(timeout);
    }

    function reportLoss(error) {
      if (!accepted || intentionalClose || lossReported) return;
      lossReported = true;
      queueMicrotask(() => onLost(error));
    }

    function fail(error) {
      if (!settled) {
        settled = true;
        clearHandshakeTimeout();
        socket.destroy();
        reject(error);
      } else {
        reportLoss(error);
      }
    }

    socket.setEncoding('utf8');
    socket.once('connect', () => {
      socket.write(createHostLeaseHandshake(config, pid));
    });
    socket.on('data', (chunk) => {
      if (accepted) return;
      acknowledgement += chunk;
      if (Buffer.byteLength(acknowledgement, 'utf8') > MAXIMUM_ACK_BYTES) {
        fail(new Error('A confirmação da lease excedeu o limite permitido.'));
        return;
      }

      const newline = acknowledgement.indexOf('\n');
      if (newline < 0) return;
      try {
        parseHostLeaseAcknowledgement(acknowledgement.slice(0, newline).replace(/\r$/, ''), config);
      } catch (error) {
        fail(error);
        return;
      }

      accepted = true;
      settled = true;
      clearHandshakeTimeout();
      resolve(Object.freeze({
        protocol: HOST_LEASE_PROTOCOL,
        close() {
          if (intentionalClose) return;
          intentionalClose = true;
          socket.end();
        }
      }));
    });
    socket.on('end', () => reportLoss(new Error('O host encerrou a lease do runtime.')));
    socket.on('close', () => {
      if (!settled) fail(new Error('A lease foi fechada antes da autenticação.'));
      else reportLoss(new Error('A conexão da lease com o host foi perdida.'));
    });
    socket.on('error', (error) => fail(error));
  });
}
