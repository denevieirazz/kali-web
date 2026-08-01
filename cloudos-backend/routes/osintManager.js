const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/osint/scan
 * Executa ferramentas de OSINT (whois, dnsenum, theHarvester, sherlock, shodan, holehe)
 */
router.post('/scan', async (req, res) => {
  const { target, module: osintModule } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo é obrigatório' });

  // Limpeza básica para prevenir injeções de comando
  const safeTarget = target.replace(/[;|&`$()]/g, '').trim();

  let command = '';
  let targetType = 'domain'; // domain, username, ip, email

  switch (osintModule) {
    case 'whois':
      targetType = 'domain';
      command = `whois ${safeTarget}`;
      break;
    case 'theharvester':
      targetType = 'domain';
      command = `theHarvester -d ${safeTarget} -b baidu,bing,duckduckgo -l 100`;
      break;
    case 'dnsenum':
      targetType = 'domain';
      command = `dnsenum --enum ${safeTarget} --noreverse`;
      break;
    case 'sherlock':
      targetType = 'username';
      command = `sherlock ${safeTarget} --timeout 10 --print --no-color`;
      break;
    case 'shodan':
      targetType = 'ip';
      command = `shodan host ${safeTarget}`;
      break;
    case 'holehe':
      targetType = 'email';
      command = `holehe ${safeTarget} --only-used --no-color`;
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
      registeredServices: [],
      rawText: stdout
    };

    // Parsing de e-mails
    const emailMatches = stdout.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g);
    if (emailMatches) structuredData.emails = [...new Set(emailMatches)];

    // Parsing de IPs
    const ipMatches = stdout.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/g);
    if (ipMatches) structuredData.ips = [...new Set(ipMatches)];

    // Parsing de Subdomínios (se for domínio)
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

    // Parsing de Serviços Registrados (Holehe)
    if (targetType === 'email') {
      // Holehe geralmente usa "[+]" para indicar serviços onde a conta existe
      const lines = stdout.split('\n');
      const services = [];
      lines.forEach(line => {
        if (line.includes('[+]') || line.includes('[x]')) {
          const cleanLine = line.replace(/\[\+\]|\[x\]/g, '').trim();
          if (cleanLine) services.push(cleanLine);
        }
      });
      if (services.length > 0) structuredData.registeredServices = services;
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
    
    if (err.message.includes('command not found')) {
      if (osintModule === 'sherlock') {
        return res.status(500).json({ 
          error: 'Sherlock não está instalado no WSL Kali.', 
          details: 'Abra o terminal e rode: sudo pip3 install sherlock-project' 
        });
      }
      if (osintModule === 'shodan') {
        return res.status(500).json({ 
          error: 'CLI do Shodan não está instalada ou configurada.', 
          details: 'Rode: sudo pip3 install shodan && shodan init YOUR_API_KEY' 
        });
      }
      if (osintModule === 'holehe') {
        return res.status(500).json({ 
          error: 'Holehe não está instalado no WSL Kali.', 
          details: 'Rode: sudo pip3 install holehe' 
        });
      }
    }
    
    res.status(500).json({ error: 'Falha ao executar varredura OSINT', details: err.message.slice(-200) });
  }
});

module.exports = router;
