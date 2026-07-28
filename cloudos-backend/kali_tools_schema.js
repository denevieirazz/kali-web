// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    // --- RECON & OSINT ---
    nmap: {
        name: "Nmap", command: "nmap", category: "recon", installCmd: "sudo apt install nmap",
        description: "Scanner de rede e portas ativo.",
        presets: [
            { name: "Scan Rápido (Top 100)", vars: { target: "scanme.nmap.org", p: "", sV: false, sS: true, T: "4", A: false } },
            { name: "Agressivo (OS + Versão)", vars: { target: "scanme.nmap.org", p: "", sV: true, sS: false, T: "4", A: true } }
        ],
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, default: "scanme.nmap.org" },
            { id: "p", label: "Portas (ex: 80,443 ou 1-1000)", type: "text", flag: "-p" },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS" },
            { id: "sV", label: "Detectar Versão do Serviço", type: "boolean", flag: "-sV" },
            { id: "A", label: "Agressivo (OS + Scripts + Trace)", type: "boolean", flag: "-A" },
            { id: "T", label: "Velocidade (0-5)", type: "select", flag: "-T", default: "4", options: ["0", "1", "2", "3", "4", "5"] }
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
        name: "Httpx", command: "httpx", category: "recon", installCmd: "sudo apt install httpx-toolkit",
        description: "Validador HTTP em massa (Descobre hosts vivos).",
        presets: [ { name: "Validar Hosts", vars: { input: "/tmp/hosts.txt", status: true, title: true, tech: true, follow: true } } ],
        fields: [
            { id: "input", label: "Arquivo com Hosts", type: "text", required: true, flag: "-l", default: "/tmp/hosts.txt" },
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
        presets: [ { name: "Scan Padrão (Porta 80)", vars: { host: "http://localhost", port: "80", ssl: false, tuning: "x" } } ],
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", default: "http://localhost" },
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
    }
};

module.exports = TOOL_SCHEMAS;
