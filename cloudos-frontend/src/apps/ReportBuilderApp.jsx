import React, { useState, useRef, useCallback } from 'react';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';
import './ReportBuilderApp.css';

const SEVERITY_COLORS = {
  critical: { bg: '#dc3545', text: '#fff', label: 'Crítico' },
  high: { bg: '#fd7e14', text: '#000', label: 'Alto' },
  medium: { bg: '#ffc107', text: '#000', label: 'Médio' },
  low: { bg: '#0dcaf0', text: '#000', label: 'Baixo' },
  info: { bg: '#6c757d', text: '#fff', label: 'Informativo' }
};

const INITIAL_FINDING = {
  id: '',
  title: '',
  severity: 'medium',
  cvss: '',
  description: '',
  impact: '',
  remediation: '',
  references: ''
};

const ReportBuilderApp = () => {
  const [projectName, setProjectName] = useState('Pentest Report');
  const [clientName, setClientName] = useState('');
  const [date, setDate] = useState(new Date().toISOString().split('T')[0]);
  const [executiveSummary, setExecutiveSummary] = useState('');
  const [scope, setScope] = useState('');
  const [methodology, setMethodology] = useState('');
  const [findings, setFindings] = useState([]);
  const [conclusion, setConclusion] = useState('');
  const [currentFinding, setCurrentFinding] = useState({ ...INITIAL_FINDING });
  const [editingIndex, setEditingIndex] = useState(-1);
  const [showPreview, setShowPreview] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  const [exportStatus, setExportStatus] = useState('');
  const previewRef = useRef(null);

  // Adicionar ou atualizar finding
  const handleSaveFinding = () => {
    if (!currentFinding.title.trim()) return;
    const newFinding = {
      ...currentFinding,
      id: currentFinding.id || Date.now().toString(36),
      date: new Date().toISOString()
    };
    let updated;
    if (editingIndex >= 0) {
      updated = [...findings];
      updated[editingIndex] = newFinding;
    } else {
      updated = [...findings, newFinding];
    }
    setFindings(updated);
    setCurrentFinding({ ...INITIAL_FINDING });
    setEditingIndex(-1);
  };

  // Editar finding existente
  const handleEditFinding = (index) => {
    setCurrentFinding({ ...findings[index] });
    setEditingIndex(index);
  };

  // Remover finding
  const handleRemoveFinding = (index) => {
    const updated = findings.filter((_, i) => i !== index);
    setFindings(updated);
    if (editingIndex === index) {
      setCurrentFinding({ ...INITIAL_FINDING });
      setEditingIndex(-1);
    }
  };

  // Gerar gráfico de severidade (barras horizontais)
  const renderSeverityChart = () => {
    const counts = { critical: 0, high: 0, medium: 0, low: 0, info: 0 };
    (findings || []).forEach(f => {
      if (counts[f.severity] !== undefined) counts[f.severity]++;
    });
    const maxCount = Math.max(...Object.values(counts), 1);
    return (
      <div className="rb-chart">
        <h4>Distribuição de Severidade</h4>
        {Object.entries(counts).map(([sev, count]) => {
          const width = (count / maxCount) * 100;
          const color = SEVERITY_COLORS[sev];
          return (
            <div key={sev} className="rb-chart-row">
              <span className="rb-chart-label" style={{ color: color.bg }}>
                {color.label}
              </span>
              <div className="rb-chart-bar-track">
                <div
                  className="rb-chart-bar-fill"
                  style={{ width: `${width}%`, backgroundColor: color.bg }}
                />
              </div>
              <span className="rb-chart-count">{count}</span>
            </div>
          );
        })}
      </div>
    );
  };

  // Preview do relatório completo
  const renderPreview = () => {
    return (
      <div className="rb-preview-overlay" onClick={() => setShowPreview(false)}>
        <div className="rb-preview-container" onClick={e => e.stopPropagation()} ref={previewRef}>
          <div className="rb-preview-header">
            <h2>📄 Pré-visualização do Relatório</h2>
            <button className="rb-btn-close" onClick={() => setShowPreview(false)}>✕</button>
          </div>
          <div className="rb-preview-content" id="report-pdf-content">
            {/* Capa */}
            <div className="rb-pdf-cover">
              <div className="rb-pdf-cover-badge">☁️ CloudOS Pentest</div>
              <h1 className="rb-pdf-title">{projectName || 'Relatório de Pentest'}</h1>
              <div className="rb-pdf-cover-meta">
                <div><strong>Cliente:</strong> {clientName || 'N/A'}</div>
                <div><strong>Data:</strong> {new Date(date).toLocaleDateString('pt-BR')}</div>
                <div><strong>Classificação:</strong> Confidencial</div>
              </div>
            </div>

            {/* Resumo Executivo */}
            <div className="rb-pdf-section">
              <h3>1. Resumo Executivo</h3>
              <p>{executiveSummary || 'Não informado.'}</p>
            </div>

            {/* Escopo */}
            <div className="rb-pdf-section">
              <h3>2. Escopo do Teste</h3>
              <p>{scope || 'Não informado.'}</p>
            </div>

            {/* Metodologia */}
            <div className="rb-pdf-section">
              <h3>3. Metodologia</h3>
              <p>{methodology || 'Não informado.'}</p>
            </div>

            {/* Gráfico de Severidade */}
            {findings.length > 0 && (
              <div className="rb-pdf-section">
                <h3>4. Resumo de Vulnerabilidades</h3>
                {renderSeverityChart()}
              </div>
            )}

            {/* Achados Detalhados */}
            <div className="rb-pdf-section">
              <h3>{findings.length > 0 ? '5. Achados Detalhados' : '4. Achados'}</h3>
              {findings.length === 0 ? (
                <p className="rb-empty">Nenhuma vulnerabilidade cadastrada.</p>
              ) : (
                findings.map((f, i) => (
                  <div key={f.id} className="rb-pdf-finding">
                    <div className="rb-pdf-finding-header">
                      <span className="rb-pdf-finding-id">#{i + 1}</span>
                      <span
                        className="rb-pdf-severity-badge"
                        style={{
                          backgroundColor: SEVERITY_COLORS[f.severity]?.bg || '#6c757d',
                          color: SEVERITY_COLORS[f.severity]?.text || '#fff'
                        }}
                      >
                        {SEVERITY_COLORS[f.severity]?.label || f.severity}
                        {f.cvss ? ` (CVSS ${f.cvss})` : ''}
                      </span>
                    </div>
                    <h4>{f.title}</h4>
                    {f.description && <p><strong>Descrição:</strong> {f.description}</p>}
                    {f.impact && <p><strong>Impacto:</strong> {f.impact}</p>}
                    {f.remediation && <p><strong>Remediação:</strong> {f.remediation}</p>}
                    {f.references && <p><strong>Referências:</strong> {f.references}</p>}
                  </div>
                ))
              )}
            </div>

            {/* Conclusão */}
            <div className="rb-pdf-section">
              <h3>{findings.length > 0 ? '6. Conclusão' : '5. Conclusão'}</h3>
              <p>{conclusion || 'Não informado.'}</p>
            </div>

            {/* Rodapé */}
            <div className="rb-pdf-footer">
              <p>Relatório gerado por CloudOS Pentest Suite • {new Date().toLocaleDateString('pt-BR')}</p>
              <p>Este documento é confidencial e destinado exclusivamente ao cliente.</p>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // Exportar para PDF
  const handleExportPDF = useCallback(async () => {
    setIsExporting(true);
    setExportStatus('Renderizando preview...');
    try {
      // Força renderização do preview no DOM (invisível)
      const container = document.createElement('div');
      container.style.position = 'absolute';
      container.style.left = '-9999px';
      container.style.top = '0';
      container.style.width = '210mm';
      container.style.backgroundColor = '#ffffff';
      container.style.color = '#000000';
      container.style.fontFamily = 'Arial, sans-serif';
      container.style.padding = '20px';
      document.body.appendChild(container);

      // Clona o conteúdo do preview
      const previewContent = document.getElementById('report-pdf-content');
      if (!previewContent) {
        throw new Error('Preview não encontrado. Abra a pré-visualização primeiro.');
      }
      container.innerHTML = previewContent.innerHTML;

      // Aguarda renderização
      await new Promise(r => setTimeout(r, 500));

      setExportStatus('Capturando conteúdo...');
      const canvas = await html2canvas(container, {
        scale: 2,
        useCORS: true,
        logging: false,
        backgroundColor: '#ffffff'
      });

      document.body.removeChild(container);

      setExportStatus('Gerando PDF...');
      const imgData = canvas.toDataURL('image/png');
      const pdf = new jsPDF({
        orientation: 'portrait',
        unit: 'mm',
        format: 'a4'
      });

      const pageWidth = pdf.internal.pageSize.getWidth();
      const pageHeight = pdf.internal.pageSize.getHeight();
      const imgWidth = pageWidth - 20; // margens
      const imgHeight = (canvas.height * imgWidth) / canvas.width;

      let heightLeft = imgHeight;
      let position = 10; // margem superior

      pdf.addImage(imgData, 'PNG', 10, position, imgWidth, imgHeight);
      heightLeft -= (pageHeight - 20);

      while (heightLeft > 0) {
        position = -(pageHeight - 30) + 10;
        pdf.addPage();
        pdf.addImage(imgData, 'PNG', 10, position, imgWidth, imgHeight);
        heightLeft -= (pageHeight - 20);
      }

      const fileName = `${(projectName || 'relatorio').replace(/\s+/g, '_').toLowerCase()}_${date}.pdf`;
      pdf.save(fileName);
      setExportStatus('✅ PDF exportado com sucesso!');
      setTimeout(() => setExportStatus(''), 3000);
    } catch (err) {
      console.error('Erro ao exportar PDF:', err);
      setExportStatus('❌ Erro: ' + err.message);
      setTimeout(() => setExportStatus(''), 5000);
    } finally {
      setIsExporting(false);
    }
  }, [projectName, date]);

  return (
    <div className="rb-container">
      {/* Header */}
      <div className="rb-header">
        <div className="rb-header-left">
          <h2>📄 Report Builder PRO</h2>
          <span className="rb-badge">CloudOS</span>
        </div>
        <div className="rb-header-right">
          <button
            className="rb-btn rb-btn-preview"
            onClick={() => setShowPreview(true)}
          >
            👁️ Preview
          </button>
          <button
            className="rb-btn rb-btn-export"
            onClick={handleExportPDF}
            disabled={isExporting}
          >
            {isExporting ? '⏳ Exportando...' : '📥 Exportar PDF'}
          </button>
        </div>
      </div>

      {exportStatus && (
        <div className={`rb-export-status ${exportStatus.includes('Erro') ? 'error' : 'success'}`}>
          {exportStatus}
        </div>
      )}

      {/* Conteúdo Principal */}
      <div className="rb-main">
        {/* Painel Esquerdo - Dados do Relatório */}
        <div className="rb-panel rb-panel-left">
          <h3>📋 Informações do Relatório</h3>

          <div className="rb-form-group">
            <label>Nome do Projeto</label>
            <input
              type="text"
              value={projectName}
              onChange={e => setProjectName(e.target.value)}
              placeholder="Ex: Pentest - Empresa XYZ"
              className="rb-input"
            />
          </div>

          <div className="rb-form-group">
            <label>Cliente</label>
            <input
              type="text"
              value={clientName}
              onChange={e => setClientName(e.target.value)}
              placeholder="Nome da empresa ou cliente"
              className="rb-input"
            />
          </div>

          <div className="rb-form-group">
            <label>Data do Teste</label>
            <input
              type="date"
              value={date}
              onChange={e => setDate(e.target.value)}
              className="rb-input"
            />
          </div>

          <div className="rb-form-group">
            <label>Resumo Executivo</label>
            <textarea
              value={executiveSummary}
              onChange={e => setExecutiveSummary(e.target.value)}
              placeholder="Descreva os objetivos e principais conclusões do pentest..."
              className="rb-textarea"
              rows={4}
            />
          </div>

          <div className="rb-form-group">
            <label>Escopo</label>
            <textarea
              value={scope}
              onChange={e => setScope(e.target.value)}
              placeholder="IPs, domínios, sistemas testados..."
              className="rb-textarea"
              rows={3}
            />
          </div>

          <div className="rb-form-group">
            <label>Metodologia</label>
            <textarea
              value={methodology}
              onChange={e => setMethodology(e.target.value)}
              placeholder="OWASP, OSSTMM, PTES..."
              className="rb-textarea"
              rows={3}
            />
          </div>

          <div className="rb-form-group">
            <label>Conclusão</label>
            <textarea
              value={conclusion}
              onChange={e => setConclusion(e.target.value)}
              placeholder="Conclusões finais e recomendações gerais..."
              className="rb-textarea"
              rows={4}
            />
          </div>
        </div>

        {/* Painel Direito - Achados (Findings) */}
        <div className="rb-panel rb-panel-right">
          <h3>🔍 Achados de Vulnerabilidade</h3>

          {/* Formulário de Finding */}
          <div className="rb-finding-form">
            <div className="rb-form-row">
              <div className="rb-form-group rb-flex-2">
                <label>Título da Vulnerabilidade</label>
                <input
                  type="text"
                  value={currentFinding.title}
                  onChange={e => setCurrentFinding(prev => ({ ...prev, title: e.target.value }))}
                  placeholder="Ex: SQL Injection em parâmetro ID"
                  className="rb-input"
                />
              </div>
              <div className="rb-form-group rb-flex-1">
                <label>Severidade</label>
                <select
                  value={currentFinding.severity}
                  onChange={e => setCurrentFinding(prev => ({ ...prev, severity: e.target.value }))}
                  className="rb-input rb-select"
                >
                  <option value="critical">Crítico</option>
                  <option value="high">Alto</option>
                  <option value="medium">Médio</option>
                  <option value="low">Baixo</option>
                  <option value="info">Informativo</option>
                </select>
              </div>
              <div className="rb-form-group rb-flex-1">
                <label>CVSS (opcional)</label>
                <input
                  type="text"
                  value={currentFinding.cvss}
                  onChange={e => setCurrentFinding(prev => ({ ...prev, cvss: e.target.value }))}
                  placeholder="Ex: 7.5"
                  className="rb-input"
                />
              </div>
            </div>

            <div className="rb-form-group">
              <label>Descrição</label>
              <textarea
                value={currentFinding.description}
                onChange={e => setCurrentFinding(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Descrição técnica da vulnerabilidade..."
                className="rb-textarea"
                rows={3}
              />
            </div>

            <div className="rb-form-group">
              <label>Impacto</label>
              <textarea
                value={currentFinding.impact}
                onChange={e => setCurrentFinding(prev => ({ ...prev, impact: e.target.value }))}
                placeholder="Qual o impacto se explorado?"
                className="rb-textarea"
                rows={2}
              />
            </div>

            <div className="rb-form-group">
              <label>Remediação</label>
              <textarea
                value={currentFinding.remediation}
                onChange={e => setCurrentFinding(prev => ({ ...prev, remediation: e.target.value }))}
                placeholder="Como corrigir a vulnerabilidade..."
                className="rb-textarea"
                rows={2}
              />
            </div>

            <div className="rb-form-group">
              <label>Referências</label>
              <input
                type="text"
                value={currentFinding.references}
                onChange={e => setCurrentFinding(prev => ({ ...prev, references: e.target.value }))}
                placeholder="CVE, OWASP, links..."
                className="rb-input"
              />
            </div>

            <div className="rb-finding-actions">
              <button className="rb-btn rb-btn-save" onClick={handleSaveFinding}>
                {editingIndex >= 0 ? '✏️ Atualizar' : '➕ Adicionar Achado'}
              </button>
              {editingIndex >= 0 && (
                <button
                  className="rb-btn rb-btn-cancel"
                  onClick={() => {
                    setCurrentFinding({ ...INITIAL_FINDING });
                    setEditingIndex(-1);
                  }}
                >
                  ❌ Cancelar
                </button>
              )}
            </div>
          </div>

          {/* Lista de Findings */}
          <div className="rb-findings-list">
            <h4>📋 Achados Cadastrados ({findings.length})</h4>
            {findings.length === 0 ? (
              <p className="rb-empty">Nenhum achado cadastrado ainda. Adicione acima.</p>
            ) : (
              findings.map((f, i) => (
                <div key={f.id} className="rb-finding-item">
                  <div className="rb-finding-item-header">
                    <span
                      className="rb-severity-dot"
                      style={{ backgroundColor: SEVERITY_COLORS[f.severity]?.bg || '#6c757d' }}
                      title={SEVERITY_COLORS[f.severity]?.label}
                    />
                    <span className="rb-finding-item-title">{f.title}</span>
                    <span className="rb-finding-item-cvss">{f.cvss ? `CVSS ${f.cvss}` : ''}</span>
                  </div>
                  <div className="rb-finding-item-actions">
                    <button className="rb-btn-icon" onClick={() => handleEditFinding(i)} title="Editar">
                      ✏️
                    </button>
                    <button className="rb-btn-icon rb-btn-danger" onClick={() => handleRemoveFinding(i)} title="Remover">
                      🗑️
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Preview Modal */}
      {showPreview && renderPreview()}
    </div>
  );
};

export default ReportBuilderApp;
