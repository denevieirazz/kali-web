// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    nmap: {
        name: "Nmap",
        command: "nmap",
        category: "recon",
        description: "Scanner de rede e portas.",
        presets: [
            { name: "Scan Rápido (Top 100)", vars: { target: "scanme.nmap.org", p: "", sV: false, sS: true, T: "4" } },
            { name: "Detectar Versões", vars: { target: "scanme.nmap.org", p: "80,443", sV: true, sS: false, T: "3" } }
        ],
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, placeholder: "192.168.1.1 ou scanme.nmap.org", default: "scanme.nmap.org" },
            { id: "p", label: "Portas (ex: 80,443)", type: "text", flag: "-p", placeholder: "80,443" },
            { id: "sV", label: "Detectar Versão", type: "boolean", flag: "-sV", default: false },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS", default: true },
            { id: "T", label: "Velocidade (0-5)", type: "select", flag: "-T", options: ["0", "1", "2", "3", "4", "5"], default: "4" }
        ]
    },
    gobuster: {
        name: "Gobuster",
        command: "gobuster",
        category: "web",
        description: "Brute-force de diretórios web.",
        presets: [
            { name: "Diretórios Padrão", vars: { mode: "dir", url: "http://127.0.0.1", wordlist: "/usr/share/wordlists/dirb/common.txt" } }
        ],
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", options: ["dir", "dns", "vhost"], default: "dir" },
            { id: "url", label: "URL Alvo", type: "text", required: true, flag: "-u", placeholder: "http://alvo.com", default: "http://127.0.0.1" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", placeholder: "/usr/share/wordlists/dirb/common.txt", default: "/usr/share/wordlists/dirb/common.txt" }
        ]
    },
    nikto: {
        name: "Nikto",
        command: "nikto",
        category: "web",
        description: "Scanner de vulnerabilidades Web.",
        presets: [
            { name: "Scan Web Completo", vars: { host: "http://127.0.0.1", port: "80" } }
        ],
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", placeholder: "http://alvo.com", default: "http://127.0.0.1" },
            { id: "port", label: "Porta", type: "text", flag: "-p", placeholder: "80", default: "80" }
        ]
    },
    sqlmap: {
        name: "SQLMap",
        command: "sqlmap",
        category: "web",
        description: "Ferramenta de teste de injeção de SQL e auditoria de banco de dados.",
        presets: [
            { name: "Enumerar Bancos (Modo Auto)", vars: { url: "http://testphp.vulnweb.com/artists.php?artist=1", dbs: true, batch: true } }
        ],
        fields: [
            { id: "url", label: "URL Alvo com Parâmetro", type: "text", required: true, flag: "-u", placeholder: "http://alvo.com/page.php?id=1", default: "http://testphp.vulnweb.com/artists.php?artist=1" },
            { id: "dbs", label: "Enumerar Bancos de Dados", type: "boolean", flag: "--dbs", default: true },
            { id: "batch", label: "Modo Automático (Sem Perguntas)", type: "boolean", flag: "--batch", default: true }
        ]
    }
};

module.exports = TOOL_SCHEMAS;
