const express = require('express');
const router = express.Router();

// Listar relatórios do usuário (opcionalmente filtrados por projeto)
router.get('/', async (req, res) => {
  const db = req.app.get('db');
  const { project_id } = req.query;
  try {
    let rows;
    if (project_id) {
      rows = await db.prepare(
        `SELECT id, project_id, title, created_at, updated_at
         FROM reports WHERE user_id = ? AND project_id = ?
         ORDER BY updated_at DESC`
      ).all(req.user.id, project_id);
    } else {
      rows = await db.prepare(
        `SELECT id, project_id, title, created_at, updated_at
         FROM reports WHERE user_id = ?
         ORDER BY updated_at DESC`
      ).all(req.user.id);
    }
    res.json(rows || []);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Obter relatório completo
router.get('/:id', async (req, res) => {
  const db = req.app.get('db');
  try {
    const row = await db.prepare(
      `SELECT * FROM reports WHERE id = ? AND user_id = ?`
    ).get(req.params.id, req.user.id);
    if (!row) return res.status(404).json({ error: 'Relatório não encontrado' });
    res.json(row);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Criar novo relatório
router.post('/', async (req, res) => {
  const db = req.app.get('db');
  const { project_id, title, content_md } = req.body;
  if (!title) return res.status(400).json({ error: 'Título obrigatório' });
  const id = 'r_' + require('crypto').randomBytes(4).toString('hex');
  try {
    await db.prepare(
      `INSERT INTO reports (id, user_id, project_id, title, content_md, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'))`
    ).run(id, req.user.id, project_id || '', title, content_md || '');
    res.json({ id });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Atualizar relatório (autosave)
router.put('/:id', async (req, res) => {
  const db = req.app.get('db');
  const { title, content_md, project_id } = req.body;
  try {
    const result = await db.prepare(
      `UPDATE reports
       SET title = COALESCE(?, title),
           content_md = COALESCE(?, content_md),
           project_id = COALESCE(?, project_id),
           updated_at = datetime('now')
       WHERE id = ? AND user_id = ?`
    ).run(title, content_md, project_id, req.params.id, req.user.id);
    if (result.changes === 0) return res.status(404).json({ error: 'Não encontrado' });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Deletar relatório
router.delete('/:id', async (req, res) => {
  const db = req.app.get('db');
  try {
    await db.prepare(`DELETE FROM reports WHERE id = ? AND user_id = ?`)
      .run(req.params.id, req.user.id);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
