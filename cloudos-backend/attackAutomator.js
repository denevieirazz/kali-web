const { getProjectExecutionContext } = require('./services/scannerSecurity');
const database = require('./database');
const rawDb = database.rawDb;

function escapeShellArg(arg) {
    return `'${String(arg).replace(/'/g, `'\\''`)}'`;
}

async function runCommand(cmd, args, sendLog, timeoutMs = 120000) {
    return new Promise((resolve) => {
        const wslArgs = ['-d', 'kali-linux', '-u', 'cloudos', '--', cmd, ...args];
        const process = spawn('wsl.exe', wslArgs);
        let output = '';

        const timer = setTimeout(() => {
            try { process.kill('SIGKILL'); } catch {}
            if (sendLog) sendLog(`⏱️ Timeout atingido para ${cmd}.\n`);
            resolve(output);
        }, timeoutMs);

        process.stdout.on('data', (data) => { 
            const str = data.toString();
            output += str;
            if (sendLog) sendLog(str);
        });
        process.stderr.on('data', (data) => { 
            const str = data.toString();
            output += str;
            if (sendLog) sendLog(str);
        });
        
        process.on('close', () => {
            clearTimeout(timer);
            resolve(output);
        });
    });
}

async function executeAutoAttack(hostId, userId, sendLog) {
    // 1. Busca o Host e suas Portas no banco SQLite
    const host = await new Promise((resolve, reject) => {
        rawDb.get('SELECT * FROM akb_hosts WHERE id = ?', [hostId], (err, row) => err ? reject(err) : resolve(row));
    });
    if (!host) {
        if (sendLog) sendLog('❌ Host não encontrado na Active Knowledge Base.\n');
        return;
    }

    if (!host.project_id) {
        if (sendLog) sendLog('❌ Host não está associado a um Projeto ativo.\n');
        return;
    }

    // 2. Validação rigorosa de Scope Guard e Contexto
    const contextCheck = await getProjectExecutionContext(userId, host.project_id, host.ip);
    if (!contextCheck.allowed) {
        if (sendLog) sendLog(`🚫 [SCOPE GUARD] Ataque bloqueado: ${contextCheck.reason}\n`);
        return;
    }

    const ports = await new Promise((resolve, reject) => {
        rawDb.all('SELECT * FROM akb_ports WHERE host_id = ?', [hostId], (err, rows) => err ? reject(err) : resolve(rows));
    });

    if (sendLog) sendLog(`🎯 Iniciando 1-Click Auto-Attack no alvo ${host.ip} (${host.hostname || 'Local'})...\n`);

    // 2. Lógica de Automação Tática baseada em Portas e Serviços
    if (!ports || ports.length === 0) {
        if (sendLog) sendLog('⚠️ Nenhuma porta aberta registrada para este host. Executando varredura rápida de serviços...\n');
        await runCommand('nmap', ['-sV', host.ip], sendLog);
        return;
    }

    for (const portObj of ports) {
        const portNum = parseInt(portObj.port || portObj.port_number || 0);
        const service = (portObj.service || '').toLowerCase();
        const version = portObj.version || '';

        // Web Inspection
        if ([80, 443, 8080, 8443].includes(portNum) || service.includes('http')) {
            if (sendLog) sendLog(`\n🌐 Porta Web ${portNum} detectada. Disparando Nikto Vulnerability Scanner...\n`);
            await runCommand('nikto', ['-h', host.ip, '-p', portNum.toString(), '-Tuning', '1,2,3'], sendLog);
        } 
        
        // SSH Searchsploit
        if (service.includes('ssh') || portNum === 22) {
            if (sendLog) sendLog(`\n🔐 Serviço SSH detectado (${version}). Consultando Searchsploit / Exploit-DB...\n`);
            const searchTerms = `ssh ${version}`.trim();
            await runCommand('searchsploit', [searchTerms], sendLog);
        }

        // SMB Enum4linux
        if (service.includes('smb') || portNum === 445 || portNum === 139) {
            if (sendLog) sendLog(`\n📁 Serviço SMB/NetBIOS detectado. Disparando Enum4linux...\n`);
            await runCommand('enum4linux', ['-a', host.ip], sendLog);
        }
    }

    if (sendLog) sendLog('\n✅ 1-Click Auto-Attack concluído! Todos os relatórios foram consolidados.');
}

module.exports = { executeAutoAttack };
