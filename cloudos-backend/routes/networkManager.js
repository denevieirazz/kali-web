const express = require('express');
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);
const router = express.Router();

// Serviços táticos suportados
const ALLOWED_SERVICES = ['postgresql', 'apache2', 'ssh', 'tor', 'nginx', 'metasploit'];

async function runWslCommand(cmd) {
  try {
    const { stdout } = await execAsync(`wsl -d kali-linux -u cloudos -- bash -c "${cmd.replace(/"/g, '\\"')}"`, {
      timeout: 5000,
      maxBuffer: 1024 * 1024 * 10
    });
    return stdout.trim();
  } catch (error) {
    return error.stdout || error.stderr || '';
  }
}

// GET /api/network/services — Checa status dos serviços essenciais
router.get('/network/services', authenticateToken, async (req, res) => {
  try {
    const servicesStatus = await Promise.all(
      ALLOWED_SERVICES.map(async (svc) => {
        const output = await runWslCommand(`service ${svc} status`);
        const isActive = output.includes('active (running)') || output.includes('active (exited)');
        return {
          name: svc,
          status: isActive ? 'running' : 'stopped',
          details: output.split('\n')[0] || 'No info'
        };
      })
    );

    res.json({ success: true, services: servicesStatus });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/network/services/:name/:action — Start/Stop/Restart
router.post('/network/services/:name/:action', authenticateToken, async (req, res) => {
  const { name, action } = req.params;

  if (!ALLOWED_SERVICES.includes(name)) {
    return res.status(400).json({ success: false, error: 'Serviço não permitido' });
  }
  if (!['start', 'stop', 'restart'].includes(action)) {
    return res.status(400).json({ success: false, error: 'Ação inválida' });
  }

  try {
    await runWslCommand(`sudo service ${name} ${action}`);
    
    const output = await runWslCommand(`service ${name} status`);
    const isActive = output.includes('active (running)') || output.includes('active (exited)');
    
    res.json({
      success: true,
      message: `Serviço ${name} ${action} executado`,
      newStatus: isActive ? 'running' : 'stopped'
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/network/ports — Lista portas abertas (ss -tulpn)
router.get('/network/ports', authenticateToken, async (req, res) => {
  try {
    const output = await runWslCommand(`sudo ss -tulpn`);
    
    const lines = output.split('\n').slice(1);
    const ports = lines.map(line => {
      const parts = line.trim().split(/\s+/);
      if (parts.length < 5) return null;
      
      const localAddr = parts[4];
      const portMatch = localAddr.match(/:(\d+)$/);
      
      return {
        state: parts[0],
        localAddress: parts[4],
        port: portMatch ? parseInt(portMatch[1]) : null,
        process: parts[5] ? parts[5].replace('users:((&','').split(',')[0] : 'unknown'
      };
    }).filter(p => p && p.port);

    res.json({ success: true, ports });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
