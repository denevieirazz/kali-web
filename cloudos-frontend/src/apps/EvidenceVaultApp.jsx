import { useState, useEffect, useRef } from 'react';
import { Upload, FileText, Vault } from 'lucide-react';

export function EvidenceVaultApp({ activeProject }) {
  const [evidence, setEvidence] = useState([]);
  const fileRef = useRef(null);
  const token = localStorage.getItem('cloudos_token');

  const load = async () => {
    if (!activeProject?.id) return;
    try {
      const res = await fetch(`http://localhost:8080/api/v3/projects/${activeProject.id}/evidence`, { headers: { 'Authorization': `Bearer ${token}` } });
      if (res.ok) setEvidence(await res.json());
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => { load(); }, [activeProject]);

  const handleUpload = async (e) => {
    const file = e.target.files[0];
    if (!file || !activeProject?.id) return;
    const formData = new FormData();
    formData.append('file', file);
    formData.append('source_tool', 'manual');

    try {
      await fetch(`http://localhost:8080/api/v3/projects/${activeProject.id}/evidence`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}` },
        body: formData
      });
      load();
    } catch (err) {
      console.error(err);
    }
  };

  return (
    <div style={{ position: 'absolute', inset: 0, padding: 16, background: '#0d1117', color: '#c9d1d9', display: 'flex', flexDirection: 'column', fontFamily: 'Inter, sans-serif' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16, flexShrink: 0 }}>
        <h2 style={{ fontSize: 16, margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}><Vault size={16} color="#58a6ff" /> Evidence Vault</h2>
        <input type="file" ref={fileRef} onChange={handleUpload} style={{ display: 'none' }} />
        <button onClick={() => fileRef.current?.click()} style={{ background: '#238636', color: '#fff', border: 'none', padding: '6px 12px', borderRadius: 6, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 600 }}>
          <Upload size={14} /> Upload Evidência
        </button>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 12, alignContent: 'start' }}>
        {evidence.map(ev => (
          <div key={ev.id} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 12 }}>
            <FileText size={20} color="#58a6ff" />
            <div style={{ fontSize: 13, marginTop: 8, wordBreak: 'break-all', fontWeight: 600 }}>{ev.filename}</div>
            <div style={{ fontSize: 11, color: '#8b949e', marginTop: 4, fontFamily: 'monospace' }}>Hash: {ev.hash ? ev.hash.substring(0, 16) : 'n/a'}...</div>
          </div>
        ))}
        {evidence.length === 0 && <div style={{ color: '#8b949e', gridColumn: '1 / -1', textAlign: 'center', padding: 20, fontSize: 13 }}>Nenhuma evidência armazenada para este projeto.</div>}
      </div>
    </div>
  );
}

export default EvidenceVaultApp;
