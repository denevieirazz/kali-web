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
const WSL_FS_ROOT = '\\\\wsl.localhost\\kali-linux'; // Acesso direto ao sistema de arquivos do WSL2 via Node FS

// Auth Setup (Simulando DB)
const usersDb = [{ id: 'u_1001', username: 'admin', passwordHash: bcrypt.hashSync('admin123', 10) }];

function authenticateToken(req, res, next) {
    const token = req.headers['authorization']?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Acesso negado.' });
    jwt.verify(token, SECRET_KEY, (err, user) => {
        if (err) return res.status(403).json({ error: 'Token inválido.' });
        req.user = user;
        next();
    });
}

app.post('/api/auth/login', (req, res) => {
    const { username, password } = req.body;
    const user = usersDb.find(u => u.username === username);
    if (!user || !bcrypt.compareSync(password, user.passwordHash)) return res.status(401).json({ error: 'Credenciais inválidas.' });
    const token = jwt.sign({ id: user.id, username: user.username }, SECRET_KEY, { expiresIn: '24h' });
    res.json({ token, user: { username: user.username, id: user.id } });
});

app.use(authenticateToken);

// =========================================================
// 🛡️ SUBSYSTEM MANAGER (Camada de Segurança e Controle)
// =========================================================
class SubsystemManager {
    constructor() {
        this.recentErrors = [];
    }

    logError(msg) {
        this.recentErrors.unshift({ time: new Date().toISOString(), msg: String(msg) });
        if (this.recentErrors.length > 10) this.recentErrors.pop();
    }

    // Sanitiza e bloqueia Path Traversal
    getSecurePath(userId, requestedPath) {
        const safeUserId = String(userId).replace(/[^a-zA-Z0-9_]/g, '');
        const baseDir = path.join(WSL_FS_ROOT, 'home', 'cloudos_users', safeUserId);
        
        // Se requestedPath for vazio, retorna a base
        const resolved = path.resolve(baseDir, requestedPath || '');
        
        // BLOQUEIO DE PATH TRAVERSAL
        if (!resolved.startsWith(baseDir)) {
            throw new Error("Acesso negado: Path Traversal detectado.");
        }
        return resolved;
    }

    // Converte caminho Windows para caminho Linux (para comandos tmux/ps)
    toLinuxPath(winPath) {
        return winPath.replace(WSL_FS_ROOT, '').replace(/\\/g, '/');
    }

    async execCommand(userId, command) {
        return new Promise((resolve, reject) => {
            // Roda como usuário 'cloudos', nunca como root!
            exec(`wsl -d kali-linux -u cloudos -- bash -c "${command.replace(/"/g, '\\"')}"`, { windowsHide: true }, (error, stdout, stderr) => {
                if (error) { this.logError(stderr || error.message); return reject(stderr || error.message); }
                resolve(stdout);
            });
        });
    }

    // --- File System Operations (Usando Node FS Nativo = Seguro) ---
    async listFiles(userId, relPath) {
        const dirPath = this.getSecurePath(userId, relPath);
        const items = await fs.promises.readdir(dirPath, { withFileTypes: true });
        return items.map(item => ({
            name: item.name,
            type: item.isDirectory() ? 'folder' : 'file',
            path: path.posix.join(relPath || '', item.name)
        }));
    }

    async readFile(userId, relPath) {
        const filePath = this.getSecurePath(userId, relPath);
        return fs.promises.readFile(filePath, 'utf-8');
    }

    async writeFile(userId, relPath, content) {
        const filePath = this.getSecurePath(userId, relPath);
        return fs.promises.writeFile(filePath, content, 'utf-8');
    }

    async createFolder(userId, relPath, name) {
        const basePath = this.getSecurePath(userId, relPath);
        const newPath = path.join(basePath, name);
        await fs.promises.mkdir(newPath, { recursive: true });
    }

    async deleteFile(userId, relPath) {
        const filePath = this.getSecurePath(userId, relPath);
        // Em vez de deletar, mover para lixeira nativa do WSL
        const trashPath = this.getSecurePath(userId, '.trash');
        await fs.promises.mkdir(trashPath, { recursive: true });
        await fs.promises.rename(filePath, path.join(trashPath, path.basename(filePath)));
    }

    // --- Terminal (Tmux) ---
    startSession(userId, cwd = null) {
        const sessionName = `cloudos_${userId}`;
        const linuxCwd = cwd ? this.toLinuxPath(this.getSecurePath(userId, cwd)) : '/home/cloudos_users/' + userId;
        
        return pty.spawn('wsl.exe', ['-d', 'kali-linux', '-u', 'cloudos', 'tmux', 'new-session', '-A', '-s', sessionName, '-c', linuxCwd, '-x', '80', '-y', '30'], {
            name: 'xterm-256color', cols: 80, rows: 30, cwd: process.env.HOME, env: process.env, useConpty: false
        });
    }

    // --- OpSec & System Monitor ---
    async getSystemStatus(userId) {
        try {
            const cmd = `service tor status | grep -q 'active' && echo 'TOR:ACTIVE' || echo 'TOR:INACTIVE'; IFACE=$(ip route | grep default | awk '{print $5}' | head -n1); MAC=$(ip link show $IFACE | grep link/ether | awk '{print $2}'); echo 'MAC:'$MAC; df -h / | tail -1 | awk '{print "DISK:"$3"/"$2}'`;
            const stdout = await this.execCommand(userId, cmd);
            
            let mac = stdout.match(/MAC:(..:..:..:..:..:..)/)?.[1] || 'Indisponível';
            // REGRA: Mascarar MAC por padrão
            const maskedMac = mac.replace(/(..:..:..):(..:..:..)/, '$1:XX:XX:XX');

            return {
                torActive: stdout.includes('TOR:ACTIVE'),
                currentMac: maskedMac,
                diskUsage: stdout.match(/DISK:(.*)/)?.[1] || 'N/A',
                activeSessions: wss.clients.size,
                recentErrors: this.recentErrors
            };
        } catch (e) { this.logError(e); throw e; }
    }
}

const subsystem = new SubsystemManager();

// Garantir que o usuário do JWT tenha sua pasta home criada
app.use(async (req, res, next) => {
    try {
        const userHome = subsystem.getSecurePath(req.user.id, '');
        await fs.promises.mkdir(userHome, { recursive: true });
        await fs.promises.mkdir(path.join(userHome, '.trash'), { recursive: true });
        next();
    } catch (e) { res.status(500).json({ error: "Erro ao inicializar home do usuário." }); }
});

// =========================================================
// 🌐 API ROUTES
// =========================================================

// FileManager APIs (Sem concatenação de shell, 100% Node FS)
app.get('/api/files', async (req, res) => {
    try { res.json({ path: req.query.path || '', items: await subsystem.listFiles(req.user.id, req.query.path) }); } 
    catch (e) { res.status(500).json({ error: 'Acesso negado ou pasta inexistente.' }); }
});

app.get('/api/files/read', async (req, res) => {
    try { res.json({ content: await subsystem.readFile(req.user.id, req.query.path) }); } 
    catch (e) { res.status(500).json({ error: 'Não foi possível ler o arquivo.' }); }
});

app.post('/api/files/save', async (req, res) => {
    try { await subsystem.writeFile(req.user.id, req.body.path, req.body.content); res.json({ success: true }); } 
    catch (e) { res.status(500).json({ error: 'Erro ao salvar.' }); }
});

app.post('/api/files/mkdir', async (req, res) => {
    try { await subsystem.createFolder(req.user.id, req.body.path, req.body.name); res.json({ success: true }); } 
    catch (e) { res.status(500).json({ error: 'Erro ao criar pasta.' }); }
});

app.post('/api/files/delete', async (req, res) => {
    try { await subsystem.deleteFile(req.user.id, req.body.path); res.json({ success: true }); } 
    catch (e) { res.status(500).json({ error: 'Erro ao mover para lixeira.' }); }
});

app.post('/api/files/upload', upload.array('files'), async (req, res) => {
    try {
        const targetDir = subsystem.getSecurePath(req.user.id, req.body.path);
        for (const file of req.files) {
            const dest = path.join(targetDir, file.originalname);
            await fs.promises.rename(file.path, dest);
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Falha no upload.' }); }
});

// System Monitor & OpSec APIs
app.get('/api/system/status', async (req, res) => {
    try { res.json(await subsystem.getSystemStatus(req.user.id)); } 
    catch (e) { res.status(500).json({ error: 'Erro ao ler sistema.' }); }
});

app.post('/api/tactical/anon', async (req, res) => {
    const { action } = req.body;
    let cmd = action === 'tor_on' ? 'sudo service tor start' : action === 'tor_off' ? 'sudo service tor stop' : null;
    if (!cmd) return res.status(400).json({ error: 'Ação inválida' });
    try { await subsystem.execCommand(req.user.id, cmd); res.json({ success: true }); } 
    catch (e) { res.status(500).json({ error: 'Erro WSL. Verifique permissões sudo do usuário cloudos.' }); }
});

// --- WebSocket (Terminal Seguro com JWT) ---
wss.on('connection', (ws, req) => {
    const token = new URL(req.url, 'http://localhost').searchParams.get('token');
    if (!token) return ws.close();
    
    jwt.verify(token, SECRET_KEY, (err, decoded) => {
        if (err) return ws.close();
        
        try {
            const ptyProcess = subsystem.startSession(decoded.id);
            ptyProcess.onData(data => ws.readyState === ws.OPEN && ws.send(data));
            ws.on('message', msg => {
                const str = msg.toString();
                if (str.startsWith('{"type":"resize"')) {
                    try { const d = JSON.parse(str); ptyProcess.resize(d.cols, d.rows); } catch {}
                } else { ptyProcess.write(msg); }
            });
            ws.on('close', () => ptyProcess.kill());
        } catch (e) { ws.close(); }
    });
});

server.listen(8080, () => console.log('🚀 CloudOS Enterprise Backend Rodando.'));
