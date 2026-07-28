// Schema de Interface Dinâmica para Ferramentas Kali
const TOOL_SCHEMAS = {
    nmap: {
        name: "Nmap",
        command: "nmap",
        category: "recon",
        description: "Network Mapper - Scanner de portas e rede.",
        fields: [
            { id: "target", label: "Alvo (IP/Host)", type: "text", required: true, placeholder: "192.168.1.1 ou scanme.nmap.org" },
            { id: "p", label: "Portas (ex: 80,443 ou 1-1000)", type: "text", flag: "-p" },
            { id: "sV", label: "Detectar Versão do Serviço", type: "boolean", flag: "-sV" },
            { id: "sS", label: "SYN Scan (Stealth)", type: "boolean", flag: "-sS" },
            { id: "T", label: "Velocidade (Timing 0-5)", type: "select", flag: "-T", options: ["0", "1", "2", "3", "4", "5"] }
        ]
    },
    gobuster: {
        name: "Gobuster",
        command: "gobuster",
        category: "web",
        description: "Brute-forcer de diretórios e arquivos web.",
        fields: [
            { id: "mode", label: "Modo", type: "select", required: true, flag: "", options: ["dir", "dns", "vhost"] },
            { id: "url", label: "URL Alvo", type: "text", required: true, flag: "-u", placeholder: "http://exemplo.com" },
            { id: "wordlist", label: "Wordlist", type: "text", required: true, flag: "-w", placeholder: "/usr/share/wordlists/dirb/common.txt" },
            { id: "x", label: "Extensões (ex: php,html)", type: "text", flag: "-x" }
        ]
    },
    nikto: {
        name: "Nikto",
        command: "nikto",
        category: "web",
        description: "Scanner de vulnerabilidades em servidores web.",
        fields: [
            { id: "host", label: "Host Alvo", type: "text", required: true, flag: "-h", placeholder: "http://exemplo.com" },
            { id: "port", label: "Porta", type: "text", flag: "-p" },
            { id: "ssl", label: "Forçar SSL", type: "boolean", flag: "-ssl" }
        ]
    },
    sqlmap: {
        name: "SQLMap",
        command: "sqlmap",
        category: "web",
        description: "Ferramenta de teste de injeção de SQL e gerenciamento de banco de dados.",
        fields: [
            { id: "url", label: "URL Alvo", type: "text", required: true, flag: "-u", placeholder: "http://alvo.com/page.php?id=1" },
            { id: "dbs", label: "Enumerar Bancos de Dados", type: "boolean", flag: "--dbs" },
            { id: "batch", label: "Modo Automático (Sem Perguntas)", type: "boolean", flag: "--batch" }
        ]
    }
};

module.exports = TOOL_SCHEMAS;
