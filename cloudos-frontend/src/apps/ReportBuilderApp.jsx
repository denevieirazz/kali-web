import React, { useState } from 'react';
import { FileText, Download, Eye, RefreshCw, Printer } from 'lucide-react';

const API_BASE = 'http://localhost:8080/api';

export function ReportBuilderApp({ payload, setPayload, openApp, setBg }) {
  const [clientName, setClientName] = useState('Cliente Corporativo');
  const [loading, setLoading] = useState(false);
  const [reportHtml, setReportHtml] = useState('');
  const [reportMd, setReportMd] = useState('');
  const [activeTab, setActiveTab] = useState('preview'); // 'preview' | 'markdown'

  const getHeaders = () => {
    const token = localStorage.getItem('cloudos_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };
  };

  const generateReport = async () => {
    setLoading(true);
    try {
      const headers = getHeaders();
      const [resHtml, resMd] = await Promise.all([
        fetch(`${API_BASE}/reports/generate?format=html&client=${encodeURIComponent(clientName)}`, { headers }),
        fetch(`${API_BASE}/reports/generate?format=markdown&client=${encodeURIComponent(clientName)}`, { headers })
      ]);

      const dataHtml = await resHtml.json();
      const dataMd = await resMd.json();

      if (dataHtml.success) setReportHtml(dataHtml.report);
      if (dataMd.success) setReportMd(dataMd.report);
    } catch (e) {
      console.error("Erro ao gerar relatório:", e);
    } finally {
      setLoading(false);
    }
  };

  const handleDownloadMd = () => {
    if (!reportMd) return;
    const blob = new Blob([reportMd], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Relatorio_Pentest_${clientName.replace(/\s+/g, '_')}.md`;
    a.click();
  };

  const handleDownloadHtml = () => {
    if (!reportHtml) return;
    const blob = new Blob([reportHtml], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Relatorio_Pentest_${clientName.replace(/\s+/g, '_')}.html`;
    a.click();
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9', fontFamily: 'sans-serif' }}>
      
      {/* Header Controls */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: '12px',
        padding: '12px 16px', background: '#161b22', borderBottom: '1px solid #30363d'
      }}>
        <FileText size={18} color="#58a6ff" />
        <span style={{ fontWeight: 600, fontSize: '14px' }}>Gerador de Relatório Executivo</span>
        
        <input 
          type="text" 
          value={clientName} 
          onChange={e => setClientName(e.target.value)}
          placeholder="Nome do Cliente / Alvo"
          style={{
            background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px',
            padding: '6px 12px', color: '#c9d1d9', fontSize: '12px', width: '220px'
          }}
        />

        <button
          onClick={generateReport}
          disabled={loading}
          style={{
            background: '#238636', border: 'none', borderRadius: '6px',
            padding: '6px 12px', color: 'white', cursor: 'pointer',
            fontSize: '12px', fontWeight: 500, display: 'flex', alignItems: 'center', gap: '6px'
          }}
        >
          <RefreshCw size={14} className={loading ? 'spin' : ''} /> {loading ? 'Gerando...' : 'Gerar com Dados do Banco'}
        </button>

        <div style={{ flex: 1 }} />

        {reportHtml && (
          <div style={{ display: 'flex', gap: '8px' }}>
            <button
              onClick={handleDownloadHtml}
              style={{
                background: '#21262d', border: '1px solid #30363d', borderRadius: '6px',
                padding: '6px 12px', color: '#58a6ff', cursor: 'pointer',
                fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px'
              }}
            >
              <Download size={14} /> Exportar HTML
            </button>

            <button
              onClick={handleDownloadMd}
              style={{
                background: '#21262d', border: '1px solid #30363d', borderRadius: '6px',
                padding: '6px 12px', color: '#3fb950', cursor: 'pointer',
                fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px'
              }}
            >
              <Download size={14} /> Exportar Markdown (.md)
            </button>
          </div>
        )}
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', background: '#161b22', borderBottom: '1px solid #30363d' }}>
        <button
          onClick={() => setActiveTab('preview')}
          style={{
            padding: '8px 16px', background: activeTab === 'preview' ? '#0d1117' : 'transparent',
            border: 'none', borderBottom: activeTab === 'preview' ? '2px solid #58a6ff' : 'none',
            color: activeTab === 'preview' ? '#c9d1d9' : '#8b949e', cursor: 'pointer', fontSize: '12px'
          }}
        >
          Visualização Prévia (HTML)
        </button>
        <button
          onClick={() => setActiveTab('markdown')}
          style={{
            padding: '8px 16px', background: activeTab === 'markdown' ? '#0d1117' : 'transparent',
            border: 'none', borderBottom: activeTab === 'markdown' ? '2px solid #58a6ff' : 'none',
            color: activeTab === 'markdown' ? '#c9d1d9' : '#8b949e', cursor: 'pointer', fontSize: '12px'
          }}
        >
          Código Markdown Raw
        </button>
      </div>

      {/* Report Area */}
      <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        {activeTab === 'preview' ? (
          reportHtml ? (
            <iframe 
              srcDoc={reportHtml} 
              title="Report Preview"
              style={{ width: '100%', height: '100%', border: 'none', background: '#0d1117' }} 
            />
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#484f58', gap: '12px' }}>
              <FileText size={48} />
              <span>Clique em <strong>"Gerar com Dados do Banco"</strong> para compilar o relatório com os achados do Findings Manager.</span>
            </div>
          )
        ) : (
          <textarea
            readOnly
            value={reportMd}
            style={{
              width: '100%', height: '100%', background: '#0d1117', color: '#c9d1d9',
              fontFamily: 'monospace', padding: '16px', border: 'none', outline: 'none', resize: 'none'
            }}
          />
        )}
      </div>

      <style>{`
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        .spin { animation: spin 1s linear infinite; }
      `}</style>
    </div>
  );
}

export default ReportBuilderApp;
