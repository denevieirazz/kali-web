// cloudos-backend/kali_tools_schema.js
const TOOL_SCHEMAS = {
    nmap: {
        name: "Nmap",
        command: "nmap",
        category: "recon",
        description: "Scanner de rede e portas.",
        presets: [
            { name: "Scan Rápido (Top 100)", vars: { p: "", sV: false, sS: true, T: "4" } },
            { name: "Detectar Versões", vars: { p: "", sV: true, sS: false, T: "3" } }
        ],
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, placeholder: "192.168.1.1" },
            { id: "p", label: "Portas (ex: 80,443)", type: "text", flag: "-p" },
            { id: "sV", label: "Detectar Versão", type: "boolean", flag: "-sV" },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS" },
            { id: "T", label: "Velocidade (0-5)", type: "select", flag: "-T", options: ["0", "1", "2", "3", "4", "5"] }
        ]
    },
    gobuster: {
        name: "Gobuster",
        command: "gobuster",
        category: "web",
        description: "Brute-force de diretórios web.",
        presets: [],
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", options: ["dir", "dns", "vhost"] },
            { id: "url", label: "URL", type: "text", required: true, flag: "-u", placeholder: "http://alvo.com" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", placeholder: "/usr/share/wordlists/dirb/common.txt" }
        ]
    },
    nikto: {
        name: "Nikto",
        command: "nikto",
        category: "web",
        description: "Scanner de vulnerabilidades Web.",
        presets: [],
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", placeholder: "http://alvo.com" },
            { id: "port", label: "Porta", type: "text", flag: "-p" }
        ]
    },
    sqlmap: {
        name: "SQLMap",
        command: "sqlmap",
        category: "web",
        description: "Ferramenta de teste de injeção de SQL e gerenciamento de banco de dados.",
        presets: [],
        fields: [
            { id: "url", label: "URL Alvo", type: "text", required: true, flag: "-u", placeholder: "http://alvo.com/page.php?id=1" },
            { id: "dbs", label: "Enumerar Bancos de Dados", type: "boolean", flag: "--dbs" },
            { id: "batch", label: "Modo Automático (Sem Perguntas)", type: "boolean", flag: "--batch" }
        ]
    }
};

module.exports = TOOL_SCHEMAS;
