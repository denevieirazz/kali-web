import { useState, useEffect } from 'react';
import { Plus, Trash2, Bug } from 'lucide-react';

export function FindingsManagerApp({ activeProject }) {
  const [findings, setFindings] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ title: '', severity: 'medium', description: '' });
  
  const token = localStorage.getItem('cloudos_token');
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` };

  const load = async () => {
    if (!activeProject?.id) return;
    try {
      const res = await fetch(`http://localhost:8080/api/v3/projects/${activeProject.id}/findings`, { headers });
      if (res.ok) setFindings(await res.json());
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => { load(); }, [activeProject]);

  const create = async () => {
    if (!activeProject?.id || !form.title) return;
    try {
      await fetch(`http://localhost:8080/api/v3/projects/${activeProject.id}/findings`, {
        method: 'POST', headers, body: JSON.stringify(form)
      });
      setForm({ title: '', severity: 'medium', description: '' });
      setShowForm(false);
      load();
    } catch (e) {
      console.error(e);
    }
  };

  const remove = async (id) => {
    try {
      await fetch(`http://localhost:8080/api/v3/findings/${id}`, { method: 'DELETE', headers });
      load();
    } catch (e) {
      console.error(e);
    }
  };

  const colors = { critical: '#f85149', high: '#ff7b72', medium: '#d29922', low: '#58a6ff', info: '#8b949e' };

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d1117', color: '#c9d1d9', padding: 16, overflowY: 'auto', fontFamily: 'Inter, sans-serif' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16 }}>
        <h2 style={{ fontSize: 16, margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
          <Bug size={16} color="#f85149" /> Findings Manager
        </h2>
        <button onClick={() => setShowForm(!showForm)} style={{ background: '#238636', color: '#fff', border: 'none', padding: '6px 12px', borderRadius: 6, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 600 }}>
          <Plus size={14} /> Novo Finding
        </button>
      </div>

      {showForm && (
        <div style={{ background: '#161b22', padding: 16, borderRadius: 8, marginBottom: 16, border: '1px solid #30363d' }}>
          <input placeholder="Título do achado (ex: SQL Injection na página de Login)" value={form.title} onChange={e => setForm({...form, title: e.target.value})} style={styles.input} />
          <select value={form.severity} onChange={e => setForm({...form, severity: e.target.value})} style={{...styles.input, marginTop: 8}}>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
            <option value="info">Info</option>
          </select>
          <textarea placeholder="Descrição técnica e passos para reprodução..." value={form.description} onChange={e => setForm({...form, description: e.target.value})} style={{...styles.input, marginTop: 8, minHeight: 80, resize: 'vertical'}}></textarea>
          <button onClick={create} style={{ marginTop: 8, background: '#1f6feb', color: '#fff', border: 'none', padding: '8px 16px', borderRadius: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600 }}>Salvar Finding</button>
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {findings.map(f => (
          <div key={f.id} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ width: 8, height: 8, borderRadius: '50%', background: colors[f.severity] || '#8b949e' }}></span>
                <strong style={{ fontSize: 13 }}>{f.title}</strong>
              </div>
              <button onClick={() => remove(f.id)} style={{ background: 'transparent', border: 'none', color: '#f85149', cursor: 'pointer', display: 'flex', alignItems: 'center' }}><Trash2 size={14} /></button>
            </div>
            {f.description && <p style={{ fontSize: 12, color: '#8b949e', marginTop: 8, lineHeight: 1.4, margin: '8px 0 0 0' }}>{f.description}</p>}
          </div>
        ))}
        {findings.length === 0 && <div style={{ color: '#8b949e', textAlign: 'center', padding: 20, fontSize: 13 }}>Nenhum finding registrado para este projeto.</div>}
      </div>
    </div>
  );
}

const styles = {
  input: { width: '100%', background: '#0d1117', border: '1px solid #30363d', borderRadius: 6, padding: '8px 10px', color: '#c9d1d9', fontSize: 13, outline: 'none', boxSizing: 'border-box' }
};

export default FindingsManagerApp;
