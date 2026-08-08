import React, { useState, useEffect } from 'react';

export default function AKBApp() {
  const [hosts, setHosts] = useState([]);
  const [newHost, setNewHost] = useState('');
  const [newPort, setNewPort] = useState('');
  const [newService, setNewService] = useState('');

  const fetchHosts = async () => {
    try {
      const res = await fetch('/api/akb/hosts');
      const data = await res.json();
      setHosts(Array.isArray(data) ? data : []);
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => { fetchHosts(); }, []);

  const handleAdd = async () => {
    if (!newHost) return;
    try {
      await fetch('/api/akb/add', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ host: newHost, port: newPort, service: newService })
      });
    } catch (e) {}
    setHosts(prev => [...prev, { host: newHost, port: newPort, service: newService }]);
    setNewHost(''); setNewPort(''); setNewService('');
  };

  return (
    <div style={{ padding: '20px', color: '#c9d1d9', fontFamily: 'monospace', height: '100%', boxSizing: 'border-box', overflowY: 'auto', background: '#0d1117' }}>
      <h2 style={{ color: '#58a6ff', marginBottom: '15px' }}>📚 Active Knowledge Base (AKB)</h2>
      
      <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', flexWrap: 'wrap' }}>
        <input value={newHost} onChange={(e) => setNewHost(e.target.value)} placeholder="Host/IP" style={styles.input} />
        <input value={newPort} onChange={(e) => setNewPort(e.target.value)} placeholder="Port" style={styles.input} />
        <input value={newService} onChange={(e) => setNewService(e.target.value)} placeholder="Service" style={styles.input} />
        <button onClick={handleAdd} style={styles.button}>➕ Add Host</button>
      </div>

      <table style={{ width: '100%', borderCollapse: 'collapse', background: '#161b22', borderRadius: '6px', overflow: 'hidden' }}>
        <thead>
          <tr style={{ borderBottom: '2px solid #30363d', background: '#21262d' }}>
            <th style={styles.th}>Host</th>
            <th style={styles.th}>Port</th>
            <th style={styles.th}>Service</th>
          </tr>
        </thead>
        <tbody>
          {hosts.length === 0 ? (
            <tr>
              <td colSpan="3" style={{ padding: '15px', textAlign: 'center', color: '#8b949e' }}>Nenhum host cadastrado na base.</td>
            </tr>
          ) : (
            hosts.map((h, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #21262d' }}>
                <td style={styles.td}>{h.host || h.ip}</td>
                <td style={styles.td}>{h.port || (h.ports ? h.ports.map(p=>p.port).join(', ') : '-')}</td>
                <td style={styles.td}>{h.service || (h.ports ? h.ports.map(p=>p.service).join(', ') : '-')}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}

const styles = {
  input: { background: '#0d1117', color: '#c9d1d9', border: '1px solid #30363d', padding: '10px', borderRadius: '6px', outline: 'none' },
  button: { background: '#1f6feb', color: 'white', border: 'none', padding: '10px 20px', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold' },
  th: { textAlign: 'left', padding: '10px', color: '#58a6ff' },
  td: { padding: '10px' }
};
