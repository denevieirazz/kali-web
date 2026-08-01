const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { promisify } = require('util');
const { authenticateToken } = require('../middleware/auth');

const execAsync = promisify(exec);

router.use(authenticateToken);

/**
 * POST /api/osint/scan
 * Executa ferramentas de OSINT (whois, dnsenum, theHarvester) no Kali via WSL2
 */
router.post('/scan', async (req, res) => {
  const { domain, module: osintModule } = req.body;

  if (!domain) return res.status(400).json({ error: 'Domínio alvo é obrigatório' });

  // Limpeza básica para prevenir injeções de comando
  const safeDomain = domain.replace(/[;|&`$()]/g, '').trim();

  let command = '';
  switch (osintModule) {
    case 'whois':
      command = `whois ${safeDomain}`;
      break;
    case 'theharvester':
      command = `theHarvester -d ${safeDomain} -b baidu,bing,duckduckgo -l 100`;
      break;
    case 'dnsenum':
      command = `dnsenum --enum ${safeDomain} --noreverse`;
      break;
    default:
      command = `whois ${safeDomain}`;
  }

  try {
    const wslCmd = `wsl -d kali-linux -u cloudos -- bash -c "${command} 2>&1"`;
    const { stdout } = await execAsync(wslCmd, { timeout: 120000, maxBuffer: 10 * 1024 * 1024 });

    const structuredData = {
      emails: [],
      subdomains: [],
      ips: [],
      rawText: stdout
    };

    // Parsing inteligente de emails
    const emailMatches = stdout.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g);
    if (emailMatches) {
      structuredData.emails = [...new Set(emailMatches)];
    }

    // Parsing inteligente de IPs
    const ipMatches = stdout.match(/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/g);
    if (ipMatches) {
      structuredData.ips = [...new Set(ipMatches)];
    }

    // Parsing de subdomínios vinculados ao domínio alvo
    const domainRegex = new RegExp(`[a-zA-Z0-9.-]+\\.${safeDomain.replace('.', '\\.')}`, 'gi');
    const subMatches = stdout.match(domainRegex);
    if (subMatches) {
      structuredData.subdomains = [...new Set(subMatches)];
    }

    res.json({
      success: true,
      domain: safeDomain,
      module: osintModule,
      rawCommand: command,
      data: structuredData
    });

  } catch (err) {
    console.error('[OsintManager] Erro:', err.message);
    res.status(500).json({ error: 'Falha ao executar varredura OSINT', details: err.message.slice(-200) });
  }
});

module.exports = router;
