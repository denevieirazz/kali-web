// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    nmap: {
        name: "Nmap", command: "nmap", installCmd: "sudo apt install nmap",
        description: "Scanner de rede e portas.",
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
    masscan: {
        name: "Masscan", command: "masscan", installCmd: "sudo apt install masscan",
        description: "Scanner de portas ultra rápido.",
        presets: [ { name: "Scan Rápido Top 100", vars: { target: "10.0.0.0/24", ports: "1-1000", rate: "1000" } } ],
        fields: [
            { id: "target", label: "Alvo (IP/Rede)", type: "text", required: true, default: "10.0.0.0/24" },
            { id: "ports", label: "Portas", type: "text", required: true, flag: "-p", default: "1-1000" },
            { id: "rate", label: "Pacotes/seg", type: "text", required: true, flag: "--rate", default: "1000" }
        ]
    },
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
    ffuf: {
        name: "Ffuf", command: "ffuf", installCmd: "sudo apt install ffuf",
        description: "Fuzzer web rápido.",
        presets: [ { name: "Fuzz Diretórios", vars: { url: "http://localhost/FUZZ", wordlist: "/usr/share/wordlists/dirb/common.txt" } } ],
        fields: [
            { id: "url", label: "URL (use FUZZ)", type: "text", required: true, flag: "-u", default: "http://localhost/FUZZ" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", default: "/usr/share/wordlists/dirb/common.txt" }
        ]
    },
    whatweb: {
        name: "WhatWeb", command: "whatweb", installCmd: "sudo apt install whatweb",
        description: "Identifica tecnologias web.",
        presets: [ { name: "Scan Agressivo", vars: { target: "http://localhost", a: true } } ],
        fields: [
            { id: "target", label: "URL Alvo", type: "text", required: true, default: "http://localhost" },
            { id: "a", label: "Agressivo (Mais info)", type: "boolean", flag: "-a" }
        ]
    },
    wpscan: {
        name: "WPScan", command: "wpscan", installCmd: "sudo apt install wpscan",
        description: "Scanner de WordPress.",
        presets: [ { name: "Enumeração de Plugins", vars: { url: "http://localhost", enumerate: "p", force: true } } ],
        fields: [
            { id: "url", label: "URL do WP", type: "text", required: true, flag: "--url", default: "http://localhost" },
            { id: "enumerate", label: "Enumerar (p,t,u)", type: "text", flag: "--enumerate", default: "p" },
            { id: "force", label: "Forçar Scan", type: "boolean", flag: "--force" }
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
    nuclei: {
        name: "Nuclei", command: "nuclei", installCmd: "sudo apt install nuclei",
        description: "Scanner de vulns baseado em templates.",
        presets: [ { name: "Scan Rápido", vars: { target: "http://localhost", severity: "low,medium,high" } } ],
        fields: [
            { id: "target", label: "URL Alvo", type: "text", required: true, flag: "-u", default: "http://localhost" },
            { id: "severity", label: "Severidade", type: "text", flag: "-severity", default: "low,medium,high" }
        ]
    },
    hydra: {
        name: "Hydra", command: "hydra", installCmd: "sudo apt install hydra",
        description: "Brute-force de logins.",
        presets: [ { name: "Atacar SSH", vars: { target: "localhost", service: "ssh", user: "root", pass: "/usr/share/wordlists/rockyou.txt" } } ],
        fields: [
            { id: "target", label: "Alvo", type: "text", required: true, default: "localhost" },
            { id: "service", label: "Serviço (ssh,ftp,...)", type: "text", required: true, default: "ssh" },
            { id: "user", label: "Usuário", type: "text", required: true, flag: "-l", default: "root" },
            { id: "pass", label: "Wordlist Senhas", type: "text", required: true, flag: "-P", default: "/usr/share/wordlists/rockyou.txt" }
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
    john: {
        name: "John the Ripper", command: "john", installCmd: "sudo apt install john",
        description: "Quebra de hashes de senha.",
        presets: [ { name: "Quebrar MD5", vars: { file: "/tmp/hashes.txt", format: "Raw-MD5", wordlist: "/usr/share/wordlists/rockyou.txt" } } ],
        fields: [
            { id: "file", label: "Arquivo de Hashes", type: "text", required: true, default: "/tmp/hashes.txt" },
            { id: "format", label: "Formato do Hash", type: "text", flag: "--format", default: "Raw-MD5" },
            { id: "wordlist", label: "Wordlist", type: "text", flag: "--wordlist", default: "/usr/share/wordlists/rockyou.txt" }
        ]
    }
};
module.exports = TOOL_SCHEMAS;
