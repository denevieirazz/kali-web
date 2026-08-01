const express = require('express');
const { WebSocketServer } = require('ws');
const cors = require('cors');
const pty = require('node-pty');
const http = require('http');
const https = require('https');
const { exec, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('./database');
const systemMonitor = require('./services/systemMonitor');
const reportsRouter = require('./routes/reports');
const snapshotsRouter = require('./routes/snapshots');

const app = express();
app.set('db', db);
app.use(cors());
app.use(express.json());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });
const upload = multer({ dest: 'temp_uploads/' });

const SECRET_KEY = process.env.JWT_SECRET || 'cloudos_super_secret_jwt_key_2026';
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

    toLinuxPath(winPath) { return winPath.replace(/\\\\wsl\.localhost\\kali-linux/gi, '').replace(/\\/g, '/'); }

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
        
        // Se o arquivo JÁ ESTIVER na lixeira, deleta permanentemente do disco
        if (relPath.startsWith('.trash')) {
            const stats = await fs.promises.stat(filePath);
            if (stats.isDirectory()) {
                await fs.promises.rm(filePath, { recursive: true, force: true }); // Deleta pasta e conteúdo
            } else {
                await fs.promises.unlink(filePath); // Deleta arquivo
            }
        } else {
            // Se for um arquivo normal, move para a lixeira
            const trashPath = this.getSecurePath(userId, '.trash');
            await fs.promises.mkdir(trashPath, { recursive: true });
            await fs.promises.rename(filePath, path.join(trashPath, path.basename(filePath)));
        }
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

// Registra rotas V3 Enterprise, Process Manager, Network Manager, Findings Manager, Reports Manager, Environment Doctor, Metasploit RPC, Dashboard, Nmap Scanner, SQLmap, Hash Cracker, Msfvenom e OSINT Hub
app.use('/api/v3', require('./routes/v3'));
app.use('/api', require('./routes/processManager'));
app.use('/api', require('./routes/networkManager'));
app.use('/api', require('./routes/findingsManager'));
app.use('/api', require('./routes/reportsManager'));
app.use('/api/environment', require('./routes/environmentDoctor'));
app.use('/api/metasploit', require('./routes/metasploitManager'));
app.use('/api/dashboard', require('./routes/dashboardManager'));
app.use('/api/nmap', require('./routes/nmapManager'));
app.use('/api/sqlmap', require('./routes/sqlmapManager'));
app.use('/api/hashcracker', require('./routes/hashCrackerManager'));
app.use('/api/msfvenom', require('./routes/msfvenomManager'));
app.use('/api/osint', require('./routes/osintManager'));
app.use('/api/history', require('./routes/historyManager'));
app.use('/payloads', express.static(path.join(__dirname, 'public', 'payloads')));

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
    try { 
        await subsystem.createFolder(req.user.id, req.body.path, req.body.name); 
        res.json({ success: true }); 
    } catch (e) {
        console.error("ERRO REAL NO MKDIR:", e.message);
        res.status(500).json({ error: 'Erro ao criar pasta.' }); 
    }
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
// =========================================================
// 📊 WORKSPACE & SNAPSHOT APIs
// =========================================================
async function logEvent(userId, type, details) {
    try {
        const id = 'e_' + crypto.randomBytes(4).toString('hex');
        await db.prepare('INSERT INTO system_events (id, user_id, event_type, details) VALUES (?, ?, ?, ?)').run(id, userId, type, details);
    } catch (e) { console.error('Erro ao salvar evento:', e); }
}

app.get('/api/workspaces', async (req, res) => {
    try {
        const workspaces = await db.prepare('SELECT * FROM workspaces WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id);
        res.json(workspaces || []);
    } catch (e) { res.status(500).json({ error: 'Erro ao listar workspaces.' }); }
});

app.post('/api/workspaces/save', async (req, res) => {
    const { name, state } = req.body;
    const id = 'w_' + crypto.randomBytes(4).toString('hex');
    try {
        await db.prepare('INSERT INTO workspaces (id, user_id, name, state) VALUES (?, ?, ?, ?)').run(id, req.user.id, name, JSON.stringify(state || {}));
        await logEvent(req.user.id, 'workspace_save', `Workspace '${name}' salvo.`);
        res.json({ success: true, id });
    } catch (e) { res.status(500).json({ error: 'Erro ao salvar workspace.' }); }
});

app.post('/api/snapshots/create', async (req, res) => {
    const { name, description, state } = req.body;
    const snapName = name || description || `Snapshot ${new Date().toLocaleTimeString('pt-BR')}`;
    const id = 's_' + crypto.randomBytes(4).toString('hex');
    try {
        await db.prepare('INSERT INTO snapshots (id, user_id, name, data) VALUES (?, ?, ?, ?)').run(id, req.user.id, snapName, JSON.stringify(state || {}));
        await logEvent(req.user.id, 'snapshot_create', `Snapshot '${snapName}' criado.`);
        res.json({ success: true, id });
    } catch (e) { res.status(500).json({ error: 'Erro ao criar snapshot.' }); }
});

app.get('/api/snapshots', async (req, res) => {
    try {
        const snaps = await db.prepare('SELECT id, name, created_at FROM snapshots WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id);
        res.json(snaps || []);
    } catch (e) { res.status(500).json({ error: 'Erro ao listar snapshots.' }); }
});

// =========================================================
// 📜 EVENT CENTER APIs
// =========================================================
app.get('/api/events', async (req, res) => {
    try {
        const events = await db.prepare('SELECT * FROM system_events WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').all(req.user.id);
        res.json(events || []);
    } catch (e) { res.status(500).json({ error: 'Erro ao listar eventos.' }); }
});

// =========================================================
// 🗂️ FILE METADATA APIs (Favoritos, Tags)
// =========================================================
app.post('/api/files/favorite', async (req, res) => {
    const { path: filePath, favorite } = req.body;
    try {
        const favVal = favorite ? 1 : 0;
        const existing = await db.prepare('SELECT * FROM file_metadata WHERE user_id = ? AND file_path = ?').get(req.user.id, filePath);
        if (existing) {
            await db.prepare('UPDATE file_metadata SET is_favorite = ? WHERE user_id = ? AND file_path = ?').run(favVal, req.user.id, filePath);
        } else {
            await db.prepare('INSERT INTO file_metadata (user_id, file_path, is_favorite) VALUES (?, ?, ?)').run(req.user.id, filePath, favVal);
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao atualizar favorito.' }); }
});

app.get('/api/files/favorites', async (req, res) => {
    try {
        const favs = await db.prepare('SELECT file_path FROM file_metadata WHERE user_id = ? AND is_favorite = 1').all(req.user.id);
        res.json((favs || []).map(f => f.file_path));
    } catch (e) { res.status(500).json({ error: 'Erro ao obter favoritos.' }); }
});

// =========================================================
// 📦 APP STORE APIs
// =========================================================
app.get('/api/apps', async (req, res) => {
    try {
        const apps = await db.prepare('SELECT app_id, is_pinned FROM installed_apps WHERE user_id = ?').all(req.user.id);
        res.json(apps || []);
    } catch (e) { res.status(500).json({ error: 'Erro ao listar apps.' }); }
});

app.post('/api/apps/toggle', async (req, res) => {
    const { app_id, is_pinned } = req.body;
    try {
        const pinnedVal = is_pinned ? 1 : 0;
        const existing = await db.prepare('SELECT * FROM installed_apps WHERE user_id = ? AND app_id = ?').get(req.user.id, app_id);
        if (existing) {
            await db.prepare('UPDATE installed_apps SET is_pinned = ? WHERE user_id = ? AND app_id = ?').run(pinnedVal, req.user.id, app_id);
        } else {
            await db.prepare('INSERT INTO installed_apps (user_id, app_id, is_pinned) VALUES (?, ?, ?)').run(req.user.id, app_id, pinnedVal);
        }
        await logEvent(req.user.id, 'app_toggle', `App ${app_id} fixado: ${is_pinned}`);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao alterar app.' }); }
});

app.post('/api/apps/uninstall', async (req, res) => {
    try {
        await db.prepare('DELETE FROM installed_apps WHERE user_id = ? AND app_id = ?').run(req.user.id, req.body.app_id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ error: 'Erro ao desinstalar app.' }); }
});

// =========================================================
// 🛠️ KALI HUB - CATÁLOGO E ROTAS SEGURAS
// =========================================================
const TOOL_SCHEMAS = require('./kali_tools_schema');

// Rota: Obter Schema da GUI de uma ferramenta
app.get('/api/kali/tools/:id/schema', (req, res) => {
    const schema = TOOL_SCHEMAS[req.params.id];
    if (!schema) return res.status(404).json({ error: "Schema não encontrado para esta ferramenta." });
    res.json(schema);
});

// Mapa de processos rodando (para o botão Stop)
const runningProcesses = new Map();

// Função de Escape para evitar Injeção de Shell (Regra de Ouro)
function escapeShellArg(arg) {
    return `'${String(arg).replace(/'/g, "'\\''")}'`;
}

// Rota: Executar Ferramenta com Streaming e Array Seguro
app.post('/api/kali/tools/:id/run', async (req, res) => {
    const schema = TOOL_SCHEMAS[req.params.id];
    if (!schema) return res.status(404).json({ error: "Ferramenta inválida." });

    const options = req.body.options || {};

    // 1. PRE-CHECK: A ferramenta está instalada?
    try {
        await subsystem.execCommand(req.user.id, `command -v ${schema.command}`);
    } catch (e) {
        return res.status(400).json({ 
            error: `A ferramenta '${schema.name}' não está instalada no WSL Kali.`,
            installCmd: schema.installCmd 
        });
    }

    // 2. MONTAGEM DO ARRAY DE ARGUMENTOS (BLINDAGEM TOTAL CONTRA INJEÇÃO)
    const args = ['-d', 'kali-linux', '-u', 'cloudos', '--', schema.command];

    if (schema.command === 'msfconsole') {
        const tempDir = path.join(subsystem.getSecurePath(req.user.id, ''), '.cloudos_temp');
        await fs.promises.mkdir(tempDir, { recursive: true });
        const rcFileWin = path.join(tempDir, `msf_${Date.now()}.rc`);
        const rawScript = options.resource_script || 'version\nexit\n';
        const safeScript = rawScript.split('\n')
            .map(l => l.trim())
            .filter(l => l && !l.startsWith('!') && !/^shell\b/.test(l))
            .join('\n') + '\nexit\n';
        await fs.promises.writeFile(rcFileWin, safeScript);
        const rcFileLinux = subsystem.toLinuxPath(rcFileWin);
        args.push('-r', rcFileLinux);
        if (options.quiet !== false) args.push('-q');
    } else {
        for (const field of schema.fields) {
            const val = options[field.id];
            if (!val) continue;

            if (field.type === 'boolean' && val === true) {
                if (field.flag) args.push(field.flag);
            } else if (field.type === 'textarea' && val) {
                const tempDir = path.join(subsystem.getSecurePath(req.user.id, ''), '.cloudos_temp');
                await fs.promises.mkdir(tempDir, { recursive: true });
                const tempFileWin = path.join(tempDir, `input_${Date.now()}.txt`);
                
                await fs.promises.writeFile(tempFileWin, val);
                const tempFileLinux = subsystem.toLinuxPath(tempFileWin);
                if (field.flag) args.push(field.flag);
                args.push(tempFileLinux);
            } else if ((field.type === 'text' || field.type === 'select') && val) {
                if (field.flag) args.push(field.flag);
                args.push(String(val));
            }
        }
    }

    logEvent(req.user.id, 'tool_execute', `Executou: ${schema.command} (Blindado)`);
    
    // Configura headers para streaming
    const runId = 'r_' + crypto.randomBytes(4).toString('hex');
    res.setHeader('Content-Type', 'text/plain');
    res.setHeader('Transfer-Encoding', 'chunked');
    res.setHeader('X-Run-Id', runId);

    // 3. EXECUÇÃO COM SPAWN (SEM SHELL = SEM INJEÇÃO)
    const toolProcess = spawn('wsl.exe', args, { windowsHide: true });
    runningProcesses.set(runId, toolProcess);
    
    toolProcess.stdout.on('data', (data) => res.write(data));
    toolProcess.stderr.on('data', (data) => res.write(data));
    
    toolProcess.on('close', () => {
        runningProcesses.delete(runId);
        res.end();
    });
});

// Rota: Interromper Scan
app.post('/api/kali/tools/stop', (req, res) => {
    const { runId } = req.body;
    if (runningProcesses.has(runId)) {
        runningProcesses.get(runId).kill('SIGKILL');
        runningProcesses.delete(runId);
        logEvent(req.user.id, 'tool_stop', `Scan ${runId} interrompido.`);
        return res.json({ success: true });
    }
    res.status(404).json({ error: "Processo não encontrado." });
});
const KALI_CATALOG = [
    { id: "nmap", name: "Nmap", packageName: "nmap", command: "nmap", category: "recon", description: "Network discovery and security auditing tool.", icon: "Radar", tags: ["network", "discovery"], riskLevel: "medium" },
    { id: "wireshark", name: "Wireshark", packageName: "wireshark", command: "wireshark", category: "network", description: "Network protocol analyzer.", icon: "Activity", tags: ["network", "packets"], riskLevel: "safe" },
    { id: "burpsuite", name: "Burp Suite", packageName: "burpsuite", command: "burpsuite", category: "web", description: "Web application security testing platform.", icon: "Bug", tags: ["web", "proxy"], riskLevel: "restricted" },
    { id: "sqlmap", name: "SQLMap", packageName: "sqlmap", command: "sqlmap", category: "web", description: "Database security testing utility.", icon: "Database", tags: ["web", "database"], riskLevel: "restricted" },
    { id: "metasploit", name: "Metasploit", packageName: "metasploit-framework", command: "msfconsole", category: "vuln", description: "Penetration testing framework.", icon: "Rocket", tags: ["exploit", "framework"], riskLevel: "restricted" },
    { id: "john", name: "John the Ripper", packageName: "john", command: "john", category: "password", description: "Password audit and recovery tool.", icon: "KeyRound", tags: ["password", "audit"], riskLevel: "restricted" },
    { id: "hashcat", name: "Hashcat", packageName: "hashcat", command: "hashcat", category: "password", description: "Password recovery and hash auditing.", icon: "Hash", tags: ["hash", "password"], riskLevel: "restricted" },
    { id: "aircrack", name: "Aircrack-ng", packageName: "aircrack-ng", command: "aircrack-ng", category: "wireless", description: "WiFi security auditing tools.", icon: "Wifi", tags: ["wifi", "wireless"], riskLevel: "restricted" },
    { id: "nikto", name: "Nikto", packageName: "nikto", command: "nikto", category: "web", description: "Web server scanner.", icon: "Eye", tags: ["web", "scanner"], riskLevel: "medium" },
    { id: "gobuster", name: "Gobuster", packageName: "gobuster", command: "gobuster", category: "recon", description: "Directory/file/DNS brute-forcer.", icon: "FolderSearch", tags: ["web", "brute"], riskLevel: "medium" }
];

app.get('/api/kali/tools', (req, res) => {
    res.json(KALI_CATALOG.map(t => ({ ...t, status: "checking" })));
});

app.get('/api/kali/tools/status', async (req, res) => {
    try {
        const cmds = KALI_CATALOG.map(t => `command -v ${t.command} >/dev/null 2>&1 && echo "${t.id}:installed" || echo "${t.id}:missing"`).join('; ');
        const stdout = await subsystem.execCommand(req.user.id, cmds);
        
        const statuses = {};
        (stdout || '').split('\n').forEach(line => {
            const [id, status] = line.trim().split(':');
            if (id && status) statuses[id] = status;
        });
        res.json(statuses);
    } catch (e) { res.status(500).json({ error: "Erro ao checar ferramentas no WSL." }); }
});

app.get('/api/kali/tools/favorites', async (req, res) => {
    try {
        const favs = await db.prepare('SELECT tool_id FROM kali_tool_favorites WHERE user_id = ?').all(req.user.id);
        res.json((favs || []).map(f => f.tool_id));
    } catch (e) { res.status(500).json({ error: 'Erro ao listar favoritos.' }); }
});

app.post('/api/kali/tools/:id/favorite', async (req, res) => {
    const toolId = req.params.id;
    try {
        const exists = await db.prepare('SELECT 1 FROM kali_tool_favorites WHERE user_id = ? AND tool_id = ?').get(req.user.id, toolId);
        if (exists) {
            await db.prepare('DELETE FROM kali_tool_favorites WHERE user_id = ? AND tool_id = ?').run(req.user.id, toolId);
        } else {
            await db.prepare('INSERT INTO kali_tool_favorites (user_id, tool_id) VALUES (?, ?)').run(req.user.id, toolId);
        }
        res.json({ success: true, isFavorite: !exists });
    } catch (e) { res.status(500).json({ error: 'Erro ao favoritar.' }); }
});

app.post('/api/kali/tools/:id/open', async (req, res) => {
    const tool = KALI_CATALOG.find(t => t.id === req.params.id);
    if (!tool) return res.status(404).json({ error: "Ferramenta não encontrada no catálogo." });
    
    try {
        const existing = await db.prepare('SELECT * FROM kali_tool_recent WHERE user_id = ? AND tool_id = ?').get(req.user.id, tool.id);
        if (existing) {
            await db.prepare('UPDATE kali_tool_recent SET opened_at = CURRENT_TIMESTAMP WHERE user_id = ? AND tool_id = ?').run(req.user.id, tool.id);
        } else {
            await db.prepare('INSERT INTO kali_tool_recent (user_id, tool_id) VALUES (?, ?)').run(req.user.id, tool.id);
        }
        await logEvent(req.user.id, 'kali_tool_open', `Ferramenta ${tool.name} selecionada para uso.`);
        res.json({ success: true, command: tool.command });
    } catch (e) { res.status(500).json({ error: 'Erro ao abrir ferramenta.' }); }
});

// =========================================================
// 🎯 GESTÃO DE PROJETOS (SCOPE MANAGER)
// =========================================================
app.post('/api/projects', async (req, res) => {
    const { name, scope } = req.body;
    const id = 'p_' + crypto.randomBytes(4).toString('hex');
    await db.prepare('INSERT INTO projects (id, user_id, name, scope) VALUES (?, ?, ?, ?)').run(id, req.user.id, name, scope || '');
    logEvent(req.user.id, 'project_create', `Projeto '${name}' criado.`);
    res.json({ success: true, id });
});

app.get('/api/projects', async (req, res) => {
    const projects = await db.prepare('SELECT * FROM projects WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id);
    res.json(projects);
});

// =========================================================
// 📄 GERADOR DE RELATÓRIOS (MARKDOWN)
// =========================================================
app.get('/api/reports/:projectId', async (req, res) => {
    const reports = await db.prepare('SELECT * FROM reports WHERE project_id = ? ORDER BY created_at DESC').all(req.params.projectId);
    res.json(reports);
});

app.post('/api/reports/save', async (req, res) => {
    const { projectId, title, content_md } = req.body;
    const id = 'r_' + crypto.randomBytes(4).toString('hex');
    await db.prepare('INSERT INTO reports (id, project_id, title, content_md) VALUES (?, ?, ?, ?)').run(id, projectId, title, content_md);
    res.json({ success: true, id });
});

// =========================================================
// 🔗 PIPELINE DE AUTOMAÇÃO (CHAIN RUNNER)
// =========================================================
app.post('/api/pipeline/recon', async (req, res) => {
    const { domain } = req.body;
    const safeDomain = String(domain || '').replace(/[^a-zA-Z0-9.-]/g, '');
    if (!safeDomain) return res.status(400).json({ error: "Domínio inválido." });

    res.setHeader('Content-Type', 'text/plain');
    res.setHeader('Transfer-Encoding', 'chunked');

    const sendLog = (msg) => res.write(`\n[*] ${msg}\n`);
    const userTempDir = path.join(subsystem.getSecurePath(req.user.id, ''), '.cloudos_temp');
    await fs.promises.mkdir(userTempDir, { recursive: true });

    try {
        // 1. Subfinder
        sendLog(`Iniciando Subfinder para ${safeDomain}...`);
        let subfinderOut = '';
        try {
            subfinderOut = await subsystem.execCommand(req.user.id, `subfinder -d ${safeDomain} -silent 2>/dev/null`);
        } catch (e) {
            subfinderOut = `${safeDomain}\n127.0.0.1`;
        }
        if (!subfinderOut.trim()) subfinderOut = `${safeDomain}\n127.0.0.1`;
        const subsFile = path.join(userTempDir, 'subs.txt');
        await fs.promises.writeFile(subsFile, subfinderOut);
        const subCount = subfinderOut.trim().split('\n').filter(Boolean).length;
        sendLog(`Encontrados ${subCount} subdomínios.`);

        // 2. Httpx (ou httpx-toolkit)
        sendLog(`Validando hosts com Httpx...`);
        let httpxCmd = 'httpx';
        try {
            await subsystem.execCommand(req.user.id, 'command -v httpx-toolkit');
            httpxCmd = 'httpx-toolkit';
        } catch {}

        const httpxOut = await subsystem.execCommand(req.user.id, `${httpxCmd} -l ${subsystem.toLinuxPath(subsFile)} -status-code -title -silent 2>/dev/null`);
        const aliveFile = path.join(userTempDir, 'alive.txt');
        await fs.promises.writeFile(aliveFile, httpxOut || subfinderOut);
        res.write(`\n--- HOSTS VIVOS ---\n${httpxOut || subfinderOut}\n-------------------\n`);
        sendLog(`Hosts ativos salvos.`);

        // 3. Nmap (Top 100 ports nos hosts vivos)
        sendLog(`Iniciando Nmap nos hosts ativos...`);
        const nmapOut = await subsystem.execCommand(req.user.id, `nmap -iL ${subsystem.toLinuxPath(aliveFile)} -T4 -F 2>/dev/null`);
        res.write(`\n--- NMAP SCAN ---\n${nmapOut}\n-----------------\n`);
        
        sendLog(`Pipeline de Recon concluído com sucesso!`);
    } catch (e) {
        res.write(`\n[ERRO NO PIPELINE] ${e.message || 'Erro ao executar comandos'}\n`);
    }
    res.end();
});

// =========================================================
// 🔄 HTTP REPEATER & DECODER
// =========================================================
app.post('/api/repeater/send', (req, res) => {
    const { rawRequest } = req.body;
    try {
        const lines = rawRequest.split('\n');
        const firstLine = lines[0].trim().split(' ');
        const method = firstLine[0] || 'GET';
        const pathStr = firstLine[1] || '/';
        
        const hostLine = lines.find(l => l.toLowerCase().startsWith('host:'));
        let host = 'localhost';
        let port = 80;
        if (hostLine) {
            const hostValue = hostLine.substring(hostLine.indexOf(':') + 1).trim();
            if (hostValue.includes(':')) {
                const parts = hostValue.split(':');
                host = parts[0];
                port = parseInt(parts[1], 10);
            } else {
                host = hostValue;
            }
        }
        
        const isHttps = rawRequest.toLowerCase().includes('https') || port === 443;
        if (isHttps && port === 80) port = 443;

        const options = {
            hostname: host,
            port: port,
            path: pathStr,
            method: method,
            headers: {}
        };

        let bodyStart = false;
        let body = '';
        for (let i = 1; i < lines.length; i++) {
            if (lines[i].trim() === '') { bodyStart = true; continue; }
            if (bodyStart) { body += lines[i] + '\n'; }
            else {
                const [key, ...val] = lines[i].split(':');
                if (key && val.length) options.headers[key.trim()] = val.join(':').trim();
            }
        }

        const httpModule = isHttps ? https : http;
        const proxyReq = httpModule.request(options, (proxyRes) => {
            let responseData = `HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage}\n`;
            Object.keys(proxyRes.headers).forEach(key => responseData += `${key}: ${proxyRes.headers[key]}\n`);
            responseData += `\n`;
            proxyRes.on('data', chunk => responseData += chunk.toString());
            proxyRes.on('end', () => res.json({ success: true, response: responseData }));
        });
        
        proxyReq.on('error', e => res.status(500).json({ error: e.message }));
        if (body.trim()) proxyReq.write(body.trim());
        proxyReq.end();
    } catch (e) { res.status(500).json({ error: "Formato HTTP inválido." }); }
});

app.use('/api/v2/reports', authenticateToken, reportsRouter);
app.use('/api/snapshots', authenticateToken, snapshotsRouter);

// --- WebSocket (Terminal Seguro & System Monitor) ---
const sysmonClients = new Set();
setInterval(() => {
    if (sysmonClients.size === 0) return;
    const data = JSON.stringify({ type: 'sysmon', payload: systemMonitor.snapshot() });
    for (const client of sysmonClients) {
        if (client.readyState === 1) client.send(data);
    }
}, 1500);

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
                } else if (str.includes('"channel":"sysmon"')) {
                    try {
                        const m = JSON.parse(str);
                        if (m.type === 'subscribe') sysmonClients.add(ws);
                        if (m.type === 'unsubscribe') sysmonClients.delete(ws);
                    } catch {}
                } else { ptyProcess.write(msg); }
            });
            ws.on('close', () => {
                sysmonClients.delete(ws);
                ptyProcess.kill();
            });
        } catch (e) { ws.close(); }
    });
});

server.listen(8080, () => console.log('🚀 CloudOS DB & SaaS Backend Rodando.'));
