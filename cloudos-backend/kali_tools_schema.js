// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    // --- RECON & OSINT ---
    nmap: {
        name: "Nmap", command: "nmap", installCmd: "sudo apt install nmap",
        description: "Scanner de rede e portas ativo.",
        presets: [
            { name: "Scan Rápido (Top 100)", vars: { target: "scanme.nmap.org", p: "", sV: false, sS: true, T: "4" } },
            { name: "Detectar Versões", vars: { target: "scanme.nmap.org", p: "", sV: true, sS: false, T: "3" } }
        ],
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, default: "scanme.nmap.org" },
            { id: "p", label: "Portas (ex: 80,443)", type: "text", flag: "-p" },
            { id: "sV", label: "Detectar Versão", type: "boolean", flag: "-sV" },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS" },
            { id: "T", label: "Velocidade (0-5)", type: "select", flag: "-T", default: "4", options: ["0", "1", "2", "3", "4", "5"] }
        ]
    },
    subfinder: {
        name: "Subfinder", command: "subfinder", installCmd: "sudo apt install subfinder",
        description: "Descoberta passiva de subdomínios (OSINT).",
        presets: [ { name: "Scan Rápido", vars: { domain: "example.com", silent: true } } ],
        fields: [
            { id: "domain", label: "Domínio Raiz", type: "text", required: true, flag: "-d", default: "example.com" },
            { id: "silent", label: "Modo Silencioso (Apenas resultados)", type: "boolean", flag: "-silent", default: true }
        ]
    },
    httpx: {
        name: "Httpx", command: "httpx", installCmd: "sudo apt install httpx-toolkit",
        description: "Validador HTTP em massa (Descobre hosts vivos).",
        presets: [ { name: "Validar Hosts", vars: { input: "/tmp/hosts.txt", status: true, title: true, tech: true } } ],
        fields: [
            { id: "input", label: "Arquivo com Hosts", type: "text", required: true, flag: "-l", default: "/tmp/hosts.txt", placeholder: "/tmp/subdomains.txt" },
            { id: "status", label: "Mostrar Status Code", type: "boolean", flag: "-status-code", default: true },
            { id: "title", label: "Extrair Título da Página", type: "boolean", flag: "-title", default: true },
            { id: "tech", label: "Detectar Tecnologias", type: "boolean", flag: "-tech-detect", default: true }
        ]
    },
    theharvester: {
        name: "theHarvester", command: "theHarvester", installCmd: "sudo apt install theharvester",
        description: "Coleta de e-mails, subdomínios e IPs públicos.",
        presets: [ { name: "Coleta Padrão", vars: { domain: "example.com", source: "all" } } ],
        fields: [
            { id: "domain", label: "Domínio", type: "text", required: true, flag: "-d", default: "example.com" },
            { id: "source", label: "Fonte de Busca", type: "text", required: true, flag: "-b", default: "all" }
        ]
    },

    // --- WEB VULN SCANNING ---
    gobuster: {
        name: "Gobuster", command: "gobuster", installCmd: "sudo apt install gobuster",
        description: "Brute-force de diretórios web.",
        presets: [ { name: "Scan Dir Padrão", vars: { mode: "dir", url: "http://localhost", wordlist: "/usr/share/wordlists/dirb/common.txt" } } ],
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", default: "dir", options: ["dir", "dns", "vhost"] },
            { id: "url", label: "URL", type: "text", required: true, flag: "-u", default: "http://localhost" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", default: "/usr/share/wordlists/dirb/common.txt" }
        ]
    },
    nikto: {
        name: "Nikto", command: "nikto", installCmd: "sudo apt install nikto",
        description: "Scanner de vulnerabilidades Web.",
        presets: [ { name: "Scan Padrão (Porta 80)", vars: { host: "http://localhost", port: "80", ssl: false } } ],
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", default: "http://localhost" },
            { id: "port", label: "Porta", type: "text", flag: "-p", default: "80" },
            { id: "ssl", label: "Forçar SSL", type: "boolean", flag: "-ssl" }
        ]
    },
    commix: {
        name: "Commix", command: "commix", installCmd: "sudo apt install commix",
        description: "Teste de Command Injection (Injeção no SO).",
        presets: [ { name: "Teste Automático", vars: { url: "http://localhost/cmd.php?cmd=test", batch: true } } ],
        fields: [
            { id: "url", label: "URL Alvo (com parâmetro)", type: "text", required: true, flag: "-u", default: "http://localhost/cmd.php?cmd=test" },
            { id: "batch", label: "Modo Automático", type: "boolean", flag: "--batch", default: true }
        ]
    },
    sqlmap: {
        name: "SQLMap", command: "sqlmap", installCmd: "sudo apt install sqlmap",
        description: "Injeção de SQL e auditoria de BD.",
        presets: [ { name: "Testar URL e Enumerar DBs", vars: { url: "http://localhost/pagina.php?id=1", dbs: true, batch: true } } ],
        fields: [
            { id: "url", label: "URL (com parametro ?id=)", type: "text", required: true, flag: "-u", default: "http://localhost/test.php?id=1" },
            { id: "dbs", label: "Enumerar Bancos", type: "boolean", flag: "--dbs" },
            { id: "batch", label: "Modo Automático", type: "boolean", flag: "--batch", default: true }
        ]
    },

    // --- EXPLOIT SEARCH ---
    searchsploit: {
        name: "SearchSploit", command: "searchsploit", installCmd: "sudo apt install exploitdb",
        description: "Busca local no banco de dados Exploit-DB.",
        presets: [ { name: "Busca Exata", vars: { query: "Apache 2.4", exact: true } } ],
        fields: [
            { id: "query", label: "Termo de Busca (ex: Apache 2.4)", type: "text", required: true, default: "Apache 2.4" },
            { id: "exact", label: "Busca Exata", type: "boolean", flag: "--exact" },
            { id: "json", label: "Retornar em JSON", type: "boolean", flag: "--json" }
        ]
    },

    // --- PASSWORD CRACKING ---
    john: {
        name: "John the Ripper", command: "john", installCmd: "sudo apt install john",
        description: "Quebra de hashes de senha.",
        presets: [ { name: "Quebrar MD5", vars: { file: "/tmp/hashes.txt", format: "Raw-MD5", wordlist: "/usr/share/wordlists/rockyou.txt" } } ],
        fields: [
            { id: "file", label: "Arquivo de Hashes", type: "text", required: true, default: "/tmp/hashes.txt" },
            { id: "format", label: "Formato do Hash", type: "text", flag: "--format", default: "Raw-MD5" },
            { id: "wordlist", label: "Wordlist", type: "text", flag: "--wordlist", default: "/usr/share/wordlists/rockyou.txt" }
        ]
    },
    hashcat: {
        name: "Hashcat", command: "hashcat", installCmd: "sudo apt install hashcat",
        description: "Quebra de hashes com aceleração GPU/CPU.",
        presets: [ { name: "Ataque MD5 com Rockyou", vars: { mode: "0", hashfile: "/tmp/hash.txt", wordlist: "/usr/share/wordlists/rockyou.txt" } } ],
        fields: [
            { id: "mode", label: "Tipo do Hash (0=MD5, 1000=NTLM)", type: "text", required: true, flag: "-m", default: "0" },
            { id: "hashfile", label: "Arquivo de Hash", type: "text", required: true, default: "/tmp/hash.txt" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, default: "/usr/share/wordlists/rockyou.txt" }
        ]
    }
};

module.exports = TOOL_SCHEMAS;
