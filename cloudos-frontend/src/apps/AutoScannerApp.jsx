import React, { useState } from 'react';

export default function AutoScannerApp() {
  const [target, setTarget] = useState('10.10.10.0/24');
  const [status, setStatus] = useState('Ready to scan.');
  const [hosts, setHosts] = useState([]);

  const handleScan = async () => {
    setStatus('⚡ Scanning and feeding AKB... (This may take a while)');
    try {
      const res = await fetch('/api/nmap/auto-scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target })
      });
      const data = await res.json();
      if (data.success) {
        setHosts(data.hosts || []);
        setStatus(`✅ Found ${data.count} open ports. AKB updated automatically!`);
      } else {
        setStatus('❌ Error: ' + (data.error || 'Scan failed'));
      }
    } catch (e) {
      setStatus('❌ Error: ' + e.message);
    }
  };

  const styles = {
    input: { background: '#0d1117', color: '#c9d1d9', border: '1px solid #30363d', padding: '10px', borderRadius: '6px', width: '260px' },
    button: { background: '#238636', color: 'white', border: 'none', padding: '10px 20px', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold' },
    th: { textAlign: 'left', padding: '10px', color: '#58a6ff' },
    td: { padding: '10px' }
  };

  return (
    <div style={{ padding: '20px', color: '#c9d1d9', fontFamily: 'monospace', height: '100%', boxSizing: 'border-box', overflowY: 'auto', background: '#0d1117' }}>
      <h2>📡 Auto-Nmap Scanner (1-Click AKB Feed)</h2>
      <div style={{ display: 'flex', gap: '10px', marginBottom: '20px' }}>
        <input 
          value={target} 
          onChange={(e) => setTarget(e.target.value)} 
          style={styles.input} 
          placeholder="IP or CIDR (e.g. 192.168.1.0/24)"
        />
        <button onClick={handleScan} style={styles.button}>🚀 Scan & Feed</button>
      </div>

      <div style={{ color: '#58a6ff', marginBottom: '20px' }}>{status}</div>

      {hosts.length > 0 && (
        <table style={{ width: '100%', borderCollapse: 'collapse', background: '#161b22', borderRadius: '6px', overflow: 'hidden' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #30363d', background: '#21262d' }}>
              <th style={styles.th}>Host</th>
              <th style={styles.th}>Port</th>
              <th style={styles.th}>Service</th>
            </tr>
          </thead>
          <tbody>
            {hosts.map((h, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #21262d' }}>
                <td style={styles.td}>{h.host}</td>
                <td style={styles.td}>{h.port}</td>
                <td style={styles.td}>{h.service}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
