const express = require('express');
const router = express.Router();

router.get('/', async (req, res) => {
  const db = req.app.get('db');
  try {
    const rows = await db.prepare(
      `SELECT id, name, scope, created_at FROM snapshots WHERE user_id = ? ORDER BY created_at DESC`
    ).all(req.user.id);
    res.json(rows || []);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/:id', async (req, res) => {
  const db = req.app.get('db');
  try {
    const row = await db.prepare(`SELECT * FROM snapshots WHERE id = ? AND user_id = ?`)
      .get(req.params.id, req.user.id);
    if (!row) return res.status(404).json({ error: 'Não encontrado' });
    res.json(row);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/', async (req, res) => {
  const db = req.app.get('db');
  const { name, data } = req.body;
  if (!name) return res.status(400).json({ error: 'Nome obrigatório' });
  const id = 's_' + require('crypto').randomBytes(4).toString('hex');
  try {
    await db.prepare(
      `INSERT INTO snapshots (id, user_id, name, data, created_at)
       VALUES (?, ?, ?, ?, datetime('now'))`
    ).run(id, req.user.id, name, data || '{}');
    res.json({ id });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/:id/restore', async (req, res) => {
  const db = req.app.get('db');
  try {
    const snap = await db.prepare(`SELECT data FROM snapshots WHERE id = ? AND user_id = ?`)
      .get(req.params.id, req.user.id);
    if (!snap) return res.status(404).json({ error: 'Não encontrado' });
    
    await db.prepare(
      `INSERT INTO desktop_state (user_id, open_windows) VALUES (?, ?)
       ON CONFLICT(user_id) DO UPDATE SET open_windows = excluded.open_windows`
    ).run(req.user.id, snap.data);
    
    res.json({ ok: true, state: JSON.parse(snap.data || '{}') });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.delete('/:id', async (req, res) => {
  const db = req.app.get('db');
  try {
    await db.prepare(`DELETE FROM snapshots WHERE id = ? AND user_id = ?`)
      .run(req.params.id, req.user.id);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
