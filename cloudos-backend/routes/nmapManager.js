const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/nmap/scan
 * Executa varredura Nmap baseada em perfis fáceis
 */
router.post('/scan', async (req, res) => {
  const { target, profile } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo (IP/URL) é obrigatório' });

  let command = '';
  switch (profile) {
    case 'fast':
      command = `nmap -T4 -F ${target}`;
      break;
    case 'versions':
      command = `nmap -sV -T4 ${target}`;
      break;
    case 'os':
      command = `nmap -O ${target}`;
      break;
    case 'intense':
      command = `nmap -A -T4 ${target}`;
      break;
    default:
      command = `nmap ${target}`;
  }

  try {
    const wslCmd = `wsl -d kali-linux -u cloudos -- bash -c "${command} -oG - 2>/dev/null"`;
    const { stdout } = await execAsync(wslCmd, { timeout: 120000, maxBuffer: 10 * 1024 * 1024 });

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
