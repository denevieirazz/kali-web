import React, { useState, useEffect } from 'react';
import { API_BASE } from '../config';

const HistoryPanel = ({ toolName, isOpen, onClose, onLoadResult }) => {
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setLoading(true);
      const token = localStorage.getItem('cloudos_token');
      fetch(`${API_BASE}/api/history?tool=${toolName}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      })
        .then(res => res.json())
        .then(data => {
          if (data.success) setHistory(data.history || []);
        })
        .catch(err => console.error('Erro ao buscar histórico:', err))
        .finally(() => setLoading(false));
    }
  }, [isOpen, toolName]);

  const handleLoad = async (id) => {
    const token = localStorage.getItem('cloudos_token');
    const res = await fetch(`${API_BASE}/api/history/${id}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    if (data.success && data.data.result) {
      onLoadResult(data.data.result);
      onClose();
    }
  };

  if (!isOpen) return null;

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div style={styles.header}>
          <h3 style={styles.title}>📂 Histórico de Varreduras ({toolName})</h3>
          <button style={styles.closeBtn} onClick={onClose}>✕</button>
        </div>
        
        <div style={styles.list}>
          {loading ? (
            <div style={styles.empty}>Carregando...</div>
          ) : history.length === 0 ? (
            <div style={styles.empty}>Nenhum scan salvo ainda.</div>
          ) : (
            history.map(item => (
              <div key={item.id} style={styles.card} onClick={() => handleLoad(item.id)}>
                <div style={styles.cardTarget}>{item.target}</div>
                <div style={styles.cardMeta}>
                  <span style={styles.badge}>{item.status}</span>
                  <span style={styles.date}>{new Date(item.created_at).toLocaleString('pt-BR')}</span>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};

const styles = {
  overlay: { position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', zIndex: 9998, backdropFilter: 'blur(4px)' },
  panel: { position: 'fixed', top: 0, right: 0, width: '400px', height: '100vh', backgroundColor: '#161b22', borderLeft: '1px solid #30363d', display: 'flex', flexDirection: 'column', boxShadow: '-5px 0 20px rgba(0,0,0,0.5)' },
  header: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 20px', borderBottom: '1px solid #30363d' },
  title: { color: '#58a6ff', fontSize: '16px', margin: 0 },
  closeBtn: { background: 'none', border: 'none', color: '#8b949e', cursor: 'pointer', fontSize: '18px' },
  list: { flex: 1, overflowY: 'auto', padding: '16px' },
  card: { backgroundColor: '#0d1117', border: '1px solid #30363d', borderRadius: '8px', padding: '14px', marginBottom: '10px', cursor: 'pointer', transition: 'border 0.2s' },
  cardTarget: { color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', fontWeight: 'bold', marginBottom: '8px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' },
  cardMeta: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' },
  badge: { backgroundColor: 'rgba(63, 185, 80, 0.2)', color: '#3fb950', border: '1px solid #3fb950', padding: '2px 8px', borderRadius: '4px', fontSize: '10px' },
  date: { color: '#8b949e', fontSize: '11px' },
  empty: { color: '#8b949e', textAlign: 'center', marginTop: '40px', fontSize: '14px' }
};

export default HistoryPanel;
