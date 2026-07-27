const express = require('express');
const { WebSocketServer } = require('ws');
const cors = require('cors');
const pty = require('node-pty');
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const app = express();
app.use(cors());
app.use(express.json());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });
const upload = multer({ dest: 'temp_uploads/' });

const SECRET_KEY = 'CLOUDOS_JWT_SECRET_2024';
const HASHED_PASSWORD = bcrypt.hashSync('admin123', 10);
const ADMIN_USER = { id: 1, username: 'admin', password: HASHED_PASSWORD };

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Acesso negado.' });
    jwt.verify(token, SECRET_KEY, (err, user) => {
        if (err) return res.status(403).json({ error: 'Token inválido.' });
        req.user = user;
        next();
    });
}

app.post('/api/auth/login', (req, res) => {
    const { username, password } = req.body;
    if (username !== ADMIN_USER.username || !bcrypt.compareSync(password, ADMIN_USER.password)) {
        return res.status(401).json({ error: 'Credenciais inválidas.' });
    }
    const token = jwt.sign({ id: ADMIN_USER.id, username: ADMIN_USER.username }, SECRET_KEY, { expiresIn: '24h' });
    res.json({ token, user: { username: ADMIN_USER.username } });
});

app.use(authenticateToken);

// =========================================================
// 🛡️ SUBSYSTEM MANAGER (CAMADA DE CONTROLE DO KALI WSL)
// =========================================================
class SubsystemManager {
    constructor(distro = 'kali-linux', defaultUser = 'root') {
        this.distro = distro;
        this.defaultUser = defaultUser;
    }

    // Executa um comando bash no WSL e retorna uma Promise
    execCommand(userId, command) {
        return new Promise((resolve, reject) => {
            const fullCmd = `wsl -d ${this.distro} -u ${this.defaultUser} -- bash -c "${command.replace(/"/g, '\\"')}"`;
            exec(fullCmd, { windowsHide: true }, (error, stdout, stderr) => {
                if (error) return reject({ error, stderr: stderr || error.message });
                resolve(stdout);
            });
        });
    }

    getSessionName(userId) {
        return `cloudos_${userId}`;
    }

    // 1. Iniciar Sessão Tmux (usado no WebSocket)
    startSession(userId, cols = 80, rows = 30) {
        const sessionName = this.getSessionName(userId);
        return pty.spawn('wsl.exe', ['-d', this.distro, 'tmux', 'new-session', '-A', '-s', sessionName, '-x', cols, '-y', rows], {
            name: 'xterm-256color', cols, rows, cwd: process.env.HOME, env: process.env, useConpty: false
        });
    }

    // 2. Parar Sessão
    async stopSession(userId) {
        const sessionName = this.getSessionName(userId);
        return this.execCommand(userId, `tmux kill-session -t ${sessionName}`);
    }

    // 3. Reiniciar Sessão
    async restartSession(userId) {
        await this.stopSession(userId);
        return { success: true, message: 'Sessão reiniciada. Abra o terminal novamente.' };
    }

    // 4. Status da Sessão
    async getStatus(userId) {
        const sessionName = this.getSessionName(userId);
        try {
            const res = await this.execCommand(userId, `tmux has-session -t ${sessionName} 2>&1 && echo 'ACTIVE' || echo 'INACTIVE'`);
            return res.includes('ACTIVE');
        } catch {
            return false;
        }
    }

    // 5. Diretório Atual
    async getWorkingDirectory(userId) {
        const sessionName = this.getSessionName(userId);
        try {
            return await this.execCommand(userId, `tmux display-message -p -t ${sessionName} '#{pane_current_path}'`);
        } catch {
            return '/root';
        }
    }

    // 6. Listar Processos (Task Manager)
    async listProcesses(userId) {
        return this.execCommand(userId, 'ps aux --sort=-%cpu');
    }

    // 7. Ler Arquivo
    async readFile(userId, filePath) {
        return this.execCommand(userId, `cat "${filePath}"`);
    }

    // 8. Escrever Arquivo
    async writeFile(userId, filePath, content) {
        const escapedContent = content ? content.replace(/'/g, "'\\''") : '';
        return this.execCommand(userId, `echo '${escapedContent}' > "${filePath}"`);
    }
}

const subsystem = new SubsystemManager();
// =========================================================

// --- APIs DO GERENCIADOR DE ARQUIVOS ---
app.get('/api/files', async (req, res) => {
    const dirPath = req.query.path || '/root';
    try {
        const stdout = await subsystem.execCommand(req.user.id, `mkdir -p "${dirPath}" && ls -1 -p "${dirPath}"`);
        const items = stdout.split('\n').filter(Boolean).map(item => ({
            name: item.replace('/', ''),
            type: item.endsWith('/') ? 'folder' : 'file',
            path: dirPath.endsWith('/') ? dirPath + item : dirPath + '/' + item
        }));
        res.json({ path: dirPath, items });
    } catch (e) {
        res.status(500).json({ error: 'Não foi possível ler o diretório.' });
    }
});

app.post('/api/files/action', async (req, res) => {
    const { action, paths, name, newPath, currentPath } = req.body;
    const targetPaths = Array.isArray(paths) ? paths.filter(Boolean) : [];
    
    try {
        if (action === 'delete') {
            await subsystem.execCommand(req.user.id, `mkdir -p /root/.trash`);
            const targets = targetPaths.map(p => `"${p}"`).join(' ');
            await subsystem.execCommand(req.user.id, `mv ${targets} /root/.trash/`);
        } else if (action === 'mkdir') {
            await subsystem.execCommand(req.user.id, `mkdir -p "${currentPath}/${name}"`);
        } else if (action === 'rename') {
            await subsystem.execCommand(req.user.id, `mv "${targetPaths[0]}" "${newPath}"`);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.stderr || 'Erro no WSL' });
    }
});

app.post('/api/files/upload', upload.array('files'), async (req, res) => {
    const targetPath = req.body.path || '/root';
    try {
        for (const file of req.files) {
            const tempPath = path.join(__dirname, file.path).replace(/\\/g, '/').replace('C:/', '/mnt/c/');
            await subsystem.execCommand(req.user.id, `cat '${tempPath}' > '${targetPath}/${file.originalname}'`);
            fs.unlinkSync(path.join(__dirname, file.path));
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Falha no upload' }); }
});

app.get('/api/files/read', async (req, res) => {
    try {
        const content = await subsystem.readFile(req.user.id, req.query.path);
        res.json({ content });
    } catch (e) { res.status(500).json({ error: 'Não foi possível ler o arquivo.' }); }
});

app.post('/api/files/save', async (req, res) => {
    try {
        await subsystem.writeFile(req.user.id, req.body.path, req.body.content);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao salvar no WSL.' }); }
});

// --- APIs DE HARDWARE (USBIPD) ---
function getUsbipdCmd() { return fs.existsSync('C:\\Program Files\\usbipd-win\\usbipd.exe') ? '"C:\\Program Files\\usbipd-win\\usbipd.exe"' : 'usbipd'; }
app.get('/api/devices', (req, res) => {
    exec(`${getUsbipdCmd()} list`, { windowsHide: true }, (error, stdout, stderr) => {
        if (error) return res.status(500).json({ error: 'usbipd-win não encontrado.' });
        const devices = stdout.split('\n').slice(2).filter(l => l.trim()).map(line => {
            const parts = line.trim().split(/\s+/);
            if (parts.length >= 4) return { busid: parts[0], name: parts.slice(3).join(' '), state: line.includes('Attached') ? 'Attached' : 'Not attached' };
            return null;
        }).filter(Boolean);
        res.json({ devices });
    });
});
app.post('/api/devices/attach', (req, res) => {
    exec(`${getUsbipdCmd()} wsl attach --busid ${req.body.busid} -d kali-linux`, { windowsHide: true }, (error) => {
        if (error) return res.status(500).json({ error: 'Node.js precisa estar como Administrador.' });
        res.json({ success: true });
    });
});

// --- APIs TÁTICAS (SUBSYSTEM) ---
app.get('/api/tactical/status', async (req, res) => {
    try {
        const cmd = `service tor status | grep -q 'active' && echo 'TOR:ACTIVE' || echo 'TOR:INACTIVE'; IFACE=$(ip route | grep default | awk '{print $5}' | head -n1); MAC=$(ip link show $IFACE | grep link/ether | awk '{print $2}'); echo 'MAC:'$MAC`;
        const stdout = await subsystem.execCommand(req.user.id, cmd);
        res.json({
            torActive: stdout.includes('TOR:ACTIVE'),
            currentMac: (stdout.match(/MAC:(..:..:..:..:..:..)/) || [])[1] || 'Indisponível'
        });
    } catch { res.status(500).json({ error: 'Falha ao ler status.' }); }
});

app.post('/api/tactical/anon', async (req, res) => {
    const { action } = req.body;
    let cmd = '';
    if (action === 'tor_on') cmd = 'service tor start && echo "export http_proxy=http://127.0.0.1:8118" >> ~/.bashrc && service privoxy start';
    else if (action === 'tor_off') cmd = 'service tor stop && sed -i "/http_proxy/d" ~/.bashrc && service privoxy stop';
    else if (action === 'mac_spoof') cmd = 'IFACE=$(ip route | grep default | awk "{print \\$5}") && macchanger -r $IFACE';
    else return res.status(400).json({ error: 'Ação inválida' });
    
    try {
        await subsystem.execCommand(req.user.id, cmd);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: e.stderr || 'Erro no WSL' }); }
});

// --- APIs DO SUBSYSTEM MANAGER ---
app.post('/api/subsystem/restart', async (req, res) => {
    try {
        await subsystem.restartSession(req.user.id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao reiniciar' }); }
});

app.get('/api/subsystem/processes', async (req, res) => {
    try {
        const processes = await subsystem.listProcesses(req.user.id);
        res.json({ processes });
    } catch (e) { res.status(500).json({ error: 'Erro ao listar processos' }); }
});

// --- WEBSOCKET COM TMUX ---
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
    const token = fullUrl.searchParams.get('token');
    if (!token) { ws.send("ERRO: Token não fornecido.\r\n"); return ws.close(); }
    
    jwt.verify(token, SECRET_KEY, (err, decoded) => {
        if (err) { ws.send("ERRO: Token inválido.\r\n"); return ws.close(); }
        
        const userId = decoded.id;
        try {
            const ptyProcess = subsystem.startSession(userId);
            ptyProcess.onData((data) => ws.readyState === ws.OPEN && ws.send(data));
            ws.on('message', (msg) => {
                const strMsg = msg.toString();
                if (strMsg.startsWith('{"type":"resize"')) {
                    try { const d = JSON.parse(strMsg); if (d.type === 'resize') ptyProcess.resize(d.cols, d.rows); } catch (e) {}
                } else { ptyProcess.write(msg); }
            });
            ws.on('close', () => ptyProcess && ptyProcess.kill());
        } catch (error) {
            if (ws.readyState === ws.OPEN) { ws.send("ERRO: WSL Kali Linux não encontrado.\r\n"); ws.close(); }
        }
    });
});

server.listen(8080, () => console.log('🚀 Backend CloudOS com SubsystemManager rodando!'));
