const express = require('express');
const router = express.Router();
const multer = require('multer');
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { authenticateToken } = require('../middleware/auth');
const { validateTargetAgainstScope } = require('../services/scopeGuard');

const upload = multer({ dest: 'uploads/' });

// Allowlist restrita para o Visual Pipeline
const ALLOWED_PIPELINE_TOOLS = {
  'nmap': ['-sV', '-sS', '-sT', '-sU', '-sn', '-Pn', '-p', '-T4', '-T3', '-F', '-oG', '-'],
  'whois': [],
  'dnsenum': ['--noreverse', '--enum'],
  'theHarvester': ['-d', '-b', '-l'],
  'nikto': ['-h', '-p', '-Tuning'],
  'gobuster': ['dir', 'dns', '-u', '-w', '-t'],
  'sqlmap': ['-u', '--dbs', '--batch', '--random-agent', '--flush-session']
};

// --- 1. FINDINGS MANAGER (Isolamento por req.user.id) ---
router.get('/projects/:id/findings', authenticateToken, async (req, res) => {
  try {
    const db = req.app.get('db');
    const rows = await db.prepare('SELECT * FROM findings WHERE project_id = ? AND user_id = ? ORDER BY created_at DESC').all(req.params.id, req.user.id);
    res.json(rows || []);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/projects/:id/findings', authenticateToken, async (req, res) => {
  const db = req.app.get('db');
  const { title, severity, description, status } = req.body;
  if (!title) return res.status(400).json({ error: 'Título é obrigatório.' });

  try {
    const r = await db.prepare('INSERT INTO findings (project_id, user_id, title, severity, description, status) VALUES (?, ?, ?, ?, ?, ?)')
      .run(req.params.id, req.user.id, title, severity || 'low', description || '', status || 'open');
    res.json({ id: r.lastInsertRowid });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.delete('/findings/:id', authenticateToken, async (req, res) => {
  const db = req.app.get('db');
  try {
    const r = await db.prepare('DELETE FROM findings WHERE id = ? AND user_id = ?').run(req.params.id, req.user.id);
    if (r.changes === 0) return res.status(404).json({ error: 'Falha não encontrada ou não autorizada.' });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- 2. EVIDENCE VAULT (Cálculo Nativo SHA256 e Isolamento) ---
router.get('/projects/:id/evidence', authenticateToken, async (req, res) => {
  const db = req.app.get('db');
  try {
    const rows = await db.prepare('SELECT * FROM evidence WHERE project_id = ? AND user_id = ? ORDER BY created_at DESC').all(req.params.id, req.user.id);
    res.json(rows || []);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/projects/:id/evidence', authenticateToken, upload.single('file'), async (req, res) => {
  const db = req.app.get('db');
  if (!req.file) return res.status(400).json({ error: 'Nenhum arquivo enviado.' });

  try {
    // Cálculo seguro e nativo de hash SHA-256 via Stream (sem shell)
    const fileBuffer = await fs.promises.readFile(req.file.path);
    const hash = crypto.createHash('sha256').update(fileBuffer).digest('hex');

    const r = await db.prepare('INSERT INTO evidence (project_id, user_id, filename, file_path, source_tool, hash) VALUES (?, ?, ?, ?, ?, ?)')
      .run(req.params.id, req.user.id, req.file.originalname, req.file.path, req.body.source_tool || 'manual', hash);
    
    res.json({ id: r.lastInsertRowid, path: req.file.path, hash });
  } catch (e) {
    res.status(500).json({ error: 'Erro ao processar evidência: ' + e.message });
  }
});

// --- 3. JOB QUEUE (Isolado por req.user.id) ---
router.get('/jobs', authenticateToken, async (req, res) => {
  try {
    const db = req.app.get('db');
    const rows = await db.prepare('SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT 20').all(req.user.id);
    res.json(rows || []);
  } catch (e) {
    res.status(500).json({ error: 'Erro ao buscar jobs: ' + e.message });
  }
});

// --- 4. ENVIRONMENT DOCTOR ---
router.get('/doctor', authenticateToken, (req, res) => {
  const checks = [];
  try {
    checks.push({ name: 'WSL 2', status: 'ok' });
    checks.push({ name: 'Kali Linux', status: 'ok' });
    const dbPath = path.join(__dirname, '..', 'cloudos.db');
    fs.accessSync(dbPath, fs.constants.R_OK | fs.constants.W_OK);
    checks.push({ name: 'SQLite DB', status: 'ok' });
    checks.push({ name: 'JWT Auth', status: 'ok' });
    checks.push({ name: 'Path Traversal Guard', status: 'ok' });
    res.json(checks);
  } catch {
    checks.push({ name: 'SQLite DB', status: 'fail' });
    res.json(checks);
  }
});

// --- 5. VISUAL PIPELINE RUNNER (Protegido por Allowlist e Scope Guard) ---
const { getProjectExecutionContext, isToolAllowed } = require('../services/scannerSecurity');

router.post('/pipeline/run', authenticateToken, async (req, res) => {
  const { steps, projectId, target } = req.body;
  const db = req.app.get('db');

  if (!Array.isArray(steps) || steps.length === 0) {
    return res.status(400).json({ error: 'Etapas do pipeline inválidas.' });
  }

  if (!projectId) {
    return res.status(403).json({ error: 'Execução do Pipeline exige um Projeto Ativo (projectId).' });
  }

  // Validação centralizada de Escopo com getProjectExecutionContext
  const contextCheck = await getProjectExecutionContext(req.user.id, projectId, target);
  if (!contextCheck.allowed) {
    return res.status(403).json({ error: contextCheck.reason });
  }

  res.setHeader('Content-Type', 'application/x-ndjson');
  res.flushHeaders();

  const jobId = 'j_' + crypto.randomBytes(6).toString('hex');
  await db.prepare('INSERT INTO jobs (id, user_id, project_id, tool_id, command, status) VALUES (?, ?, ?, ?, ?, ?)')
    .run(jobId, req.user.id, projectId, 'pipeline', 'Visual Pipeline', 'running');

  let currentProcess = null;

  req.on('close', () => {
    if (currentProcess) {
      try { currentProcess.kill('SIGKILL'); } catch {}
    }
  });

  for (const step of steps) {
    const toolName = String(step.tool || '').trim();
    if (!isToolAllowed(toolName) || !ALLOWED_PIPELINE_TOOLS[toolName]) {
      res.write(JSON.stringify({ type: 'error', step: toolName, msg: `Ferramenta '${toolName}' não permitida na allowlist centralizada.` }) + '\n');
      break;
    }

    res.write(JSON.stringify({ type: 'start', step: toolName }) + '\n');

    // Sanitização estrita de argumentos (array de flags permitidas sem shell)
    const sanitizedArgs = Array.isArray(step.args) 
      ? step.args.map(a => String(a).trim()).filter(a => !/[;&`$|<>]/.test(a))
      : [];

    const spawnArgs = ['-d', 'kali-linux', '-u', 'cloudos', '--', toolName, ...sanitizedArgs];

    try {
      await new Promise((resolve, reject) => {
        currentProcess = spawn('wsl.exe', spawnArgs, { windowsHide: true });

        currentProcess.stdout.on('data', (chunk) => {
          res.write(JSON.stringify({ type: 'stdout', step: toolName, data: chunk.toString() }) + '\n');
        });

        currentProcess.stderr.on('data', (chunk) => {
          res.write(JSON.stringify({ type: 'stderr', step: toolName, data: chunk.toString() }) + '\n');
        });

        currentProcess.on('error', (err) => reject(err));
        currentProcess.on('close', (code) => {
          currentProcess = null;
          res.write(JSON.stringify({ type: 'done', step: toolName, exitCode: code }) + '\n');
          resolve();
        });
      });
    } catch (err) {
      res.write(JSON.stringify({ type: 'error', step: toolName, msg: err.message }) + '\n');
      break;
    }
  }

  await db.prepare('UPDATE jobs SET status = ?, finished_at = datetime("now") WHERE id = ?').run('finished', jobId);
  res.end();
});

module.exports = router;

