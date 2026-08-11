import express from 'express';
import { authenticateToken } from '../middleware/auth.js';

let si = null;
try {
  si = (await import('systeminformation')).default;
} catch (e) {
  console.warn('⚠️  systeminformation não disponível — métricas via os.cpus()/os.freemem().');
}

import os from 'os';

export const systemRouter = express.Router();

systemRouter.get('/metrics', authenticateToken, async (req, res) => {
  try {
    if (si) {
      const [cpu, mem, currentLoad, osInfo] = await Promise.all([
        si.cpu(),
        si.mem(),
        si.currentLoad(),
        si.osInfo()
      ]);

      return res.json({
        cpu: {
          manufacturer: cpu.manufacturer || 'Desconhecido',
          brand: cpu.brand || 'Processador Virtual',
          cores: cpu.cores || 1,
          speed: cpu.speed || 0,
          loadPercentage: Math.round(currentLoad.currentLoad || 0)
        },
        memory: {
          total: mem.total || 0,
          free: mem.free || 0,
          used: mem.used || 0,
          usagePercentage: Math.round(((mem.used || 0) / (mem.total || 1)) * 100)
        },
        os: {
          platform: osInfo.platform || process.platform,
          distro: osInfo.distro || 'Windows/Linux',
          release: osInfo.release || '',
          uptimeSeconds: Math.round(si.time().uptime || 0)
        },
        status: 'operational'
      });
    }

    // Fallback sem systeminformation
    const cpus = os.cpus();
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;

    res.json({
      cpu: {
        manufacturer: '',
        brand: cpus.length > 0 ? cpus[0].model : 'Desconhecido',
        cores: cpus.length,
        speed: cpus.length > 0 ? cpus[0].speed : 0,
        loadPercentage: -1
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
  } catch (error) {
    res.status(503).json({
      status: 'unavailable',
      error: 'Não foi possível coletar as métricas do sistema.'
    });
  }
});
