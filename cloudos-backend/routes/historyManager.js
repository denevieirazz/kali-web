const express = require('express');
const router = express.Router();
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');

router.use(authenticateToken);

// Criar tabela se não existir
db.rawDb.serialize(() => {
  db.rawDb.run(`
    CREATE TABLE IF NOT EXISTS scan_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tool TEXT NOT NULL,
      target TEXT NOT NULL,
      status TEXT NOT NULL,
      result_json TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);
});

// POST /api/history - Salvar novo scan
router.post('/', (req, res) => {
  const { tool, target, status, result } = req.body;
  
  if (!tool || !target) {
    return res.status(400).json({ error: 'Ferramenta e alvo são obrigatórios' });
  }

  const result_json = JSON.stringify(result);
  
  db.rawDb.run(
    'INSERT INTO scan_history (tool, target, status, result_json) VALUES (?, ?, ?, ?)',
    [tool, target, status || 'success', result_json],
    function(err) {
      if (err) {
        console.error('[HistoryManager] Erro ao salvar:', err.message);
        return res.status(500).json({ error: 'Falha ao salvar histórico' });
      }
      res.json({ success: true, id: this.lastID });
    }
  );
});

// GET /api/history - Listar histórico (com filtro opcional por ferramenta)
router.get('/', (req, res) => {
  const { tool } = req.query;
  let query = 'SELECT id, tool, target, status, created_at FROM scan_history';
  let params = [];
  
  if (tool) {
    query += ' WHERE tool = ?';
    params.push(tool);
  }
  
  query += ' ORDER BY created_at DESC LIMIT 50';
  
  db.rawDb.all(query, params, (err, rows) => {
    if (err) {
      console.error('[HistoryManager] Erro ao buscar:', err.message);
      return res.status(500).json({ error: 'Falha ao buscar histórico' });
    }
    res.json({ success: true, history: rows || [] });
  });
});

// GET /api/history/:id - Buscar resultado completo de um scan específico
router.get('/:id', (req, res) => {
  const { id } = req.params;
  
  db.rawDb.get('SELECT * FROM scan_history WHERE id = ?', [id], (err, row) => {
    if (err) {
      console.error('[HistoryManager] Erro ao buscar detalhe:', err.message);
      return res.status(500).json({ error: 'Falha ao buscar detalhe' });
    }
    if (!row) {
      return res.status(404).json({ error: 'Registro não encontrado' });
    }
    
    res.json({
      success: true,
      data: {
        ...row,
        result: row.result_json ? JSON.parse(row.result_json) : null
      }
    });
  });
});

// DELETE /api/history/:id - Deletar um registro
router.delete('/:id', (req, res) => {
  const { id } = req.params;
  
  db.rawDb.run('DELETE FROM scan_history WHERE id = ?', [id], function(err) {
    if (err) {
      console.error('[HistoryManager] Erro ao deletar:', err.message);
      return res.status(500).json({ error: 'Falha ao deletar' });
    }
    res.json({ success: true });
  });
});

module.exports = router;
