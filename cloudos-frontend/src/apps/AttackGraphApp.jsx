import React, { useState, useEffect } from 'react';

export default function AttackGraphApp({ openApp }) {
  const [hosts, setHosts] = useState([]);
  const [selectedHost, setSelectedHost] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      try {
        const res = await fetch('/api/akb/hosts', {
          headers: { 'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}` }
        });
        if (res.ok) {
          const data = await res.json();
          setHosts(Array.isArray(data) ? data : []);
          if (Array.isArray(data) && data.length > 0) {
            setSelectedHost(data[0]);
          }
        }
      } catch (err) {
        console.error('Erro ao carregar dados do Attack Graph:', err);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  const sendToTool = (toolId, target) => {
    if (openApp) {
      openApp('toolrunner', { toolId, target });
    }
  };

  if (loading) {
    return (
      <div style={{ padding: '30px', color: '#58a6ff', background: '#0d1117', height: '100%', fontFamily: 'Segoe UI, sans-serif' }}>
        ⚡ Carregando Mapeamento da Superfície de Ataque...
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', width: '100%', background: '#0d1117', color: '#c9d1d9', fontFamily: 'Segoe UI, sans-serif', overflow: 'hidden' }}>
      {/* Top Bar Header */}
      <div style={{ padding: '12px 20px', background: '#161b22', borderBottom: '1px solid #30363d', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <span style={{ fontSize: '20px' }}>🗺️</span>
          <h3 style={{ margin: 0, color: '#58a6ff', fontSize: '16px' }}>Attack Graph - Mapeamento Tático de Superfície</h3>
        </div>
        <span style={{ background: 'rgba(88,166,255,0.15)', color: '#58a6ff', padding: '4px 10px', borderRadius: '12px', fontSize: '12px', border: '1px solid rgba(88,166,255,0.3)', fontWeight: 'bold' }}>
          {hosts.length} Host(s) Mapeado(s)
        </span>
      </div>

      {/* Main Graph & Detail Layout */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Visual Graph Canvas */}
        <div style={{ flex: 1, padding: '20px', position: 'relative', overflow: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          {hosts.length === 0 ? (
            <div style={{ marginTop: '60px', textAlign: 'center', color: '#8b949e' }}>
              <div style={{ fontSize: '48px', marginBottom: '10px' }}>🕸️</div>
              <p style={{ fontSize: '16px', fontWeight: 'bold' }}>Nenhum host encontrado para gerar o Attack Graph.</p>
              <p style={{ fontSize: '13px' }}>Execute varreduras no <strong>Tool Runner</strong> para popular a Active Knowledge Base.</p>
            </div>
          ) : (
            <svg style={{ width: '100%', height: '100%', minHeight: '500px' }}>
              <defs>
                <linearGradient id="lineGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#58a6ff" stopOpacity="0.8" />
                  <stop offset="100%" stopColor="#3fb950" stopOpacity="0.8" />
                </linearGradient>
              </defs>

              {/* Draw nodes & connections */}
              {hosts.map((host, idx) => {
                const centerX = 200 + (idx % 3) * 260;
                const centerY = 120 + Math.floor(idx / 3) * 220;
                const isSelected = selectedHost?.id === host.id;

                return (
                  <g key={host.id} style={{ cursor: 'pointer' }} onClick={() => setSelectedHost(host)}>
                    {/* Central Host Circle */}
                    <circle
                      cx={centerX}
                      cy={centerY}
                      r="40"
                      fill={isSelected ? '#1f6feb' : '#161b22'}
                      stroke={isSelected ? '#58a6ff' : '#30363d'}
                      strokeWidth={isSelected ? '3' : '2'}
                    />
                    <text x={centerX} y={centerY - 5} textAnchor="middle" fill="#fff" fontSize="18" fontWeight="bold">🖥️</text>
                    <text x={centerX} y={centerY + 15} textAnchor="middle" fill="#c9d1d9" fontSize="11" fontWeight="bold">{host.ip}</text>

                    {/* Port Satellite Nodes */}
                    {host.ports && host.ports.map((port, pIdx) => {
                      const totalPorts = host.ports.length;
                      const angle = (pIdx / totalPorts) * 2 * Math.PI - Math.PI / 2;
                      const radius = 90;
                      const portX = centerX + radius * Math.cos(angle);
                      const portY = centerY + radius * Math.sin(angle);

                      return (
                        <g key={port.id || pIdx} onClick={(e) => { e.stopPropagation(); setSelectedHost(host); }}>
                          {/* Animated Connection Line */}
                          <line
                            x1={centerX}
                            y1={centerY}
                            x2={portX}
                            y2={portY}
                            stroke="url(#lineGrad)"
                            strokeWidth="2"
                            strokeDasharray="4 4"
                          />
                          <circle cx={portX} cy={portY} r="22" fill="#0d1117" stroke="#30363d" strokeWidth="1.5" />
                          <text x={portX} y={portY + 4} textAnchor="middle" fill="#7ee787" fontSize="10" fontWeight="bold">
                            {port.port}
                          </text>
                        </g>
                      );
                    })}
                  </g>
                );
              })}
            </svg>
          )}
        </div>

        {/* Selected Host Inspector Panel */}
        {selectedHost && (
          <div style={{ width: '320px', background: '#161b22', borderLeft: '1px solid #30363d', padding: '16px', overflowY: 'auto' }}>
            <h4 style={{ margin: '0 0 10px 0', color: '#58a6ff' }}>🔍 Detalhes do Alvo</h4>
            <div style={{ background: '#0d1117', border: '1px solid #30363d', padding: '12px', borderRadius: '6px', marginBottom: '15px' }}>
              <div style={{ fontSize: '15px', fontWeight: 'bold', color: '#fff' }}>{selectedHost.ip}</div>
              {selectedHost.hostname && <div style={{ fontSize: '12px', color: '#8b949e' }}>Host: {selectedHost.hostname}</div>}
              <div style={{ marginTop: '8px' }}>
                <span style={{ background: selectedHost.status === 'up' ? '#238636' : '#da3633', color: '#fff', padding: '2px 8px', borderRadius: '10px', fontSize: '11px', fontWeight: 'bold' }}>
                  {selectedHost.status?.toUpperCase() || 'UNKNOWN'}
                </span>
              </div>
            </div>

            <h5 style={{ margin: '10px 0', color: '#8b949e' }}>Serviços Ativos ({selectedHost.ports?.length || 0})</h5>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginBottom: '20px' }}>
              {selectedHost.ports && selectedHost.ports.map((port, pIdx) => (
                <div key={pIdx} style={{ background: '#0d1117', border: '1px solid #30363d', padding: '8px 12px', borderRadius: '6px', fontSize: '12px' }}>
                  <div style={{ color: '#f0883e', fontWeight: 'bold' }}>{port.port}/{port.protocol}</div>
                  <div style={{ color: '#7ee787' }}>{port.service}</div>
                  {port.version && <div style={{ color: '#8b949e', fontSize: '11px' }}>{port.version}</div>}
                </div>
              ))}
            </div>

            <h5 style={{ margin: '10px 0', color: '#8b949e' }}>Ações Rápidas</h5>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <button
                onClick={() => sendToTool('nikto', selectedHost.ip)}
                style={actionBtnStyle}
              >
                🛡️ Disparar Nikto Scan
              </button>
              <button
                onClick={() => sendToTool('gobuster', selectedHost.ip)}
                style={actionBtnStyle}
              >
                📁 Disparar Gobuster Dir
              </button>
              <button
                onClick={() => sendToTool('nmap', selectedHost.ip)}
                style={actionBtnStyle}
              >
                🔍 Re-escanear Nmap
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

const actionBtnStyle = {
  background: '#21262d',
  border: '1px solid #30363d',
  color: '#c9d1d9',
  padding: '8px 12px',
  borderRadius: '6px',
  cursor: 'pointer',
  fontSize: '12px',
  textAlign: 'left',
  transition: '0.2s'
};
