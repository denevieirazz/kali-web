import { useState, useEffect, useRef } from 'react';
import { Search, Folder, Terminal, Cpu, X } from 'lucide-react';

export default function UniversalSearch({ apps = [], onClose }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const inputRef = useRef(null);
  const token = localStorage.getItem('cloudos_token');

  useEffect(() => {
    inputRef.current?.focus();
    if (!query) return setResults([]);

    const searchAll = async () => {
      const headers = { 'Authorization': `Bearer ${token}` };
      try {
        const [toolsRes, projsRes] = await Promise.all([
          fetch(`http://localhost:8080/api/kali/tools?q=${encodeURIComponent(query)}`, { headers }),
          fetch(`http://localhost:8080/api/projects?q=${encodeURIComponent(query)}`, { headers })
        ]);

        const tools = toolsRes.ok ? await toolsRes.json() : [];
        const projects = projsRes.ok ? await projsRes.json() : [];
        
        const matchedApps = apps.filter(a => a.title?.toLowerCase().includes(query.toLowerCase()));

        setResults([
          ...matchedApps.map(a => ({ type: 'App', icon: Terminal, name: a.title, desc: 'Aplicativo CloudOS', action: () => a.open?.() })),
          ...tools.map(t => ({ type: 'Kali Tool', icon: Cpu, name: t.name, desc: t.description })),
          ...projects.map(p => ({ type: 'Project', icon: Folder, name: p.name, desc: p.description || 'Projeto de Pentest' })),
        ]);
      } catch (e) {
        console.error(e);
      }
    };

    const timer = setTimeout(searchAll, 300);
    return () => clearTimeout(timer);
  }, [query, apps, token]);

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div style={styles.header}>
          <Search size={18} color="#8b949e" />
          <input
            ref={inputRef}
            style={styles.input}
            placeholder="Buscar apps, ferramentas, projetos..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button onClick={onClose} style={styles.closeBtn}><X size={16} /></button>
        </div>
        
        <div style={styles.resultsList}>
          {results.length === 0 && query && <div style={styles.empty}>Nenhum resultado encontrado.</div>}
          {results.map((r, i) => (
            <div key={i} style={styles.resultItem} onClick={() => { if (r.action) r.action(); onClose(); }}>
              <r.icon size={16} color="#58a6ff" />
              <div>
                <div style={styles.resName}>{r.name}</div>
                <div style={styles.resType}>{r.type} {r.desc ? `- ${r.desc}` : ''}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

const styles = {
  overlay: { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)', zIndex: 99999, display: 'flex', justifyContent: 'center', alignItems: 'flex-start', paddingTop: '15vh' },
  modal: { width: '90%', maxWidth: '600px', background: '#161b22', border: '1px solid #30363d', borderRadius: '12px', boxShadow: '0 10px 40px rgba(0,0,0,0.5)', overflow: 'hidden' },
  header: { display: 'flex', alignItems: 'center', gap: '12px', padding: '16px', borderBottom: '1px solid #30363d' },
  input: { flex: 1, background: 'transparent', border: 'none', outline: 'none', color: '#c9d1d9', fontSize: '15px' },
  closeBtn: { background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center' },
  resultsList: { maxHeight: '400px', overflowY: 'auto', padding: '8px' },
  resultItem: { display: 'flex', alignItems: 'center', gap: '12px', padding: '10px 12px', borderRadius: '6px', cursor: 'pointer', transition: 'background 0.2s' },
  resName: { fontSize: '13px', color: '#c9d1d9', fontWeight: '500' },
  resType: { fontSize: '11px', color: '#8b949e' },
  empty: { padding: '24px', textAlign: 'center', color: '#8b949e', fontSize: '13px' }
};
