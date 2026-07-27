const express = require('express');
const { WebSocketServer } = require('ws');
const cors = require('cors');
const pty = require('node-pty');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

const app = express();
app.use(cors());
app.use(express.json());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });

const upload = multer({ dest: 'temp_uploads/' });

// Função de segurança para paths com espaço no WSL (usa aspas duplas)
function wslPath(p) {
    if (!p) return '""';
    return `"${p}"`;
}

// API DE LISTAGEM
app.get('/api/files', (req, res) => {
    const dirPath = req.query.path || '/root';
    const cmd = `wsl -d kali-linux -u root -- bash -c "mkdir -p ${wslPath(dirPath)} && ls -1 -p ${wslPath(dirPath)}"`;
    
    exec(cmd, { windowsHide: true }, (error, stdout, stderr) => {
        if (error) {
            console.error("Erro WSL ls:", stderr || error.message);
            return res.status(500).json({ error: 'Não foi possível ler o diretório.' });
        }
        const items = stdout.split('\n').filter(Boolean).map(item => ({
            name: item.replace('/', ''),
            type: item.endsWith('/') ? 'folder' : 'file',
            path: dirPath.endsWith('/') ? dirPath + item : dirPath + '/' + item
        }));
        res.json({ path: dirPath, items });
    });
});

// API DE AÇÕES
app.post('/api/files/action', (req, res) => {
    const { action, paths, name, newPath, currentPath } = req.body;
    const rawPaths = Array.isArray(paths) ? paths : (req.body.path ? [req.body.path] : []);
    const targetPaths = rawPaths.filter(Boolean);
    
    // Ação de Deletar precisa de dois passos (criar lixeira e mover)
    if (action === 'delete') {
        exec('wsl -d kali-linux -u root -- mkdir -p /root/.trash', { windowsHide: true }, (err) => {
            if (err) return res.status(500).json({ error: 'Erro ao criar lixeira' });
            const targets = targetPaths.map(wslPath).join(' ');
            const cmd = `wsl -d kali-linux -u root -- mv ${targets} /root/.trash/`;
            exec(cmd, { windowsHide: true }, (error, stdout, stderr) => {
                if (error) return res.status(500).json({ error: stderr });
                res.json({ success: true });
            });
        });
        return;
    }

    let cmd = '';
    const escapedTargets = targetPaths.map(wslPath).join(' ');
    const escapedName = name ? wslPath(name) : '';
    const escapedNewPath = newPath ? wslPath(newPath) : '';
    const escapedCurrent = wslPath(currentPath || targetPaths[0]);

    try {
        if (action === 'mkdir') {
            cmd = `wsl -d kali-linux -u root -- mkdir -p ${escapedCurrent}/${escapedName}`;
        } else if (action === 'rename') {
            cmd = `wsl -d kali-linux -u root -- mv ${escapedTargets} ${escapedNewPath}`;
        } else {
            return res.status(400).json({ error: 'Ação inválida' });
        }

        exec(cmd, { windowsHide: true }, (error, stdout, stderr) => {
            if (error) {
                console.error("Erro Ação WSL:", stderr);
                return res.status(500).json({ error: stderr || 'Erro no WSL' });
            }
            res.json({ success: true });
        });
    } catch (e) {
        res.status(500).json({ error: 'Erro interno ao montar comando.' });
    }
});

app.post('/api/files/upload', upload.array('files'), async (req, res) => {
    const targetPath = req.body.path || '/root';
    const sTarget = targetPath.replace(/"/g, '\\"');
    try {
        if (req.files && req.files.length > 0) {
            for (const file of req.files) {
                const tempPath = path.join(__dirname, file.path).replace(/\\/g, '/').replace('C:/', '/mnt/c/');
                const sName = file.originalname.replace(/"/g, '\\"');
                await new Promise((resolve, reject) => {
                    exec(`wsl -d kali-linux -- bash -c "cat '${tempPath}' > '${sTarget}/${sName}'"`, (err) => err ? reject(err) : resolve());
                });
                try { fs.unlinkSync(path.join(__dirname, file.path)); } catch (e) {}
            }
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Falha no upload' }); }
});

function getUsbipdCmd() {
    const defaultPath = 'C:\\Program Files\\usbipd-win\\usbipd.exe';
    return fs.existsSync(defaultPath) ? `"${defaultPath}"` : 'usbipd';
}

// API PARA LISTAR HARDWARE DO WINDOWS
app.get('/api/devices', (req, res) => {
    const usbipd = getUsbipdCmd();
    exec(`${usbipd} list`, { windowsHide: true }, (error, stdout, stderr) => {
        if (error) {
            console.error("Erro usbipd:", stderr);
            return res.status(500).json({ error: 'usbipd-win não encontrado. Instale com: winget install usbipd' });
        }
        // Limpa o texto do powershell e transforma em JSON
        const lines = stdout.split('\n').slice(2).filter(l => l.trim());
        const devices = lines.map(line => {
            const parts = line.trim().split(/\s+/);
            if (parts.length >= 4) {
                return {
                    busid: parts[0],
                    name: parts.slice(3).join(' '),
                    state: line.includes('Attached') ? 'Attached' : 'Not attached'
                };
            }
            return null;
        }).filter(Boolean);
        res.json({ devices });
    });
});

// API PARA PEDIR PERMISSÃO E PLUGAR O HARDWARE NO KALI
app.post('/api/devices/attach', (req, res) => {
    const { busid } = req.body;
    const usbipd = getUsbipdCmd();
    const cmd = `${usbipd} wsl attach --busid ${busid} -d kali-linux`;
    
    exec(cmd, { windowsHide: true }, (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: 'Falha ao anexar. O Node.js precisa estar rodando como Administrador.' });
        }
        res.json({ success: true });
    });
});

// API DE CONFIGURAÇÕES TÁTICAS (ANONIMATO)
app.post('/api/tactical/anon', (req, res) => {
    const { action } = req.body; // 'tor_on', 'tor_off', 'mac_spoof'
    let cmd = '';

    if (action === 'tor_on') {
        cmd = 'wsl -d kali-linux -u root -- bash -c "service tor start && echo \\"export http_proxy=http://127.0.0.1:8118\\" >> ~/.bashrc && echo \\"export https_proxy=http://127.0.0.1:8118\\" >> ~/.bashrc && service privoxy start"';
    } else if (action === 'tor_off') {
        cmd = 'wsl -d kali-linux -u root -- bash -c "service tor stop && sed -i \\"/http_proxy/d\\" ~/.bashrc && sed -i \\"/https_proxy/d\\" ~/.bashrc && service privoxy stop"';
    } else if (action === 'mac_spoof') {
        cmd = 'wsl -d kali-linux -u root -- bash -c "IFACE=$(ip route | grep default | awk \\"{print \\$5}\\") && macchanger -r $IFACE"';
    } else {
        return res.status(400).json({ error: 'Ação inválida' });
    }

    exec(cmd, { windowsHide: true }, (error, stdout, stderr) => {
        if (error) return res.status(500).json({ error: stderr || 'Erro no WSL. Verifique se o macchanger está instalado.' });
        res.json({ success: true, output: stdout });
    });
});

// API PARA SALVAR CHAVES DE API DE OSINT
app.post('/api/tactical/osint', (req, res) => {
    const { keys } = req.body;
    const configPath = '~/.config/cloudos_osint.json';
    const cmd = `wsl -d kali-linux -u root -- bash -c "mkdir -p ~/.config && echo '${JSON.stringify(keys)}' > ${configPath}"`;
    
    exec(cmd, { windowsHide: true }, (error) => {
        if (error) return res.status(500).json({ error: 'Erro ao salvar chaves' });
        res.json({ success: true });
    });
});

// WebSocket com TMUX (Persistência de Terminal)
function heartbeat() { this.isAlive = true; }
const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) return ws.terminate();
        ws.isAlive = false; ws.ping();
    });
}, 300000);

wss.on('connection', async (ws, req) => {
    ws.isAlive = true;
    ws.on('pong', heartbeat);

    const fullUrl = new URL(req.url, 'http://localhost');
    const userId = fullUrl.searchParams.get('userId') || 'kali_user';
    const sessionName = `cloudos_${userId}`;

    let ptyProcess;
    try {
        // Inicia WSL com Tmux. Se a sessão já existir, ele apenas se reconecta a ela!
        ptyProcess = pty.spawn('wsl.exe', ['-d', 'kali-linux', 'tmux', 'new-session', '-A', '-s', sessionName, '-x', '80', '-y', '30'], {
            name: 'xterm-256color',
            cols: 80, rows: 30,
            cwd: process.env.HOME || process.cwd(),
            env: process.env,
            useConpty: false
        });

        ptyProcess.onData((data) => ws.readyState === ws.OPEN && ws.send(data));
        ws.on('message', (msg) => {
            const strMsg = msg.toString();
            if (strMsg.startsWith('{"type":"resize"')) {
                try { const d = JSON.parse(strMsg); if (d.type === 'resize') ptyProcess.resize(d.cols, d.rows); } catch (e) {}
            } else { ptyProcess.write(msg); }
        });

        ws.on('close', () => ptyProcess && ptyProcess.kill());
    } catch (error) {
        console.error("ERRO WSL:", error.message);
        if (ws.readyState === ws.OPEN) { ws.send("ERRO: WSL Kali Linux não encontrado.\r\n"); ws.close(); }
    }
});

server.listen(8080, () => console.log('🚀 Backend CloudOS (Persistente e Responsivo) rodando!'));
