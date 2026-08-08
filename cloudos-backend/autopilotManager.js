// cloudos-backend/autopilotManager.js
const { spawn } = require('child_process');
const akbManager = require('./akbManager');

function escapeShellArg(arg) {
    return `'${arg.replace(/'/g, `'\\''`)}'`;
}

async function runCommand(cmd, args) {
    return new Promise((resolve) => {
        const wslArgs = ['-e', 'bash', '-c', `${cmd} ${args.map(escapeShellArg).join(' ')}`];
        const process = spawn('wsl.exe', wslArgs);
        let output = '';

        process.stdout.on('data', (data) => { output += data.toString(); });
        process.stderr.on('data', (data) => { output += data.toString(); });
        
        process.on('close', (code) => {
            resolve({ code, output });
        });
    });
}

async function runWebReconPipeline(target, sendLog) {
    sendLog(`🚀 Iniciando Web Recon em: ${target}`);

    // 1. WhatWeb (Tecnologias)
    sendLog('🔍 Identificando tecnologias (WhatWeb)...');
    const whatweb = await runCommand('whatweb', [target]);
    sendLog(whatweb.output || '[WhatWeb executado sem saída]');

    // 2. Nmap (Salvando direto na AKB)
    sendLog('🛡️ Rodando Nmap (Top 1000 ports + Versions)...');
    const nmap = await runCommand('nmap', ['-sV', '-oX', '-', target]);
    if (nmap.code === 0 && nmap.output) {
        await akbManager.parseAndSaveNmap(nmap.output);
        sendLog('✅ Nmap concluído e Host/Portas salvos na Knowledge Base (AKB).');
    }

    // 3. TheHarvester (E-mails e Subdomínios)
    sendLog('📧 Extraindo e-mails e hosts (theHarvester)...');
    const harvester = await runCommand('theHarvester', ['-d', target, '-b', 'all']);
    sendLog(harvester.output || '✅ Coleta OSINT concluída.');

    sendLog('✅ Pipeline Web finalizado com sucesso!');
}

async function runPersonReconPipeline(username, sendLog) {
    sendLog(`🕵️ Rastreando perfil: ${username} no Sherlock...`);
    
    const sherlock = await runCommand('sherlock', [username, '--timeout', '10', '--print']);
    sendLog(sherlock.output || 'Rastreio concluído.');
    
    sendLog('✅ Rastreio de pessoa concluído!');
}

module.exports = { runWebReconPipeline, runPersonReconPipeline };
