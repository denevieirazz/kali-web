const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);
const router = express.Router();

// Helper: Executa comando no WSL e retorna stdout
async function runWslCommand(cmd) {
  try {
    const { stdout } = await execAsync(`wsl -d kali-linux -u cloudos -- bash -c "${cmd.replace(/"/g, '\\"')}"`, {
      timeout: 5000,
      maxBuffer: 1024 * 1024 * 10
    });
    return stdout.trim();
  } catch (error) {
    console.error('[ProcessManager] Erro:', error.message);
    throw error;
  }
}

// GET /api/processes — Lista processos no formato JSON estruturado
router.get('/processes', authenticateToken, async (req, res) => {
  try {
    const output = await runWslCommand(
      `ps -eo pid,pcpu,pmem,user,args --sort=-pcpu | head -n 51`
    );

    const lines = output.split('\n').slice(1); // Remove header
    const processes = lines.map(line => {
      const parts = line.trim().split(/\s+/);
      return {
        pid: parseInt(parts[0]),
        cpu: parseFloat(parts[1]),
        mem: parseFloat(parts[2]),
        user: parts[3],
        command: parts.slice(4).join(' ')
      };
    }).filter(p => p.pid && !isNaN(p.pid));

    res.json({
      success: true,
      count: processes.length,
      processes
    });
  } catch (error) {
    res.status(500).json({ 
      success: false, 
      error: 'Falha ao listar processos',
      details: error.message 
    });
  }
});

// GET /api/processes/stats/summary — Resumo de carga do sistema
router.get('/processes/stats/summary', authenticateToken, async (req, res) => {
  try {
    const [loadAvg, memInfo, uptime] = await Promise.all([
      runWslCommand('cat /proc/loadavg'),
      runWslCommand('free -m | grep Mem'),
      runWslCommand('uptime -p')
    ]);

    const loadParts = loadAvg.split(/\s+/);
    const memParts = memInfo.split(/\s+/);

    res.json({
      success: true,
      stats: {
        loadAvg: {
          '1min': parseFloat(loadParts[0]) || 0,
          '5min': parseFloat(loadParts[1]) || 0,
          '15min': parseFloat(loadParts[2]) || 0
        },
        memory: {
          total: parseInt(memParts[1]) || 0,
          used: parseInt(memParts[2]) || 0,
          free: parseInt(memParts[3]) || 0,
          shared: parseInt(memParts[4]) || 0,
          cache: parseInt(memParts[5]) || 0,
          available: parseInt(memParts[6]) || 0
        },
        uptime: (uptime || '').replace('up ', ''),
        runningProcesses: parseInt((loadParts[3] || '0/0').split('/')[0])
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/processes/:pid — Detalhes de um processo específico
router.get('/processes/:pid', authenticateToken, async (req, res) => {
  const { pid } = req.params;
  
  if (!/^\d+$/.test(pid)) {
    return res.status(400).json({ success: false, error: 'PID inválido' });
  }

  try {
    const output = await runWslCommand(`ps -p ${pid} -o pid,pcpu,pmem,user,args --no-headers`);
    
    if (!output) {
      return res.status(404).json({ success: false, error: 'Processo não encontrado' });
    }

    const parts = output.trim().split(/\s+/);
    res.json({
      success: true,
      process: {
        pid: parseInt(parts[0]),
        cpu: parseFloat(parts[1]),
        mem: parseFloat(parts[2]),
        user: parts[3],
        command: parts.slice(4).join(' ')
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/processes/:pid — Mata um processo (kill -9)
router.delete('/processes/:pid', authenticateToken, async (req, res) => {
  const { pid } = req.params;
  
  if (!/^\d+$/.test(pid)) {
    return res.status(400).json({ success: false, error: 'PID inválido' });
  }

  try {
    await runWslCommand(`kill ${pid} 2>/dev/null || sudo kill -9 ${pid}`);
    
    res.json({ 
      success: true, 
      message: `Processo ${pid} finalizado`,
      pid: parseInt(pid)
    });
  } catch (error) {
    try {
      await runWslCommand(`sudo kill -9 ${pid}`);
      res.json({ success: true, message: `Processo ${pid} finalizado (forçado)` });
    } catch (err2) {
      res.status(500).json({ 
        success: false, 
        error: `Não foi possível finalizar o processo ${pid}`,
        details: err2.message 
      });
    }
  }
});

module.exports = router;
