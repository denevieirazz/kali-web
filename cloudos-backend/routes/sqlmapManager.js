const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/sqlmap/scan
 * Executa varredura SQLmap em modo batch e extrai estruturas
 */
router.post('/scan', async (req, res) => {
  const { url } = req.body;

  if (!url) return res.status(400).json({ error: 'URL é obrigatória' });

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return res.status(400).json({ error: 'URL deve começar com http:// ou https://' });
  }

  try {
    const safeUrl = url.replace(/'/g, `'"'"'`);
    const cmd = `wsl -d kali-linux -u cloudos -- bash -c "sqlmap -u '${safeUrl}' --batch --dbs --random-agent --flush-session 2>&1"`;
    
    const { stdout } = await execAsync(cmd, { timeout: 180000, maxBuffer: 10 * 1024 * 1024 });

    const result = {
      vulnerable: false,
      dbms: 'Desconhecido',
      databases: [],
      payload: null,
      logs: stdout.slice(-1500)
    };

    if (/is vulnerable|appears to be injectable|injectable/i.test(stdout)) {
      result.vulnerable = true;
    }

    const dbmsMatch = stdout.match(/back-end DBMS:\s*(.+?)\n/i);
    if (dbmsMatch) {
      result.dbms = dbmsMatch[1].trim();
    }

    const payloadMatch = stdout.match(/Payload:\s*(.+?)\n/i);
    if (payloadMatch) {
      result.payload = payloadMatch[1].trim();
    }

    const dbsMatch = stdout.match(/available databases \[\d+\]:\s*([\s\S]*?)(\n\n|\n\[INFO\])/i);
    if (dbsMatch) {
      const dbsString = dbsMatch[1].trim();
      result.databases = dbsString.split('\n')
        .map(db => db.replace(/^\[\*\]/, '').trim())
        .filter(db => db.length > 0 && !db.startsWith('['));
    }

    res.json({ success: true, ...result });

  } catch (err) {
    console.error('[SqlmapManager] Erro:', err.message);
    
    if (err.killed) {
      return res.status(504).json({ error: 'O scan demorou mais de 3 minutos e foi cancelado. O alvo pode estar lento ou bloqueando requisições.' });
    }
    
    res.status(500).json({ error: 'Falha ao executar SQLmap', details: err.message.slice(-200) });
  }
});

module.exports = router;
