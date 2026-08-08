const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const crypto = require('crypto');

const execAsync = promisify(exec);
const { authenticateToken } = require('../middleware/auth');

router.use(authenticateToken);

// Catálogo de ferramentas táticas essenciais autorizadas
const TACTICAL_TOOLS = [
  { name: 'nmap',          package: 'nmap',                  category: 'Reconhecimento', description: 'Scanner de rede e portas' },
  { name: 'masscan',       package: 'masscan',               category: 'Reconhecimento', description: 'Scanner de portas ultra-rápido' },
  { name: 'msfconsole',    package: 'metasploit-framework',  category: 'Exploração',     description: 'Framework de exploração' },
  { name: 'sqlmap',        package: 'sqlmap',                category: 'Exploração',     description: 'Automação de SQL Injection' },
  { name: 'searchsploit',  package: 'exploitdb',             category: 'Exploração',     description: 'Base de dados de exploits' },
  { name: 'hydra',         package: 'hydra',                 category: 'Brute Force',    description: 'Força bruta multi-protocolo' },
  { name: 'john',          package: 'john',                  category: 'Criptografia',   description: 'Quebra de hashes de senhas' },
  { name: 'hashcat',       package: 'hashcat',               category: 'Criptografia',   description: 'Quebra de hashes com GPU' },
  { name: 'tshark',        package: 'tshark',                category: 'Sniffing',       description: 'Captura e análise de pacotes' },
  { name: 'tcpdump',       package: 'tcpdump',               category: 'Sniffing',       description: 'Captura de tráfego de rede' },
  { name: 'nikto',         package: 'nikto',                 category: 'Web',            description: 'Scanner de vulnerabilidades web' },
  { name: 'gobuster',      package: 'gobuster',              category: 'Web',            description: 'Brute force de diretórios e DNS' },
  { name: 'wpscan',        package: 'wpscan',                category: 'Web',            description: 'Scanner de WordPress' },
  { name: 'nc',            package: 'netcat-traditional',    category: 'Rede',           description: 'Canivete suíço de rede' },
  { name: 'socat',         package: 'socat',                 category: 'Rede',           description: 'Relay bidirecional multipropósito' },
  { name: 'proxychains',   package: 'proxychains4',          category: 'Rede',           description: 'Encadeamento de proxy' },
  { name: 'aircrack-ng',   package: 'aircrack-ng',           category: 'Wireless',       description: 'Auditoria de redes WiFi' },
  { name: 'recon-ng',      package: 'recon-ng',              category: 'OSINT',          description: 'Framework de reconhecimento' },
  { name: 'theharvester',  package: 'theharvester',          category: 'OSINT',          description: 'Coleta de e-mails e subdomínios' },
  { name: 'python3',       package: 'python3',               category: 'Base',           description: 'Interpretador Python 3' },
  { name: 'git',           package: 'git',                   category: 'Base',           description: 'Controle de versão' },
  { name: 'curl',          package: 'curl',                  category: 'Base',           description: 'Cliente HTTP' },
  { name: 'jq',            package: 'jq',                    category: 'Base',           description: 'Processador JSON CLI' },
  { name: 'ssh',           package: 'openssh-client',        category: 'Rede',           description: 'Cliente SSH' },
];

let isInstalling = false;

async function logAudit(db, userId, op, tool, result, err = null) {
  try {
    const id = 'ev_' + crypto.randomBytes(4).toString('hex');
    const details = JSON.stringify({ operation: op, tool, result, error: err ? String(err) : null, timestamp: new Date().toISOString() });
    await db.prepare('INSERT INTO system_events (id, user_id, event_type, details) VALUES (?, ?, ?, ?)').run(id, userId, 'environment_audit', details);
  } catch (e) {
    console.error('Falha ao registrar auditoria:', e.message);
  }
}

/**
 * GET /api/environment/check
 */
router.get('/check', async (req, res) => {
  const wslManager = require('../services/wslManager');
  try {
    const diag = await wslManager.getSystemDiagnostics();

    // Se o WSL/Kali ainda não estiverem prontos, responde o estado real sem falha opaca
    if (diag.overallStatus !== 'READY') {
      return res.json({
        tools: TACTICAL_TOOLS.map(t => ({ ...t, installed: false })),
        system: {
          distro: diag.wsl.kaliInstalled ? 'Kali Linux (Não configurado)' : 'WSL/Kali não instalado',
          kernel: 'N/A',
          uptime: 'N/A'
        },
        disk: {
          filesystem: 'C:',
          size: `${diag.hardware.diskTotalGB}G`,
          available: `${diag.hardware.diskFreeGB}G`,
          usePercent: '0%',
          mount: '/'
        },
        memory: {
          total: Math.round(diag.hardware.totalMemGB * 1024),
          free: Math.round(diag.hardware.freeMemGB * 1024),
          used: Math.round((diag.hardware.totalMemGB - diag.hardware.freeMemGB) * 1024),
          available: Math.round(diag.hardware.freeMemGB * 1024)
        },
        wslState: diag,
        summary: {
          total: TACTICAL_TOOLS.length,
          installed: 0,
          missing: TACTICAL_TOOLS.length,
          healthScore: 0,
          message: 'Ambiente WSL/Kali ainda não inicializado. Acesse o Setup Wizard do CloudOS.'
        }
      });
    }

    const toolNames = TACTICAL_TOOLS.map(t => t.name).join(' ');

    const script = `echo "===TOOLS==="
for tool in ${toolNames}; do
  if command -v "$tool" &>/dev/null; then
    echo "$tool:INSTALLED"
  else
    echo "$tool:MISSING"
  fi
done
echo "===SYSTEM==="
echo "KERNEL:$(uname -r)"
echo "DISTRO:$(grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | sed 's/PRETTY_NAME=//;s/"//g')"
echo "UPTIME:$(uptime -p 2>/dev/null || echo unknown)"
echo "CPUS:$(nproc)"
echo "===DISK==="
df -h / 2>/dev/null | tail -1
echo "===MEMORY==="
free -m 2>/dev/null | grep '^Mem:'
echo "===END==="`;

    const encoded = Buffer.from(script).toString('base64');
    const wslCommand = `wsl -d kali-linux -u cloudos -- bash -c "echo '${encoded}' | base64 -d | bash"`;
    
    const { stdout } = await execAsync(wslCommand, { timeout: 15000, maxBuffer: 1024 * 1024 });

    const lines = stdout.split('\n');
    const tools = [];
    const system = {};
    let disk = {};
    let memory = {};
    let section = '';

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      if (trimmed === '===TOOLS===')    { section = 'tools';   continue; }
      if (trimmed === '===SYSTEM===')   { section = 'system';  continue; }
      if (trimmed === '===DISK===')     { section = 'disk';    continue; }
      if (trimmed === '===MEMORY===')   { section = 'memory';  continue; }
      if (trimmed === '===END===')      { break; }

      if (section === 'tools') {
        const [name, status] = trimmed.split(':');
        if (!name) continue;
        const toolInfo = TACTICAL_TOOLS.find(t => t.name === name);
        if (toolInfo) {
          tools.push({ ...toolInfo, installed: status === 'INSTALLED' });
        }
      } else if (section === 'system') {
        const [key, ...valueParts] = trimmed.split(':');
        if (key) system[key.toLowerCase()] = valueParts.join(':');
      } else if (section === 'disk') {
        const parts = trimmed.split(/\s+/);
        if (parts.length >= 6) {
          disk = {
            filesystem: parts[0],
            size:       parts[1],
            used:       parts[2],
            available:  parts[3],
            usePercent: parts[4],
            mount:      parts[5]
          };
        }
      } else if (section === 'memory') {
        const parts = trimmed.split(/\s+/);
        if (parts.length >= 7) {
          memory = {
            total:     parseInt(parts[1]),
            used:      parseInt(parts[2]),
            free:      parseInt(parts[3]),
            shared:    parseInt(parts[4]),
            cache:     parseInt(parts[5]),
            available: parseInt(parts[6])
          };
        }
      }
    }

    const installedCount = tools.filter(t => t.installed).length;
    const missingCount   = tools.length - installedCount;

    res.json({
      tools,
      system,
      disk,
      memory,
      wslState: diag,
      summary: {
        total:      tools.length,
        installed:  installedCount,
        missing:    missingCount,
        healthScore: tools.length > 0 ? Math.round((installedCount / tools.length) * 100) : 0
      }
    });
  } catch (err) {
    console.error('[EnvironmentDoctor] Erro no diagnóstico:', err.message);
    res.status(500).json({ error: 'Falha ao diagnosticar ambiente', details: err.message });
  }
});

/**
 * POST /api/environment/install/:toolName
 */
router.post('/install/:toolName', async (req, res) => {
  const { toolName } = req.params;
  const tool = TACTICAL_TOOLS.find(t => t.name === toolName);
  const db = req.app.get('db');

  if (!tool) {
    return res.status(404).json({ error: 'Ferramenta não catalogada' });
  }

  if (isInstalling) {
    return res.status(429).json({ error: 'Uma instalação já está em andamento. Aguarde.' });
  }

  isInstalling = true;
  try {
    const installCmd = `wsl -d kali-linux -u cloudos -- bash -c "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing ${tool.package} 2>&1"`;
    const { stdout } = await execAsync(installCmd, { timeout: 180000, maxBuffer: 10 * 1024 * 1024 });

    const checkCmd = `wsl -d kali-linux -u cloudos -- bash -c "command -v ${tool.name}"`;
    let installed = false;
    try {
      const { stdout: checkOut } = await execAsync(checkCmd, { timeout: 5000 });
      installed = checkOut.trim().length > 0;
    } catch {
      installed = false;
    }

    await logAudit(db, req.user.id, 'install_single', tool.name, installed ? 'SUCCESS' : 'FAILED');

    res.json({
      success: installed,
      tool: tool.name,
      package: tool.package,
      message: installed
        ? `${tool.name} instalado com sucesso`
        : 'Instalação concluída mas binário não encontrado no PATH',
      output: stdout.slice(-500)
    });
  } catch (err) {
    console.error(`[EnvironmentDoctor] Erro ao instalar ${toolName}:`, err.message);
    await logAudit(db, req.user.id, 'install_single', tool.name, 'ERROR', err.message);
    res.status(500).json({
      success: false,
      error: `Falha ao instalar ${tool.name}`,
      details: err.message
    });
  } finally {
    isInstalling = false;
  }
});

/**
 * POST /api/environment/install-all-missing
 */
router.post('/install-all-missing', async (req, res) => {
  const db = req.app.get('db');
  if (isInstalling) {
    return res.status(429).json({ error: 'Uma instalação já está em andamento.' });
  }

  isInstalling = true;
  try {
    const toolNames = TACTICAL_TOOLS.map(t => t.name).join(' ');

    const checkScript = `for tool in ${toolNames}; do
  if ! command -v "$tool" &>/dev/null; then
    echo "$tool"
  fi
done`;

    const encoded = Buffer.from(checkScript).toString('base64');
    const checkCmd = `wsl -d kali-linux -u cloudos -- bash -c "echo '${encoded}' | base64 -d | bash"`;
    const { stdout: missingOut } = await execAsync(checkCmd, { timeout: 15000 });

    const missing = missingOut.trim().split('\n').filter(Boolean);

    if (missing.length === 0) {
      return res.json({ success: true, message: 'Todas as ferramentas já estão instaladas', installed: [] });
    }

    const packages = missing
      .map(name => TACTICAL_TOOLS.find(t => t.name === name)?.package)
      .filter(Boolean)
      .join(' ');

    const installCmd = `wsl -d kali-linux -u cloudos -- bash -c "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing ${packages} 2>&1"`;
    const { stdout } = await execAsync(installCmd, { timeout: 600000, maxBuffer: 20 * 1024 * 1024 });

    await logAudit(db, req.user.id, 'install_all_missing', packages, 'SUCCESS');

    res.json({
      success: true,
      message: `${missing.length} ferramenta(s) instalada(s)`,
      installed: missing,
      output: stdout.slice(-500)
    });
  } catch (err) {
    console.error('[EnvironmentDoctor] Erro ao instalar todas:', err.message);
    await logAudit(db, req.user.id, 'install_all_missing', 'multiple', 'ERROR', err.message);
    res.status(500).json({ success: false, error: err.message });
  } finally {
    isInstalling = false;
  }
});

/**
 * POST /api/environment/update
 */
router.post('/update', async (req, res) => {
  const db = req.app.get('db');
  if (isInstalling) {
    return res.status(429).json({ error: 'Outro processo de atualização ou instalação já está em andamento.' });
  }

  isInstalling = true;
  try {
    const updateCmd = `wsl -d kali-linux -u cloudos -- bash -c "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1"`;
    const { stdout } = await execAsync(updateCmd, { timeout: 300000, maxBuffer: 20 * 1024 * 1024 });

    await logAudit(db, req.user.id, 'apt_update_upgrade', 'system', 'SUCCESS');

    res.json({
      success: true,
      message: 'Sistema atualizado com sucesso',
      output: stdout.slice(-1000)
    });
  } catch (err) {
    console.error('[EnvironmentDoctor] Erro ao atualizar:', err.message);
    await logAudit(db, req.user.id, 'apt_update_upgrade', 'system', 'ERROR', err.message);
    res.status(500).json({
      success: false,
      error: 'Falha ao atualizar sistema',
      details: err.message
    });
  } finally {
    isInstalling = false;
  }
});

module.exports = router;

