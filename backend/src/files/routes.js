import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { wslFilesService } from './wslFilesService.js';
import { startWslCopyTransaction } from './wslFileTransactions.js';

export const filesRouter = express.Router();
filesRouter.use(authenticateToken);

const MAX_SEGMENTS = 64;
const MAX_NAME = 255;
const ACTOR_HEADER = 'x-cloudos-file-actor';

function sendError(res, error, status = 503) {
  const safe = wslFilesService.safeError(error);
  return res.status(status).json({ status: 'unavailable', source: 'wsl', error: safe, message: safe.message });
}

function requireUserIntent(req, res, next) {
  if (req.headers[ACTOR_HEADER] !== 'user-ui') {
    return res.status(403).json({
      error: {
        code: 'FILES_EXPLICIT_USER_INTENT_REQUIRED',
        message: 'Acesso real a arquivos exige uma ação explícita do usuário na interface do Files.',
      },
    });
  }
  next();
}

function requireConfirmed(req, res, next) {
  if (req.body?.confirmed !== true) {
    return res.status(400).json({
      error: { code: 'CONFIRMATION_REQUIRED', message: 'Confirmação explícita é obrigatória para esta alteração.' },
    });
  }
  next();
}

function pathSegments(value, { allowEmpty = true } = {}) {
  if (!Array.isArray(value) || value.length > MAX_SEGMENTS) throw Object.assign(new Error('invalid path'), { code: 'FILES_PATH_INVALID' });
  if (!allowEmpty && value.length === 0) throw Object.assign(new Error('invalid path'), { code: 'FILES_PATH_INVALID' });
  return value.map(segment => {
    if (typeof segment !== 'string') throw Object.assign(new Error('invalid path'), { code: 'FILES_PATH_INVALID' });
    if (!segment || segment === '.' || segment === '..' || segment.includes('/') || segment.includes('\\') || segment.includes('\0') || Buffer.byteLength(segment, 'utf8') > MAX_NAME) {
      throw Object.assign(new Error('invalid path'), { code: 'FILES_PATH_INVALID' });
    }
    return segment;
  });
}

function boundedInt(value, fallback, min, max) {
  const numeric = Number(value);
  return Number.isSafeInteger(numeric) ? Math.max(min, Math.min(max, numeric)) : fallback;
}

function boundedText(value, max = 1024) {
  return typeof value === 'string' ? value.slice(0, max) : '';
}

filesRouter.use(requireUserIntent);

filesRouter.get('/status', async (_req, res) => {
  try { return res.json(await wslFilesService.status()); }
  catch (error) { return sendError(res, error); }
});

filesRouter.post('/list', async (req, res) => {
  try {
    const path = pathSegments(req.body?.path ?? []);
    const result = await wslFilesService.request('fs.list', { path });
    return res.json({ source: 'wsl', mode: 'wsl-core-v2', ...result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/read', async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const offset = boundedInt(req.body?.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const limit = boundedInt(req.body?.limit, 256 * 1024, 1, 256 * 1024);
    const result = await wslFilesService.request('fs.read', { path, offset, limit }, 15000);
    return res.json({ source: 'wsl', mode: 'wsl-core-v2', ...result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/write', requireConfirmed, async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const offset = boundedInt(req.body?.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const data = boundedText(req.body?.data, 400 * 1024);
    const mode = boundedInt(req.body?.mode, 0o600, 0, 0o7777);
    const result = await wslFilesService.request('fs.write', { path, offset, data, truncate: req.body?.truncate === true, mode }, 15000);
    return res.json({ source: 'wsl', ...result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/mkdir', requireConfirmed, async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const mode = boundedInt(req.body?.mode, 0o700, 0, 0o7777);
    const result = await wslFilesService.request('fs.mkdir', { path, mode });
    return res.json({ source: 'wsl', ...result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/move', requireConfirmed, async (req, res) => {
  try {
    const source = pathSegments(req.body?.source, { allowEmpty: false });
    const destination = pathSegments(req.body?.destination, { allowEmpty: false });
    const result = await wslFilesService.request('fs.move', { source, destination });
    return res.json({ source: 'wsl', ...result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/copy', requireConfirmed, async (req, res) => {
  try {
    const source = pathSegments(req.body?.source, { allowEmpty: false });
    const destination = pathSegments(req.body?.destination, { allowEmpty: false });
    const operation = startWslCopyTransaction(source, destination);
    return res.status(202).json({ source: 'wsl', operation });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/trash', requireConfirmed, async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const result = await wslFilesService.request('fs.trash', { path });
    return res.json({ source: 'wsl', trashed: true, entry: result });
  } catch (error) { return sendError(res, error, error?.code === 'FILES_PATH_INVALID' ? 400 : 503); }
});

filesRouter.post('/trash/list', async (_req, res) => {
  try {
    const result = await wslFilesService.request('fs.trash.list');
    return res.json({ source: 'wsl', ...result });
  } catch (error) { return sendError(res, error); }
});

filesRouter.post('/trash/restore', requireConfirmed, async (req, res) => {
  try {
    const id = boundedText(req.body?.id, 64);
    if (!/^[a-f0-9]{8,64}$/i.test(id)) return res.status(400).json({ error: { code: 'FILES_TRASH_ID_INVALID', message: 'Identificador de lixeira inválido.' } });
    const result = await wslFilesService.request('fs.trash.restore', { id });
    return res.json({ source: 'wsl', restored: true, entry: result });
  } catch (error) { return sendError(res, error); }
});

filesRouter.post('/trash/delete', requireConfirmed, async (req, res) => {
  try {
    const id = boundedText(req.body?.id, 64);
    if (!/^[a-f0-9]{8,64}$/i.test(id)) return res.status(400).json({ error: { code: 'FILES_TRASH_ID_INVALID', message: 'Identificador de lixeira inválido.' } });
    const result = await wslFilesService.request('fs.trash.delete', { id });
    return res.json({ source: 'wsl', ...result });
  } catch (error) { return sendError(res, error); }
});
