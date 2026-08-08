import React, { useState } from 'react';

export default function AutoAttackApp() {
  const [status, setStatus] = useState('Ready to strike.');
  const [results, setResults] = useState([]);

  const handleAttack = async () => {
    setStatus('🔥 Reading AKB and launching attacks... (Wait)');
    try {
      const res = await fetch('/api/auto-attack/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
      });
      const data = await res.json();
      if (data.success) {
        setResults(data.results || []);
        setStatus('✅ Attack cycle completed. Review findings below.');
      } else {
        setStatus('❌ Error: ' + (data.error || 'Attack cycle failed'));
      }
    } catch (e) {
      setStatus('❌ Error: ' + e.message);
    }
  };

  const styles = {
    button: { background: '#da3633', color: 'white', border: 'none', padding: '15px 30px', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontSize: '16px' },
    card: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '15px', marginBottom: '15px' },
    pre: { background: '#0d1117', border: '1px solid #21262d', padding: '10px', borderRadius: '6px', overflowX: 'auto', color: '#c9d1d9', whiteSpace: 'pre-wrap' }
  };

  return (
    <div style={{ padding: '20px', color: '#c9d1d9', fontFamily: 'monospace', height: '100%', boxSizing: 'border-box', overflowY: 'auto', background: '#0d1117' }}>
      <h2>⚔️ Auto-Attack Orchestrator</h2>
      <button onClick={handleAttack} style={styles.button}>🔥 LAUNCH 1-CLICK MASS ATTACK</button>
      
      <div style={{ marginTop: '20px', color: '#58a6ff' }}>{status}</div>

      <div style={{ marginTop: '20px' }}>
        {results.map((r, i) => (
          <div key={i} style={styles.card}>
            <h3 style={{ color: '#7ee787' }}>🎯 {r.target}:{r.port} ({r.service})</h3>
            {r.outputs && r.outputs.map((o, j) => (
              <div key={j} style={{ marginTop: '10px' }}>
                <h4 style={{ color: '#f85149' }}>[{o.tool}]</h4>
                <pre style={styles.pre}>{o.output}</pre>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
