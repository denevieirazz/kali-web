import React, { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';

export function NmapScannerApp() {
  const [target, setTarget] = useState('');
  const [profile, setProfile] = useState('fast');
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);

  const getToken = () => localStorage.getItem('cloudos_token');

  const profiles = [
    { id: 'fast',     icon: '⚡', name: 'Varredura Rápida',     desc: 'Checa as 100 portas mais comuns em segundos' },
    { id: 'versions', icon: '🔍', name: 'Detectar Versões',     desc: 'Identifica qual serviço roda em cada porta' },
    { id: 'os',       icon: '💻', name: 'Detectar Sistema',     desc: 'Tenta adivinhar o Sistema Operacional do alvo' },
    { id: 'intense',  icon: '🔥', name: 'Varredura Intensa',    desc: 'Scan completo (pode demorar minutos)' }
  ];

  const handleScan = useCallback(async () => {
    if (!target) { setError('Digite um IP ou URL alvo!'); return; }
    
    setScanning(true);
    setError(null);
    setResults(null);

    try {
      const res = await fetch(`${API_BASE}/api/nmap/scan`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ target, profile })
      });
      
      const data = await res.json();
      if (data.success) {
        setResults(data);
      } else {
        setError(data.error || 'Erro desconhecido');
      }
    } catch (err) {
      setError('Falha de comunicação com o backend');
    } finally {
      setScanning(false);
    }
  }, [target, profile]);

  const getStateColor = (state) => {
    if (state === 'open') return '#3fb950';
    if (state === 'closed') return '#f85149';
    return '#8b949e';
  };

  return (
    <div style={styles.container}>
      {/* PAINEL DE CONTROLE SUPERIOR */}
      <div style={styles.controlPanel}>
        <div style={styles.inputGroup}>
          <label style={styles.label}>🎯 Alvo (IP ou URL)</label>
          <input
            style={styles.targetInput}
            placeholder="Ex: 192.168.1.1 ou scanme.nmap.org"
            value={target}
            onChange={(e) => setTarget(e.target.value)}
          />
        </div>
        
        <button 
          style={{ ...styles.btnScan, ...(scanning ? styles.btnDisabled : {}) }}
          onClick={handleScan}
          disabled={scanning}
        >
          {scanning ? '⏳ Escaneando...' : '🚀 Iniciar Varredura'}
        </button>
      </div>

      {/* SELEÇÃO DE PERFIS (CLIQUE NO BOTÃO) */}
      <div style={styles.profilesGrid}>
        {profiles.map(p => (
          <div
            key={p.id}
            style={{
              ...styles.profileCard,
              borderColor: profile === p.id ? '#58a6ff' : '#30363d',
              background: profile === p.id ? 'rgba(88, 166, 255, 0.1)' : 'transparent'
            }}
            onClick={() => setProfile(p.id)}
          >
            <span style={{ fontSize: '24px' }}>{p.icon}</span>
            <div style={styles.profileName}>{p.name}</div>
            <div style={styles.profileDesc}>{p.desc}</div>
          </div>
        ))}
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {/* ÁREA DE RESULTADOS */}
      {scanning && (
        <div style={styles.loadingBox}>
          <div style={styles.spinner} />
          <div style={styles.loadingText}>Executando Nmap no Kali Linux via WSL2...</div>
        </div>
      )}

      {!scanning && results && (
        <div style={styles.resultsContainer}>
          <h3 style={styles.resultsTitle}>
            📡 Resultados para: {results.target}
          </h3>
          
          {results.hosts.length === 0 ? (
            <div style={styles.noResults}>Nenhum host ativo encontrado.</div>
          ) : (
            results.hosts.map((host, idx) => (
              <div key={idx} style={styles.hostCard}>
                <div style={styles.hostHeader}>
                  <span style={styles.hostIp}>🖥️ {host.ip}</span>
                  <span style={styles.hostStatus}>● ATIVO</span>
                </div>
                
                {host.ports.length > 0 ? (
                  <table style={styles.table}>
                    <thead>
                      <tr style={styles.tableHeader}>
                        <th style={styles.th}>Porta</th>
                        <th style={styles.th}>Estado</th>
                        <th style={styles.th}>Serviço</th>
                        <th style={styles.th}>Versão</th>
                      </tr>
                    </thead>
                    <tbody>
                      {host.ports.map((port, i) => (
                        <tr key={i} style={styles.tableRow}>
                          <td style={styles.td}><strong style={{color: '#58a6ff'}}>{port.port}/{port.protocol}</strong></td>
                          <td style={{ ...styles.td, color: getStateColor(port.state) }}>
                            {port.state === 'open' ? 'Aberta' : 'Fechada'}
                          </td>
                          <td style={styles.td}>{port.service}</td>
                          <td style={{ ...styles.td, color: '#8b949e' }}>{port.version || '-'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                ) : (
                  <div style={styles.noPorts}>Nenhuma porta aberta encontrada neste perfil.</div>
                )}
              </div>
            ))
          )}
          
          {/* Box educacional mostrando o comando equivalente */}
          <div style={styles.cmdBox}>
            <span style={{color: '#8b949e'}}>Comando equivalente no terminal:</span>
            <code style={styles.cmdCode}>{results.rawCommand}</code>
          </div>
        </div>
      )}
    </div>
  );
}

const styles = {
  container: { padding: '20px', height: '100%', overflowY: 'auto', background: '#0d1117', fontFamily: 'sans-serif' },
  controlPanel: { display: 'flex', gap: '16px', marginBottom: '20px', alignItems: 'flex-end', background: '#161b22', padding: '16px', borderRadius: '8px', border: '1px solid #30363d' },
  inputGroup: { flex: 1 },
  label: { display: 'block', color: '#8b949e', fontSize: '12px', marginBottom: '6px', fontWeight: 'bold' },
  targetInput: { width: '100%', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box' },
  btnScan: { padding: '10px 20px', background: '#238636', color: '#fff', border: '1px solid #2ea043', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px', whiteSpace: 'nowrap' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  profilesGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '12px', marginBottom: '24px' },
  profileCard: { padding: '16px', border: '1px solid', borderRadius: '8px', cursor: 'pointer', textAlign: 'center', transition: 'all 0.2s' },
  profileName: { color: '#c9d1d9', fontSize: '13px', fontWeight: 'bold', margin: '8px 0 4px 0' },
  profileDesc: { color: '#8b949e', fontSize: '10px', lineHeight: '1.4' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', gap: '16px' },
  spinner: { width: '32px', height: '32px', border: '3px solid #30363d', borderTopColor: '#58a6ff', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#58a6ff', fontSize: '14px' },
  resultsContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '20px' },
  resultsTitle: { color: '#58a6ff', marginTop: 0, marginBottom: '16px', fontSize: '16px' },
  noResults: { color: '#8b949e', textAlign: 'center', padding: '20px' },
  hostCard: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', marginBottom: '16px', overflow: 'hidden' },
  hostHeader: { display: 'flex', justifyContent: 'space-between', padding: '12px 16px', background: '#161b22', borderBottom: '1px solid #30363d' },
  hostIp: { color: '#c9d1d9', fontWeight: 'bold', fontSize: '14px' },
  hostStatus: { color: '#3fb950', fontSize: '12px' },
  table: { width: '100%', borderCollapse: 'collapse' },
  tableHeader: { borderBottom: '1px solid #30363d' },
  th: { padding: '8px 12px', textAlign: 'left', color: '#8b949e', fontSize: '11px', textTransform: 'uppercase' },
  tableRow: { borderBottom: '1px solid #21262d' },
  td: { padding: '10px 12px', color: '#c9d1d9', fontSize: '13px' },
  noPorts: { padding: '16px', color: '#8b949e', fontSize: '13px', textAlign: 'center' },
  cmdBox: { marginTop: '20px', padding: '12px', background: '#0d1117', borderRadius: '6px', border: '1px solid #30363d' },
  cmdCode: { display: 'block', color: '#3fb950', marginTop: '6px', fontSize: '12px', fontFamily: 'monospace' }
};

export default NmapScannerApp;
