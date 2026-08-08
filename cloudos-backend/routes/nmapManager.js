const express = require('express');
const router = express.Router();
const { spawn } = require('child_process');
const { authenticateToken } = require('../middleware/auth');
const { getProjectExecutionContext } = require('../services/scannerSecurity');

router.use(authenticateToken);

/**
 * POST /api/nmap/scan
 * Monta o comando Nmap dinamicamente baseado nas opções visuais e validação de escopo
 */
router.post('/scan', async (req, res) => {
  const { target, options = {}, projectId } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo (IP/URL) é obrigatório' });
  if (!projectId) return res.status(403).json({ error: 'Varredura Nmap exige um Projeto Ativo (projectId).' });

  // Validação centralizada de escopo e contexto do projeto
  const contextCheck = await getProjectExecutionContext(req.user.id, projectId, target);
  if (!contextCheck.allowed) {
    return res.status(403).json({ error: contextCheck.reason });
  }

  const nmapArgs = [];

  // 1. Tipo de Varredura
  if (options.scanType === 'ping') nmapArgs.push('-sn');
  else if (options.scanType === 'syn') nmapArgs.push('-sS');
  else if (options.scanType === 'connect') nmapArgs.push('-sT');
  else if (options.scanType === 'udp') nmapArgs.push('-sU');
  else if (options.scanType === 'ack') nmapArgs.push('-sA');

  // 2. Detecções
  if (options.versionDetection) nmapArgs.push('-sV');
  if (options.osDetection) nmapArgs.push('-O');
  if (options.nseScripts) nmapArgs.push('-sC');
  if (options.aggressive) nmapArgs.push('-A');

  // 3. Configurações de Rede
  if (options.skipPing) nmapArgs.push('-Pn');
  if (options.portRange && options.portRange.trim() !== '') {
    const safePort = options.portRange.trim().replace(/[^0-9,-]/g, '');
    if (safePort) {
      nmapArgs.push('-p', safePort);
    }
  }

  // 4. Timing Template (0 a 5)
  if (options.timing !== undefined && options.timing >= 0 && options.timing <= 5) {
    nmapArgs.push(`-T${parseInt(options.timing, 10)}`);
  }

  // 5. Adiciona o alvo limpo
  const safeTarget = target.replace(/[^a-zA-Z0-9.-]/g, '').trim();
  if (!safeTarget) return res.status(400).json({ error: 'Alvo com formato inválido.' });
  nmapArgs.push(safeTarget);

  try {
    const args = ['-d', 'kali-linux', '-u', 'cloudos', '--', 'nmap', ...nmapArgs];
    
    const stdout = await new Promise((resolve, reject) => {
      const p = spawn('wsl.exe', args);
      let out = '';
      let err = '';
      const timer = setTimeout(() => {
        try { p.kill('SIGKILL'); } catch {}
        reject(new Error('Timeout na varredura Nmap (180s).'));
      }, 180000);

      p.stdout.on('data', (d) => { out += d.toString(); });
      p.stderr.on('data', (d) => { err += d.toString(); });

      p.on('close', () => {
        clearTimeout(timer);
        resolve(out + (err ? '\n' + err : ''));
      });
      p.on('error', (e) => {
        clearTimeout(timer);
        reject(e);
      });
    });

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
