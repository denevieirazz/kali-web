import express from 'express';
import os from 'node:os';
import { authenticateToken } from '../middleware/auth.js';

export const systemRouter = express.Router();

let prevCpuInfo = null;

function getCpuLoad() {
  const cpus = os.cpus();
  if (!cpus || cpus.length === 0) return -1;
  let totalIdle = 0;
  let totalTick = 0;
  for (const cpu of cpus) {
    for (const type of Object.keys(cpu.times)) {
      totalTick += cpu.times[type];
    }
    totalIdle += cpu.times.idle;
  }
  if (!prevCpuInfo) {
    prevCpuInfo = { totalIdle, totalTick };
    return 15; // Initial estimation
  }
  const idleDiff = totalIdle - prevCpuInfo.totalIdle;
  const totalDiff = totalTick - prevCpuInfo.totalTick;
  prevCpuInfo = { totalIdle, totalTick };
  if (totalDiff <= 0) return 0;
  const load = 100 - Math.round((100 * idleDiff) / totalDiff);
  return Math.max(0, Math.min(100, load));
}

systemRouter.get('/metrics', authenticateToken, async (req, res) => {
  try {
    const cpus = os.cpus();
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;

    res.json({
      cpu: {
        manufacturer: 'Intel/AMD',
        brand: cpus.length > 0 ? cpus[0].model : 'Processador Host',
        cores: cpus.length,
        speed: cpus.length > 0 ? cpus[0].speed : 0,
        loadPercentage: getCpuLoad()
      },
      memory: {
        total: totalMem,
        free: freeMem,
        used: usedMem,
        usagePercentage: Math.round((usedMem / totalMem) * 100)
      },
      os: {
        platform: os.platform(),
        distro: os.type(),
        release: os.release(),
        uptimeSeconds: Math.round(os.uptime())
      },
      status: 'operational'
    });
  } catch {
    res.status(503).json({
      status: 'unavailable',
      error: 'Não foi possível coletar as métricas do sistema.'
    });
  }
});
