import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config/index.js';

const CURRENT_VERSION = 2;

function clone(value) {
  return structuredClone(value);
}

function cloneEmptyState() {
  return {
    version: CURRENT_VERSION,
    revision: 0,
    users: [],
    operations: [],
    security: {
      login: {
        failed_attempts: 0,
        window_started_at: null,
        locked_until: null
      },
      recovery: {
        failed_attempts: 0,
        window_started_at: null,
        locked_until: null
      }
    }
  };
}

export class DatabaseCorruptionError extends Error {
  constructor(filePath) {
    super(`O banco de dados do CloudOS esta corrompido e nenhum backup valido foi encontrado: ${filePath}`);
    this.name = 'DatabaseCorruptionError';
    this.code = 'DATABASE_CORRUPT';
  }
}

function optionalTimestamp(value) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function normalizeUser(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('INVALID_USER_RECORD');
  }

  const id = typeof value.id === 'string' ? value.id.trim() : '';
  const username = typeof value.username === 'string' ? value.username.trim() : '';
  const passwordHash = typeof value.password_hash === 'string' ? value.password_hash : '';
  const role = typeof value.role === 'string' ? value.role : '';
  if (!id || !username || !passwordHash || !role) throw new Error('INVALID_USER_RECORD');

  const createdAt = optionalTimestamp(value.created_at) || new Date(0).toISOString();
  const updatedAt = optionalTimestamp(value.updated_at) || createdAt;
  const authVersionCandidate = Number(value.auth_version ?? value.authVersion ?? 1);
  const authVersion = Number.isSafeInteger(authVersionCandidate) && authVersionCandidate >= 1
    ? authVersionCandidate
    : 1;

  const normalized = {
    ...value,
    id,
    username,
    display_name: typeof value.display_name === 'string' && value.display_name.trim()
      ? value.display_name.trim()
      : (typeof value.displayName === 'string' && value.displayName.trim() ? value.displayName.trim() : username),
    password_hash: passwordHash,
    recovery_code_hash: typeof value.recovery_code_hash === 'string' && value.recovery_code_hash
      ? value.recovery_code_hash
      : null,
    auth_version: authVersion,
    role,
    created_at: createdAt,
    updated_at: updatedAt
  };

  // Campos de texto puro nunca pertencem ao armazenamento de credenciais.
  delete normalized.password;
  delete normalized.recoveryCode;
  delete normalized.recovery_code;
  delete normalized.displayName;
  delete normalized.authVersion;
  return normalized;
}

function normalizeThrottleState(value) {
  const failedAttempts = Number(value?.failed_attempts ?? 0);
  return {
    failed_attempts: Number.isSafeInteger(failedAttempts) && failedAttempts >= 0 ? failedAttempts : 0,
    window_started_at: optionalTimestamp(value?.window_started_at),
    locked_until: optionalTimestamp(value?.locked_until)
  };
}

function normalizeState(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('INVALID_DATABASE_ROOT');
  }
  if (value.version !== 1 && value.version !== CURRENT_VERSION) {
    throw new Error('UNSUPPORTED_DATABASE_VERSION');
  }
  if (value.users !== undefined && !Array.isArray(value.users)) throw new Error('INVALID_USERS_COLLECTION');
  if (value.operations !== undefined && !Array.isArray(value.operations)) throw new Error('INVALID_OPERATIONS_COLLECTION');

  const revisionCandidate = Number(value.revision ?? 0);
  return {
    version: CURRENT_VERSION,
    revision: Number.isSafeInteger(revisionCandidate) && revisionCandidate >= 0 ? revisionCandidate : 0,
    users: (value.users || []).map(normalizeUser),
    operations: clone(value.operations || []),
    security: {
      ...(value.security && typeof value.security === 'object' ? value.security : {}),
      login: normalizeThrottleState(value.security?.login),
      recovery: normalizeThrottleState(value.security?.recovery)
    }
  };
}

function publicCopy(value) {
  return value ? clone(value) : value;
}

export class PersistentDatabase {
  constructor(filePath = config.databasePath) {
    this.filePath = path.resolve(filePath);
    this.backupPath = `${this.filePath}.bak`;
    this.state = this.#load();
  }

  #readCandidate(candidatePath) {
    try {
      const parsed = JSON.parse(fs.readFileSync(candidatePath, 'utf8'));
      return {
        exists: true,
        valid: true,
        migrated: parsed.version !== CURRENT_VERSION,
        state: normalizeState(parsed)
      };
    } catch (error) {
      if (error.code === 'ENOENT') return { exists: false, valid: false, error };
      return { exists: true, valid: false, error };
    }
  }

  #atomicWrite(targetPath, contents) {
    const temporary = `${targetPath}.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2)}.tmp`;
    let descriptor;
    try {
      descriptor = fs.openSync(temporary, 'w', 0o600);
      fs.writeFileSync(descriptor, contents, { encoding: 'utf8' });
      fs.fsyncSync(descriptor);
      fs.closeSync(descriptor);
      descriptor = undefined;
      fs.renameSync(temporary, targetPath);
    } catch (error) {
      if (descriptor !== undefined) {
        try { fs.closeSync(descriptor); } catch {}
      }
      try { fs.unlinkSync(temporary); } catch {}
      throw error;
    }
  }

  #preservePreV2SnapshotFrom(sourcePath) {
    const migrationBackupPath = `${this.filePath}.pre-v2.bak`;
    let descriptor;
    try {
      descriptor = fs.openSync(migrationBackupPath, 'wx', 0o600);
      try {
        const originalContents = fs.readFileSync(sourcePath);
        fs.writeFileSync(descriptor, originalContents);
        fs.fsyncSync(descriptor);
      } finally {
        fs.closeSync(descriptor);
        descriptor = undefined;
      }
    } catch (error) {
      if (descriptor !== undefined) {
        try { fs.closeSync(descriptor); } catch {}
        try { fs.unlinkSync(migrationBackupPath); } catch {}
      }
      if (error.code !== 'EEXIST') throw error;
    }
  }

  #preservePreV2Snapshot() {
    this.#preservePreV2SnapshotFrom(this.filePath);
  }

  #writeCopies(state, { commitToMemory = false } = {}) {
    const contents = `${JSON.stringify(state, null, 2)}\n`;
    // O arquivo principal define o commit. Se ele falhar, a memoria continua no estado anterior.
    this.#atomicWrite(this.filePath, contents);
    if (commitToMemory) this.state = state;
    try {
      this.#atomicWrite(this.backupPath, contents);
      this.backupWriteError = null;
    } catch (error) {
      // O principal ja foi confirmado. Mantemos memoria e disco coerentes e tentamos
      // atualizar o backup novamente no proximo commit, sem reportar falso rollback.
      this.backupWriteError = error;
    }
  }

  #quarantine(candidatePath) {
    if (!fs.existsSync(candidatePath)) return;
    const damagedPath = `${candidatePath}.corrupt-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    try { fs.renameSync(candidatePath, damagedPath); } catch {}
  }

  #load() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const main = this.#readCandidate(this.filePath);
    const backup = this.#readCandidate(this.backupPath);

    if (!main.exists && !backup.exists) {
      const initial = cloneEmptyState();
      this.#writeCopies(initial);
      return initial;
    }

    const validCandidates = [
      main.valid ? { source: 'main', ...main } : null,
      backup.valid ? { source: 'backup', ...backup } : null
    ].filter(Boolean).sort((left, right) => {
      const revisionDifference = right.state.revision - left.state.revision;
      if (revisionDifference !== 0) return revisionDifference;
      return left.source === 'main' ? -1 : 1;
    });

    if (!validCandidates.length) {
      // Falha fechada: nunca transforma corrupcao em uma instalacao vazia.
      throw new DatabaseCorruptionError(this.filePath);
    }

    const selected = validCandidates[0];
    if (main.exists && !main.valid) this.#quarantine(this.filePath);
    if (backup.exists && !backup.valid) this.#quarantine(this.backupPath);

    const copiesDiffer = !main.valid || !backup.valid ||
      main.state.revision !== selected.state.revision || backup.state.revision !== selected.state.revision;
    if (selected.migrated) {
      if (selected.source === 'main') {
        this.#preservePreV2Snapshot();
      } else {
        this.#preservePreV2SnapshotFrom(this.backupPath);
      }
    }
    if (selected.source === 'backup' || selected.migrated || copiesDiffer) {
      this.#writeCopies(selected.state);
    }
    return selected.state;
  }

  #persist(nextState) {
    const snapshot = normalizeState({
      ...nextState,
      version: CURRENT_VERSION,
      revision: this.state.revision + 1
    });
    this.#writeCopies(snapshot, { commitToMemory: true });
  }

  #change(mutator) {
    const nextState = clone(this.state);
    const result = mutator(nextState);
    this.#persist(nextState);
    return result;
  }

  #clearRecoveryThrottle(state) {
    state.security.recovery = normalizeThrottleState(null);
  }

  #clearLoginThrottle(state) {
    state.security.login = normalizeThrottleState(null);
  }

  get(query, params, callback) {
    try {
      if (query.includes('FROM users WHERE id = ?')) {
        const id = String(Array.isArray(params) ? params[0] : params || '');
        return callback(null, publicCopy(this.state.users.find(user => user.id === id) || null));
      }
      if (query.includes('FROM users WHERE username = ?')) {
        const username = String(Array.isArray(params) ? params[0] : params || '').toLowerCase();
        return callback(null, publicCopy(this.state.users.find(user => user.username.toLowerCase() === username) || null));
      }
      if (query.includes('COUNT(*) as count FROM users')) {
        const role = Array.isArray(params) && params.length ? String(params[0]) : null;
        const users = role ? this.state.users.filter(user => user.role === role) : this.state.users;
        return callback(null, { count: users.length });
      }
      if (query.includes('FROM users WHERE role = ?')) {
        const role = String(Array.isArray(params) ? params[0] : params || '');
        return callback(null, publicCopy(this.state.users.find(user => user.role === role) || null));
      }
      if (query.includes('FROM operations WHERE id = ?')) {
        return callback(null, publicCopy(this.state.operations.find(operation => operation.id === params[0]) || null));
      }
      return callback(null, null);
    } catch (error) { return callback(error); }
  }

  all(query, params, callback) {
    try {
      if (query.includes('FROM users')) return callback(null, publicCopy(this.state.users));
      if (query.includes('FROM operations')) return callback(null, publicCopy(this.state.operations));
      return callback(null, []);
    } catch (error) { return callback(error); }
  }

  run(query, params, callback = () => {}) {
    try {
      if (query.includes('INSERT INTO users')) {
        const hasExtendedFields = query.includes('display_name');
        const [id, username] = params;
        const displayName = hasExtendedFields ? params[2] : username;
        const passwordHash = hasExtendedFields ? params[3] : params[2];
        const recoveryCodeHash = hasExtendedFields ? params[4] : null;
        const authVersion = hasExtendedFields ? params[5] : 1;
        const role = hasExtendedFields ? params[6] : params[3];

        this.#change((state) => {
          const duplicate = state.users.some(user => user.username.toLowerCase() === String(username).toLowerCase());
          if (duplicate) throw new Error('USERNAME_EXISTS');
          if (role === 'admin' && state.users.some(user => user.role === 'admin')) throw new Error('ADMIN_EXISTS');
          const now = new Date().toISOString();
          state.users.push(normalizeUser({
            id,
            username,
            display_name: displayName,
            password_hash: passwordHash,
            recovery_code_hash: recoveryCodeHash,
            auth_version: authVersion,
            role,
            created_at: now,
            updated_at: now
          }));
        });
      } else if (query.includes('INSERT INTO operations')) {
        const [id, type, status = 'running', progress = 10, step = 'checking', message = 'Validando pre-requisitos do sistema...'] = params;
        this.#change(state => state.operations.push({
          id, type, status, progress, step, message, created_at: new Date().toISOString()
        }));
      } else {
        return callback(new Error('UNSUPPORTED_QUERY'));
      }
      return callback(null);
    } catch (error) { return callback(error); }
  }

  getRecoveryThrottle(now = Date.now()) {
    const recovery = this.state.security.recovery;
    const lockedUntil = recovery.locked_until ? Date.parse(recovery.locked_until) : 0;
    return {
      limited: Number.isFinite(lockedUntil) && lockedUntil > now,
      retryAfterMs: Number.isFinite(lockedUntil) && lockedUntil > now ? lockedUntil - now : 0,
      failedAttempts: recovery.failed_attempts
    };
  }

  getLoginThrottle(now = Date.now()) {
    const login = this.state.security.login;
    const lockedUntil = login.locked_until ? Date.parse(login.locked_until) : 0;
    return {
      limited: Number.isFinite(lockedUntil) && lockedUntil > now,
      retryAfterMs: Number.isFinite(lockedUntil) && lockedUntil > now ? lockedUntil - now : 0,
      failedAttempts: login.failed_attempts
    };
  }

  recordLoginFailure({ now = Date.now(), maxAttempts, windowMs, lockMs }) {
    return this.#change((state) => {
      const login = state.security.login;
      const currentLock = login.locked_until ? Date.parse(login.locked_until) : 0;
      if (Number.isFinite(currentLock) && currentLock > now) {
        return { limited: true, retryAfterMs: currentLock - now, failedAttempts: login.failed_attempts };
      }

      const windowStartedAt = login.window_started_at ? Date.parse(login.window_started_at) : 0;
      if (!Number.isFinite(windowStartedAt) || windowStartedAt <= 0 || now - windowStartedAt >= windowMs) {
        login.failed_attempts = 0;
        login.window_started_at = new Date(now).toISOString();
        login.locked_until = null;
      }

      login.failed_attempts += 1;
      if (login.failed_attempts >= maxAttempts) login.locked_until = new Date(now + lockMs).toISOString();
      const lockedUntil = login.locked_until ? Date.parse(login.locked_until) : 0;
      return {
        limited: Number.isFinite(lockedUntil) && lockedUntil > now,
        retryAfterMs: Number.isFinite(lockedUntil) && lockedUntil > now ? lockedUntil - now : 0,
        failedAttempts: login.failed_attempts
      };
    });
  }

  clearLoginThrottle(callback = () => {}) {
    try {
      this.#change(state => this.#clearLoginThrottle(state));
      callback(null);
    } catch (error) { callback(error); }
  }

  recordRecoveryFailure({ now = Date.now(), maxAttempts, windowMs, lockMs }) {
    return this.#change((state) => {
      const recovery = state.security.recovery;
      const currentLock = recovery.locked_until ? Date.parse(recovery.locked_until) : 0;
      if (Number.isFinite(currentLock) && currentLock > now) {
        return { limited: true, retryAfterMs: currentLock - now, failedAttempts: recovery.failed_attempts };
      }

      const windowStartedAt = recovery.window_started_at ? Date.parse(recovery.window_started_at) : 0;
      if (!Number.isFinite(windowStartedAt) || windowStartedAt <= 0 || now - windowStartedAt >= windowMs) {
        recovery.failed_attempts = 0;
        recovery.window_started_at = new Date(now).toISOString();
        recovery.locked_until = null;
      }

      recovery.failed_attempts += 1;
      if (recovery.failed_attempts >= maxAttempts) {
        recovery.locked_until = new Date(now + lockMs).toISOString();
      }
      const lockedUntil = recovery.locked_until ? Date.parse(recovery.locked_until) : 0;
      return {
        limited: Number.isFinite(lockedUntil) && lockedUntil > now,
        retryAfterMs: Number.isFinite(lockedUntil) && lockedUntil > now ? lockedUntil - now : 0,
        failedAttempts: recovery.failed_attempts
      };
    });
  }

  rotateRecoveryCode(userId, recoveryCodeHash, callback = () => {}) {
    try {
      this.#change((state) => {
        const user = state.users.find(candidate => candidate.id === userId && candidate.role === 'admin');
        if (!user) throw new Error('USER_NOT_FOUND');
        user.recovery_code_hash = recoveryCodeHash;
        user.updated_at = new Date().toISOString();
        this.#clearRecoveryThrottle(state);
      });
      callback(null);
    } catch (error) { callback(error); }
  }

  enrollRecoveryCode(userId, recoveryCodeHash, callback = () => {}) {
    try {
      let enrolled = false;
      this.#change((state) => {
        const user = state.users.find(candidate => candidate.id === userId && candidate.role === 'admin');
        if (!user) throw new Error('USER_NOT_FOUND');
        if (!user.recovery_code_hash) {
          user.recovery_code_hash = recoveryCodeHash;
          user.updated_at = new Date().toISOString();
          this.#clearRecoveryThrottle(state);
          enrolled = true;
        }
      });
      callback(null, enrolled);
    } catch (error) { callback(error); }
  }

  recoverAdmin(credentials, callback = () => {}) {
    try {
      let updatedUser;
      this.#change((state) => {
        const user = state.users.find(candidate => candidate.id === credentials.id && candidate.role === 'admin');
        if (!user || user.recovery_code_hash !== credentials.expectedRecoveryCodeHash) {
          throw new Error('RECOVERY_CODE_CHANGED');
        }
        const duplicate = state.users.some(candidate =>
          candidate.id !== user.id && candidate.username.toLowerCase() === credentials.username.toLowerCase()
        );
        if (duplicate) throw new Error('USERNAME_EXISTS');

        user.username = credentials.username;
        user.display_name = credentials.displayName;
        user.password_hash = credentials.passwordHash;
        user.recovery_code_hash = credentials.recoveryCodeHash;
        user.auth_version = credentials.authVersion;
        user.updated_at = new Date().toISOString();
        this.#clearLoginThrottle(state);
        this.#clearRecoveryThrottle(state);
        updatedUser = clone(user);
      });
      callback(null, updatedUser);
    } catch (error) { callback(error); }
  }

  reset() {
    this.#persist(cloneEmptyState());
  }

  serialize(fn) { fn(); }
  close(callback) { if (callback) callback(); }
}

let dbInstance;
export function getDb() {
  if (!dbInstance) dbInstance = new PersistentDatabase();
  return dbInstance;
}
export function resetLocalDatabase() { getDb().reset(); }
export function createDatabaseForTests(filePath) { return new PersistentDatabase(filePath); }
