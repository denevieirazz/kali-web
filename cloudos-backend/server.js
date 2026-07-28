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
const crypto = require('crypto');
const db = require('./database');

const app = express();
app.use(cors());
app.use(express.json());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });
const upload = multer({ dest: 'temp_uploads/' });

const SECRET_KEY = 'CLOUDOS_JWT_SECRET_2024';
const WSL_FS_ROOT = '\\\\wsl.localhost\\kali-linux';

// Inicializar Usuário Admin Padrão (se não existir no DB)
(async () => {
    try {
        const existingAdmin = await db.prepare('SELECT * FROM users WHERE username = ?').get('admin');
        if (!existingAdmin) {
            const adminId = 'u_1001';
            const hash = bcrypt.hashSync('admin123', 10);
            await db.prepare('INSERT INTO users (id, username, password_hash, tier) VALUES (?, ?, ?, ?)').run(adminId, 'admin', hash, 'pro');
            await db.prepare('INSERT OR IGNORE INTO user_settings (user_id) VALUES (?)').run(adminId);
            await db.prepare('INSERT OR IGNORE INTO desktop_state (user_id) VALUES (?)').run(adminId);
            console.log('✅ Admin padrão (admin/admin123) criado no Banco SQLite.');
        }
    } catch (e) {
        console.error('Erro ao verificar/criar admin:', e);
    }
})();

// =========================================================
// 🛡️ MIDDLEWARES E AUTH
// =========================================================
async function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Acesso negado. Token não fornecido.' });
    
    jwt.verify(token, SECRET_KEY, async (err, decoded) => {
        if (err) return res.status(403).json({ error: 'Token inválido ou expirado.' });
        
        try {
            // Suporte para tokens legados onde id era numérico (1) ou username era admin
            let userId = decoded.id;
            let dbUser = await db.prepare('SELECT * FROM users WHERE id = ?').get(String(userId));
            
            if (!dbUser && (decoded.username === 'admin' || String(userId) === '1')) {
                dbUser = await db.prepare('SELECT * FROM users WHERE username = ?').get('admin');
                if (dbUser) userId = dbUser.id;
            }
            
            if (!dbUser) {
                return res.status(401).json({ error: 'Sessão inválida. Faça login novamente.' });
            }
            
            req.user = { id: dbUser.id, username: dbUser.username, tier: dbUser.tier };
            next();
        } catch (e) {
            res.status(500).json({ error: 'Erro de validação de usuário.' });
        }
    });
}

app.post('/api/auth/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const user = await db.prepare('SELECT * FROM users WHERE username = ?').get(username);
        
        if (!user || !bcrypt.compareSync(password, user.password_hash)) {
            return res.status(401).json({ error: 'Credenciais inválidas.' });
        }
        
        const token = jwt.sign({ id: user.id, username: user.username, tier: user.tier }, SECRET_KEY, { expiresIn: '24h' });
        res.json({ token, user: { username: user.username, id: user.id, tier: user.tier } });
    } catch (e) {
        res.status(500).json({ error: 'Erro no servidor de autenticação.' });
    }
});

// Rota de Registro
app.post('/api/auth/register', async (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) return res.status(400).json({ error: 'Dados incompletos.' });
    
    const id = 'u_' + crypto.randomBytes(8).toString('hex');
    const hash = bcrypt.hashSync(password, 10);
    
    try {
        await db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(id, username, hash);
        await db.prepare('INSERT INTO user_settings (user_id) VALUES (?)').run(id);
        await db.prepare('INSERT INTO desktop_state (user_id) VALUES (?)').run(id);
        res.json({ success: true, message: 'Usuário criado.' });
    } catch (e) {
        res.status(400).json({ error: 'Usuário já existe.' });
    }
});

app.use(authenticateToken);

// =========================================================
// 🛡️ SUBSYSTEM MANAGER (WSL Controller)
// =========================================================
class SubsystemManager {
    constructor() {
        this.recentErrors = [];
    }

    logError(msg) {
        this.recentErrors.unshift({ time: new Date().toISOString(), msg: String(msg) });
        if (this.recentErrors.length > 10) this.recentErrors.pop();
    }

    getSecurePath(userId, requestedPath) {
        const safeUserId = String(userId).replace(/[^a-zA-Z0-9_]/g, '');
        const baseDir = path.join(WSL_FS_ROOT, 'home', 'cloudos_users', safeUserId);
        const resolved = path.resolve(baseDir, requestedPath || '');
        if (!resolved.startsWith(baseDir)) throw new Error("Path Traversal detectado.");
        return resolved;
    }

    toLinuxPath(winPath) { return winPath.replace(WSL_FS_ROOT, '').replace(/\\/g, '/'); }

    async execCommand(userId, command) {
        return new Promise((resolve, reject) => {
            exec(`wsl -d kali-linux -u cloudos -- bash -c "${command.replace(/"/g, '\\"')}"`, { windowsHide: true }, (error, stdout, stderr) => {
                if (error) { this.logError(stderr || error.message); return reject(stderr || error.message); }
                resolve(stdout);
            });
        });
    }

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
        const trashPath = this.getSecurePath(userId, '.trash');
        await fs.promises.mkdir(trashPath, { recursive: true });
        await fs.promises.rename(filePath, path.join(trashPath, path.basename(filePath)));
    }

    startSession(userId, cwd = null) {
        const sessionName = `cloudos_${userId}`;
        const linuxCwd = cwd ? this.toLinuxPath(this.getSecurePath(userId, cwd)) : '/home/cloudos_users/' + userId;
        return pty.spawn('wsl.exe', ['-d', 'kali-linux', '-u', 'cloudos', 'tmux', 'new-session', '-A', '-s', sessionName, '-c', linuxCwd, '-x', '80', '-y', '30'], {
            name: 'xterm-256color', cols: 80, rows: 30, cwd: process.env.HOME, env: process.env, useConpty: false
        });
    }

    async getSystemStatus(userId) {
        try {
            const cmd = `service tor status | grep -q 'active' && echo 'TOR:ACTIVE' || echo 'TOR:INACTIVE'; IFACE=$(ip route | grep default | awk '{print $5}' | head -n1); MAC=$(ip link show $IFACE | grep link/ether | awk '{print $2}'); echo 'MAC:'$MAC; df -h / | tail -1 | awk '{print "DISK:"$3"/"$2}'`;
            const stdout = await this.execCommand(userId, cmd);
            
            let mac = stdout.match(/MAC:(..:..:..:..:..:..)/)?.[1] || 'Indisponível';
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

// Garante que o usuário tenha a pasta home no WSL e configs no DB
app.use(async (req, res, next) => {
    try {
        const userHome = subsystem.getSecurePath(req.user.id, '');
        await fs.promises.mkdir(userHome, { recursive: true });
        await fs.promises.mkdir(path.join(userHome, '.trash'), { recursive: true });
        
        await db.prepare('INSERT OR IGNORE INTO user_settings (user_id) VALUES (?)').run(req.user.id);
        await db.prepare('INSERT OR IGNORE INTO desktop_state (user_id) VALUES (?)').run(req.user.id);
        next();
    } catch (e) { res.status(500).json({ error: "Erro ao inicializar ambiente do usuário." }); }
});

// =========================================================
// 🌐 API ROUTES
// =========================================================

// --- User Settings & Desktop State Persistence ---
app.get('/api/user/state', async (req, res) => {
    try {
        const settings = await db.prepare('SELECT * FROM user_settings WHERE user_id = ?').get(req.user.id);
        const desktop = await db.prepare('SELECT * FROM desktop_state WHERE user_id = ?').get(req.user.id);
        res.json({ settings: settings || {}, desktop: desktop || {} });
    } catch (e) { res.status(500).json({ error: 'Erro ao carregar estado do usuário.' }); }
});

app.post('/api/user/settings', async (req, res) => {
    const { wallpaper, theme } = req.body;
    try {
        await db.prepare('UPDATE user_settings SET wallpaper = ?, theme = ? WHERE user_id = ?').run(wallpaper, theme, req.user.id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao salvar configurações.' }); }
});

app.post('/api/user/desktop', async (req, res) => {
    const { icon_positions, open_windows, taskbar_pins } = req.body;
    try {
        await db.prepare('UPDATE desktop_state SET icon_positions = ?, open_windows = ?, taskbar_pins = ? WHERE user_id = ?')
          .run(JSON.stringify(icon_positions || {}), JSON.stringify(open_windows || []), JSON.stringify(taskbar_pins || []), req.user.id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao salvar estado do desktop.' }); }
});

// --- Notifications ---
app.get('/api/notifications', async (req, res) => {
    try {
        const notifs = await db.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 20').all(req.user.id);
        res.json(notifs || []);
    } catch (e) { res.status(500).json({ error: 'Erro ao listar notificações.' }); }
});

app.post('/api/notifications/read', async (req, res) => {
    try {
        await db.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?').run(req.user.id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao marcar notificações como lidas.' }); }
});

// --- File Manager APIs (Node FS Nativo) ---
app.get('/api/files', async (req, res) => {
    try { res.json({ path: req.query.path || '', items: await subsystem.listFiles(req.user.id, req.query.path) }); } 
    catch (e) { res.status(500).json({ error: 'Acesso negado.' }); }
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

app.get('/api/files/properties', async (req, res) => {
    try {
        const winPath = subsystem.getSecurePath(req.user.id, req.query.path);
        const stats = await fs.promises.stat(winPath);
        res.json({
            size: stats.size,
            isDirectory: stats.isDirectory(),
            modified: stats.mtime,
            created: stats.birthtime
        });
    } catch (e) { res.status(500).json({ error: 'Erro ao ler propriedades.' }); }
});

app.get('/api/files/download', async (req, res) => {
    try {
        const relPath = req.query.path;
        const winPath = subsystem.getSecurePath(req.user.id, relPath);
        const linuxPath = subsystem.toLinuxPath(winPath);
        
        res.setHeader('Content-Disposition', `attachment; filename="${path.basename(relPath)}.zip"`);
        res.setHeader('Content-Type', 'application/zip');
        
        const zipProcess = exec(`wsl -d kali-linux -u cloudos -- bash -c "cd '${path.dirname(linuxPath)}' && zip -r - '${path.basename(linuxPath)}'"`);
        zipProcess.stdout.pipe(res);
        zipProcess.stderr.on('data', (d) => console.error(d.toString()));
        zipProcess.on('close', () => res.end());
    } catch (e) { res.status(500).json({ error: 'Erro ao gerar ZIP.' }); }
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

// --- System & OpSec APIs ---
app.get('/api/system/status', async (req, res) => {
    try { res.json(await subsystem.getSystemStatus(req.user.id)); } 
    catch (e) { res.status(500).json({ error: 'Erro ao ler sistema.' }); }
});

app.post('/api/tactical/anon', async (req, res) => {
    const { action } = req.body;
    let cmd = action === 'tor_on' ? 'sudo service tor start' : action === 'tor_off' ? 'sudo service tor stop' : null;
    if (!cmd) return res.status(400).json({ error: 'Ação inválida' });
    try { await subsystem.execCommand(req.user.id, cmd); res.json({ success: true }); } 
    catch (e) { res.status(500).json({ error: 'Erro WSL.' }); }
});

// --- WebSocket (Terminal Seguro) ---
wss.on('connection', (ws, req) => {
    const token = new URL(req.url, 'http://localhost').searchParams.get('token');
    if (!token) return ws.close();
    
    jwt.verify(token, SECRET_KEY, async (err, decoded) => {
        if (err) return ws.close();
        try {
            let userId = decoded.id;
            let dbUser = await db.prepare('SELECT * FROM users WHERE id = ?').get(String(userId));
            if (!dbUser && (decoded.username === 'admin' || String(userId) === '1')) {
                dbUser = await db.prepare('SELECT * FROM users WHERE username = ?').get('admin');
                if (dbUser) userId = dbUser.id;
            }
            if (!dbUser) return ws.close();

            const ptyProcess = subsystem.startSession(userId);
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

server.listen(8080, () => console.log('🚀 CloudOS DB & SaaS Backend Rodando.'));
