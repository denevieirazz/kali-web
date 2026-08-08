import React, { useState, useEffect } from 'react';

export default function KnowledgeBaseApp({ openApp, websocket }) {
  const [hosts, setHosts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [logs, setLogs] = useState([]);
  const [attackingHostId, setAttackingHostId] = useState(null);

  const fetchHosts = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/akb/hosts', {
        headers: { 'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}` }
      });
      if (res.ok) {
        const data = await res.json();
        setHosts(Array.isArray(data) ? data : []);
      } else {
        setHosts([]);
      }
    } catch (err) {
      console.error('Erro ao carregar AKB:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchHosts(); }, []);

  useEffect(() => {
    if (!websocket) return;
    const handleMsg = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'log' || data.type === 'done' || data.type === 'attack') {
          setLogs((prev) => [...prev, data.message]);
          if (data.type === 'done') setAttackingHostId(null);
        }
      } catch (e) {}
    };
    websocket.addEventListener('message', handleMsg);
    return () => websocket.removeEventListener('message', handleMsg);
  }, [websocket]);

  const sendToTool = (toolId, target) => {
    if (openApp) {
      openApp('toolrunner', { toolId, target });
    }
  };

  const handleAutoAttack = async (hostId, ip) => {
    setAttackingHostId(hostId);
    setLogs([`⏳ [1-CLICK AUTO-ATTACK] Iniciando orquestração tática para o alvo ${ip} (ID: ${hostId})...`]);
    try {
      const res = await fetch(`/api/automate/attack/${hostId}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        }
      });
      if (res.ok) {
        const data = await res.json();
        setLogs(prev => [...prev, `🟢 ${data.message || 'Auto-Attack em execução no backend...'}`]);
      } else {
        setLogs(prev => [...prev, '❌ Erro ao disparar Auto-Attack no servidor backend.']);
        setAttackingHostId(null);
      }
    } catch (err) {
      setLogs(prev => [...prev, `❌ Erro de conexão: ${err.message}`]);
      setAttackingHostId(null);
    }
  };

  if (loading) return <div style={{ padding: '20px', color: '#fff' }}>Carregando Base de Conhecimento...</div>;

  return (
    <div style={{ padding: '20px', color: '#e6edf3', fontFamily: 'Segoe UI, sans-serif', overflowY: 'auto', height: '100%', backgroundColor: '#0d1117', boxSizing: 'border-box' }}>
      <h2 style={{ borderBottom: '1px solid #30363d', paddingBottom: '10px', color: '#58a6ff', display: 'flex', alignItems: 'center', gap: '10px' }}>
        <span>🧠</span> Active Knowledge Base (AKB) & 1-Click Auto-Attack
      </h2>
      
      {hosts.length === 0 ? (
        <div style={{ marginTop: '40px', textAlign: 'center', color: '#8b949e' }}>
          <p style={{ fontSize: '16px', fontWeight: 'bold' }}>Nenhum host encontrado ainda.</p>
          <p style={{ fontSize: '14px' }}>Execute o <strong>Nmap</strong> com a flag <code>-oX -</code> no Tool Runner para popular a base automaticamente.</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '15px', marginTop: '20px' }}>
          {hosts.map(host => (
            <div key={host.id} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '15px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <span style={{ fontSize: '18px', fontWeight: 'bold', color: '#58a6ff' }}>{host.ip}</span>
                  {host.hostname && <span style={{ marginLeft: '10px', color: '#8b949e' }}>({host.hostname})</span>}
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{ 
                    background: host.status === 'up' ? '#238636' : '#da3633', 
                    color: '#fff',
                    padding: '2px 8px', 
                    borderRadius: '12px', 
                    fontSize: '12px',
                    fontWeight: 'bold'
                  }}>
                    {host.status ? host.status.toUpperCase() : 'UNKNOWN'}
                  </span>
                  
                  {/* Botão MÁGICO 1-Click Auto-Attack */}
                  <button
                    onClick={() => handleAutoAttack(host.id, host.ip)}
                    disabled={attackingHostId === host.id}
                    style={{
                      background: attackingHostId === host.id ? '#21262d' : '#da3633',
                      color: '#fff',
                      border: 'none',
                      padding: '6px 14px',
                      borderRadius: '6px',
                      cursor: attackingHostId === host.id ? 'not-allowed' : 'pointer',
                      fontWeight: 'bold',
                      fontSize: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px'
                    }}
                  >
                    {attackingHostId === host.id ? '⏳ Atacando...' : '⚔️ 1-Click Auto-Attack'}
                  </button>
                </div>
              </div>
              
              {/* Lista de Portas */}
              <div style={{ marginTop: '15px', display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: '10px' }}>
                {host.ports && host.ports.map(port => (
                  <div key={port.id || `${port.port}-${port.protocol}`} style={{ background: '#0d1117', border: '1px solid #30363d', padding: '10px', borderRadius: '6px', fontSize: '14px' }}>
                    <div style={{ color: '#f0883e', fontWeight: 'bold' }}>{port.port}/{port.protocol}</div>
                    <div style={{ color: '#7ee787' }}>{port.service}</div>
                    {port.version && <div style={{ color: '#8b949e', fontSize: '12px' }}>{port.version}</div>}
                  </div>
                ))}
              </div>

              {/* Botões de Ação Rápida */}
              <div style={{ marginTop: '15px', display: 'flex', gap: '10px', borderTop: '1px solid #30363d', paddingTop: '15px', flexWrap: 'wrap' }}>
                <button 
                  onClick={() => sendToTool('nikto', host.ip)}
                  style={btnStyle}
                >🛡️ Nikto Web Scan</button>
                
                <button 
                  onClick={() => sendToTool('gobuster', host.ip)}
                  style={btnStyle}
                >📁 Gobuster Dir</button>

                {host.ports && host.ports.some(p => p.port == 445 || p.port == '445') && (
                  <button 
                    onClick={() => sendToTool('enum4linux', host.ip)}
                    style={btnStyle}
                  >🔧 Enum4Linux</button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Console de Auto-Attack em Tempo Real */}
      {logs.length > 0 && (
        <div style={{ marginTop: '24px', background: '#010409', border: '1px solid #30363d', borderRadius: '8px', padding: '16px', color: '#c9d1d9', fontFamily: 'Consolas, monospace', fontSize: '13px', lineHeight: '1.5', maxHeight: '250px', overflowY: 'auto' }}>
          <div style={{ color: '#58a6ff', fontWeight: 'bold', marginBottom: '8px', borderBottom: '1px solid #21262d', paddingBottom: '4px' }}>
            📺 Console de Execução Tática (Auto-Attack Logs)
          </div>
          {logs.map((log, i) => (
            <div key={i} style={{ marginBottom: '4px', color: log.includes('✅') ? '#3fb950' : log.includes('❌') ? '#f85149' : '#8b949e' }}>
              {log}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

const btnStyle = {
  background: '#21262d',
  border: '1px solid #30363d',
  color: '#c9d1d9',
  padding: '8px 12px',
  borderRadius: '6px',
  cursor: 'pointer',
  fontSize: '13px',
  transition: '0.2s'
};
