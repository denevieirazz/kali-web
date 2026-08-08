// cloudos-backend/kali_tools_schema.js
// Arsenal Tático CloudOS - 55 Ferramentas de Pentest Profissional
// Categorias: Recon, Port Scan, Web, Exploit, Cracking, Post-Exploit, Cloud, Wireless, Forensics

const TOOL_SCHEMAS = {
    // ============================================================
    // 🔍 RECON & OSINT (Descoberta Passiva)
    // ============================================================
    nmap: {
        name: 'Nmap',
        command: 'nmap',
        category: 'Reconhecimento',
        description: 'O melhor scanner de portas e rede da atualidade.',
        installCmd: 'sudo apt install -y nmap',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (IP ou Domínio)', required: true, default: 'scanme.nmap.org', placeholder: 'ex: scanme.nmap.org ou 192.168.0.1', description: 'O endereço IP, site ou faixa de rede que você quer escanear.' },
            { id: 'ports', type: 'text', label: 'Portas', flag: '-p', placeholder: 'ex: 80,443 ou 1-1000', description: 'Especifique portas específicas. Deixe vazio para escanear as 1000 portas mais comuns.' },
            { id: 'syn_scan', type: 'boolean', label: 'SYN Scan (Stealth)', flag: '-sS', default: true, description: 'Escaneio silencioso e rápido (-sS). Não completa a conexão TCP. Requer privilégios de root.' },
            { id: 'service_version', type: 'boolean', label: 'Detectar Versão do Serviço', flag: '-sV', default: true, description: 'Tenta determinar a versão exata do software rodando na porta aberta (-sV).' },
            { id: 'aggressive', type: 'boolean', label: 'Modo Agressivo', flag: '-A', default: false, description: 'Ativa detecção de SO, traceroute e scripts padrão (-A). É barulhento e pode chamar atenção.' },
            { id: 'timing', type: 'select', label: 'Velocidade do Scan', flag: '-T', options: ['0 (Paranóico)', '1 (Descolado)', '2 (Educado)', '3 (Normal)', '4 (Agressivo)', '5 (Insano)'], default: '3 (Normal)', description: 'Controla o quão rápido os pacotes são enviados. 5 é muito rápido mas pula firewalls. 0 é invisível mas demora horas.' }
        ],
        presets: [
            { name: 'Scan Rápido (Top 100)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: false, aggressive: false, timing: '4 (Agressivo)' } },
            { name: 'Agressivo (OS + Versão)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: true, aggressive: true, timing: '4 (Agressivo)' } },
            { name: 'Furtivo (Lento)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: false, aggressive: false, timing: '1 (Descolado)' } }
        ]
    },
    subfinder: {
        name: 'Subfinder', command: 'subfinder', category: 'Reconhecimento', installCmd: 'sudo apt install -y subfinder',
        description: 'Descoberta passiva de subdomínios (OSINT) usando APIs públicas.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio Raiz', required: true, flag: '-d', default: 'example.com', description: 'Domínio principal para descobrir subdomínios.' },
            { id: 'silent', type: 'boolean', label: 'Modo Silencioso (Apenas resultados)', flag: '-silent', default: true, description: 'Exibe apenas os subdomínios encontrados, sem banners.' },
            { id: 'all', type: 'boolean', label: 'Usar todas as fontes (Lento)', flag: '-all', default: false, description: 'Consulta TODAS as fontes disponíveis. Mais resultados, mas bem mais lento.' }
        ],
        presets: [
            { name: 'Scan Rápido', vars: { domain: 'example.com', silent: true, all: false } },
            { name: 'Scan Completo (Todas as Fontes)', vars: { domain: 'example.com', silent: true, all: true } }
        ]
    },
    amass: {
        name: 'Amass (OWASP)', command: 'amass', category: 'Reconhecimento', installCmd: 'sudo apt install -y amass',
        description: 'Mapeamento profundo de superfície de ataque. Enumera subdomínios com técnicas ativas e passivas.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio', required: true, flag: '-d', default: 'example.com', description: 'Domínio para mapeamento de superfície de ataque.' },
            { id: 'active', type: 'boolean', label: 'Modo Ativo (Recomendado)', flag: '-active', default: true, description: 'Realiza enumeração ativa (consulta DNS, varredura de certificados).' },
            { id: 'brute', type: 'boolean', label: 'Brute-Force de Subdomínios', flag: '-brute', default: false, description: 'Tenta adivinhar subdomínios usando wordlist interna.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-o', default: '/tmp/amass.txt', description: 'Caminho para salvar os resultados.' }
        ],
        presets: [
            { name: 'Mapeamento Passivo', vars: { domain: 'example.com', active: false, brute: false, output: '/tmp/amass.txt' } },
            { name: 'Mapeamento Completo (Ativo + Brute)', vars: { domain: 'example.com', active: true, brute: true, output: '/tmp/amass_completo.txt' } }
        ]
    },
    theHarvester: {
        name: 'theHarvester', command: 'theHarvester', category: 'Reconhecimento', installCmd: 'sudo apt install -y theharvester',
        description: 'Coleta de emails, nomes, subdomínios e IPs de fontes públicas.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio', required: true, flag: '-d', default: 'example.com', description: 'Domínio alvo para coleta de informações.' },
            { id: 'source', type: 'select', label: 'Fonte de Dados', flag: '-b', default: 'google', options: ['google', 'bing', 'yahoo', 'linkedin', 'all'], description: 'Mecanismo de busca ou fonte para coleta. "all" usa todas.' },
            { id: 'limit', type: 'text', label: 'Limite de Resultados', flag: '-l', default: '50', description: 'Número máximo de resultados a retornar.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-f', default: '/tmp/harvester.html', description: 'Salva os resultados em arquivo HTML/XML.' }
        ],
        presets: [
            { name: 'Coleta Rápida (Google)', vars: { domain: 'example.com', source: 'google', limit: '100', output: '/tmp/harvester.html' } },
            { name: 'Coleta Completa (All Sources)', vars: { domain: 'example.com', source: 'all', limit: '200', output: '/tmp/harvester_full.html' } }
        ]
    },
    whatweb: {
        name: 'WhatWeb', command: 'whatweb', category: 'Reconhecimento', installCmd: 'sudo apt install -y whatweb',
        description: 'Identifica tecnologias web (CMS, frameworks, servidores, analytics). Fingerprint passivo.',
        fields: [
            { id: 'target', type: 'text', label: 'URL Alvo', required: true, default: 'http://example.com', description: 'URL do site para identificar tecnologias.' },
            { id: 'aggression', type: 'select', label: 'Nível de Agressividade', flag: '-a', default: '1', options: ['1 (Passivo)', '2 (Moderado)', '3 (Agressivo)', '4 (Muito Agressivo)'], description: 'Controla quantas requisições e testes o WhatWeb faz.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-v', default: true, description: 'Mostra detalhes de cada plugin executado.' }
        ],
        presets: [
            { name: 'Fingerprint Passivo', vars: { target: 'http://example.com', aggression: '1 (Passivo)', verbose: true } },
            { name: 'Fingerprint Agressivo', vars: { target: 'http://example.com', aggression: '3 (Agressivo)', verbose: true } }
        ]
    },
    dnsrecon: {
        name: 'DNSRecon', command: 'dnsrecon', category: 'Reconhecimento', installCmd: 'sudo apt install -y dnsrecon',
        description: 'Enumeração de DNS (registros A, AAAA, MX, NS, AXFR, brute-force de subdomínios).',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio', required: true, flag: '-d', default: 'example.com', description: 'Domínio para enumeração DNS.' },
            { id: 'type', type: 'select', label: 'Tipo de Enumeração', flag: '-t', default: 'std', options: ['std (Registros Comuns)', 'axfr (Transferência de Zona)', 'brt (Brute-Force)', 'all (Completo)'], description: 'Tipo de scan DNS a ser executado.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist (para Brute-Force)', flag: '-D', default: '/usr/share/wordlists/dnsmap.txt', description: 'Wordlist usada no modo brute-force de subdomínios.' }
        ],
        presets: [
            { name: 'Registros DNS Comuns', vars: { domain: 'example.com', type: 'std (Registros Comuns)', wordlist: '' } },
            { name: 'Tentativa de Transferência de Zona', vars: { domain: 'example.com', type: 'axfr (Transferência de Zona)', wordlist: '' } },
            { name: 'Brute-Force de Subdomínios', vars: { domain: 'example.com', type: 'brt (Brute-Force)', wordlist: '/usr/share/wordlists/dnsmap.txt' } }
        ]
    },
    wafw00f: {
        name: 'WafW00f', command: 'wafw00f', category: 'Reconhecimento', installCmd: 'sudo apt install -y wafw00f',
        description: 'Detecta Web Application Firewalls (WAF) protegendo o alvo.',
        fields: [
            { id: 'target', type: 'text', label: 'URL Alvo', required: true, default: 'http://example.com', description: 'URL do site para detectar presença de WAF.' },
            { id: 'findall', type: 'boolean', label: 'Buscar Todos os WAFs', flag: '-a', default: false, description: 'Tenta identificar múltiplos WAFs em cadeia.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-v', default: true, description: 'Exibe testes realizados e detalhes da detecção.' }
        ],
        presets: [
            { name: 'Detectar WAF', vars: { target: 'http://example.com', findall: false, verbose: true } },
            { name: 'Detectar Múltiplos WAFs', vars: { target: 'http://example.com', findall: true, verbose: true } }
        ]
    },

    // ============================================================
    // 🔌 PORT SCANNING (Descoberta de Portas)
    // ============================================================
    masscan: {
        name: 'Masscan', command: 'masscan', category: 'Port Scanning', installCmd: 'sudo apt install -y masscan',
        description: 'Scanner de portas mais rápido do mundo. Escaneia a Internet inteira em minutos.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (IP ou Range CIDR)', required: true, default: '192.168.0.1', flag: '', description: 'IP único ou faixa CIDR (ex: 192.168.0.0/24) para escanear.' },
            { id: 'ports', type: 'text', label: 'Portas', required: true, default: '1-65535', flag: '-p', description: 'Range de portas a escanear. Padrão: todas as 65535 portas.' },
            { id: 'rate', type: 'text', label: 'Taxa de Pacotes/s', flag: '--rate', default: '1000', description: 'Pacotes por segundo. 1000 é seguro, 10000 é rápido, 100000+ pode travar redes.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-oJ', default: '/tmp/masscan.json', description: 'Arquivo JSON com resultados do scan.' }
        ],
        presets: [
            { name: 'Top 100 Portas (Rápido)', vars: { target: '192.168.0.1', ports: '1-100', rate: '1000', output: '/tmp/masscan_top100.json' } },
            { name: 'Todas as Portas (Full Scan)', vars: { target: '192.168.0.1', ports: '1-65535', rate: '5000', output: '/tmp/masscan_full.json' } }
        ]
    },
    naabu: {
        name: 'Naabu (ProjectDiscovery)', command: 'naabu', category: 'Port Scanning', installCmd: 'sudo apt install -y naabu',
        description: 'Scanner de portas rápido e confiável, focado em velocidade com SYN Scan.',
        fields: [
            { id: 'host', type: 'text', label: 'Host Alvo', required: true, flag: '-host', default: 'scanme.nmap.org', description: 'IP ou domínio para escanear portas.' },
            { id: 'ports', type: 'text', label: 'Portas (Top 100 se vazio)', flag: '-p', default: '', description: 'Deixe vazio para Top 100 ou especifique (ex: 80,443,8080).' },
            { id: 'rate', type: 'text', label: 'Taxa de Pacotes/s', flag: '-rate', default: '1000', description: 'Velocidade de envio de pacotes SYN.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-v', default: false, description: 'Mostra progresso e portas abertas em tempo real.' }
        ],
        presets: [
            { name: 'Top 100 Portas (Rápido)', vars: { host: 'scanme.nmap.org', ports: '', rate: '1000', verbose: false } },
            { name: 'Portas Específicas', vars: { host: 'scanme.nmap.org', ports: '80,443,8080,8443,3000,5000', rate: '1000', verbose: true } }
        ]
    },
    rustscan: {
        name: 'RustScan', command: 'rustscan', category: 'Port Scanning', installCmd: 'sudo apt install -y rustscan',
        description: 'Scanner de portas ultrarrápido escrito em Rust. Faz scan de 65k portas em 3 segundos.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (IP ou Domínio)', required: true, default: 'scanme.nmap.org', description: 'IP ou domínio para escanear.' },
            { id: 'range', type: 'select', label: 'Range de Portas', flag: '', default: 'top', options: ['top (Top 1000)', 'all (1-65535)'], description: 'Escolha entre portas mais comuns ou varredura completa.' },
            { id: 'timeout', type: 'text', label: 'Timeout (ms)', flag: '-t', default: '1500', description: 'Timeout em milissegundos. Reduza para scans mais rápidos.' },
            { id: 'ulimit', type: 'text', label: 'Ulimit (Conexões Simultâneas)', flag: '-u', default: '5000', description: 'Número de sockets abertos simultaneamente.' }
        ],
        presets: [
            { name: 'Top 1000 Portas (3 segundos)', vars: { target: 'scanme.nmap.org', range: 'top (Top 1000)', timeout: '1500', ulimit: '5000' } },
            { name: 'Full Scan (65k Portas)', vars: { target: 'scanme.nmap.org', range: 'all (1-65535)', timeout: '1000', ulimit: '5000' } }
        ]
    },

    // ============================================================
    // 🌐 WEB SCANNING (Aplicações Web)
    // ============================================================
    gobuster: {
        name: 'Gobuster', command: 'gobuster', category: 'Web Scanning', installCmd: 'sudo apt install -y gobuster',
        description: 'Brute-force de diretórios, arquivos, DNS e VHosts em aplicações web.',
        fields: [
            { id: 'mode', type: 'select', label: 'Modo', required: true, flag: '', default: 'dir', options: ['dir', 'dns', 'vhost', 'fuzz'], description: 'Modo de brute-force: diretórios, subdomínios DNS, hosts virtuais ou fuzzing.' },
            { id: 'url', type: 'text', label: 'URL', required: true, flag: '-u', default: 'http://localhost', description: 'URL base do alvo (com http:// ou https://).' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', required: true, flag: '-w', default: '/usr/share/wordlists/dirb/common.txt', description: 'Caminho da wordlist no Kali Linux.' },
            { id: 'x', type: 'text', label: 'Extensões (php,html,txt)', flag: '-x', description: 'Extensões de arquivo para testar, separadas por vírgula.' },
            { id: 't', type: 'text', label: 'Threads (Velocidade)', flag: '-t', default: '50', description: 'Número de threads concorrentes.' },
            { id: 'status_codes', type: 'text', label: 'Status Codes (ex: 200,302,403)', flag: '-s', default: '200,204,301,302,307,401,403', description: 'Códigos HTTP considerados válidos.' }
        ],
        presets: [
            { name: 'Scan Dir + php,html,txt', vars: { mode: 'dir', url: 'http://localhost', wordlist: '/usr/share/wordlists/dirb/common.txt', x: 'php,html,txt,bak,zip', t: '50', status_codes: '200,204,301,302,307,401,403' } },
            { name: 'DNS Subdomain Brute-Force', vars: { mode: 'dns', url: 'example.com', wordlist: '/usr/share/wordlists/dnsmap.txt', x: '', t: '50', status_codes: '' } }
        ]
    },
    ffuf: {
        name: 'FFuF (Fuzz Faster U Fool)', command: 'ffuf', category: 'Web Scanning', installCmd: 'sudo apt install -y ffuf',
        description: 'Fuzzer web ultrarrápido escrito em Go. Substitui Dirbuster e WFuzz.',
        fields: [
            { id: 'url', type: 'text', label: 'URL com FUZZ', required: true, flag: '-u', default: 'http://localhost/FUZZ', description: 'URL onde a palavra FUZZ será substituída pela wordlist.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', required: true, flag: '-w', default: '/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt', description: 'Wordlist para fuzzing.' },
            { id: 'mc', type: 'text', label: 'Match Status Codes', flag: '-mc', default: '200,301,302,307,401,403', description: 'Códigos HTTP a considerar como válidos.' },
            { id: 't', type: 'text', label: 'Threads', flag: '-t', default: '40', description: 'Número de threads concorrentes.' },
            { id: 'recursion', type: 'boolean', label: 'Recursão', flag: '-recursion', default: false, description: 'Ativa scan recursivo dentro de diretórios encontrados.' },
            { id: 'recursion_depth', type: 'text', label: 'Profundidade da Recursão', flag: '-recursion-depth', default: '2', description: 'Nível máximo de profundidade na recursão.' }
        ],
        presets: [
            { name: 'Fuzzing de Diretórios', vars: { url: 'http://localhost/FUZZ', wordlist: '/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt', mc: '200,301,302,307,401,403', t: '40', recursion: false } },
            { name: 'Fuzzing Recursivo', vars: { url: 'http://localhost/FUZZ', wordlist: '/usr/share/wordlists/dirb/common.txt', mc: '200,301,302,307', t: '20', recursion: true, recursion_depth: '2' } }
        ]
    },
    nikto: {
        name: 'Nikto', command: 'nikto', category: 'Web Scanning', installCmd: 'sudo apt install -y nikto',
        description: 'Scanner de vulnerabilidades web. Testa 6700+ arquivos/CGIs perigosos e versões desatualizadas.',
        fields: [
            { id: 'host', type: 'text', label: 'Host Alvo (sem http://)', required: true, flag: '-h', default: '127.0.0.1', description: 'IP ou domínio do servidor web.' },
            { id: 'port', type: 'text', label: 'Porta', flag: '-p', default: '80', description: 'Porta do servidor web.' },
            { id: 'ssl', type: 'boolean', label: 'Forçar SSL/TLS', flag: '-ssl', default: false, description: 'Usa HTTPS para conexão.' },
            { id: 'tuning', type: 'text', label: 'Tuning (Tipos de teste)', flag: '-Tuning', default: 'x', description: 'Códigos de teste: x (todos), 1 (arquivos), 2 (CGI), 3 (servidor), 4 (XSS), 5 (diretórios), 6 (injeção).' }
        ],
        presets: [
            { name: 'Scan Completo (Porta 80)', vars: { host: '127.0.0.1', port: '80', ssl: false, tuning: 'x' } },
            { name: 'Scan Focado em XSS e Injeção', vars: { host: '127.0.0.1', port: '443', ssl: true, tuning: '46' } }
        ]
    },
    nuclei: {
        name: 'Nuclei (ProjectDiscovery)', command: 'nuclei', category: 'Web Scanning', installCmd: 'sudo apt install -y nuclei',
        description: 'Scanner de vulnerabilidades baseado em templates YAML. +3000 templates oficiais.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (URL ou arquivo)', required: true, flag: '-u', default: 'http://example.com', description: 'URL alvo ou caminho de arquivo com lista de hosts.' },
            { id: 'templates', type: 'select', label: 'Templates', flag: '-t', default: 'vulnerabilities', options: ['vulnerabilities', 'cves', 'misconfiguration', 'exposures', 'technologies', 'all'], description: 'Categoria de templates a executar.' },
            { id: 'severity', type: 'select', label: 'Severidade Mínima', flag: '-severity', default: 'medium', options: ['info', 'low', 'medium', 'high', 'critical'], description: 'Exibe apenas vulnerabilidades com esta severidade ou superior.' },
            { id: 'silent', type: 'boolean', label: 'Modo Silencioso', flag: '-silent', default: true, description: 'Mostra apenas resultados, sem banners.' },
            { id: 'rate_limit', type: 'text', label: 'Rate Limit (req/s)', flag: '-rl', default: '150', description: 'Limite de requisições por segundo para não sobrecarregar o alvo.' }
        ],
        presets: [
            { name: 'Scan Rápido (Vulnerabilidades Críticas)', vars: { target: 'http://example.com', templates: 'vulnerabilities', severity: 'high', silent: true, rate_limit: '50' } },
            { name: 'Scan Completo (Todas as Categorias)', vars: { target: 'http://example.com', templates: 'all', severity: 'medium', silent: true, rate_limit: '100' } }
        ]
    },
    sqlmap: {
        name: 'SQLMap', command: 'sqlmap', category: 'Web Scanning', installCmd: 'sudo apt install -y sqlmap',
        description: 'Ferramenta automática de detecção e exploração de injeção SQL. Suporte a 40+ bancos de dados.',
        fields: [
            { id: 'url', type: 'text', label: 'URL (com parâmetro ?id=)', required: true, flag: '-u', default: 'http://localhost/test.php?id=1', description: 'URL completa com parâmetro vulnerável a SQLi.' },
            { id: 'dbs', type: 'boolean', label: 'Enumerar Bancos de Dados', flag: '--dbs', default: true, description: 'Lista todos os bancos de dados após explorar a injeção.' },
            { id: 'os_shell', type: 'boolean', label: 'Tentar obter OS Shell (Crítico)', flag: '--os-shell', default: false, description: 'Tenta abrir um shell no sistema operacional do servidor. Requer privilégios altos.' },
            { id: 'batch', type: 'boolean', label: 'Modo Automático (Sem Perguntas)', flag: '--batch', default: true, description: 'Responde automaticamente SIM para todas as perguntas do SQLMap.' },
            { id: 'level', type: 'select', label: 'Nível de Teste (1-5)', flag: '--level', default: '1', options: ['1', '2', '3', '4', '5'], description: '1 = rápido, 5 = testa todos os payloads incluindo HTTP headers.' },
            { id: 'risk', type: 'select', label: 'Risco (1-3)', flag: '--risk', default: '1', options: ['1', '2', '3'], description: '1 = seguro, 3 = pode causar danos ao banco de dados.' }
        ],
        presets: [
            { name: 'Testar URL e Enumerar DBs', vars: { url: 'http://localhost/test.php?id=1', dbs: true, os_shell: false, batch: true, level: '1', risk: '1' } },
            { name: 'Tentar OS Shell (RCE)', vars: { url: 'http://localhost/test.php?id=1', dbs: false, os_shell: true, batch: true, level: '3', risk: '2' } }
        ]
    },
    wpscan: {
        name: 'WPScan', command: 'wpscan', category: 'Web Scanning', installCmd: 'sudo apt install -y wpscan',
        description: 'Scanner de vulnerabilidades especializado em WordPress. Banco de dados de vulns atualizado.',
        fields: [
            { id: 'url', type: 'text', label: 'URL do WordPress', required: true, flag: '--url', default: 'http://localhost/wordpress', description: 'URL base do site WordPress.' },
            { id: 'enumerate', type: 'select', label: 'Enumeração', flag: '-e', default: 'vp,vt,u', options: ['vp (Plugins Vulneráveis)', 'vt (Temas Vulneráveis)', 'u (Usuários)', 'vp,vt,u (Completo)'], description: 'O que enumerar no WordPress.' },
            { id: 'plugins_detection', type: 'select', label: 'Detecção de Plugins', flag: '--plugins-detection', default: 'mixed', options: ['passive', 'aggressive', 'mixed'], description: 'Modo passivo (silencioso), agressivo (mais resultados) ou misto.' },
            { id: 'api_token', type: 'text', label: 'API Token (opcional)', flag: '--api-token', description: 'Token da WPScan API para dados de vulnerabilidades em tempo real.' }
        ],
        presets: [
            { name: 'Enumeração Básica (Sem Token)', vars: { url: 'http://localhost/wordpress', enumerate: 'vp,vt,u', plugins_detection: 'mixed', api_token: '' } },
            { name: 'Enumeração Completa Agressiva', vars: { url: 'http://localhost/wordpress', enumerate: 'vp,vt,u (Completo)', plugins_detection: 'aggressive', api_token: '' } }
        ]
    },
    dirb: {
        name: 'Dirb', command: 'dirb', category: 'Web Scanning', installCmd: 'sudo apt install -y dirb',
        description: 'Scanner de diretórios web clássico. Simples, rápido e eficaz.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Base', required: true, default: 'http://localhost', description: 'URL do alvo (com http://).' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', flag: '', default: '/usr/share/wordlists/dirb/common.txt', description: 'Caminho da wordlist no Kali.' },
            { id: 'extensions', type: 'text', label: 'Extensões', flag: '-X', default: '.php,.html,.txt', description: 'Extensões separadas por vírgula.' },
            { id: 'recursive', type: 'boolean', label: 'Modo Recursivo', flag: '-r', default: false, description: 'Entra em diretórios encontrados e continua o scan.' }
        ],
        presets: [
            { name: 'Scan Básico', vars: { url: 'http://localhost', wordlist: '/usr/share/wordlists/dirb/common.txt', extensions: '.php,.html,.txt', recursive: false } },
            { name: 'Scan Recursivo', vars: { url: 'http://localhost', wordlist: '/usr/share/wordlists/dirb/common.txt', extensions: '.php', recursive: true } }
        ]
    },
    arjun: {
        name: 'Arjun', command: 'arjun', category: 'Web Scanning', installCmd: 'sudo apt install -y arjun',
        description: 'Descoberta de parâmetros HTTP ocultos (GET/POST/JSON/XML).',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '-u', default: 'http://localhost/page.php', description: 'URL da página a ser analisada.' },
            { id: 'method', type: 'select', label: 'Método HTTP', flag: '-m', default: 'GET', options: ['GET', 'POST', 'JSON', 'XML'], description: 'Método HTTP para testar os parâmetros.' },
            { id: 'threads', type: 'text', label: 'Threads (Velocidade)', flag: '-t', default: '5', description: 'Número de threads concorrentes.' },
            { id: 'stable', type: 'boolean', label: 'Modo Estável (Menos Ruído)', flag: '--stable', default: true, description: 'Modo de espera entre requisições para evitar bloqueios.' }
        ],
        presets: [
            { name: 'Scan Rápido GET', vars: { url: 'http://localhost/page.php', method: 'GET', threads: '8', stable: false } },
            { name: 'Scan Estável POST', vars: { url: 'http://localhost/api/endpoint', method: 'POST', threads: '3', stable: true } }
        ]
    },
    paramspider: {
        name: 'ParamSpider', command: 'paramspider', category: 'Web Scanning', installCmd: 'git clone https://github.com/devanshbatham/ParamSpider && cd ParamSpider && pip install -r requirements.txt',
        description: 'Minerador de parâmetros a partir de archives.org e links do domínio.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio', required: true, flag: '-d', default: 'example.com', description: 'Domínio para minerar parâmetros de URLs.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-o', default: '/tmp/params.txt', description: 'Arquivo para salvar os parâmetros encontrados.' },
            { id: 'placeholder', type: 'boolean', label: 'Incluir Placeholder FUZZ', flag: '--placeholder', default: true, description: 'Adiciona marcador FUZZ nos parâmetros para uso com FFuF.' }
        ],
        presets: [
            { name: 'Minerar Parâmetros', vars: { domain: 'example.com', output: '/tmp/params.txt', placeholder: true } }
        ]
    },
    ghauri: {
        name: 'Ghauri', command: 'ghauri', category: 'Web Scanning', installCmd: 'sudo apt install -y ghauri',
        description: 'Ferramenta avançada de detecção e exploração de SQL Injection (sucessor moderno do SQLMap).',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '-u', default: 'http://localhost/test.php?id=1', description: 'URL vulnerável a SQLi.' },
            { id: 'dbs', type: 'boolean', label: 'Enumerar Bancos de Dados', flag: '--dbs', default: true, description: 'Lista bancos de dados após explorar.' },
            { id: 'batch', type: 'boolean', label: 'Modo Automático', flag: '--batch', default: true, description: 'Responde sim para todas as perguntas.' }
        ],
        presets: [
            { name: 'Teste SQLi Automático', vars: { url: 'http://localhost/test.php?id=1', dbs: true, batch: true } }
        ]
    },
    commix: {
        name: 'Commix', command: 'commix', category: 'Web Scanning', installCmd: 'sudo apt install -y commix',
        description: 'Detector e explorador automático de Command Injection / OS Command Injection.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '--url', default: 'http://localhost/ping.php?ip=127.0.0.1', description: 'URL com parâmetro vulnerável a injeção de comando.' },
            { id: 'data', type: 'text', label: 'Dados POST (se aplicável)', flag: '--data', description: 'Dados POST no formato param1=valor1&param2=valor2.' },
            { id: 'os_shell', type: 'boolean', label: 'Tentar Obter Shell Interativo', flag: '--os-shell', default: false, description: 'Tenta estabelecer um shell reverso no servidor.' }
        ],
        presets: [
            { name: 'Testar Command Injection (GET)', vars: { url: 'http://localhost/ping.php?ip=127.0.0.1', os_shell: false } },
            { name: 'Tentar Shell Reverso (POST)', vars: { url: 'http://localhost/api/ping', data: 'ip=127.0.0.1', os_shell: true } }
        ]
    },
    xsstrike: {
        name: 'XSStrike', command: 'xsstrike', category: 'Web Scanning', installCmd: 'git clone https://github.com/s0md3v/XSStrike && cd XSStrike && pip install -r requirements.txt',
        description: 'Scanner de XSS avançado com análise de contexto e bypass de WAF.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '-u', default: 'http://localhost/search.php?q=test', description: 'URL com parâmetro para testar XSS.' },
            { id: 'crawl', type: 'boolean', label: 'Rastrear e Testar Páginas', flag: '--crawl', default: false, description: 'Faz crawling do site e testa todos os parâmetros encontrados.' },
            { id: 'blind', type: 'boolean', label: 'Modo Blind XSS', flag: '--blind', default: false, description: 'Testa XSS cego (armazenado).' }
        ],
        presets: [
            { name: 'Testar XSS Refletido', vars: { url: 'http://localhost/search.php?q=test', crawl: false, blind: false } },
            { name: 'Crawling + Teste XSS', vars: { url: 'http://localhost', crawl: true, blind: false } }
        ]
    },
    ssrfmap: {
        name: 'SSRFmap', command: 'ssrfmap', category: 'Web Scanning', installCmd: 'git clone https://github.com/swisskyrepo/SSRFmap && cd SSRFmap && pip install -r requirements.txt',
        description: 'Explorador automático de Server-Side Request Forgery (SSRF).',
        fields: [
            { id: 'url', type: 'text', label: 'URL Vulnerável', required: true, default: 'http://localhost/proxy.php?url=FUZZ', description: 'URL com parâmetro SSRF (use FUZZ como placeholder).' },
            { id: 'module', type: 'select', label: 'Módulo de Ataque', default: 'portscan', options: ['portscan', 'readfiles', 'aws', 'gce', 'custom'], description: 'Tipo de exploração SSRF.' },
            { id: 'lhost', type: 'text', label: 'IP do Atacante (LHOST)', default: '127.0.0.1', description: 'Seu IP para receber callbacks em módulos específicos.' }
        ],
        presets: [
            { name: 'Portscan Interno via SSRF', vars: { url: 'http://localhost/proxy.php?url=FUZZ', module: 'portscan', lhost: '127.0.0.1' } },
            { name: 'Ler Arquivos Internos (AWS Metadata)', vars: { url: 'http://localhost/proxy.php?url=FUZZ', module: 'aws', lhost: '127.0.0.1' } }
        ]
    },
    lfimap: {
        name: 'LFImap', command: 'lfimap', category: 'Web Scanning', installCmd: 'git clone https://github.com/hansmach1ne/LFImap && cd LFImap && pip install -r requirements.txt',
        description: 'Scanner e explorador de Local File Inclusion (LFI) com suporte a +20 técnicas de bypass.',
        fields: [
            { id: 'url', type: 'text', label: 'URL com parâmetro LFI', required: true, default: 'http://localhost/page.php?file=FUZZ', description: 'URL onde FUZZ será substituído pelos payloads LFI.' },
            { id: 'rce', type: 'boolean', label: 'Tentar RCE (via Log Poisoning)', default: false, description: 'Tenta obter execução remota de código via envenenamento de logs.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist de Arquivos', default: '/usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt', description: 'Wordlist com caminhos de arquivos para testar.' }
        ],
        presets: [
            { name: 'Testar LFI Básico', vars: { url: 'http://localhost/page.php?file=FUZZ', rce: false, wordlist: '/usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt' } },
            { name: 'LFI + Tentar RCE', vars: { url: 'http://localhost/page.php?file=FUZZ', rce: true, wordlist: '/usr/share/seclists/Fuzzing/LFI/LFI-Jhaddix.txt' } }
        ]
    },
    log4jscanner: {
        name: 'Log4j-Scanner', command: 'log4j-scan', category: 'Web Scanning', installCmd: 'git clone https://github.com/fullhunt/log4j-scan && cd log4j-scan && pip install -r requirements.txt',
        description: 'Scanner automatizado para CVE-2021-44228 (Log4Shell) em cabeçalhos e parâmetros.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '-u', default: 'http://localhost', description: 'URL para testar Log4Shell.' },
            { id: 'callback', type: 'text', label: 'Servidor de Callback (DNS/HTTP)', flag: '--callback-server', default: '', description: 'Seu servidor para receber callbacks DNS (ex: burpcollaborator.net).' },
            { id: 'headers', type: 'textarea', label: 'Headers Customizados (JSON)', flag: '--headers', description: 'Headers HTTP adicionais no formato JSON.' }
        ],
        presets: [
            { name: 'Scan Log4j Básico', vars: { url: 'http://localhost', callback: '', headers: '' } },
            { name: 'Scan com Callback DNS', vars: { url: 'http://localhost', callback: 'xyz.burpcollaborator.net', headers: '' } }
        ]
    },

    // ============================================================
    // 💣 EXPLOIT (Exploração de Vulnerabilidades)
    // ============================================================
    searchsploit: {
        name: 'SearchSploit', command: 'searchsploit', category: 'Exploit', installCmd: 'sudo apt install -y exploitdb',
        description: 'Busca offline no Exploit-DB. +45.000 exploits locais para consulta rápida.',
        fields: [
            { id: 'query', type: 'text', label: 'Termo de Busca', required: true, default: 'Apache 2.4', description: 'Termo para buscar no Exploit-DB.' },
            { id: 'exact', type: 'boolean', label: 'Busca Exata', flag: '--exact', default: true, description: 'Correspondência exata do termo.' },
            { id: 'json', type: 'boolean', label: 'Retornar em JSON', flag: '--json', default: false, description: 'Formato JSON para parse automatizado.' },
            { id: 'exclude', type: 'text', label: 'Excluir Termos', flag: '--exclude', description: 'Termos a excluir dos resultados.' }
        ],
        presets: [
            { name: 'Buscar por Serviço', vars: { query: 'Apache 2.4', exact: true, json: false } },
            { name: 'Buscar por CVE', vars: { query: 'CVE-2021-44228', exact: true, json: true } }
        ]
    },
    metasploit: {
        name: 'Metasploit (msfconsole)', command: 'msfconsole', category: 'Exploit', installCmd: 'sudo apt install -y metasploit-framework',
        description: 'Framework de exploração mais famoso do mundo. +2000 exploits e +500 módulos auxiliares.',
        fields: [
            { id: 'resource_script', type: 'textarea', label: 'Resource Script (.rc)', required: true, flag: '-r', default: 'use auxiliary/scanner/portscan/tcp\nset RHOSTS 127.0.0.1\nset PORTS 1-1000\nrun\nexit', description: 'Script de automação do Metasploit. Cada linha é um comando.' },
            { id: 'quiet', type: 'boolean', label: 'Modo Silencioso (-q)', flag: '-q', default: true, description: 'Suprime o banner de inicialização.' }
        ],
        presets: [
            { name: 'Portscan TCP', vars: { resource_script: 'use auxiliary/scanner/portscan/tcp\nset RHOSTS 127.0.0.1\nset PORTS 1-1000\nrun\nexit', quiet: true } },
            { name: 'SMB Version Scan', vars: { resource_script: 'use auxiliary/scanner/smb/smb_version\nset RHOSTS 192.168.1.0/24\nset THREADS 10\nrun\nexit', quiet: true } }
        ]
    },
    routersploit: {
        name: 'RouterSploit', command: 'rsf', category: 'Exploit', installCmd: 'sudo apt install -y routersploit',
        description: 'Framework de exploração especializado em dispositivos embarcados, roteadores e IoT.',
        fields: [
            { id: 'module', type: 'select', label: 'Módulo de Ataque', default: 'scanners/autopwn', options: ['scanners/autopwn', 'routers/cisco', 'cameras/cctv', 'misc/wifi'], description: 'Categoria de módulo a executar.' },
            { id: 'target', type: 'text', label: 'IP Alvo', required: true, default: '192.168.1.1', description: 'IP do dispositivo embarcado alvo.' }
        ],
        presets: [
            { name: 'AutoPwn (Todos os Exploits)', vars: { module: 'scanners/autopwn', target: '192.168.1.1' } },
            { name: 'Scanner de Câmeras CCTV', vars: { module: 'cameras/cctv', target: '192.168.1.0/24' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'echo', args: [`use ${f.module}; set target ${f.target}; run; exit | rsf`] };
        }
    },
    crackmapexec: {
        name: 'CrackMapExec (CME)', command: 'crackmapexec', category: 'Exploit', installCmd: 'sudo apt install -y crackmapexec',
        description: 'O canivete suíço para ambientes Windows/AD. Enumera, explora e executa lateralmente.',
        fields: [
            { id: 'protocol', type: 'select', label: 'Protocolo', required: true, default: 'smb', options: ['smb', 'winrm', 'mssql', 'ssh', 'ldap', 'rdp'], description: 'Protocolo para ataque.' },
            { id: 'target', type: 'text', label: 'Alvo (IP ou Range)', required: true, default: '192.168.1.0/24', description: 'IP único, range CIDR ou arquivo com lista de hosts.' },
            { id: 'user', type: 'text', label: 'Usuário', flag: '-u', default: 'Administrator', description: 'Nome de usuário para autenticação.' },
            { id: 'password', type: 'text', label: 'Senha', flag: '-p', description: 'Senha para autenticação.' },
            { id: 'hash', type: 'text', label: 'NTLM Hash (Pass-the-Hash)', flag: '-H', description: 'Hash NTLM para autenticação sem senha.' },
            { id: 'shares', type: 'boolean', label: 'Enumerar Compartilhamentos', flag: '--shares', default: true, description: 'Lista todos os compartilhamentos SMB acessíveis.' },
            { id: 'exec_method', type: 'select', label: 'Execução Remota', flag: '-x', default: '', options: ['', 'atexec', 'smbexec', 'wmiexec'], description: 'Método de execução de comandos (deixe vazio para não executar).' }
        ],
        presets: [
            { name: 'Enumerar Compartilhamentos SMB', vars: { protocol: 'smb', target: '192.168.1.0/24', user: 'Administrator', password: '', hash: '', shares: true, exec_method: '' } },
            { name: 'Pass-the-Hash + Executar Comando', vars: { protocol: 'smb', target: '192.168.1.10', user: 'Administrator', password: '', hash: 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0', shares: false, exec_method: 'wmiexec' } }
        ]
    },
    impacket: {
        name: 'Impacket (psexec.py)', command: 'psexec.py', category: 'Exploit', installCmd: 'sudo apt install -y impacket-scripts',
        description: 'Coleção de ferramentas Python para manipulação de protocolos Windows. Psexec, secretsdump, wmiexec.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (IP)', required: true, default: '192.168.1.10', description: 'IP do host Windows alvo.' },
            { id: 'username', type: 'text', label: 'Usuário', required: true, default: 'Administrator', description: 'Nome de usuário para autenticação.' },
            { id: 'password', type: 'text', label: 'Senha', default: '', description: 'Senha do usuário (deixe vazio para usar hash).' },
            { id: 'hashes', type: 'text', label: 'Hash NTLM (LM:NT)', flag: '-hashes', description: 'Hash NTLM no formato LM:NT para Pass-the-Hash.' },
            { id: 'command', type: 'text', label: 'Comando a Executar', flag: '-c', default: 'whoami', description: 'Comando a ser executado remotamente.' }
        ],
        presets: [
            { name: 'Psexec com Senha', vars: { target: '192.168.1.10', username: 'Administrator', password: 'P@ssw0rd', hashes: '', command: 'whoami' } },
            { name: 'Psexec Pass-the-Hash', vars: { target: '192.168.1.10', username: 'Administrator', password: '', hashes: 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0', command: 'ipconfig /all' } }
        ]
    },
    evilwinrm: {
        name: 'Evil-WinRM', command: 'evil-winrm', category: 'Exploit', installCmd: 'sudo gem install evil-winrm',
        description: 'Shell interativo WinRM para Windows. Suporte a Pass-the-Hash, upload/download e scripts.',
        fields: [
            { id: 'ip', type: 'text', label: 'IP Alvo', required: true, flag: '-i', default: '192.168.1.10', description: 'IP do servidor Windows com WinRM habilitado.' },
            { id: 'user', type: 'text', label: 'Usuário', required: true, flag: '-u', default: 'Administrator', description: 'Nome de usuário.' },
            { id: 'password', type: 'text', label: 'Senha', flag: '-p', description: 'Senha do usuário (ou use Hash).' },
            { id: 'hash', type: 'text', label: 'Hash NTLM', flag: '-H', description: 'Hash NTLM para Pass-the-Hash.' },
            { id: 'ssl', type: 'boolean', label: 'Usar SSL', flag: '-S', default: false, description: 'Habilita conexão via HTTPS (porta 5986).' }
        ],
        presets: [
            { name: 'WinRM com Senha', vars: { ip: '192.168.1.10', user: 'Administrator', password: 'P@ssw0rd', hash: '', ssl: false } },
            { name: 'WinRM Pass-the-Hash', vars: { ip: '192.168.1.10', user: 'Administrator', password: '', hash: '31d6cfe0d16ae931b73c59d7e0c089c0', ssl: false } }
        ]
    },
    chisel: {
        name: 'Chisel (Tunneling)', command: 'chisel', category: 'Exploit', installCmd: 'sudo apt install -y chisel',
        description: 'Túnel TCP/UDP rápido sobre HTTP/HTTPS. Perfeito para pivotear redes internas.',
        fields: [
            { id: 'mode', type: 'select', label: 'Modo', required: true, default: 'client', options: ['client', 'server'], description: 'Cliente (sua máquina) ou Servidor (máquina alvo).' },
            { id: 'server_ip', type: 'text', label: 'IP do Servidor', required: true, default: '192.168.1.100:8080', description: 'IP:porta do servidor Chisel.' },
            { id: 'local_port', type: 'text', label: 'Porta Local', default: '1080', description: 'Porta local para SOCKS proxy ou redirecionamento.' },
            { id: 'remote_host', type: 'text', label: 'Host Remoto (opcional)', default: 'socks', description: 'Use "socks" para proxy SOCKS5 ou IP:porta para redirecionamento específico.' }
        ],
        presets: [
            { name: 'SOCKS Proxy Reverso', vars: { mode: 'client', server_ip: '192.168.1.100:8080', local_port: '1080', remote_host: 'socks' } },
            { name: 'Redirecionar Porta Interna', vars: { mode: 'client', server_ip: '192.168.1.100:8080', local_port: '3389', remote_host: '172.16.0.10:3389' } }
        ]
    },

    // ============================================================
    // 🔑 CRACKING (Quebra de Senhas e Hashes)
    // ============================================================
    hashcat: {
        name: 'Hashcat', command: 'hashcat', category: 'Cracking', installCmd: 'sudo apt install -y hashcat',
        description: 'Quebrador de hashes mais rápido do mundo. Aceleração GPU/CPU com +300 algoritmos.',
        fields: [
            { id: 'mode', type: 'text', label: 'Tipo do Hash', required: true, flag: '-m', default: '0', description: '0=MD5, 1000=NTLM, 1800=sha512crypt, 3200=bcrypt, 13100=Kerberos TGS.' },
            { id: 'hashfile', type: 'text', label: 'Arquivo de Hash', required: true, default: '/tmp/hash.txt', description: 'Caminho do arquivo contendo os hashes.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', required: true, default: '/usr/share/wordlists/rockyou.txt', description: 'Wordlist para ataque de dicionário.' },
            { id: 'rules', type: 'text', label: 'Regras (ex: best64.rule)', flag: '-r', default: '', description: 'Arquivo de regras para mutação de palavras (ex: /usr/share/hashcat/rules/best64.rule).' },
            { id: 'force', type: 'boolean', label: 'Forçar CPU (Sem GPU)', flag: '--force', default: false, description: 'Força uso de CPU quando GPU não está disponível.' },
            { id: 'show', type: 'boolean', label: 'Apenas Mostrar Resultados Anteriores', flag: '--show', default: false, description: 'Exibe hashes já quebrados sem rodar novo ataque.' }
        ],
        presets: [
            { name: 'Ataque MD5 com Rockyou', vars: { mode: '0', hashfile: '/tmp/hash.txt', wordlist: '/usr/share/wordlists/rockyou.txt', rules: '', force: false } },
            { name: 'NTLM + Regras (AD)', vars: { mode: '1000', hashfile: '/tmp/ntlm.txt', wordlist: '/usr/share/wordlists/rockyou.txt', rules: '/usr/share/hashcat/rules/best64.rule', force: false } },
            { name: 'Kerberoasting (TGS-REP)', vars: { mode: '13100', hashfile: '/tmp/kerb.txt', wordlist: '/usr/share/wordlists/rockyou.txt', rules: '/usr/share/hashcat/rules/rockyou-30000.rule', force: false } }
        ]
    },
    john: {
        name: 'John the Ripper', command: 'john', category: 'Cracking', installCmd: 'sudo apt install -y john',
        description: 'Quebrador de hashes versátil com auto-detecção de formato e suporte a GPU (Johnny).',
        fields: [
            { id: 'hash_file', type: 'text', label: 'Arquivo de Hashes', required: true, default: '/tmp/hashes.txt', description: 'Arquivo com hashes para quebrar.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', default: '/usr/share/wordlists/rockyou.txt', description: 'Wordlist para ataque de dicionário.' },
            { id: 'format', type: 'text', label: 'Formato do Hash (opcional)', default: '', description: 'Força formato específico: Raw-MD5, NT, sha512crypt, bcrypt.' },
            { id: 'rules', type: 'text', label: 'Regras', flag: '--rules', default: '', description: 'Nome da regra (ex: --rules=Wordlist).' }
        ],
        presets: [
            { name: 'Auto-Detect + Rockyou', vars: { hash_file: '/tmp/hashes.txt', wordlist: '/usr/share/wordlists/rockyou.txt', format: '', rules: '' } },
            { name: 'NTLM + Regras', vars: { hash_file: '/tmp/ntlm.txt', wordlist: '/usr/share/wordlists/rockyou.txt', format: 'NT', rules: '--rules=Wordlist' } }
        ],
        buildCmd: (f) => {
            const args = [];
            if (f.format) args.push(`--format=${f.format}`);
            if (f.wordlist) args.push(`--wordlist=${f.wordlist}`);
            if (f.rules) args.push(f.rules);
            args.push(f.hash_file);
            return { cmd: 'john', args };
        }
    },
    hydra: {
        name: 'Hydra', command: 'hydra', category: 'Cracking', installCmd: 'sudo apt install -y hydra',
        description: 'Brute-force de login online. Suporte a +50 protocolos: SSH, FTP, HTTP, RDP, SMB, MySQL.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (IP ou Domínio)', required: true, default: '192.168.1.10', description: 'IP ou hostname do serviço alvo.' },
            { id: 'service', type: 'select', label: 'Serviço', required: true, flag: '', default: 'ssh', options: ['ssh', 'ftp', 'http-post-form', 'rdp', 'smb', 'mysql', 'postgres', 'mssql', 'vnc'], description: 'Protocolo do serviço a atacar.' },
            { id: 'userlist', type: 'text', label: 'Arquivo de Usuários', flag: '-L', default: '/usr/share/wordlists/usernames.txt', description: 'Wordlist de nomes de usuário.' },
            { id: 'passlist', type: 'text', label: 'Arquivo de Senhas', flag: '-P', default: '/usr/share/wordlists/rockyou.txt', description: 'Wordlist de senhas.' },
            { id: 'threads', type: 'text', label: 'Threads', flag: '-t', default: '16', description: 'Número de threads paralelas.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-V', default: false, description: 'Mostra cada tentativa de login.' }
        ],
        presets: [
            { name: 'SSH Brute-Force', vars: { target: '192.168.1.10', service: 'ssh', userlist: '/usr/share/wordlists/usernames.txt', passlist: '/usr/share/wordlists/rockyou.txt', threads: '16', verbose: false } },
            { name: 'RDP Brute-Force', vars: { target: '192.168.1.10', service: 'rdp', userlist: '/usr/share/wordlists/usernames.txt', passlist: '/usr/share/wordlists/rockyou.txt', threads: '4', verbose: true } }
        ]
    },
    medusa: {
        name: 'Medusa', command: 'medusa', category: 'Cracking', installCmd: 'sudo apt install -y medusa',
        description: 'Brute-force paralelo e modular. Mais rápido que Hydra em ambientes com muitos alvos.',
        fields: [
            { id: 'host', type: 'text', label: 'Host Alvo', required: true, flag: '-h', default: '192.168.1.10', description: 'IP do servidor.' },
            { id: 'module', type: 'select', label: 'Módulo', required: true, flag: '-M', default: 'ssh', options: ['ssh', 'ftp', 'http', 'rdp', 'smbnt', 'mysql', 'postgres', 'vnc'], description: 'Módulo de serviço.' },
            { id: 'user', type: 'text', label: 'Arquivo de Usuários', flag: '-U', default: '/usr/share/wordlists/usernames.txt' },
            { id: 'pass', type: 'text', label: 'Arquivo de Senhas', flag: '-P', default: '/usr/share/wordlists/rockyou.txt' },
            { id: 'threads', type: 'text', label: 'Threads', flag: '-t', default: '4' }
        ],
        presets: [
            { name: 'SSH Multi-Thread', vars: { host: '192.168.1.10', module: 'ssh', user: '/usr/share/wordlists/usernames.txt', pass: '/usr/share/wordlists/rockyou.txt', threads: '10' } }
        ]
    },
    crunch: {
        name: 'Crunch', command: 'crunch', category: 'Cracking', installCmd: 'sudo apt install -y crunch',
        description: 'Gerador de wordlists customizadas com padrões de charset. Essencial para ataques direcionados.',
        fields: [
            { id: 'min_len', type: 'text', label: 'Tamanho Mínimo', required: true, default: '6', description: 'Comprimento mínimo da senha gerada.' },
            { id: 'max_len', type: 'text', label: 'Tamanho Máximo', required: true, default: '8', description: 'Comprimento máximo da senha gerada.' },
            { id: 'charset', type: 'text', label: 'Charset', default: 'abcdefghijklmnopqrstuvwxyz0123456789', description: 'Caracteres permitidos. Use @ (lower), , (upper), % (nums), ^ (special).' },
            { id: 'pattern', type: 'text', label: 'Padrão (ex: @,@%%)', default: '', description: 'Padrão de geração: @ = lower, , = upper, % = número, ^ = símbolo.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-o', default: '/tmp/custom_wordlist.txt', description: 'Arquivo para salvar a wordlist gerada.' }
        ],
        presets: [
            { name: 'Senhas 6-8 chars (lower+nums)', vars: { min_len: '6', max_len: '8', charset: 'abcdefghijklmnopqrstuvwxyz0123456789', pattern: '', output: '/tmp/wordlist.txt' } },
            { name: 'Padrão Empresa (NomeAno!)', vars: { min_len: '0', max_len: '0', charset: '', pattern: '@@%%^^', output: '/tmp/empresa_wordlist.txt' } }
        ]
    },
    cewl: {
        name: 'CeWL', command: 'cewl', category: 'Cracking', installCmd: 'sudo apt install -y cewl',
        description: 'Custom Word List generator. Extrai palavras de sites para criar wordlists direcionadas.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, default: 'http://example.com', description: 'URL do site para extrair palavras.' },
            { id: 'depth', type: 'text', label: 'Profundidade de Crawling', flag: '-d', default: '2', description: 'Níveis de links a seguir.' },
            { id: 'min_length', type: 'text', label: 'Tamanho Mínimo da Palavra', flag: '-m', default: '5', description: 'Ignora palavras menores que este tamanho.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-w', default: '/tmp/cewl_wordlist.txt', description: 'Arquivo para salvar a wordlist.' },
            { id: 'email', type: 'boolean', label: 'Incluir Emails', flag: '-e', default: false, description: 'Extrai também endereços de email.' }
        ],
        presets: [
            { name: 'Extrair Palavras (Profundidade 2)', vars: { url: 'http://example.com', depth: '2', min_length: '5', output: '/tmp/wordlist.txt', email: false } },
            { name: 'Extrair Palavras + Emails', vars: { url: 'http://example.com', depth: '1', min_length: '6', output: '/tmp/wordlist_emails.txt', email: true } }
        ]
    },

    // ============================================================
    // 🕵️ POST-EXPLOIT & AD (Ambiente Windows/Active Directory)
    // ============================================================
    bloodhound: {
        name: 'BloodHound (Neo4j)', command: 'bloodhound', category: 'Post-Exploit', installCmd: 'sudo apt install -y bloodhound',
        description: 'Mapeador de relações de confiança e caminhos de ataque em Active Directory.',
        fields: [
            { id: 'neo4j_user', type: 'text', label: 'Usuário Neo4j', default: 'neo4j', description: 'Usuário do banco Neo4j.' },
            { id: 'neo4j_pass', type: 'text', label: 'Senha Neo4j', default: 'bloodhound', description: 'Senha do banco Neo4j.' }
        ],
        presets: [
            { name: 'Iniciar BloodHound', vars: { neo4j_user: 'neo4j', neo4j_pass: 'bloodhound' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'bloodhound', args: [] };
        }
    },
    responder: {
        name: 'Responder', command: 'responder', category: 'Post-Exploit', installCmd: 'sudo apt install -y responder',
        description: 'Envenenador de LLMNR/NBT-NS/MDNS para captura de hashes NTLMv2 em redes Windows.',
        fields: [
            { id: 'interface', type: 'text', label: 'Interface de Rede', flag: '-I', default: 'eth0', description: 'Interface de rede para escutar (ex: eth0, wlan0).' },
            { id: 'analyze', type: 'boolean', label: 'Modo Análise (Passivo)', flag: '-A', default: false, description: 'Apenas analisa o tráfego sem envenenar.' },
            { id: 'wpad', type: 'boolean', label: 'Ativar Servidor WPAD', flag: '-w', default: true, description: 'Habilita servidor WPAD falso para capturar hashes HTTP.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-v', default: true }
        ],
        presets: [
            { name: 'Envenenamento Padrão (LLMNR+NBT+WPAD)', vars: { interface: 'eth0', analyze: false, wpad: true, verbose: true } },
            { name: 'Modo Análise Passiva', vars: { interface: 'eth0', analyze: true, wpad: false, verbose: true } }
        ]
    },
    enum4linux: {
        name: 'Enum4linux', command: 'enum4linux', category: 'Post-Exploit', installCmd: 'sudo apt install -y enum4linux',
        description: 'Enumeração de informações SMB em hosts Windows/Linux. Usuários, grupos, shares e políticas.',
        fields: [
            { id: 'target', type: 'text', label: 'IP Alvo', required: true, default: '192.168.1.10', description: 'IP do servidor SMB.' },
            { id: 'verbose', type: 'boolean', label: 'Modo Verboso', flag: '-v', default: true, description: 'Exibe detalhes de cada consulta.' },
            { id: 'all', type: 'boolean', label: 'Enumeração Completa (-a)', flag: '-a', default: true, description: 'Executa TODOS os testes de enumeração.' }
        ],
        presets: [
            { name: 'Enumeração Completa', vars: { target: '192.168.1.10', verbose: true, all: true } },
            { name: 'Enumeração de Usuários', vars: { target: '192.168.1.10', verbose: true, all: false } }
        ]
    },
    smbmap: {
        name: 'Smbmap', command: 'smbmap', category: 'Post-Exploit', installCmd: 'sudo apt install -y smbmap',
        description: 'Enumeração de compartilhamentos SMB com verificação de permissões de leitura/escrita.',
        fields: [
            { id: 'host', type: 'text', label: 'Host Alvo', required: true, flag: '-H', default: '192.168.1.10', description: 'IP do servidor SMB.' },
            { id: 'user', type: 'text', label: 'Usuário', flag: '-u', default: 'Administrator' },
            { id: 'password', type: 'text', label: 'Senha', flag: '-p' },
            { id: 'recursive', type: 'boolean', label: 'Listagem Recursiva', flag: '-R', default: false, description: 'Lista recursivamente todos os arquivos dos compartilhamentos acessíveis.' }
        ],
        presets: [
            { name: 'Verificar Compartilhamentos', vars: { host: '192.168.1.10', user: 'Administrator', password: '', recursive: false } },
            { name: 'Listagem Recursiva', vars: { host: '192.168.1.10', user: 'Administrator', password: 'P@ssw0rd', recursive: true } }
        ]
    },
    linpeas: {
        name: 'LinPEAS', command: 'linpeas.sh', category: 'Post-Exploit', installCmd: 'wget https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh -O /opt/linpeas.sh && chmod +x /opt/linpeas.sh',
        description: 'Enumerador de escalação de privilégios Linux. Analisa 100+ vetores de ataque.',
        fields: [
            { id: 'output', type: 'text', label: 'Arquivo de Saída', default: '/tmp/linpeas_output.txt', description: 'Arquivo para salvar o relatório de enumeração.' },
            { id: 'thorough', type: 'boolean', label: 'Modo Completo (Lento)', default: false, description: 'Executa verificações adicionais mais demoradas.' },
            { id: 'network', type: 'boolean', label: 'Incluir Scan de Rede', default: false, description: 'Verifica portas abertas e conexões de rede.' }
        ],
        presets: [
            { name: 'Enumeração Rápida', vars: { output: '/tmp/linpeas.txt', thorough: false, network: false } },
            { name: 'Enumeração Completa', vars: { output: '/tmp/linpeas_completo.txt', thorough: true, network: true } }
        ],
        buildCmd: (f) => {
            const args = ['-a'];
            if (f.thorough) args.push('-t');
            if (f.network) args.push('-n');
            return { cmd: '/opt/linpeas.sh', args: [...args, '>', f.output || '/tmp/linpeas.txt', '2>&1'] };
        }
    },
    winpeas: {
        name: 'WinPEAS', command: 'winpeas.exe', category: 'Post-Exploit', installCmd: 'wget https://github.com/carlospolop/PEASS-ng/releases/latest/download/winPEASx64.exe -O /opt/winpeas.exe',
        description: 'Enumerador de escalação de privilégios Windows. Análise completa do sistema.',
        fields: [
            { id: 'output', type: 'text', label: 'Arquivo de Saída', default: '/tmp/winpeas_output.txt', description: 'Caminho no alvo Windows para salvar o relatório.' },
            { id: 'quiet', type: 'boolean', label: 'Modo Silencioso', default: false, description: 'Não exibe banner e cores.' },
            { id: 'systeminfo', type: 'boolean', label: 'Incluir System Info', default: true, description: 'Coleta informações do sistema Windows.' }
        ],
        presets: [
            { name: 'Enumeração Rápida', vars: { output: 'C:\\Users\\Public\\winpeas.txt', quiet: true, systeminfo: true } }
        ],
        buildCmd: (f) => {
            const args = [];
            if (f.quiet) args.push('-q');
            if (f.systeminfo) args.push('-s');
            return { cmd: '/opt/winpeas.exe', args: [...args, '>', f.output || 'C:\\Users\\Public\\winpeas.txt'] };
        }
    },
    mimikatz: {
        name: 'Mimikatz', command: 'mimikatz', category: 'Post-Exploit', installCmd: 'echo "Mimikatz deve ser baixado manualmente do repositório oficial"',
        description: 'Extrator de credenciais do Windows. Senhas em texto plano, hashes NTLM, tickets Kerberos.',
        fields: [
            { id: 'command', type: 'select', label: 'Comando', default: 'sekurlsa::logonpasswords', options: ['sekurlsa::logonpasswords', 'sekurlsa::ekeys', 'lsadump::sam', 'lsadump::secrets', 'lsadump::cache', 'lsadump::lsa /patch', 'privilege::debug'], description: 'Módulo do Mimikatz a executar.' }
        ],
        presets: [
            { name: 'Dump de Senhas (LogonPasswords)', vars: { command: 'sekurlsa::logonpasswords' } },
            { name: 'Dump SAM Database', vars: { command: 'lsadump::sam' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'echo', args: [`${f.command} | mimikatz`] };
        }
    },

    // ============================================================
    // ☁️ CLOUD SECURITY (AWS, Azure, GCP)
    // ============================================================
    cloudbrute: {
        name: 'CloudBrute', command: 'cloudbrute', category: 'Cloud Security', installCmd: 'git clone https://github.com/0xsha/CloudBrute && cd CloudBrute && go build',
        description: 'Brute-force de buckets, apps e storage em clouds (AWS, Azure, GCP, DigitalOcean).',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio/Nome da Empresa', required: true, flag: '-d', default: 'example.com', description: 'Nome da empresa para gerar permutations.' },
            { id: 'keyword', type: 'text', label: 'Palavra-chave', required: true, flag: '-k', default: 'example', description: 'Palavra-chave base para brute-force.' },
            { id: 'providers', type: 'select', label: 'Provedores Cloud', flag: '-p', default: 'all', options: ['AWS', 'Azure', 'GCP', 'DigitalOcean', 'all'], description: 'Cloud a ser atacada.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-o', default: '/tmp/cloudbrute.txt' }
        ],
        presets: [
            { name: 'Brute-Force Todas as Clouds', vars: { domain: 'example.com', keyword: 'example', providers: 'all', output: '/tmp/cloudbrute.txt' } },
            { name: 'Focado AWS + GCP', vars: { domain: 'example.com', keyword: 'example', providers: 'AWS', output: '/tmp/aws_buckets.txt' } }
        ]
    },
    scoutsuite: {
        name: 'ScoutSuite', command: 'scout', category: 'Cloud Security', installCmd: 'pip install scoutsuite',
        description: 'Auditor de segurança multi-cloud (AWS, Azure, GCP). Gera relatórios HTML detalhados.',
        fields: [
            { id: 'provider', type: 'select', label: 'Provedor', required: true, flag: '', default: 'aws', options: ['aws', 'azure', 'gcp'], description: 'Cloud a ser auditada.' },
            { id: 'report_dir', type: 'text', label: 'Diretório do Relatório', flag: '--report-dir', default: '/tmp/scout_report', description: 'Pasta onde o relatório HTML será salvo.' }
        ],
        presets: [
            { name: 'Auditar AWS', vars: { provider: 'aws', report_dir: '/tmp/scout_aws' } },
            { name: 'Auditar GCP', vars: { provider: 'gcp', report_dir: '/tmp/scout_gcp' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'scout', args: [f.provider, '--report-dir', f.report_dir || '/tmp/scout_report'] };
        }
    },
    trufflehog: {
        name: 'TruffleHog', command: 'trufflehog', category: 'Cloud Security', installCmd: 'sudo apt install -y trufflehog',
        description: 'Varre repositórios Git em busca de segredos vazados (API keys, senhas, tokens).',
        fields: [
            { id: 'url', type: 'text', label: 'URL do Repositório Git', required: true, default: 'https://github.com/user/repo', description: 'URL do repositório a ser escaneado.' },
            { id: 'json', type: 'boolean', label: 'Saída em JSON', flag: '--json', default: true, description: 'Formato JSON para parse automatizado.' },
            { id: 'regex', type: 'boolean', label: 'Usar Regex Avançado', flag: '--regex', default: true, description: 'Habilita detecção com expressões regulares customizadas.' }
        ],
        presets: [
            { name: 'Scan de Repositório', vars: { url: 'https://github.com/user/repo.git', json: true, regex: true } }
        ]
    },
    semgrep: {
        name: 'Semgrep', command: 'semgrep', category: 'Cloud Security', installCmd: 'pip install semgrep',
        description: 'Scanner de segurança SAST (Static Analysis). Encontra vulnerabilidades no código-fonte.',
        fields: [
            { id: 'path', type: 'text', label: 'Diretório do Código', required: true, default: '/tmp/project', description: 'Caminho do código a ser analisado.' },
            { id: 'config', type: 'select', label: 'Conjunto de Regras', flag: '--config', default: 'p/owasp-top-ten', options: ['p/owasp-top-ten', 'p/security-audit', 'p/secrets', 'p/r2c'], description: 'Regras de análise.' },
            { id: 'json', type: 'boolean', label: 'Saída JSON', flag: '--json', default: true }
        ],
        presets: [
            { name: 'OWASP Top 10', vars: { path: '/tmp/project', config: 'p/owasp-top-ten', json: true } },
            { name: 'Auditoria de Segurança Completa', vars: { path: '/tmp/project', config: 'p/security-audit', json: true } }
        ]
    },

    // ============================================================
    // 📡 WIRELESS & REDES (Wi-Fi, Bluetooth, Radio)
    // ============================================================
    aircrack: {
        name: 'Aircrack-ng', command: 'aircrack-ng', category: 'Wireless', installCmd: 'sudo apt install -y aircrack-ng',
        description: 'Suíte completa para auditoria de redes Wi-Fi (WEP/WPA/WPA2).',
        fields: [
            { id: 'capture_file', type: 'text', label: 'Arquivo de Captura (.cap)', required: true, default: '/tmp/captura.cap', description: 'Arquivo com handshake WPA ou IVs WEP capturados.' },
            { id: 'wordlist', type: 'text', label: 'Wordlist', default: '/usr/share/wordlists/rockyou.txt', description: 'Wordlist para quebrar a senha do Wi-Fi.' }
        ],
        presets: [
            { name: 'Rockyou WPA', vars: { capture_file: '/tmp/captura.cap', wordlist: '/usr/share/wordlists/rockyou.txt' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'aircrack-ng', args: ['-w', f.wordlist || '/usr/share/wordlists/rockyou.txt', f.capture_file] };
        }
    },
    airodump: {
        name: 'Airodump-ng', command: 'airodump-ng', category: 'Wireless', installCmd: 'sudo apt install -y aircrack-ng',
        description: 'Captura de pacotes e redes Wi-Fi. Scanner de redes e clientes em tempo real.',
        fields: [
            { id: 'interface', type: 'text', label: 'Interface Monitor', required: true, default: 'wlan0mon', description: 'Interface em modo monitor (ex: wlan0mon).' },
            { id: 'channel', type: 'text', label: 'Canal (opcional)', flag: '-c', default: '', description: 'Fixa em um canal específico. Deixe vazio para saltar canais.' },
            { id: 'band', type: 'select', label: 'Banda', flag: '--band', default: 'abg', options: ['a (5GHz)', 'bg (2.4GHz)', 'abg (Ambas)'], description: 'Banda de frequência a monitorar.' },
            { id: 'write', type: 'text', label: 'Arquivo de Saída', flag: '-w', default: '/tmp/captura', description: 'Prefixo do arquivo para salvar a captura.' }
        ],
        presets: [
            { name: 'Scan 2.4GHz + 5GHz', vars: { interface: 'wlan0mon', channel: '', band: 'abg (Ambas)', write: '/tmp/scan' } },
            { name: 'Capturar em Canal Específico', vars: { interface: 'wlan0mon', channel: '6', band: 'bg (2.4GHz)', write: '/tmp/canal6' } }
        ],
        buildCmd: (f) => {
            const args = [f.interface];
            if (f.channel) { args.push('-c', f.channel); }
            if (f.write) { args.push('-w', f.write); }
            if (f.band) { const b = f.band.split(' ')[0]; if (b) args.push('--band', b); }
            return { cmd: 'airodump-ng', args };
        }
    },
    bettercap: {
        name: 'Bettercap', command: 'bettercap', category: 'Wireless', installCmd: 'sudo apt install -y bettercap',
        description: 'Framework completo para ataque Man-in-the-Middle. ARP Spoof, DNS Spoof, HTTP/HTTPS proxy.',
        fields: [
            { id: 'interface', type: 'text', label: 'Interface de Rede', flag: '-I', default: 'eth0', description: 'Interface de rede para o ataque.' },
            { id: 'module', type: 'select', label: 'Módulo Principal', default: 'arp.spoof', options: ['arp.spoof', 'net.probe', 'dns.spoof', 'http.proxy', 'https.proxy', 'wifi'], description: 'Módulo a ativar no Bettercap.' },
            { id: 'target', type: 'text', label: 'Alvo (IP)', default: '192.168.1.0/24', description: 'IP ou range de alvos.' }
        ],
        presets: [
            { name: 'ARP Spoof + Sniffing', vars: { interface: 'eth0', module: 'arp.spoof', target: '192.168.1.0/24' } },
            { name: 'Network Probe (Descoberta)', vars: { interface: 'eth0', module: 'net.probe', target: '192.168.1.0/24' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'bettercap', args: ['-I', f.interface, '-eval', `set ${f.module}.target ${f.target}; ${f.module} on; sleep 10; net.show`] };
        }
    },

    // ============================================================
    // 🔬 FORENSICS & ANÁLISE (Análise Forense de Arquivos e Memória)
    // ============================================================
    exiftool: {
        name: 'ExifTool', command: 'exiftool', category: 'Forensics', installCmd: 'sudo apt install -y exiftool',
        description: 'Leitor e manipulador de metadados. Suporta 200+ formatos de arquivo (JPEG, PDF, DOCX, etc.).',
        fields: [
            { id: 'file', type: 'text', label: 'Arquivo', required: true, default: '/tmp/imagem.jpg', description: 'Caminho do arquivo para ler metadados.' },
            { id: 'all', type: 'boolean', label: 'Mostrar Todos os Metadados', flag: '-a', default: true },
            { id: 'json', type: 'boolean', label: 'Saída em JSON', flag: '-j', default: false }
        ],
        presets: [
            { name: 'Ler Metadados', vars: { file: '/tmp/imagem.jpg', all: true, json: false } },
            { name: 'Ler Metadados (JSON)', vars: { file: '/tmp/documento.pdf', all: true, json: true } }
        ]
    },
    binwalk: {
        name: 'Binwalk', command: 'binwalk', category: 'Forensics', installCmd: 'sudo apt install -y binwalk',
        description: 'Analisador de firmware. Extrai sistemas de arquivos, kernels e dados ocultos em binários.',
        fields: [
            { id: 'file', type: 'text', label: 'Arquivo de Firmware', required: true, default: '/tmp/firmware.bin', description: 'Arquivo binário de firmware para análise.' },
            { id: 'extract', type: 'boolean', label: 'Extrair Arquivos', flag: '-e', default: true, description: 'Extrai automaticamente os sistemas de arquivos encontrados.' },
            { id: 'entropy', type: 'boolean', label: 'Análise de Entropia', flag: '-E', default: false, description: 'Gera gráfico de entropia para identificar seções comprimidas/criptografadas.' },
            { id: 'signature', type: 'boolean', label: 'Scan de Assinaturas', flag: '-B', default: true, description: 'Varre o arquivo em busca de assinaturas mágicas conhecidas.' }
        ],
        presets: [
            { name: 'Análise + Extração', vars: { file: '/tmp/firmware.bin', extract: true, entropy: false, signature: true } },
            { name: 'Análise Completa (com Entropia)', vars: { file: '/tmp/firmware.bin', extract: true, entropy: true, signature: true } }
        ]
    },
    volatility: {
        name: 'Volatility 3', command: 'vol', category: 'Forensics', installCmd: 'sudo apt install -y volatility3',
        description: 'Framework de análise de memória RAM. Extrai processos, conexões, registros e malwares.',
        fields: [
            { id: 'memory_dump', type: 'text', label: 'Arquivo de Dump de Memória', required: true, flag: '-f', default: '/tmp/memory.dmp', description: 'Dump de memória RAM para análise.' },
            { id: 'plugin', type: 'select', label: 'Plugin', required: true, default: 'windows.pslist', options: ['windows.pslist (Lista Processos)', 'windows.netscan (Conexões Rede)', 'windows.cmdline (Linha de Comando)', 'windows.dlllist (DLLs Carregadas)', 'windows.malfind (Detectar Malware)', 'linux.pslist', 'mac.pslist'], description: 'Plugin de análise a executar.' }
        ],
        presets: [
            { name: 'Listar Processos Windows', vars: { memory_dump: '/tmp/memory.dmp', plugin: 'windows.pslist (Lista Processos)' } },
            { name: 'Detectar Malware', vars: { memory_dump: '/tmp/memory.dmp', plugin: 'windows.malfind (Detectar Malware)' } },
            { name: 'Conexões de Rede', vars: { memory_dump: '/tmp/memory.dmp', plugin: 'windows.netscan (Conexões Rede)' } }
        ],
        buildCmd: (f) => {
            const pluginMap = {
                'windows.pslist (Lista Processos)': 'windows.pslist',
                'windows.netscan (Conexões Rede)': 'windows.netscan',
                'windows.cmdline (Linha de Comando)': 'windows.cmdline',
                'windows.dlllist (DLLs Carregadas)': 'windows.dlllist',
                'windows.malfind (Detectar Malware)': 'windows.malfind',
                'linux.pslist': 'linux.pslist',
                'mac.pslist': 'mac.pslist'
            };
            const plugin = pluginMap[f.plugin] || f.plugin;
            return { cmd: 'vol', args: ['-f', f.memory_dump, plugin] };
        }
    },
    steghide: {
        name: 'Steghide', command: 'steghide', category: 'Forensics', installCmd: 'sudo apt install -y steghide',
        description: 'Esteganografia. Extrai e oculta dados em imagens e arquivos de áudio.',
        fields: [
            { id: 'file', type: 'text', label: 'Arquivo Portador', required: true, flag: '--extract', default: '/tmp/imagem.jpg', description: 'Arquivo que contém dados ocultos.' },
            { id: 'passphrase', type: 'text', label: 'Senha', flag: '-p', default: '', description: 'Senha para extrair os dados ocultos.' },
            { id: 'output', type: 'text', label: 'Arquivo de Saída', flag: '-f', default: '/tmp/dados_ocultos.txt', description: 'Arquivo para salvar os dados extraídos.' }
        ],
        presets: [
            { name: 'Extrair Dados Ocultos', vars: { file: '/tmp/imagem.jpg', passphrase: '', output: '/tmp/extraido.txt' } }
        ],
        buildCmd: (f) => {
            const args = ['extract', '-sf', f.file, '-xf', f.output];
            if (f.passphrase) args.push('-p', f.passphrase);
            return { cmd: 'steghide', args };
        }
    },
    foremost: {
        name: 'Foremost', command: 'foremost', category: 'Forensics', installCmd: 'sudo apt install -y foremost',
        description: 'Recuperação de arquivos deletados. Escava arquivos baseado em headers e footers (file carving).',
        fields: [
            { id: 'image', type: 'text', label: 'Arquivo de Imagem (dd/iso/img)', required: true, flag: '-i', default: '/tmp/disk_image.dd', description: 'Imagem de disco para recuperação.' },
            { id: 'output_dir', type: 'text', label: 'Diretório de Saída', flag: '-o', default: '/tmp/foremost_output', description: 'Pasta onde os arquivos recuperados serão salvos.' },
            { id: 'type', type: 'text', label: 'Tipos de Arquivo (opcional)', flag: '-t', default: 'all', description: 'Tipos a recuperar: jpg,png,pdf,doc,zip,tar,gz,all.' }
        ],
        presets: [
            { name: 'Recuperar Todos os Tipos', vars: { image: '/tmp/disk_image.dd', output_dir: '/tmp/foremost_output', type: 'all' } },
            { name: 'Recuperar Apenas Imagens', vars: { image: '/tmp/disk_image.dd', output_dir: '/tmp/fotos', type: 'jpg,png,gif' } }
        ]
    },
    strings: {
        name: 'Strings (Análise de Binários)', command: 'strings', category: 'Forensics', installCmd: 'Pré-instalado no Kali',
        description: 'Extrai strings legíveis de arquivos binários. Essencial para análise rápida de malwares e firmwares.',
        fields: [
            { id: 'file', type: 'text', label: 'Arquivo', required: true, default: '/tmp/suspeito.exe', description: 'Arquivo binário para extrair strings.' },
            { id: 'min_len', type: 'text', label: 'Tamanho Mínimo da String', flag: '-n', default: '6', description: 'Exibe apenas strings com este tamanho ou mais.' },
            { id: 'encoding', type: 'select', label: 'Encoding', flag: '-e', default: 'l', options: ['l (ASCII 8-bit)', 'b (16-bit big-endian)', 'L (16-bit little-endian)'], description: 'Codificação das strings.' }
        ],
        presets: [
            { name: 'Extrair Strings ASCII', vars: { file: '/tmp/suspeito.exe', min_len: '6', encoding: 'l (ASCII 8-bit)' } },
            { name: 'Extrair Strings Unicode', vars: { file: '/tmp/malware.dll', min_len: '4', encoding: 'L (16-bit little-endian)' } }
        ]
    },

    // ============================================================
    // 🌐 ELITE GLOBAL RED TEAM TOOLS (China, Rússia, EUA, Global)
    // ============================================================
    yakit: {
        name: 'Yakit / YSO (China)', command: 'yakit', category: 'Global RedTeam (CN)', installCmd: 'curl -sSL https://yaklang.com/install.sh | bash',
        description: 'Plataforma chinesa de análise de vulnerabilidade web, fuzzing tático e tráfego interceptado.',
        fields: [
            { id: 'target', type: 'text', label: 'URL / Alvo', required: true, flag: '--target', default: 'http://example.com', description: 'URL ou IP para análise via Yakit engine.' },
            { id: 'mode', type: 'select', label: 'Modo de Inspeção', default: 'fuzz', options: ['fuzz', 'mitm', 'scan'], description: 'Selecione o modo de análise tática.' }
        ],
        presets: [
            { name: 'Fuzzing de Requisições (Yaklang)', vars: { target: 'http://example.com', mode: 'fuzz' } }
        ]
    },
    afrog: {
        name: 'Afrog POC Engine (China)', command: 'afrog', category: 'Global RedTeam (CN)', installCmd: 'go install -v github.com/zan8in/afrog/v2/cmd/afrog@latest',
        description: 'Ferramenta de varredura POC chinesa ultrarrápida para detecção de vulnerabilidades e exploits dia-0.',
        fields: [
            { id: 'target', type: 'text', label: 'Alvo (URL ou Arquivo)', required: true, flag: '-t', default: 'http://example.com', description: 'Alvo único ou lista em arquivo.' },
            { id: 'output', type: 'text', label: 'Arquivo HTML de Saída', flag: '-o', default: '/tmp/afrog_report.html' }
        ],
        presets: [
            { name: 'Scan Rápido de POCs', vars: { target: 'http://example.com', output: '/tmp/afrog.html' } }
        ]
    },
    xray: {
        name: 'Xray Community (China)', command: 'xray', category: 'Global RedTeam (CN)', installCmd: 'wget https://github.com/chaitin/xray/releases/download/1.9.11/xray_linux_amd64.zip -O /tmp/xray.zip && unzip /tmp/xray.zip -d /opt/',
        description: 'Scanner de segurança web da Chaitin Tech (China) com mecanismo de análise passiva e ativada.',
        fields: [
            { id: 'url', type: 'text', label: 'URL Alvo', required: true, flag: '--url', default: 'http://example.com', description: 'URL para varredura de vulnerabilidades.' },
            { id: 'html_output', type: 'text', label: 'Relatório HTML', flag: '--html-output', default: '/tmp/xray.html' }
        ],
        presets: [
            { name: 'Scan Web Ativo Xray', vars: { url: 'http://example.com', html_output: '/tmp/xray.html' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'xray', args: ['webscan', '--url', f.url, '--html-output', f.html_output || '/tmp/xray.html'] };
        }
    },
    oneforall: {
        name: 'OneForAll (China)', command: 'oneforall', category: 'Global RedTeam (CN)', installCmd: 'git clone https://github.com/shmilylty/OneForAll.git /opt/oneforall && cd /opt/oneforall && pip install -r requirements.txt',
        description: 'Ferramenta de ponta chinesa para enumeração completa e massiva de subdomínios.',
        fields: [
            { id: 'target', type: 'text', label: 'Domínio Alvo', required: true, flag: '--target', default: 'example.com', description: 'Domínio raiz para coleta agressiva.' }
        ],
        presets: [
            { name: 'Enumeração Massiva OneForAll', vars: { target: 'example.com' } }
        ],
        buildCmd: (f) => {
            return { cmd: 'python3', args: ['/opt/oneforall/oneforall.py', '--target', f.target, 'run'] };
        }
    },
    havoc: {
        name: 'Havoc C2 Framework (USA/EU)', command: 'havoc', category: 'Global RedTeam (US)', installCmd: 'git clone https://github.com/HavocFramework/Havoc.git /opt/havoc && cd /opt/havoc && make',
        description: 'Framework de Command & Control (C2) moderno de nível governamental com suporte a agentes Demon.',
        fields: [
            { id: 'profile', type: 'text', label: 'Perfil de Configuração (yaotl)', default: '/opt/havoc/profiles/havoc.yaotl', description: 'Caminho do arquivo de configuração do C2 Server.' }
        ],
        presets: [
            { name: 'Iniciar Servidor Havoc C2', vars: { profile: '/opt/havoc/profiles/havoc.yaotl' } }
        ],
        buildCmd: (f) => {
            return { cmd: '/opt/havoc/havoc', args: ['server', '--profile', f.profile] };
        }
    },
    donut: {
        name: 'Donut Shellcode Generator (USA)', command: 'donut', category: 'Global RedTeam (US)', installCmd: 'sudo apt install -y donut',
        description: 'Gerador de shellcode de posição independente a partir de binários VBScript, JScript, EXE ou DLL (.NET/Unmanaged).',
        fields: [
            { id: 'input_file', type: 'text', label: 'Arquivo Binário de Entrada (.exe/.dll)', required: true, flag: '-i', default: '/tmp/payload.exe' },
            { id: 'output', type: 'text', label: 'Arquivo de Shellcode (.bin)', flag: '-o', default: '/tmp/payload.bin' }
        ],
        presets: [
            { name: 'Gerar Shellcode Donut', vars: { input_file: '/tmp/payload.exe', output: '/tmp/payload.bin' } }
        ]
    },
    bloodhound_python: {
        name: 'BloodHound Python Ingestor (USA)', command: 'bloodhound-python', category: 'Global RedTeam (US)', installCmd: 'pip install bloodhound',
        description: 'Ingestor Python oficial para coletar dados do Active Directory sem dependências do .NET.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio AD', required: true, flag: '-d', default: 'corp.local' },
            { id: 'user', type: 'text', label: 'Usuário AD', required: true, flag: '-u', default: 'user' },
            { id: 'password', type: 'text', label: 'Senha AD', flag: '-p', default: 'pass' },
            { id: 'nameserver', type: 'text', label: 'Domain Controller IP (DNS)', flag: '-ns', default: '192.168.1.1' },
            { id: 'collection', type: 'select', label: 'Método de Coleta', flag: '-c', default: 'All', options: ['All', 'Default', 'DCOnly', 'Group'] }
        ],
        presets: [
            { name: 'Coleta Completa de AD', vars: { domain: 'corp.local', user: 'user', password: 'pass', nameserver: '192.168.1.1', collection: 'All' } }
        ]
    },
    ligolo_ng: {
        name: 'Ligolo-ng (Pivot Transparente)', command: 'ligolo-ng', category: 'Global RedTeam (Global)', installCmd: 'sudo apt install -y ligolo-ng',
        description: 'Ferramenta avançada de pivoting de rede usando interfaces TUN/TAP falsas. Rápida e invisível.',
        fields: [
            { id: 'mode', type: 'select', label: 'Modo de Operação', default: 'proxy', options: ['proxy', 'agent'] },
            { id: 'listen', type: 'text', label: 'Endereço de Escuta', flag: '-laddr', default: '0.0.0.0:11601' }
        ],
        presets: [
            { name: 'Iniciar Servidor Proxy Ligolo', vars: { mode: 'proxy', listen: '0.0.0.0:11601' } }
        ]
    },
    kube_hunter: {
        name: 'Kube-Hunter (Kubernetes Security)', command: 'kube-hunter', category: 'Global RedTeam (Global)', installCmd: 'pip install kube-hunter',
        description: 'Caçador de vulnerabilidades em clusters Kubernetes (K8s). Varre nós e serviços expostos.',
        fields: [
            { id: 'remote', type: 'text', label: 'IP / Host do Cluster K8s', flag: '--remote', default: '192.168.1.50' },
            { id: 'active', type: 'boolean', label: 'Modo Ativo (Testa Exploits)', flag: '--active', default: false }
        ],
        presets: [
            { name: 'Scan Passivo K8s Cluster', vars: { remote: '192.168.1.50', active: false } }
        ]
    },
    chaos: {
        name: 'ProjectDiscovery Chaos (Global)', command: 'chaos', category: 'Global RedTeam (Global)', installCmd: 'go install -v github.com/projectdiscovery/chaos-client/cmd/chaos@latest',
        description: 'Cliente para consultar o banco de dados da ProjectDiscovery contendo subdomínios indexados em tempo real.',
        fields: [
            { id: 'domain', type: 'text', label: 'Domínio', required: true, flag: '-d', default: 'example.com' },
            { id: 'key', type: 'text', label: 'API Key Chaos', flag: '-key', default: '' }
        ],
        presets: [
            { name: 'Consultar Subdomínios na Nuvem', vars: { domain: 'example.com', key: '' } }
        ]
    }
};

module.exports = TOOL_SCHEMAS;

