const express = require('express');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// GET /api/reports/generate - Gera relatório completo em HTML ou Markdown puxando do SQLite
router.get('/reports/generate', authenticateToken, async (req, res) => {
  const format = req.query.format || 'html';
  const clientName = req.query.client || 'Cliente Corporativo';

  try {
    const db = req.app.get('db');
    const findings = await db.prepare('SELECT * FROM findings WHERE user_id = ? ORDER BY created_at DESC').all(req.user.id);
    const evidenceList = await db.prepare('SELECT id, project_id, filename, hash as sha256, created_at FROM evidence WHERE user_id = ?').all(req.user.id);

    const dateStr = new Date().toLocaleDateString('pt-BR');

    if (format === 'markdown') {
      let md = `# Relatório Executivo de Teste de Intrusão\n\n`;
      md += `**Cliente / Alvo:** ${clientName}\n`;
      md += `**Data da Emissão:** ${dateStr}\n\n`;
      md += `## 1. Resumo das Vulnerabilidades\n\n`;
      
      if (!findings || findings.length === 0) {
        md += `*Nenhuma vulnerabilidade cadastrada no sistema.*` + '\n';
      } else {
        findings.forEach((f, idx) => {
          md += `### 1.${idx + 1} ${f.title} [Severidade: ${f.severity.toUpperCase()}]\n`;
          md += `**Status:** ${f.status}\n\n`;
          md += `**Descrição Técnica:**\n${f.description || 'Sem descrição.'}\n\n`;
        });
      }

      md += `\n## 2. Cofre de Evidências Forenses (Cadeia de Custódia)\n\n`;
      if (!evidenceList || evidenceList.length === 0) {
        md += `*Nenhuma evidência anexada.*` + '\n';
      } else {
        evidenceList.forEach((e) => {
          md += `- **Arquivo:** \`${e.filename}\` | **Hash SHA256:** \`${e.sha256}\` | **Data:** ${e.created_at}\n`;
        });
      }

      return res.json({ success: true, format: 'markdown', report: md });
    }

    // Formato HTML Executivo com visualização gráfica elegante
    let html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Relatório de Penetration Testing - ${clientName}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #0d1117; color: #c9d1d9; padding: 40px; line-height: 1.6; }
    .container { max-width: 900px; margin: 0 auto; background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 32px; }
    h1 { color: #58a6ff; border-bottom: 1px solid #30363d; padding-bottom: 12px; }
    h2 { color: #f0f6fc; margin-top: 28px; border-bottom: 1px solid #21262d; padding-bottom: 8px; }
    .meta { font-size: 14px; color: #8b949e; margin-bottom: 24px; }
    .badge { padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 11px; text-transform: uppercase; }
    .critical { background: #f85149; color: white; }
    .high { background: #ff7b72; color: white; }
    .medium { background: #d29922; color: white; }
    .low { background: #58a6ff; color: white; }
    .finding-card { background: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 16px; margin-bottom: 16px; }
    .evidence-item { font-family: monospace; font-size: 12px; background: #0d1117; padding: 10px; border-radius: 4px; border: 1px solid #21262d; margin-bottom: 8px; word-break: break-all; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Relatório Executivo de Intrusão</h1>
    <div class="meta">
      <strong>Cliente/Alvo:</strong> ${clientName} | <strong>Data:</strong> ${dateStr} | <strong>Emissor:</strong> CloudOS Offensive Security
    </div>

    <h2>1. Resumo de Vulnerabilidades</h2>
`;

    if (!findings || findings.length === 0) {
      html += `<p style="color: #8b949e;">Nenhuma vulnerabilidade registrada.</p>`;
    } else {
      findings.forEach(f => {
        const sevClass = (f.severity || '').toLowerCase().includes('crít') ? 'critical' : 
                         (f.severity || '').toLowerCase().includes('alt') ? 'high' : 
                         (f.severity || '').toLowerCase().includes('méd') ? 'medium' : 'low';
        html += `
        <div class="finding-card">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <h3 style="margin: 0; font-size: 16px; color: #58a6ff;">${f.title}</h3>
            <span class="badge ${sevClass}">${f.severity}</span>
          </div>
          <p style="margin: 0; font-size: 13px; color: #c9d1d9;">${f.description || 'Sem descrição.'}</p>
        </div>
        `;
      });
    }

    html += `<h2>2. Cadeia de Custódia & Evidências (SHA256)</h2>`;
    if (!evidenceList || evidenceList.length === 0) {
      html += `<p style="color: #8b949e;">Nenhuma evidência forense cadastrada.</p>`;
    } else {
      evidenceList.forEach(e => {
        html += `
        <div class="evidence-item">
          <strong>Arquivo:</strong> ${e.filename}<br/>
          <span style="color: #58a6ff;">SHA256:</span> ${e.sha256}<br/>
          <span style="color: #3fb950;">Data de Coleta:</span> ${e.created_at}
        </div>
        `;
      });
    }

    html += `
  </div>
</body>
</html>`;

    res.json({ success: true, format: 'html', report: html });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
