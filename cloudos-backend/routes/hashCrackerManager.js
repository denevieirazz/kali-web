const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const crypto = require('crypto');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

const FORMAT_MAP = {
  md5: 'raw-md5',
  sha1: 'raw-sha1',
  sha256: 'raw-sha256',
  ntlm: 'NT'
};

/**
 * POST /api/hashcracker/crack
 */
router.post('/crack', async (req, res) => {
  const { hash, format } = req.body;

  if (!hash) return res.status(400).json({ error: 'Hash é obrigatório' });
  
  const johnFormat = FORMAT_MAP[format] || 'raw-md5';
  const safeHash = String(hash).replace(/[^a-fA-F0-9$:]/g, '');

  if (!safeHash) return res.status(400).json({ error: 'Formato de hash inválido.' });

  const tempFileId = 'h_' + crypto.randomUUID();
  const tmpFilePath = `/tmp/${tempFileId}.txt`;

  try {
    const cmd = `wsl -d kali-linux -u cloudos -- bash -c "echo '${safeHash}' > ${tmpFilePath} && john --format=${johnFormat} --wordlist=/usr/share/wordlists/rockyou.txt ${tmpFilePath} 2>&1 ; john --show ${tmpFilePath} 2>&1 ; rm -f ${tmpFilePath}"`;
    
    const { stdout } = await execAsync(cmd, { timeout: 120000, maxBuffer: 10 * 1024 * 1024 });

    let crackedPassword = null;
    let logs = stdout;

    const match = stdout.match(/^[^:]+:(.+?)$/m);
    if (match && !match[1].includes('password hash detected') && !match[1].includes('0 password hashes')) {
      if (!match[1].includes('cracked') && match[1].length < 100) {
        crackedPassword = match[1].trim();
      }
    }

    const crackedMatch = stdout.match(/^(?:[^:]+):([^\s]+)\s+/m);
    if (crackedMatch && !crackedMatch[1].includes('left')) {
      crackedPassword = crackedMatch[1].trim();
    }

    res.json({
      success: true,
      cracked: crackedPassword !== null,
      password: crackedPassword,
      logs: logs.slice(-1500)
    });

  } catch (err) {
    console.error('[HashCracker] Erro:', err.message);
    if (err.killed) {
      return res.status(504).json({ error: 'O processo demorou mais de 2 minutos e foi cancelado.' });
    }
    res.status(500).json({ error: 'Falha ao quebrar hash', details: err.message.slice(-200) });
  }
});

module.exports = router;
