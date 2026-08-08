import React, { useState, useEffect } from 'react';

export default function ListenerManagerApp() {
  const [listeners, setListeners] = useState([]);
  const [port, setPort] = useState('4444');
  const [protocol, setProtocol] = useState('tcp');
  const [logs, setLogs] = useState('');
  const [statusMsg, setStatusMsg] = useState('');

  const startListener = async () => {
    if (!port || isNaN(port)) return;
    setStatusMsg('⏳ Iniciando Listener...');
    try {
      const res = await fetch('/api/listeners/start', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        },
        body: JSON.stringify({ port: parseInt(port), protocol })
      });
      if (res.ok) {
        const data = await res.json();
        setListeners(prev => [...prev.filter(l => l.port !== parseInt(port)), { port: parseInt(port), protocol }]);
        setLogs(prev => prev + `\n[Listener Manager] 🟢 Listener iniciado na porta ${port}/${protocol.toUpperCase()}`);
        setStatusMsg('');
      } else {
        const err = await res.json();
        setStatusMsg(`❌ Erro: ${err.error || 'Falha ao iniciar listener'}`);
      }
    } catch (e) {
      setStatusMsg(`❌ Erro de conexão: ${e.message}`);
    }
  };

  const stopListener = async (p) => {
    try {
      const res = await fetch('/api/listeners/stop', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        },
        body: JSON.stringify({ port: parseInt(p) })
      });
      if (res.ok) {
        setListeners(prev => prev.filter(l => l.port !== parseInt(p)));
        setLogs(prev => prev + `\n[Listener Manager] 🔴 Listener interrompido na porta ${p}`);
      }
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', width: '100%', padding: '20px', background: '#0d1117', color: '#e6edf3', fontFamily: 'Segoe UI, sans-serif', boxSizing: 'border-box', overflowY: 'auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', borderBottom: '1px solid #30363d', paddingBottom: '12px' }}>
        <span style={{ fontSize: '24px' }}>🕸️</span>
        <div>
          <h2 style={{ margin: 0, color: '#58a6ff', fontSize: '18px' }}>Listener Manager (Receber Shells Reversas)</h2>
          <span style={{ color: '#8b949e', fontSize: '13px' }}>Gerencie conexões ncat / netcat nativas no subsistema WSL2 Kali.</span>
        </div>
      </div>

      {/* Form Controls */}
      <div style={{ display: 'flex', gap: '12px', alignItems: 'center', marginTop: '20px', background: '#161b22', border: '1px solid #30363d', padding: '16px', borderRadius: '8px' }}>
        <div>
          <label style={{ display: 'block', fontSize: '12px', color: '#8b949e', marginBottom: '4px' }}>Porta de Escuta</label>
          <input
            type="number"
            value={port}
            onChange={(e) => setPort(e.target.value)}
            placeholder="Ex: 4444"
            style={inputStyle}
          />
        </div>
        <div>
          <label style={{ display: 'block', fontSize: '12px', color: '#8b949e', marginBottom: '4px' }}>Protocolo</label>
          <select value={protocol} onChange={(e) => setProtocol(e.target.value)} style={inputStyle}>
            <option value="tcp">TCP</option>
            <option value="udp">UDP</option>
          </select>
        </div>
        <div style={{ marginTop: '18px' }}>
          <button onClick={startListener} style={btnStartStyle}>
            ▶️ Iniciar Listener
          </button>
        </div>
        {statusMsg && <div style={{ marginTop: '18px', fontSize: '13px', color: '#f0883e' }}>{statusMsg}</div>}
      </div>

      {/* Active Listeners List */}
      <h3 style={{ marginTop: '24px', color: '#c9d1d9', fontSize: '15px' }}>Listeners Ativos ({listeners.length})</h3>
      {listeners.length === 0 ? (
        <div style={{ padding: '20px', background: '#161b22', border: '1px border-dashed #30363d', borderRadius: '6px', textAlign: 'center', color: '#8b949e', fontSize: '14px' }}>
          Nenhum listener em execução. Escolha uma porta acima e clique em "Iniciar Listener".
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {listeners.map((l, i) => (
            <div key={i} style={{ background: '#161b22', border: '1px solid #30363d', padding: '14px 18px', borderRadius: '8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <span style={{ fontSize: '20px' }}>⚡</span>
                <div>
                  <span style={{ color: '#58a6ff', fontWeight: 'bold', fontSize: '16px' }}>Porta {l.port}</span>
                  <span style={{ color: '#7ee787', marginLeft: '10px', fontWeight: 'bold', fontSize: '13px' }}>[{l.protocol.toUpperCase()}]</span>
                  <div style={{ color: '#3fb950', fontSize: '12px', marginTop: '2px' }}>🟢 Escutando conexões no WSL2...</div>
                </div>
              </div>
              <button onClick={() => stopListener(l.port)} style={btnStopStyle}>
                ⏹️ Interromper
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Execution Console Logs */}
      <h3 style={{ marginTop: '24px', color: '#c9d1d9', fontSize: '15px' }}>Console de Eventos</h3>
      <textarea
        value={logs}
        readOnly
        rows={8}
        placeholder="Os logs de conexões e shells recebidas aparecerão aqui em tempo real..."
        style={{
          width: '100%',
          background: '#0d1117',
          border: '1px solid #30363d',
          borderRadius: '6px',
          color: '#7ee787',
          fontFamily: 'Consolas, monospace',
          fontSize: '13px',
          padding: '12px',
          resize: 'none',
          boxSizing: 'border-box'
        }}
      />
    </div>
  );
}

const inputStyle = {
  background: '#0d1117',
  border: '1px solid #30363d',
  color: '#fff',
  padding: '8px 12px',
  borderRadius: '6px',
  fontSize: '14px',
  outline: 'none'
};

const btnStartStyle = {
  background: '#238636',
  border: 'none',
  color: '#fff',
  padding: '9px 18px',
  borderRadius: '6px',
  cursor: 'pointer',
  fontWeight: 'bold',
  fontSize: '13px'
};

const btnStopStyle = {
  background: '#da3633',
  border: 'none',
  color: '#fff',
  padding: '8px 14px',
  borderRadius: '6px',
  cursor: 'pointer',
  fontWeight: 'bold',
  fontSize: '12px'
};
