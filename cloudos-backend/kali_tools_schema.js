// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    nmap: {
        name: "Nmap",
        command: "nmap",
        description: "Scanner de rede e portas.",
        presets: [
            { name: "Scan Rápido (Top 100)", vars: { target: "scanme.nmap.org", p: "", sV: false, sS: true, T: "4" } },
            { name: "Detectar Versões", vars: { target: "scanme.nmap.org", p: "", sV: true, sS: false, T: "3" } }
        ],
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, default: "scanme.nmap.org", placeholder: "192.168.1.1" },
            { id: "p", label: "Portas (ex: 80,443)", type: "text", flag: "-p" },
            { id: "sV", label: "Detectar Versão", type: "boolean", flag: "-sV" },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS" },
            { id: "T", label: "Velocidade (0-5)", type: "select", flag: "-T", default: "4", options: ["0", "1", "2", "3", "4", "5"] }
        ]
    },
    gobuster: {
        name: "Gobuster",
        command: "gobuster",
        description: "Brute-force de diretórios web.",
        presets: [
            { name: "Scan Dir Padrão", vars: { mode: "dir", url: "http://localhost", wordlist: "/usr/share/wordlists/dirb/common.txt" } }
        ],
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", default: "dir", options: ["dir", "dns", "vhost"] },
            { id: "url", label: "URL", type: "text", required: true, flag: "-u", default: "http://localhost", placeholder: "http://alvo.com" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", default: "/usr/share/wordlists/dirb/common.txt", placeholder: "/usr/share/wordlists/..." }
        ]
    },
    nikto: {
        name: "Nikto",
        command: "nikto",
        description: "Scanner de vulnerabilidades Web.",
        presets: [
            { name: "Scan Padrão (Porta 80)", vars: { host: "http://localhost", port: "80", ssl: false } },
            { name: "Scan SSL (Porta 443)", vars: { host: "localhost", port: "443", ssl: true } }
        ],
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", default: "http://localhost", placeholder: "http://alvo.com" },
            { id: "port", label: "Porta", type: "text", flag: "-p", default: "80" },
            { id: "ssl", label: "Forçar SSL", type: "boolean", flag: "-ssl" }
        ]
    },
    sqlmap: {
        name: "SQLMap",
        command: "sqlmap",
        description: "Injeção de SQL e auditoria de BD.",
        presets: [
            { name: "Testar URL e Enumerar DBs", vars: { url: "http://localhost/pagina.php?id=1", dbs: true, batch: true } }
        ],
        fields: [
            { id: "url", label: "URL (com parametro ?id=)", type: "text", required: true, flag: "-u", default: "http://localhost/test.php?id=1", placeholder: "http://alvo.com/artigo?id=1" },
            { id: "dbs", label: "Enumerar Bancos", type: "boolean", flag: "--dbs" },
            { id: "batch", label: "Modo Automático (Sem Perguntas)", type: "boolean", flag: "--batch", default: true }
        ]
    }
};
module.exports = TOOL_SCHEMAS;
