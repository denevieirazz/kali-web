import express from 'express';
import os from 'os';
import { authenticateToken, requireAdmin } from '../middleware/auth.js';
import { linuxSystemCenterService } from './linuxSystemCenterService.js';

let si = null;
try {
  si = (await import('systeminformation')).default;
} catch {
  console.warn('⚠️  systeminformation não disponível — métricas via os.cpus()/os.freemem().');
}

export const systemRouter = express.Router();

systemRouter.get('/metrics', authenticateToken, async (_req, res) => {
  try {
    if (si) {
      const [cpu, mem, currentLoad, osInfo] = await Promise.all([si.cpu(), si.mem(), si.currentLoad(), si.osInfo()]);
      return res.json({
        source: 'host-windows',
        cpu: { manufacturer: cpu.manufacturer || 'Desconhecido', brand: cpu.brand || 'Processador Virtual', cores: cpu.cores || 1, speed: cpu.speed || 0, loadPercentage: Math.round(currentLoad.currentLoad || 0) },
        memory: { total: mem.total || 0, free: mem.free || 0, used: mem.used || 0, usagePercentage: Math.round(((mem.used || 0) / (mem.total || 1)) * 100) },
        os: { platform: osInfo.platform || process.platform, distro: osInfo.distro || 'Windows/Linux', release: osInfo.release || '', uptimeSeconds: Math.round(si.time().uptime || 0) },
        status: 'operational'
      });
    }
    const cpus = os.cpus(); const totalMem = os.totalmem(); const freeMem = os.freemem(); const usedMem = totalMem - freeMem;
    return res.json({ source: 'host-windows', cpu: { manufacturer: '', brand: cpus[0]?.model || 'Desconhecido', cores: cpus.length, speed: cpus[0]?.speed || 0, loadPercentage: -1 }, memory: { total: totalMem, free: freeMem, used: usedMem, usagePercentage: Math.round((usedMem / totalMem) * 100) }, os: { platform: os.platform(), distro: os.type(), release: os.release(), uptimeSeconds: Math.round(os.uptime()) }, status: 'operational' });
  } catch {
    return res.status(503).json({ status: 'unavailable', error: 'Não foi possível coletar as métricas do sistema.' });
  }
});

function sendLinuxError(res, error, status = 503) {
  const safe = linuxSystemCenterService.safeError(error);
  return res.status(status).json({ status: 'unavailable', source: 'linux-real', error: safe, message: safe.message });
}
function queryInt(value, fallback, min, max) { const parsed = Number.parseInt(String(value ?? ''), 10); return Number.isInteger(parsed) ? Math.max(min, Math.min(max, parsed)) : fallback; }

systemRouter.get('/linux/status', authenticateToken, async (_req, res) => res.json(await linuxSystemCenterService.status()));
systemRouter.get('/linux/processes', authenticateToken, async (req, res) => {
  try {
    const result = await linuxSystemCenterService.request('process.list', { page: queryInt(req.query.page, 1, 1, 100000), pageSize: queryInt(req.query.pageSize, 50, 1, 100), query: String(req.query.query || '').slice(0, 128), state: String(req.query.state || '').slice(0, 16), user: String(req.query.user || '').slice(0, 64), sortBy: String(req.query.sortBy || 'pid').slice(0, 16), sortDir: String(req.query.sortDir || 'asc').slice(0, 8) });
    return res.json({ source: 'linux-real', mode: 'wsl-core-v2', ...result });
  } catch (error) { return sendLinuxError(res, error); }
});
systemRouter.get('/linux/processes/:pid', authenticateToken, async (req, res) => {
  try { return res.json({ source: 'linux-real', process: await linuxSystemCenterService.request('process.get', { pid: queryInt(req.params.pid, 0, 0, 2147483647) }) }); }
  catch (error) { return sendLinuxError(res, error, error?.code === 'PROCESS_NOT_FOUND' ? 404 : 503); }
});
systemRouter.get('/linux/metrics', authenticateToken, async (_req, res) => {
  try { return res.json({ source: 'linux-real', mode: 'wsl-core-v2', ...(await linuxSystemCenterService.request('system.metrics')) }); }
  catch (error) { return sendLinuxError(res, error); }
});
systemRouter.get('/linux/cgroups/capabilities', authenticateToken, async (_req, res) => {
  try { return res.json({ source: 'linux-real', ...(await linuxSystemCenterService.request('cgroup.capabilities')) }); }
  catch (error) { return sendLinuxError(res, error); }
});
systemRouter.get('/linux/audit', authenticateToken, requireAdmin, (_req, res) => res.json({ entries: linuxSystemCenterService.getAudit() }));

systemRouter.post('/linux/processes/:pid/signal', authenticateToken, requireAdmin, async (req, res) => {
  if (req.body?.confirmed !== true) return res.status(400).json({ error: { code: 'CONFIRMATION_REQUIRED', message: 'Explicit confirmation is required.' } });
  const pid = queryInt(req.params.pid, 0, 0, 2147483647); const signal = String(req.body?.signal || '').toUpperCase(); const startTimeTicks = Number(req.body?.startTimeTicks || 0);
  if (!['SIGINT','SIGTERM','SIGKILL'].includes(signal) || !Number.isSafeInteger(startTimeTicks) || startTimeTicks <= 0) return res.status(400).json({ error: { code: 'REQUEST_INVALID', message: 'Signal request is invalid.' } });
  try {
    const result = await linuxSystemCenterService.request('process.signal', { pid, startTimeTicks, signal });
    linuxSystemCenterService.recordAudit({ userId: req.user?.id, action: 'process.signal', pid, signal, result: 'accepted' });
    return res.json({ source: 'linux-real', ...result });
  } catch (error) {
    linuxSystemCenterService.recordAudit({ userId: req.user?.id, action: 'process.signal', pid, signal, result: error?.code || 'failed' });
    return sendLinuxError(res, error, ['PROCESS_PROTECTED','PROCESS_DENIED','PID_REUSED'].includes(error?.code) ? 409 : 503);
  }
});

systemRouter.post('/linux/cgroups/policy', authenticateToken, requireAdmin, async (req, res) => {
  if (req.body?.confirmed !== true) return res.status(400).json({ error: { code: 'CONFIRMATION_REQUIRED', message: 'Explicit confirmation is required.' } });
  const pid = Number(req.body?.pid); const startTimeTicks = Number(req.body?.startTimeTicks); const policy = req.body?.policy;
  if (!Number.isSafeInteger(pid) || pid <= 1 || !Number.isSafeInteger(startTimeTicks) || startTimeTicks <= 0 || !policy || typeof policy !== 'object') return res.status(400).json({ error: { code: 'REQUEST_INVALID', message: 'Cgroup policy request is invalid.' } });
  try {
    const assignment = await linuxSystemCenterService.request('cgroup.policy.apply', { pid, startTimeTicks, policy });
    linuxSystemCenterService.recordAudit({ userId: req.user?.id, action: 'cgroup.policy.apply', pid, result: 'applied' });
    return res.json({ source: 'linux-real', applied: true, assignment });
  } catch (error) {
    linuxSystemCenterService.recordAudit({ userId: req.user?.id, action: 'cgroup.policy.apply', pid, result: error?.code || 'failed' });
    return sendLinuxError(res, error, error?.code === 'CGROUP_CONTROL_DISABLED' ? 409 : 503);
  }
});
systemRouter.delete('/linux/cgroups/assignments/:id', authenticateToken, requireAdmin, async (req, res) => {
  if (req.body?.confirmed !== true) return res.status(400).json({ error: { code: 'CONFIRMATION_REQUIRED', message: 'Explicit confirmation is required.' } });
  try {
    const result = await linuxSystemCenterService.request('cgroup.policy.clear', { id: String(req.params.id || '').slice(0, 64) });
    linuxSystemCenterService.recordAudit({ userId: req.user?.id, action: 'cgroup.policy.clear', result: 'cleared' });
    return res.json({ source: 'linux-real', ...result });
  } catch (error) { return sendLinuxError(res, error); }
});
