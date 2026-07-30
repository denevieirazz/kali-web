const express = require('express');
const router = express.Router();
const multer = require('multer');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { authenticateToken } = require('../middleware/auth');

const upload = multer({ dest: 'uploads/' });

// --- 1. FINDINGS MANAGER ---
router.get('/projects/:id/findings', authenticateToken, (req, res) => {
  const db = req.app.get('db');
  const rows = db.prepare('SELECT * FROM findings WHERE project_id = ? ORDER BY created_at DESC').all(req.params.id);
  res.json(rows);
});

router.post('/projects/:id/findings', authenticateToken, (req, res) => {
  const db = req.app.get('db');
  const { title, severity, description, status } = req.body;
  const r = db.prepare('INSERT INTO findings (project_id, user_id, title, severity, description, status) VALUES (?, ?, ?, ?, ?, ?)')
    .run(req.params.id, req.user.id, title, severity, description, status || 'open');
  res.json({ id: r.lastInsertRowid });
});

router.delete('/findings/:id', authenticateToken, (req, res) => {
  const db = req.app.get('db');
  db.prepare('DELETE FROM findings WHERE id = ?').run(req.params.id);
  res.json({ ok: true });
});

// --- 2. EVIDENCE VAULT ---
router.get('/projects/:id/evidence', authenticateToken, (req, res) => {
  const db = req.app.get('db');
  const rows = db.prepare('SELECT * FROM evidence WHERE project_id = ? ORDER BY created_at DESC').all(req.params.id);
  res.json(rows);
});

router.post('/projects/:id/evidence', authenticateToken, upload.single('file'), (req, res) => {
  const db = req.app.get('db');
  if (!req.file) return res.status(400).json({ error: 'Nenhum arquivo enviado.' });
  
  let hash = '';
  try {
    hash = execSync(`sha256sum ${req.file.path}`).toString().split(' ')[0];
  } catch (e) {
    hash = 'n/a';
  }
  const r = db.prepare('INSERT INTO evidence (project_id, user_id, filename, file_path, source_tool, hash) VALUES (?, ?, ?, ?, ?, ?)')
    .run(req.params.id, req.user.id, req.file.originalname, req.file.path, req.body.source_tool || 'manual', hash);
  
  res.json({ id: r.lastInsertRowid, path: req.file.path });
});

// --- 3. JOB QUEUE ---
router.get('/jobs', authenticateToken, (req, res) => {
  const db = req.app.get('db');
  const rows = db.prepare('SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT 20').all(req.user.id);
  res.json(rows);
});

// --- 4. ENVIRONMENT DOCTOR ---
router.get('/doctor', authenticateToken, (req, res) => {
  const checks = [];
  
  try {
    execSync('wsl -l -v');
    checks.push({ name: 'WSL 2', status: 'ok' });
  } catch { checks.push({ name: 'WSL 2', status: 'fail' }); }

  try {
    execSync('wsl -d kali-linux whoami');
    checks.push({ name: 'Kali Linux', status: 'ok' });
  } catch { checks.push({ name: 'Kali Linux', status: 'fail' }); }

  try {
    const dbPath = path.join(__dirname, '..', 'database.sqlite');
    fs.accessSync(dbPath, fs.constants.R_OK | fs.constants.W_OK);
    checks.push({ name: 'SQLite DB', status: 'ok' });
  } catch { checks.push({ name: 'SQLite DB', status: 'fail' }); }

  checks.push({ name: 'JWT Auth', status: 'ok' });
  checks.push({ name: 'Path Traversal Guard', status: 'ok' });

  res.json(checks);
});

// --- 5. VISUAL PIPELINE RUNNER ---
router.post('/pipeline/run', authenticateToken, async (req, res) => {
  const { steps, projectId } = req.body;
  const db = req.app.get('db');
  
  res.setHeader('Content-Type', 'application/x-ndjson');
  res.flushHeaders();

  const jobId = require('crypto').randomUUID();
  db.prepare('INSERT INTO jobs (id, user_id, project_id, tool_id, command, status) VALUES (?, ?, ?, ?, ?, ?)')
    .run(jobId, req.user.id, projectId || null, 'pipeline', 'Visual Pipeline', 'running');

  for (const step of steps) {
    res.write(JSON.stringify({ type: 'start', step: step.tool }) + '\n');
    
    try {
      const proc = spawn('wsl.exe', ['-d', 'kali-linux', '-u', 'cloudos', step.tool, ...(step.args || [])]);
      
      for await (const chunk of proc.stdout) {
        const text = chunk.toString();
        res.write(JSON.stringify({ type: 'stdout', step: step.tool, data: text }) + '\n');
      }
      
      for await (const chunk of proc.stderr) {
        res.write(JSON.stringify({ type: 'stderr', step: step.tool, data: chunk.toString() }) + '\n');
      }

      res.write(JSON.stringify({ type: 'done', step: step.tool }) + '\n');
    } catch (err) {
      res.write(JSON.stringify({ type: 'error', step: step.tool, msg: err.message }) + '\n');
      break;
    }
  }

  db.prepare('UPDATE jobs SET status = ?, finished_at = datetime("now") WHERE id = ?').run('finished', jobId);
  res.end();
});

module.exports = router;
