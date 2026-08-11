import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config/index.js';

const EMPTY_STATE = Object.freeze({ version: 1, users: [], operations: [] });

function cloneEmptyState() {
  return { version: EMPTY_STATE.version, users: [], operations: [] };
}

function normalizeState(value) {
  if (!value || value.version !== 1) return cloneEmptyState();
  return {
    version: 1,
    users: Array.isArray(value.users) ? value.users : [],
    operations: Array.isArray(value.operations) ? value.operations : []
  };
}

export class PersistentDatabase {
  constructor(filePath = config.databasePath) {
    this.filePath = path.resolve(filePath);
    this.state = this.#load();
  }

  #load() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    try {
      return normalizeState(JSON.parse(fs.readFileSync(this.filePath, 'utf8')));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        const damaged = `${this.filePath}.corrupt-${Date.now()}`;
        try { fs.renameSync(this.filePath, damaged); } catch {}
      }
      const state = cloneEmptyState();
      this.#persist(state);
      return state;
    }
  }

  #persist(nextState = this.state) {
    const temporary = `${this.filePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(nextState, null, 2)}\n`, {
      encoding: 'utf8', mode: 0o600
    });
    fs.renameSync(temporary, this.filePath);
  }

  get(query, params, callback) {
    try {
      if (query.includes('FROM users WHERE username = ?')) {
        const username = String(Array.isArray(params) ? params[0] : params || '').toLowerCase();
        return callback(null, this.state.users.find(user => user.username.toLowerCase() === username) || null);
      }
      if (query.includes('COUNT(*) as count FROM users')) {
        return callback(null, { count: this.state.users.filter(user => user.role === 'admin').length });
      }
      if (query.includes('FROM operations WHERE id = ?')) {
        return callback(null, this.state.operations.find(operation => operation.id === params[0]) || null);
      }
      return callback(null, null);
    } catch (error) { return callback(error); }
  }

  all(query, params, callback) {
    try {
      if (query.includes('FROM users')) return callback(null, [...this.state.users]);
      if (query.includes('FROM operations')) return callback(null, [...this.state.operations]);
      return callback(null, []);
    } catch (error) { return callback(error); }
  }

  run(query, params, callback = () => {}) {
    try {
      if (query.includes('INSERT INTO users')) {
        const [id, username, password_hash, role] = params;
        const duplicate = this.state.users.some(user => user.username.toLowerCase() === String(username).toLowerCase());
        if (duplicate) return callback(new Error('USERNAME_EXISTS'));
        this.state.users.push({ id, username, password_hash, role, created_at: new Date().toISOString() });
      } else if (query.includes('INSERT INTO operations')) {
        const [id, type, status = 'running', progress = 10, step = 'checking', message = 'Validando pré-requisitos do sistema...'] = params;
        this.state.operations.push({ id, type, status, progress, step, message, created_at: new Date().toISOString() });
      } else {
        return callback(new Error('UNSUPPORTED_QUERY'));
      }
      this.#persist();
      return callback(null);
    } catch (error) { return callback(error); }
  }

  reset() {
    this.state = cloneEmptyState();
    this.#persist();
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
