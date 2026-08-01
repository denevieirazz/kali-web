const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * GET /api/dashboard/summary
 * Retorna um resumo leve e rápido para o Dashboard
 */
router.get('/summary', async (req, res) => {
  try {
    const db = req.app.get('db');

    // 1. Resumo de Vulnerabilidades (do SQLite)
    const findings = { critical: 0, high: 0, medium: 0, low: 0, total: 0 };
    try {
      const rows = await db.prepare('SELECT severity, COUNT(*) as count FROM findings WHERE user_id = ? GROUP BY severity').all(req.user.id);
      (rows || []).forEach(row => {
        const sevRaw = (row.severity || '').toLowerCase();
        let key = 'low';
        if (sevRaw.includes('crít') || sevRaw.includes('crit')) key = 'critical';
        else if (sevRaw.includes('alt') || sevRaw.includes('high')) key = 'high';
        else if (sevRaw.includes('méd') || sevRaw.includes('med')) key = 'medium';

        findings[key] += row.count;
        findings.total += row.count;
      });
    } catch (dbErr) {
      console.log('[Dashboard] Tabela de findings não pronta ou vazia.');
    }

    // 2. Status do Sistema (Leitura rápida WSL2)
    let system = { memory: 'N/A', disk: 'N/A', cpuUsage: 'N/A' };
    try {
      const script = `echo "MEM:$(free -m 2>/dev/null | awk '/^Mem:/ {print $3\"/\"$2\"MB\"}')" && echo "DISK:$(df -h / 2>/dev/null | awk 'NR==2 {print $3\"/\"$2\" (\"$5\")\"}')"`;
      const encoded = Buffer.from(script).toString('base64');
      const { stdout } = await execAsync(`wsl -d kali-linux -u cloudos -- bash -c "echo '${encoded}' | base64 -d | bash"`, { timeout: 3000 });
      
      const lines = stdout.split('\n');
      lines.forEach(line => {
        if (line.startsWith('MEM:')) system.memory = line.replace('MEM:', '').trim();
        if (line.startsWith('DISK:')) system.disk = line.replace('DISK:', '').trim();
      });
    } catch (wslErr) {
      console.error('[Dashboard] Erro lendo WSL2:', wslErr.message);
    }

    // 3. Status Metasploit (Apenas verifica porta, não sobe daemon)
    let msfStatus = 'offline';
    try {
      const { stdout } = await execAsync('powershell -Command "(Test-NetConnection -ComputerName 127.0.0.1 -Port 55553 -WarningAction SilentlyContinue).TcpTestSucceeded"');
      if (stdout.trim() === 'True') msfStatus = 'online';
    } catch {
      msfStatus = 'offline';
    }

    res.json({
      findings,
      system,
      msfStatus,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[Dashboard] Erro geral:', err.message);
    res.status(500).json({ error: 'Falha ao gerar resumo' });
  }
});

module.exports = router;
