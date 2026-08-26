import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { cloudOsDrive, CloudOsDriveError } from './cloudosDrive.js';

export const cloudOsDriveRouter = express.Router();
cloudOsDriveRouter.use(authenticateToken);

const ACTOR_HEADER = 'x-cloudos-file-actor';
const MAX_SEGMENTS = 64;
const MAX_NAME_BYTES = 255;
const MAX_BLOCK_BYTES = 256 * 1024;

function requirePrimaryAccount(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({
      error: {
        code: 'CLOUDOS_DRIVE_SECONDARY_USER_BLOCKED',
        message: 'O CloudOS Drive compartilhado ainda é restrito à conta principal.',
      },
    });
  }
  next();
}

function requireUserIntent(req, res, next) {
  if (req.headers[ACTOR_HEADER] !== 'user-ui') {
    return res.status(403).json({
      error: {
        code: 'CLOUDOS_DRIVE_EXPLICIT_USER_INTENT_REQUIRED',
        message: 'Acesso ao CloudOS Drive por esta API exige ação explícita do usuário.',
      },
    });
  }
  next();
}

function requireConfirmed(req, res, next) {
  if (req.body?.confirmed !== true) {
    return res.status(400).json({ error: { code: 'CONFIRMATION_REQUIRED', message: 'Confirmação explícita é obrigatória para esta alteração.' } });
  }
  next();
}

function pathSegments(value, { allowEmpty = true } = {}) {
  if (!Array.isArray(value) || value.length > MAX_SEGMENTS || (!allowEmpty && value.length === 0)) {
    throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
  }
  return value.map(raw => {
    if (typeof raw !== 'string') throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
    const segment = raw.normalize('NFC');
    if (!segment || segment === '.' || segment === '..' || segment.includes('/') || segment.includes('\\') || segment.includes('\0')
      || Buffer.byteLength(segment, 'utf8') > MAX_NAME_BYTES || segment === '.cloudos-system') {
      throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
    }
    return segment;
  });
}

function boundedInt(value, fallback, min, max) {
  const numeric = Number(value);
  return Number.isSafeInteger(numeric) ? Math.max(min, Math.min(max, numeric)) : fallback;
}

function decodeBase64(value) {
  if (typeof value !== 'string' || value.length > Math.ceil(MAX_BLOCK_BYTES / 3) * 4 + 8) {
    throw new CloudOsDriveError('CLOUDOS_DRIVE_DATA_INVALID', 'Bloco de gravação inválido.');
  }
  if (value && !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new CloudOsDriveError('CLOUDOS_DRIVE_DATA_INVALID', 'Bloco base64 inválido.');
  }
  const buffer = Buffer.from(value, 'base64');
  if (buffer.length > MAX_BLOCK_BYTES) throw new CloudOsDriveError('CLOUDOS_DRIVE_DATA_INVALID', 'Bloco de gravação excede o limite.');
  return buffer;
}

function statusFor(error) {
  if (!(error instanceof CloudOsDriveError)) return 503;
  if (error.code.includes('PATH_INVALID') || error.code.includes('DATA_INVALID') || error.code.includes('TRASH_ID_INVALID')) return 400;
  if (error.code.endsWith('NOT_FOUND')) return 404;
  if (error.code.endsWith('CONFLICT')) return 409;
  if (error.code.endsWith('ACCESS_DENIED')) return 403;
  return 503;
}

function sendError(res, error) {
  const safe = error instanceof CloudOsDriveError
    ? { code: error.code, message: error.message }
    : { code: 'CLOUDOS_DRIVE_UNAVAILABLE', message: 'O CloudOS Drive está indisponível.' };
  return res.status(statusFor(error)).json({ status: 'unavailable', source: 'cloudos', error: safe, message: safe.message });
}

cloudOsDriveRouter.use(requirePrimaryAccount);
cloudOsDriveRouter.use(requireUserIntent);

cloudOsDriveRouter.get('/status', async (_req, res) => {
  try { return res.json(await cloudOsDrive.status()); }
  catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/list', async (req, res) => {
  try {
    const entries = await cloudOsDrive.list(pathSegments(req.body?.path ?? []));
    return res.json({ source: 'cloudos', mode: 'cloudos-drive-v1', entries });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/read', async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const offset = boundedInt(req.body?.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const limit = boundedInt(req.body?.limit, MAX_BLOCK_BYTES, 1, MAX_BLOCK_BYTES);
    return res.json({ source: 'cloudos', ...(await cloudOsDrive.read(path, offset, limit)) });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/write', requireConfirmed, async (req, res) => {
  try {
    const path = pathSegments(req.body?.path, { allowEmpty: false });
    const offset = boundedInt(req.body?.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const data = decodeBase64(req.body?.data ?? '');
    const result = await cloudOsDrive.write(path, data, { offset, truncate: req.body?.truncate === true });
    return res.json({ source: 'cloudos', ...result });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/mkdir', requireConfirmed, async (req, res) => {
  try {
    const result = await cloudOsDrive.mkdir(pathSegments(req.body?.path, { allowEmpty: false }));
    return res.json({ source: 'cloudos', ...result });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/move', requireConfirmed, async (req, res) => {
  try {
    const source = pathSegments(req.body?.source, { allowEmpty: false });
    const destination = pathSegments(req.body?.destination, { allowEmpty: false });
    return res.json({ source: 'cloudos', ...(await cloudOsDrive.move(source, destination)) });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/copy', requireConfirmed, async (req, res) => {
  try {
    const source = pathSegments(req.body?.source, { allowEmpty: false });
    const destination = pathSegments(req.body?.destination, { allowEmpty: false });
    return res.json({ source: 'cloudos', ...(await cloudOsDrive.copy(source, destination)) });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/trash', requireConfirmed, async (req, res) => {
  try {
    const entry = await cloudOsDrive.trash(pathSegments(req.body?.path, { allowEmpty: false }));
    return res.json({ source: 'cloudos', trashed: true, entry });
  } catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/trash/list', async (_req, res) => {
  try { return res.json({ source: 'cloudos', entries: await cloudOsDrive.listTrash() }); }
  catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/trash/restore', requireConfirmed, async (req, res) => {
  try { return res.json({ source: 'cloudos', ...(await cloudOsDrive.restoreTrash(req.body?.id)) }); }
  catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/trash/delete', requireConfirmed, async (req, res) => {
  try { return res.json({ source: 'cloudos', ...(await cloudOsDrive.deleteTrash(req.body?.id)) }); }
  catch (error) { return sendError(res, error); }
});

cloudOsDriveRouter.post('/trash/empty', requireConfirmed, async (_req, res) => {
  try { return res.json({ source: 'cloudos', ...(await cloudOsDrive.emptyTrash()) }); }
  catch (error) { return sendError(res, error); }
});
