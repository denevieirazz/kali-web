const express = require('express');
const crypto = require('crypto');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// GET /api/findings - Lista todas as falhas do usuário
router.get('/findings', authenticateToken, async (req, res) => {
  try {
    const db = req.app.get('db');
    const rows = await db.prepare('SELECT * FROM findings WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id);
    res.json({ success: true, findings: rows || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/findings - Cria nova falha
router.post('/findings', authenticateToken, async (req, res) => {
  const { title, severity, description } = req.body;
  const projectId = req.body.project_id || 'default_project';
  
  try {
    const db = req.app.get('db');
    const r = await db.prepare('INSERT INTO findings (project_id, user_id, title, severity, description, status) VALUES (?, ?, ?, ?, ?, ?)')
      .run(projectId, req.user.id, title, severity || 'Média', description || '', 'open');
    res.json({ success: true, finding: { id: r.lastInsertRowid, title, severity, description, status: 'open' } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/findings/:id/evidence - Upload de evidência (Base64) com Hash SHA256 para cadeia de custódia
router.post('/findings/:id/evidence', authenticateToken, async (req, res) => {
  const { id } = req.params;
  const { filename, base64Data } = req.body;

  if (!filename || !base64Data) {
    return res.status(400).json({ success: false, error: 'Filename e Base64 são obrigatórios' });
  }

  try {
    const db = req.app.get('db');
    const base64Pure = base64Data.includes(',') ? base64Data.split(',')[1] : base64Data;
    const buffer = Buffer.from(base64Pure, 'base64');
    
    // Calcula o Hash SHA256 da evidência para cadeia de custódia forense
    const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
    
    const r = await db.prepare('INSERT INTO evidence (project_id, user_id, filename, file_path, source_tool, hash) VALUES (?, ?, ?, ?, ?, ?)')
      .run(String(id), req.user.id, filename, base64Data, 'base64_upload', sha256);
      
    res.json({ 
      success: true, 
      evidence: { id: r.lastInsertRowid, filename, sha256 }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Erro ao processar base64: ' + error.message });
  }
});

// GET /api/findings/:id/evidence - Lista evidências de uma falha
router.get('/findings/:id/evidence', authenticateToken, async (req, res) => {
  const { id } = req.params;
  try {
    const db = req.app.get('db');
    const rows = await db.prepare('SELECT id, project_id, filename, hash as sha256, created_at FROM evidence WHERE project_id = ? OR user_id = ?').all(String(id), req.user.id);
    res.json({ success: true, evidence: rows || [] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
