import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { authenticateToken } from '../middleware/auth.js';

function readProductMetadata(environment = process.env, cwd = process.cwd()) {
  const candidates = [
    path.join(cwd, 'meta', 'product.json'),
    path.join(cwd, 'productization', 'cloudos-product.json')
  ];
  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(fs.readFileSync(candidate, 'utf8'));
      if (parsed?.schemaVersion === 1 && parsed?.product === 'CloudOS') return parsed;
    } catch {}
  }
  return {
    schemaVersion: 1,
    product: 'CloudOS',
    version: environment.CLOUDOS_PRODUCT_VERSION || 'development',
    channel: environment.CLOUDOS_PRODUCT_CHANNEL || 'development',
    baseSha: environment.CLOUDOS_PRODUCT_SHA || null,
    signing: 'unsigned-development',
    stableUpdatesEnabled: false
  };
}

function resolveLocalRoot(environment = process.env) {
  const configured = String(environment.CLOUDOS_LOCAL_ROOT || '').trim();
  if (configured) return path.resolve(configured);
  const localAppData = String(environment.LOCALAPPDATA || '').trim();
  if (localAppData) return path.resolve(localAppData, 'CloudOS');
  return path.resolve(os.homedir(), '.cloudos');
}

function resolveKnownPaths(environment = process.env) {
  const root = resolveLocalRoot(environment);
  return {
    root,
    data: path.join(root, 'data'),
    logs: path.join(root, 'logs'),
    cache: path.join(root, 'cache'),
    updates: path.join(root, 'updates')
  };
}

function sanitizeProductStatus(environment = process.env, cwd = process.cwd()) {
  const metadata = readProductMetadata(environment, cwd);
  const known = resolveKnownPaths(environment);
  const packagedCore = path.join(cwd, 'runtime', 'cloudos-core');
  const sourceCore = path.join(cwd, 'core', 'wsl', 'cloudos-core', 'go.mod');
  return {
    schemaVersion: 1,
    product: 'CloudOS',
    version: String(metadata.version || 'development'),
    sha: typeof metadata.baseSha === 'string' ? metadata.baseSha : null,
    channel: String(metadata.channel || 'development'),
    signing: String(metadata.signing || 'unsigned-development'),
    stableUpdatesEnabled: metadata.stableUpdatesEnabled === true,
    mode: environment.CLOUDOS_NATIVE_HOST === '1' ? 'Full' : 'WebOnly',
    nativeHost: environment.CLOUDOS_NATIVE_HOST === '1',
    wslCorePayload: fs.existsSync(packagedCore) || fs.existsSync(sourceCore),
    protocolVersion: 1,
    dataDirectory: known.data,
    logDirectory: known.logs,
    updateConfigured: Boolean(String(environment.CLOUDOS_UPDATE_SOURCE || '').trim())
  };
}

function parseSemver(value) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/.exec(String(value || '').trim());
  if (!match) return null;
  return {
    raw: match[0],
    core: [Number(match[1]), Number(match[2]), Number(match[3])],
    pre: match[4] ? match[4].split('.') : []
  };
}

function compareIdentifiers(left, right) {
  const leftNumeric = /^\d+$/.test(left);
  const rightNumeric = /^\d+$/.test(right);
  if (leftNumeric && rightNumeric) return Number(left) - Number(right);
  if (leftNumeric !== rightNumeric) return leftNumeric ? -1 : 1;
  return left.localeCompare(right, 'en', { sensitivity: 'case' });
}

function compareSemver(left, right) {
  for (let index = 0; index < 3; index += 1) {
    const diff = left.core[index] - right.core[index];
    if (diff) return diff;
  }
  if (!left.pre.length && !right.pre.length) return 0;
  if (!left.pre.length) return 1;
  if (!right.pre.length) return -1;
  const length = Math.max(left.pre.length, right.pre.length);
  for (let index = 0; index < length; index += 1) {
    if (left.pre[index] === undefined) return -1;
    if (right.pre[index] === undefined) return 1;
    const diff = compareIdentifiers(left.pre[index], right.pre[index]);
    if (diff) return diff;
  }
  return 0;
}

function validateUpdateSource(rawSource, channel, environment = process.env) {
  const source = String(rawSource || '').trim();
  if (!source) return { kind: 'none' };
  if (path.isAbsolute(source)) {
    if (channel !== 'development') throw new Error('Fonte local é permitida somente no canal development.');
    const directory = path.resolve(source);
    if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) throw new Error('Diretório local de atualização não encontrado.');
    return { kind: 'directory', base: directory };
  }
  try {
    const url = new URL(source);
    if (url.username || url.password || url.search || url.hash) throw new Error('Fonte de atualização contém dados não permitidos.');
    if (url.protocol === 'https:') return { kind: 'https', base: url.toString().replace(/\/$/, '') };
    const loopback = ['127.0.0.1', 'localhost', '::1'].includes(url.hostname);
    if (url.protocol === 'http:' && loopback && channel === 'development' && environment.CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE === '1') {
      return { kind: 'http-loopback', base: url.toString().replace(/\/$/, '') };
    }
    throw new Error('Feeds remotos exigem HTTPS. HTTP só é aceito para fixture loopback de development explicitamente habilitada.');
  } catch (error) {
    if (error instanceof TypeError) {
      throw new Error('Fonte de atualização inválida.');
    }
    throw error;
  }
}

async function readReleaseFeed(source, channel, signal) {
  const fileName = `releases.${channel}.json`;
  if (source.kind === 'directory') return JSON.parse(await fs.promises.readFile(path.join(source.base, fileName), 'utf8'));
  const response = await fetch(`${source.base}/${fileName}`, { signal, redirect: 'error' });
  if (!response.ok) throw new Error(`Feed respondeu HTTP ${response.status}.`);
  const text = await response.text();
  if (text.length > 2 * 1024 * 1024) throw new Error('Feed de atualização excede o limite permitido.');
  return JSON.parse(text);
}

async function checkUpdate(environment = process.env, cwd = process.cwd(), signal) {
  const metadata = readProductMetadata(environment, cwd);
  const channel = String(metadata.channel || 'development').toLowerCase();
  if (!['stable', 'preview', 'development'].includes(channel)) throw new Error('Canal de atualização inválido.');
  if (channel === 'stable' && metadata.stableUpdatesEnabled !== true) return { configured: false, channel, state: 'disabled' };
  const source = validateUpdateSource(environment.CLOUDOS_UPDATE_SOURCE, channel, environment);
  if (source.kind === 'none') return { configured: false, channel, state: 'not-configured' };
  const current = parseSemver(metadata.version);
  if (!current) throw new Error('Versão atual inválida para comparação SemVer.');
  const feed = await readReleaseFeed(source, channel, signal);
  const assets = Array.isArray(feed?.Assets) ? feed.Assets : Array.isArray(feed?.assets) ? feed.assets : [];
  const full = assets
    .filter(asset => String(asset?.Type ?? asset?.type).toLowerCase() === 'full')
    .map(asset => ({
      version: parseSemver(asset?.Version ?? asset?.version),
      fileName: String(asset?.FileName ?? asset?.fileName ?? ''),
      sha256: String(asset?.SHA256 ?? asset?.sha256 ?? ''),
      size: Number(asset?.Size ?? asset?.size ?? 0)
    }))
    .filter(asset => asset.version && asset.fileName && /^[0-9a-f]{64}$/i.test(asset.sha256) && Number.isSafeInteger(asset.size) && asset.size > 0)
    .sort((a, b) => compareSemver(b.version, a.version));
  const latest = full[0];
  if (!latest) throw new Error('Feed não contém pacote Full com SHA-256 válido.');
  const comparison = compareSemver(latest.version, current);
  return {
    configured: true,
    channel,
    state: comparison > 0 ? 'available' : comparison === 0 ? 'current' : 'downgrade-rejected',
    currentVersion: current.raw,
    latestVersion: latest.version.raw,
    sha256: latest.sha256,
    size: latest.size
  };
}

function assertKnownDirectory(requested, environment = process.env) {
  const known = resolveKnownPaths(environment);
  if (!['data', 'logs'].includes(requested)) throw new Error('Diretório não permitido.');
  const target = known[requested];
  fs.mkdirSync(target, { recursive: true });
  return target;
}

function openKnownDirectory(kind, environment = process.env) {
  if (process.platform !== 'win32') throw new Error('A abertura de pasta está disponível somente no Windows.');
  const target = assertKnownDirectory(kind, environment);
  const systemRoot = String(environment.SystemRoot || environment.WINDIR || 'C:\\Windows');
  const explorer = path.join(systemRoot, 'explorer.exe');
  const child = spawn(explorer, [target], { shell: false, detached: true, stdio: 'ignore', windowsHide: false });
  child.unref();
}

function clearCache(environment = process.env) {
  const cache = resolveKnownPaths(environment).cache;
  fs.rmSync(cache, { recursive: true, force: true });
  fs.mkdirSync(cache, { recursive: true });
}

function exportDiagnostics(environment = process.env, cwd = process.cwd()) {
  const known = resolveKnownPaths(environment);
  fs.mkdirSync(known.logs, { recursive: true });
  const fileName = `diagnostico-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  const payload = {
    exportedAt: new Date().toISOString(),
    product: sanitizeProductStatus(environment, cwd),
    process: { platform: process.platform, arch: process.arch, node: process.version },
    secretsIncluded: false
  };
  fs.writeFileSync(path.join(known.logs, fileName), JSON.stringify(payload, null, 2), { encoding: 'utf8', flag: 'wx' });
  return fileName;
}

export function createProductRouter({ environment = process.env, cwd = process.cwd() } = {}) {
  const router = express.Router();
  router.use(authenticateToken);
  router.get('/status', (_req, res) => res.json(sanitizeProductStatus(environment, cwd)));
  router.get('/update', async (req, res, next) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    req.once('close', () => controller.abort());
    try { return res.json(await checkUpdate(environment, cwd, controller.signal)); }
    catch (error) { return next(error); }
    finally { clearTimeout(timer); }
  });
  router.post('/cache/clear', (_req, res, next) => {
    try { clearCache(environment); return res.json({ ok: true }); } catch (error) { return next(error); }
  });
  router.post('/diagnostics/export', (_req, res, next) => {
    try { return res.json({ ok: true, fileName: exportDiagnostics(environment, cwd) }); } catch (error) { return next(error); }
  });
  router.post('/folder/:kind/open', (req, res, next) => {
    try { openKnownDirectory(String(req.params.kind || ''), environment); return res.json({ ok: true }); } catch (error) { return next(error); }
  });
  return router;
}

export { checkUpdate, compareSemver, parseSemver, readProductMetadata, resolveKnownPaths, sanitizeProductStatus, validateUpdateSource };

export const productRouter = createProductRouter();
