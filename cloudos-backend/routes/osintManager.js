const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/osint/scan
 * Executa ferramentas de OSINT (whois, dnsenum, theHarvester, sherlock)
 */
router.post('/scan', async (req, res) => {
  const { target, module: osintModule } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo é obrigatório' });

  // Limpeza básica para prevenir injeções de comando
  const safeTarget = target.replace(/[;|&`$()]/g, '').trim();

  let command = '';
  let targetType = 'domain'; // default

  switch (osintModule) {
    case 'whois':
      command = `whois ${safeTarget}`;
      break;
    case 'theharvester':
      command = `theHarvester -d ${safeTarget} -b baidu,bing,duckduckgo -l 100`;
      break;
    case 'dnsenum':
      command = `dnsenum --enum ${safeTarget} --noreverse`;
      break;
    case 'sherlock':
      targetType = 'username';
      // --timeout 10 para não travar em sites lentos
      command = `sherlock ${safeTarget} --timeout 10 --print --no-color`;
      break;
    default:
      command = `whois ${safeTarget}`;
  }

  try {
    const wslCmd = `wsl -d kali-linux -u cloudos -- bash -c "${command} 2>&1"`;
    const { stdout } = await execAsync(wslCmd, { timeout: 120000, maxBuffer: 10 * 1024 * 1024 });

    const structuredData = {
      emails: [],
      subdomains: [],
      ips: [],
      profiles: [],
      rawText: stdout
    };

    // Parsing de e-mails
    const emailMatches = stdout.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g);
    if (emailMatches) structuredData.emails = [...new Set(emailMatches)];

    // Parsing de IPs
    const ipMatches = stdout.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/g);
    if (ipMatches) structuredData.ips = [...new Set(ipMatches)];

    // Parsing de Subdomínios (apenas se for domínio)
    if (targetType === 'domain') {
      const domainRegex = new RegExp(`[a-zA-Z0-9.-]+\\.${safeTarget.replace('.', '\\.')}`, 'gi');
      const subMatches = stdout.match(domainRegex);
      if (subMatches) structuredData.subdomains = [...new Set(subMatches)];
    }

    // Parsing de Perfis (Sherlock)
    if (targetType === 'username') {
      const urlMatches = stdout.match(/https?:\/\/[^\s]+/gi);
      if (urlMatches) structuredData.profiles = [...new Set(urlMatches)];
    }

    res.json({
      success: true,
      target: safeTarget,
      module: osintModule,
      targetType,
      rawCommand: command,
      data: structuredData
    });

  } catch (err) {
    console.error('[OsintManager] Erro:', err.message);
    
    if (err.message.includes('command not found') && osintModule === 'sherlock') {
      return res.status(500).json({ 
        error: 'Sherlock não está instalado no WSL Kali.', 
        details: 'Abra o terminal e rode: sudo pip3 install sherlock-project' 
      });
    }
    
    res.status(500).json({ error: 'Falha ao executar varredura OSINT', details: err.message.slice(-200) });
  }
});

module.exports = router;
