// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    // --- RECON & OSINT ---
    nmap: {
        name: 'Nmap',
        command: 'nmap',
        category: 'Reconhecimento',
        description: 'O melhor scanner de portas e rede da atualidade.',
        installCmd: 'sudo apt install -y nmap',
        fields: [
            { 
                id: 'target', 
                type: 'text', 
                label: 'Alvo (IP ou Domínio)', 
                required: true, 
                default: 'scanme.nmap.org',
                placeholder: 'ex: scanme.nmap.org ou 192.168.0.1',
                description: 'O endereço IP, site ou faixa de rede que você quer escanear.'
            },
            { 
                id: 'ports', 
                type: 'text', 
                label: 'Portas', 
                flag: '-p',
                placeholder: 'ex: 80,443 ou 1-1000',
                description: 'Especifique portas específicas. Deixe vazio para escanear as 1000 portas mais comuns.'
            },
            { 
                id: 'syn_scan', 
                type: 'boolean', 
                label: 'SYN Scan (Stealth)', 
                flag: '-sS',
                default: true,
                description: 'Escaneio silencioso e rápido (-sS). Não completa a conexão TCP. Requer privilégios de root.'
            },
            { 
                id: 'service_version', 
                type: 'boolean', 
                label: 'Detectar Versão do Serviço', 
                flag: '-sV',
                default: true,
                description: 'Tenta determinar a versão exata do software rodando na porta aberta (-sV).'
            },
            { 
                id: 'aggressive', 
                type: 'boolean', 
                label: 'Modo Agressivo', 
                flag: '-A',
                default: false,
                description: 'Ativa detecção de SO, traceroute e scripts padrão (-A). É barulhento e pode chamar atenção.'
            },
            { 
                id: 'timing', 
                type: 'select', 
                label: 'Velocidade do Scan', 
                flag: '-T',
                options: ['0 (Paranóico)', '1 (Descolado)', '2 (Educado)', '3 (Normal)', '4 (Agressivo)', '5 (Insano)'], 
                default: '3 (Normal)',
                description: 'Controla o quão rápido os pacotes são enviados. 5 é muito rápido mas pula firewalls. 0 é invisível mas demora horas.'
            }
        ],
        presets: [
            { name: 'Scan Rápido (Top 100)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: false, aggressive: false, timing: '4 (Agressivo)' } },
            { name: 'Agressivo (OS + Versão)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: true, aggressive: true, timing: '4 (Agressivo)' } },
            { name: 'Furtivo (Lento)', vars: { target: 'scanme.nmap.org', ports: '', syn_scan: true, service_version: false, aggressive: false, timing: '1 (Descolado)' } }
        ]
    },
    subfinder: {
        name: "Subfinder", command: "subfinder", category: "recon", installCmd: "sudo apt install subfinder",
        description: "Descoberta passiva de subdomínios (OSINT).",
        presets: [ { name: "Scan Rápido", vars: { domain: "example.com", silent: true, all: false } } ],
        fields: [
            { id: "domain", label: "Domínio Raiz", type: "text", required: true, flag: "-d", default: "example.com" },
            { id: "silent", label: "Modo Silencioso (Apenas resultados)", type: "boolean", flag: "-silent", default: true },
            { id: "all", label: "Usar todas as fontes (Lento)", type: "boolean", flag: "-all" }
        ]
    },
    httpx: {
        name: "Httpx", command: "httpx-toolkit", category: "recon", installCmd: "sudo apt install httpx-toolkit",
        description: "Validador HTTP em massa (Descobre hosts vivos).",
        presets: [ { name: "Validar Hosts", vars: { input_text: "http://localhost\nhttp://127.0.0.1", status: true, title: true, tech: true, follow: true } } ],
        fields: [
            { id: "input_text", label: "Lista de Hosts (1 por linha)", type: "textarea", required: true, flag: "-l", default: "http://localhost\nhttp://127.0.0.1" },
            { id: "status", label: "Mostrar Status Code", type: "boolean", flag: "-status-code", default: true },
            { id: "title", label: "Extrair Título da Página", type: "boolean", flag: "-title", default: true },
            { id: "tech", label: "Detectar Tecnologias", type: "boolean", flag: "-tech-detect", default: true },
            { id: "follow", label: "Seguir Redirects", type: "boolean", flag: "-follow" }
        ]
    },

    // --- WEB SCANNING ---
    gobuster: {
        name: "Gobuster", command: "gobuster", category: "web", installCmd: "sudo apt install gobuster",
        description: "Brute-force de diretórios e arquivos web.",
        presets: [ { name: "Scan Dir Padrão + php,html", vars: { mode: "dir", url: "http://localhost", wordlist: "/usr/share/wordlists/dirb/common.txt", x: "php,html,txt" } } ],
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", default: "dir", options: ["dir", "dns", "vhost"] },
            { id: "url", label: "URL", type: "text", required: true, flag: "-u", default: "http://localhost" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", default: "/usr/share/wordlists/dirb/common.txt" },
            { id: "x", label: "Extensões (ex: php,html)", type: "text", flag: "-x" },
            { id: "t", label: "Threads (Velocidade)", type: "text", flag: "-t", default: "50" }
        ]
    },
    nikto: {
        name: "Nikto", command: "nikto", category: "web", installCmd: "sudo apt install nikto",
        description: "Scanner de vulnerabilidades Web.",
        presets: [ { name: "Scan Padrão (Porta 80)", vars: { host: "127.0.0.1", port: "80", ssl: false, tuning: "x" } } ],
        fields: [
            { id: "host", label: "Host Alvo (sem http://)", type: "text", required: true, flag: "-h", default: "127.0.0.1" },
            { id: "port", label: "Porta", type: "text", flag: "-p", default: "80" },
            { id: "ssl", label: "Forçar SSL", type: "boolean", flag: "-ssl" },
            { id: "tuning", label: "Tuning (Tipos de teste)", type: "text", flag: "-Tuning", default: "x" }
        ]
    },
    sqlmap: {
        name: "SQLMap", command: "sqlmap", category: "web", installCmd: "sudo apt install sqlmap",
        description: "Injeção de SQL e auditoria de BD.",
        presets: [
            { name: "Testar URL e Enumerar DBs", vars: { url: "http://localhost/test.php?id=1", dbs: true, batch: true, os_shell: false } },
            { name: "Tentar OS Shell (RCE)", vars: { url: "http://localhost/test.php?id=1", dbs: false, batch: true, os_shell: true } }
        ],
        fields: [
            { id: "url", label: "URL (com parametro ?id=)", type: "text", required: true, flag: "-u", default: "http://localhost/test.php?id=1" },
            { id: "dbs", label: "Enumerar Bancos de Dados", type: "boolean", flag: "--dbs" },
            { id: "os_shell", label: "Tentar obter OS Shell (Crítico)", type: "boolean", flag: "--os-shell" },
            { id: "batch", label: "Modo Automático (Sem Perguntas)", type: "boolean", flag: "--batch", default: true },
            { id: "level", label: "Nível de Teste (1-5)", type: "select", flag: "--level", default: "1", options: ["1", "2", "3", "4", "5"] }
        ]
    },

    // --- EXPLOIT & CRACKING ---
    searchsploit: {
        name: "SearchSploit", command: "searchsploit", category: "exploit", installCmd: "sudo apt install exploitdb",
        description: "Busca local no banco de dados Exploit-DB.",
        presets: [ { name: "Busca Exata", vars: { query: "Apache 2.4", exact: true, json: false } } ],
        fields: [
            { id: "query", label: "Termo de Busca (ex: Apache 2.4)", type: "text", required: true, default: "Apache 2.4" },
            { id: "exact", label: "Busca Exata", type: "boolean", flag: "--exact" },
            { id: "json", label: "Retornar em JSON", type: "boolean", flag: "--json" }
        ]
    },
    hashcat: {
        name: "Hashcat", command: "hashcat", category: "cracking", installCmd: "sudo apt install hashcat",
        description: "Quebra de hashes com aceleração GPU/CPU.",
        presets: [ { name: "Ataque MD5 com Rockyou", vars: { mode: "0", hashfile: "/tmp/hash.txt", wordlist: "/usr/share/wordlists/rockyou.txt", force: false } } ],
        fields: [
            { id: "mode", label: "Tipo do Hash (0=MD5, 1000=NTLM, 1800=sha512crypt)", type: "text", required: true, flag: "-m", default: "0" },
            { id: "hashfile", label: "Arquivo de Hash", type: "text", required: true, default: "/tmp/hash.txt" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, default: "/usr/share/wordlists/rockyou.txt" },
            { id: "force", label: "Forçar uso de CPU (Sem GPU)", type: "boolean", flag: "--force" }
        ]
    },
    arjun: {
        name: "Arjun", command: "arjun", category: "web", installCmd: "sudo apt install arjun",
        description: "Descoberta de parâmetros HTTP ocultos.",
        presets: [ { name: "Scan Rápido GET", vars: { url: "http://localhost/page.php", method: "GET", threads: "8" } } ],
        fields: [
            { id: "url", label: "URL Alvo", type: "text", required: true, flag: "-u", default: "http://localhost/page.php" },
            { id: "method", label: "Método HTTP", type: "select", flag: "-m", default: "GET", options: ["GET", "POST", "JSON", "XML"] },
            { id: "threads", label: "Threads (Velocidade)", type: "text", flag: "-t", default: "4" }
        ]
    },
    metasploit: {
        name: "Metasploit", command: "msfconsole", category: "exploit", installCmd: "sudo apt install metasploit-framework",
        description: "Console do Metasploit Framework (Resource Script).",
        presets: [ { name: "Portscan TCP", vars: { resource_script: "use auxiliary/scanner/portscan/tcp\nset RHOSTS 127.0.0.1\nset PORTS 1-1000\nrun\nexit", quiet: true } } ],
        fields: [
            { id: "resource_script", label: "Resource Script (.rc)", type: "textarea", required: true, flag: "-r", default: "use auxiliary/scanner/portscan/tcp\nset RHOSTS 127.0.0.1\nset PORTS 1-1000\nrun\nexit" },
            { id: "quiet", label: "Modo Silencioso (-q)", type: "boolean", flag: "-q", default: true }
        ]
    },
    john: {
        name: 'John the Ripper',
        command: 'john',
        category: 'Cracking',
        description: 'Quebrador de hashes e senhas offline muito rápido.',
        installCmd: 'sudo apt install -y john',
        fields: [
            { 
                id: 'hash_file', 
                type: 'text', 
                label: 'Caminho do arquivo de hashes', 
                required: true, 
                placeholder: '/home/cloudos_users/hashes.txt',
                description: 'Arquivo de texto contendo os hashes que você quer quebrar.'
            },
            { 
                id: 'wordlist', 
                type: 'text', 
                label: 'Wordlist', 
                placeholder: '/usr/share/wordlists/rockyou.txt',
                description: 'Lista de palavras que o John vai usar para tentar quebrar o hash.'
            },
            { 
                id: 'format', 
                type: 'text', 
                label: 'Formato do Hash (opcional)', 
                placeholder: 'ex: Raw-MD5, SHA-512',
                description: 'Acelera o processo informando o tipo exato do hash.'
            }
        ],
        presets: [
            { name: 'Rockyou (MD5)', vars: { hash_file: '', wordlist: '/usr/share/wordlists/rockyou.txt', format: 'Raw-MD5' } },
            { name: 'Auto-Detect', vars: { hash_file: '', wordlist: '/usr/share/wordlists/rockyou.txt', format: '' } }
        ],
        buildCmd: (f) => {
            const args = [];
            if (f.format) args.push(`--format=${f.format}`);
            if (f.wordlist) args.push(`--wordlist=${f.wordlist}`);
            args.push(f.hash_file);
            return { cmd: 'john', args };
        }
    },
    aircrack: {
        name: 'Aircrack-ng',
        command: 'aircrack-ng',
        category: 'Wireless',
        description: 'Suíte para auditoria de redes Wi-Fi (quebra de WEP/WPA).',
        installCmd: 'sudo apt install -y aircrack-ng',
        fields: [
            { 
                id: 'capture_file', 
                type: 'text', 
                label: 'Arquivo de captura (.cap)', 
                required: true, 
                placeholder: '/home/cloudos_users/captura.cap',
                description: 'Arquivo de captura de pacotes da rede Wi-Fi alvo.'
            },
            { 
                id: 'wordlist', 
                type: 'text', 
                label: 'Wordlist', 
                placeholder: '/usr/share/wordlists/rockyou.txt',
                description: 'Wordlist para tentar descobrir a senha do Wi-Fi.'
            }
        ],
        presets: [
            { name: 'Rockyou WPA', vars: { capture_file: '', wordlist: '/usr/share/wordlists/rockyou.txt' } }
        ],
        buildCmd: (f) => {
            const args = ['-w', f.wordlist || '/usr/share/wordlists/rockyou.txt', f.capture_file];
            return { cmd: 'aircrack-ng', args };
        }
    }
};

module.exports = TOOL_SCHEMAS;
