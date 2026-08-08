import React, { useState, useEffect } from 'react';

const API = '/api';

const lbl = { display: 'block', color: '#8b949e', fontSize: '12px', marginTop: '12px', marginBottom: '4px', fontWeight: 'bold' };
const inp = { width: '100%', background: '#0d1117', color: '#c9d1d9', border: '1px solid #30363d', padding: '8px 12px', borderRadius: '6px', fontSize: '13px', outline: 'none', boxSizing: 'border-box' };
const btn = { width: '100%', background: '#238636', color: 'white', border: 'none', padding: '10px', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontSize: '13px', marginTop: '16px' };
const miniBtn = { background: '#21262d', color: '#58a6ff', border: '1px solid #30363d', padding: '3px 8px', borderRadius: '4px', cursor: 'pointer', fontSize: '11px' };

export default function ReportGeneratorApp() {
  const [meta, setMeta] = useState({ engagement: 'ENG-2026-001', client: 'Target Corp', tester: 'redteam' });
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [reports, setReports] = useState([]);
  const [preview, setPreview] = useState('');

  useEffect(() => { refreshList(); }, []);

  async function refreshList() {
    try {
      const r = await fetch(`${API}/report/list`).then(r => r.json());
      setReports(r.reports || []);
    } catch (e) { console.error(e); }
  }

  async function generate() {
    setBusy(true); setResult(null);
    try {
      const r = await fetch(`${API}/report/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(meta)
      }).then(r => r.json());
      setResult(r);
      if (r.ok) refreshList();
    } catch (e) { setResult({ ok: false, error: String(e) }); }
    setBusy(false);
  }

  function openDownload(file) {
    window.open(`${API}/report/download?file=${encodeURIComponent(file)}`, '_blank');
  }

  async function previewHtml(file) {
    const html = await fetch(`${API}/report/download?file=${encodeURIComponent(file)}`).then(r => r.text());
    setPreview(html);
  }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 16, height: '100%', padding: '16px', boxSizing: 'border-box', background: '#0d1117', fontFamily: 'Segoe UI, sans-serif' }}>
      {/* Painel de config */}
      <div style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 16, overflowY: 'auto' }}>
        <h3 style={{ color: '#58a6ff', marginTop: 0, borderBottom: '1px solid #30363d', paddingBottom: 8, fontSize: '16px' }}>📊 Report Generator</h3>
        <label style={lbl}>Engagement ID</label>
        <input style={inp} value={meta.engagement} onChange={e => setMeta({...meta, engagement: e.target.value})} />
        <label style={lbl}>Client</label>
        <input style={inp} value={meta.client} onChange={e => setMeta({...meta, client: e.target.value})} />
        <label style={lbl}>Tester</label>
        <input style={inp} value={meta.tester} onChange={e => setMeta({...meta, tester: e.target.value})} />
        <button onClick={generate} disabled={busy} style={{ ...btn, opacity: busy ? 0.6 : 1, cursor: busy ? 'not-allowed' : 'pointer' }}>
          {busy ? '⏳ Gerando HTML & PDF...' : '🚀 Generate HTML + PDF'}
        </button>
        {result && (
          <div style={{ marginTop: 12, padding: 10, background: result.ok ? '#0d2818' : '#2a0e0e', borderRadius: 6, fontSize: 12 }}>
            <span style={{ color: result.ok ? '#3fb950' : '#f85149', fontWeight: 'bold' }}>
              {result.ok ? '✅ Report gerado com sucesso!' : '❌ Falha na geração do report'}
            </span>
            <div style={{ marginTop: 8, display: 'flex', gap: 6 }}>
              {result.pdf && <button onClick={() => openDownload(result.pdf)} style={miniBtn}>⬇ PDF</button>}
              {result.html && <button onClick={() => previewHtml(result.html)} style={miniBtn}>👁 Preview</button>}
            </div>
            {result.stderr && <pre style={{ color: '#f85149', marginTop: 6, fontSize: 11, whiteSpace: 'pre-wrap' }}>{result.stderr}</pre>}
          </div>
        )}
        <h4 style={{ color: '#8b949e', marginTop: 20, marginBottom: 10, fontSize: '13px' }}>Recent Reports</h4>
        {reports.length === 0 ? (
          <div style={{ color: '#8b949e', fontSize: '12px' }}>Nenhum relatório gerado ainda.</div>
        ) : (
          reports.map(f => (
            <div key={f.name} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 0', borderBottom: '1px solid #21262d', fontSize: 12 }}>
              <span style={{ color: '#c9d1d9', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '190px' }} title={f.name}>{f.name}</span>
              <span style={{ display: 'flex', gap: '4px' }}>
                <button onClick={() => previewHtml(f.name)} style={miniBtn}>👁</button>
                <button onClick={() => openDownload(f.name)} style={miniBtn}>⬇</button>
              </span>
            </div>
          ))
        )}
      </div>

      {/* Preview / HTML Display */}
      <div style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {preview ? (
          <iframe title="preview" srcDoc={preview} style={{ width: '100%', height: '100%', border: 0, background: '#0d1117' }} />
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#8b949e', gap: '12px' }}>
            <span style={{ fontSize: '48px' }}>📊</span>
            <div style={{ fontSize: '14px', fontWeight: 'bold' }}>CloudOS Report Generator</div>
            <div style={{ fontSize: '12px', maxWidth: '360px', textAlign: 'center' }}>
              Clique em <strong>Generate HTML + PDF</strong> para compilar o relatório da AKB e Auto-Attack, ou selecione um relatório da lista para visualização prévia.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
