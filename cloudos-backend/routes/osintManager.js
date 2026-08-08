const { getProjectExecutionContext, isToolAllowed } = require('../services/scannerSecurity');

router.use(authenticateToken);

/**
 * POST /api/osint/scan
 * Executa ferramentas de OSINT protegidas pelo Scope Guard
 */
router.post('/scan', async (req, res) => {
  const { target, module: osintModule, projectId } = req.body;

  if (!target) return res.status(400).json({ error: 'Alvo é obrigatório' });
  if (!projectId) return res.status(403).json({ error: 'Operação de OSINT exige um Projeto Ativo (projectId).' });

  // Validação centralizada de Contexto e Scope Guard
  const contextCheck = await getProjectExecutionContext(req.user.id, projectId, target);
  if (!contextCheck.allowed) {
    return res.status(403).json({ error: contextCheck.reason });
  }

  // Limpeza estrita contra injeções
  const safeTarget = target.replace(/[^a-zA-Z0-9.@_-]/g, '').trim();
  if (!safeTarget) return res.status(400).json({ error: 'Alvo com formato inválido.' });

  let toolName = 'whois';
  let toolArgs = [];

  switch (osintModule) {
    case 'whois':
      toolName = 'whois';
      toolArgs = [safeTarget];
      break;
    case 'theharvester':
      toolName = 'theHarvester';
      toolArgs = ['-d', safeTarget, '-b', 'baidu,bing,duckduckgo', '-l', '100'];
      break;
    case 'dnsenum':
      toolName = 'dnsenum';
      toolArgs = ['--enum', safeTarget, '--noreverse'];
      break;
    default:
      toolName = 'whois';
      toolArgs = [safeTarget];
  }
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
    const args = ['-d', 'kali-linux', '-u', 'cloudos', '--', toolName, ...toolArgs];
    
    const stdout = await new Promise((resolve, reject) => {
      const p = spawn('wsl.exe', args);
      let out = '';
      let err = '';
      const timer = setTimeout(() => {
        try { p.kill('SIGKILL'); } catch {}
        reject(new Error('Timeout de execução atingido.'));
      }, 120000);

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
