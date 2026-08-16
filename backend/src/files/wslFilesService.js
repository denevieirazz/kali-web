import { createWslFilesRpcSession } from './wslFilesRpcSession.js';
import { getWslSnapshot } from '../wsl/distroService.js';
import { WSL_CORE_PROTOCOL, WSL_CORE_PROTECTION } from '../terminal/wslCoreAdapter.js';

const RESET_CODES = new Set(['CHANNEL_CLOSED', 'REQUEST_TIMEOUT', 'FRAME_SEQUENCE', 'FRAME_INTEGRITY']);
const MAX_CONCURRENT = 2;

function enabled(env = process.env) {
  return env.CLOUDOS_WSL_CORE_FOUNDATION === '1' && env.CLOUDOS_WSL_CORE_FILES === '1';
}

function safeCode(error) {
  const code = typeof error?.code === 'string' ? error.code : 'FILES_UNAVAILABLE';
  return /^[A-Z0-9_]{2,64}$/.test(code) ? code : 'FILES_UNAVAILABLE';
}

function safeError(error) {
  const code = safeCode(error);
  const messages = {
    FEATURE_DISABLED: 'Linux Files está desabilitado.',
    WSL_NOT_FOUND: 'WSL não está disponível neste host.',
    DISTRO_NOT_FOUND: 'Nenhuma distribuição WSL2 disponível.',
    DISTRO_NOT_WSL2: 'Linux Files requer WSL2.',
    CORE_PATH_INVALID: 'O caminho do CloudOS Core no Linux é inválido.',
    FILES_PATH_INVALID: 'O caminho solicitado é inválido.',
    FILES_PATH_LIMIT: 'O caminho solicitado excede o limite.',
    FILES_PATH_RESERVED: 'O caminho solicitado é reservado pelo CloudOS.',
    FILES_SYMLINK_DENIED: 'Symlinks não podem ser seguidos neste escopo.',
    FILES_NOT_FOUND: 'Arquivo ou pasta não encontrado.',
    FILES_PERMISSION_DENIED: 'Permissão POSIX insuficiente para esta operação.',
    FILES_TYPE_DENIED: 'Esse tipo de entrada não pode ser manipulado.',
    FILES_ALREADY_EXISTS: 'Já existe um item com esse nome.',
    FILES_READ_FAILED: 'Falha ao ler o arquivo Linux.',
    FILES_WRITE_FAILED: 'Falha ao gravar o arquivo Linux.',
    FILES_COPY_FAILED: 'Falha ao copiar o item Linux.',
    FILES_RENAME_FAILED: 'Falha ao mover ou renomear o item Linux.',
    FILES_TRASH_FAILED: 'Falha ao mover o item para a lixeira Linux.',
    FILES_RESTORE_FAILED: 'Falha ao restaurar o item Linux.',
    FILES_DELETE_FAILED: 'Falha ao excluir o item da lixeira Linux.',
    FILES_TRASH_UNAVAILABLE: 'A lixeira Linux está indisponível.',
    REQUEST_TIMEOUT: 'A operação Linux excedeu o tempo limite.',
    CHANNEL_CLOSED: 'O canal protegido do Linux foi encerrado.',
  };
  return { code, message: messages[code] || 'A operação de arquivos Linux falhou.' };
}

class WslFilesService {
  constructor() {
    this.session = null;
    this.connecting = null;
    this.active = 0;
    this.waiters = [];
  }

  async configuration() {
    const active = enabled();
    const corePath = process.env.CLOUDOS_WSL_CORE_LINUX_PATH || '';
    let snapshot = null;
    if (active) {
      try { snapshot = await getWslSnapshot(); } catch {}
    }
    const preferred = snapshot?.preferred || snapshot?.default || null;
    const distro = snapshot?.distributions?.find(item => item.name.toLowerCase() === String(preferred || '').toLowerCase()) || null;
    return {
      enabled: active,
      distribution: preferred,
      wsl2: distro?.version === 2,
      corePathConfigured: corePath.startsWith('/'),
      protocol: WSL_CORE_PROTOCOL,
      protection: WSL_CORE_PROTECTION,
      source: 'wsl',
      mode: 'wsl-core-v2',
    };
  }

  async status() {
    const config = await this.configuration();
    if (!config.enabled) return { ...config, available: false, reason: 'FEATURE_DISABLED' };
    if (!config.distribution) return { ...config, available: false, reason: 'DISTRO_NOT_FOUND' };
    if (!config.wsl2) return { ...config, available: false, reason: 'DISTRO_NOT_WSL2' };
    if (!config.corePathConfigured) return { ...config, available: false, reason: 'CORE_PATH_INVALID' };
    try {
      const info = await this.request('fs.info', null, 5000);
      return { ...config, available: true, root: info };
    } catch (error) {
      return { ...config, available: false, reason: safeCode(error) };
    }
  }

  async request(method, params = null, timeoutMs = 8000) {
    if (!enabled()) throw Object.assign(new Error('disabled'), { code: 'FEATURE_DISABLED' });
    await this.#acquire();
    try {
      const session = await this.#ensureSession();
      return await session.request(method, params, Math.max(500, Math.min(30000, Number(timeoutMs) || 8000)));
    } catch (error) {
      if (RESET_CODES.has(safeCode(error))) await this.#resetSession();
      throw error;
    } finally {
      this.#release();
    }
  }

  safeError(error) { return safeError(error); }

  async dispose() { await this.#resetSession(); }

  async #ensureSession() {
    if (this.session) return this.session;
    if (this.connecting) return await this.connecting;
    const config = await this.configuration();
    if (!config.distribution) throw Object.assign(new Error('distribution missing'), { code: 'DISTRO_NOT_FOUND' });
    if (!config.wsl2) throw Object.assign(new Error('not wsl2'), { code: 'DISTRO_NOT_WSL2' });
    const linuxCorePath = process.env.CLOUDOS_WSL_CORE_LINUX_PATH || '';
    this.connecting = createWslFilesRpcSession({ distribution: config.distribution, linuxCorePath })
      .then(session => {
        this.session = session;
        return session;
      })
      .finally(() => { this.connecting = null; });
    return await this.connecting;
  }

  async #resetSession() {
    const session = this.session;
    this.session = null;
    if (session) {
      try { await session.close(); } catch {}
    }
  }

  async #acquire() {
    if (this.active < MAX_CONCURRENT) {
      this.active += 1;
      return;
    }
    await new Promise(resolve => this.waiters.push(resolve));
    this.active += 1;
  }

  #release() {
    this.active = Math.max(0, this.active - 1);
    this.waiters.shift()?.();
  }
}

export const wslFilesService = new WslFilesService();
export { enabled as wslFilesEnabled, safeError as sanitizeWslFilesError };
