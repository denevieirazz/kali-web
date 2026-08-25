import express from 'express';
import os from 'node:os';
import { authenticateToken } from '../middleware/auth.js';

export const systemRouter = express.Router();

function readCpuTimes() {
  const cpus = os.cpus();
  if (!cpus || cpus.length === 0) return null;
  let totalIdle = 0;
  let totalTick = 0;
  for (const cpu of cpus) {
    for (const type of Object.keys(cpu.times)) totalTick += cpu.times[type];
    totalIdle += cpu.times.idle;
  }
  return { totalIdle, totalTick };
}

// Seed at module load so the first API request reports a real delta rather than a made-up percentage.
let prevCpuInfo = readCpuTimes();

function getCpuLoad() {
  const current = readCpuTimes();
  if (!current) return -1;
  if (!prevCpuInfo) {
    prevCpuInfo = current;
    return 0;
  }
  const idleDiff = current.totalIdle - prevCpuInfo.totalIdle;
  const totalDiff = current.totalTick - prevCpuInfo.totalTick;
  prevCpuInfo = current;
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
        usagePercentage: totalMem > 0 ? Math.round((usedMem / totalMem) * 100) : 0
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