const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/nmap/scan
 * Monta o comando Nmap dinamicamente baseado nas opções visuais
 */
router.post('/scan', async (req, res) => {
  const { target, options = {} } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo (IP/URL) é obrigatório' });

  let cmdParts = ['nmap'];

  // 1. Tipo de Varredura
  if (options.scanType === 'ping') cmdParts.push('-sn');
  else if (options.scanType === 'syn') cmdParts.push('-sS');
  else if (options.scanType === 'connect') cmdParts.push('-sT');
  else if (options.scanType === 'udp') cmdParts.push('-sU');
  else if (options.scanType === 'ack') cmdParts.push('-sA');

  // 2. Detecções
  if (options.versionDetection) cmdParts.push('-sV');
  if (options.osDetection) cmdParts.push('-O');
  if (options.nseScripts) cmdParts.push('-sC');
  if (options.aggressive) cmdParts.push('-A');

  // 3. Configurações de Rede
  if (options.skipPing) cmdParts.push('-Pn');
  if (options.portRange && options.portRange.trim() !== '') {
    cmdParts.push(`-p ${options.portRange.trim()}`);
  }

  // 4. Timing Template (0 a 5)
  if (options.timing !== undefined && options.timing >= 0 && options.timing <= 5) {
    cmdParts.push(`-T${options.timing}`);
  }

  // 5. Adiciona o alvo (proteção básica contra injeção de comando)
  const safeTarget = target.replace(/[;|&`$()]/g, '');
  cmdParts.push(safeTarget);

  const command = cmdParts.join(' ');
  
  try {
    const wslCmd = `wsl -d kali-linux -u cloudos -- bash -c "${command} -oG - 2>/dev/null"`;
    const { stdout } = await execAsync(wslCmd, { timeout: 300000, maxBuffer: 10 * 1024 * 1024 });

    const hosts = [];
    const lines = stdout.split('\n');
    let currentHost = null;

    for (const line of lines) {
      if (line.startsWith('Host:')) {
        const parts = line.split('\t');
        const ip = parts[0].replace('Host: ', '').trim();
        const status = parts[1]?.replace('Status: ', '').trim();
        const hostnamesStr = parts.find(p => p.startsWith('Hostnames:'))?.replace('Hostnames: ', '').trim();
        
        if (status === 'Up' || status === 'up' || parts.length >= 2) {
          currentHost = { ip, hostnames: hostnamesStr || ip, ports: [] };
          hosts.push(currentHost);
        }
      } else if (line.startsWith('Ports:') && currentHost) {
        const portsStr = line.replace('Ports: ', '').trim();
        const portEntries = portsStr.split(', ');
        
        for (const entry of portEntries) {
          const match = entry.match(/^(\d+)\/(\w+)\/(\w+)\/\/?([^\/]*)\/\/?(.*)/);
          if (match) {
            currentHost.ports.push({
              port: match[1],
              state: match[2],
              protocol: match[3],
              service: match[4] || 'unknown',
              version: match[5] || ''
            });
          }
        }
      }
    }

    res.json({ 
      success: true, 
      hosts, 
      rawCommand: command,
      target 
    });
  } catch (err) {
    console.error('[NmapManager] Erro:', err.message);
    res.status(500).json({ error: 'Falha na varredura', details: err.message.slice(-200) });
  }
});

module.exports = router;
