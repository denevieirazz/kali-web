import React, { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';

export function NmapScannerApp() {
  const [target, setTarget] = useState('');
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);

  // Estado das opções avançadas
  const [opts, setOpts] = useState({
    scanType: 'connect', // syn, connect, udp, ack, ping
    versionDetection: true,
    osDetection: false,
    nseScripts: false,
    aggressive: false,
    skipPing: false,
    portRange: '',
    timing: 4 // T0 a T5
  });

  const getToken = () => localStorage.getItem('cloudos_token');

  const handleOptChange = (key, value) => {
    setOpts(prev => ({ ...prev, [key]: value }));
  };

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
        body: JSON.stringify({ target, options: opts })
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
  }, [target, opts]);

  const getStateColor = (state) => {
    if (state === 'open') return '#3fb950';
    if (state === 'closed') return '#f85149';
    return '#8b949e';
  };

  return (
    <div style={styles.container}>
      {/* BARRA SUPERIOR FIXA */}
      <div style={styles.topBar}>
        <div style={styles.inputGroup}>
          <label style={styles.label}>🎯 Alvo (IP / URL / Rede)</label>
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
          {scanning ? '⏳ Escaneando...' : '🚀 Executar Varredura'}
        </button>
      </div>

      <div style={styles.mainArea}>
        {/* PAINEL ESQUERDO DE OPÇÕES */}
        <div style={styles.optionsPanel}>
          
          <div style={styles.optSection}>
            <div style={styles.optTitle}>Tipo de Scan</div>
            <div style={styles.btnGroup}>
              {[
                { val: 'syn', label: 'SYN (-sS)' },
                { val: 'connect', label: 'Connect (-sT)' },
                { val: 'udp', label: 'UDP (-sU)' },
                { val: 'ack', label: 'ACK (-sA)' },
                { val: 'ping', label: 'Ping (-sn)' }
              ].map(t => (
                <button 
                  key={t.val} 
                  style={opts.scanType === t.val ? styles.toggleBtnActive : styles.toggleBtn}
                  onClick={() => handleOptChange('scanType', t.val)}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </div>

          <div style={styles.optSection}>
            <div style={styles.optTitle}>Detecções</div>
            <div style={styles.checkGroup}>
              <label style={styles.checkLabel}>
                <input type="checkbox" checked={opts.versionDetection} onChange={(e) => handleOptChange('versionDetection', e.target.checked)} /> Versões (-sV)
              </label>
              <label style={styles.checkLabel}>
                <input type="checkbox" checked={opts.osDetection} onChange={(e) => handleOptChange('osDetection', e.target.checked)} /> SO (-O)
              </label>
              <label style={styles.checkLabel}>
                <input type="checkbox" checked={opts.nseScripts} onChange={(e) => handleOptChange('nseScripts', e.target.checked)} /> Scripts (-sC)
              </label>
              <label style={styles.checkLabel}>
                <input type="checkbox" checked={opts.aggressive} onChange={(e) => handleOptChange('aggressive', e.target.checked)} /> Agressivo (-A)
              </label>
            </div>
          </div>

          <div style={styles.optSection}>
            <div style={styles.optTitle}>Configurações</div>
            <label style={styles.checkLabel}>
              <input type="checkbox" checked={opts.skipPing} onChange={(e) => handleOptChange('skipPing', e.target.checked)} /> Pular Descoberta de Host (-Pn)
            </label>
            
            <label style={styles.label}>Portas (ex: 80,443,1-1000 ou vazio para padrão)</label>
            <input
              style={styles.textInput}
              value={opts.portRange}
              onChange={(e) => handleOptChange('portRange', e.target.value)}
              placeholder="Todas as portas padrão"
            />
          </div>

          <div style={styles.optSection}>
            <div style={styles.optTitle}>Velocidade (Timing)</div>
            <div style={styles.btnGroup}>
              {[0, 1, 2, 3, 4, 5].map(t => (
                <button 
                  key={t} 
                  style={opts.timing === t ? styles.toggleBtnActive : styles.toggleBtn}
                  onClick={() => handleOptChange('timing', t)}
                  title={`T${t}`}
                >
                  {t}
                </button>
              ))}
            </div>
            <div style={{ fontSize: '10px', color: '#8b949e', marginTop: '4px' }}>
              0 = Paranoid | 5 = Insane
            </div>
          </div>

        </div>

        {/* PAINEL DIREITO DE RESULTADOS */}
        <div style={styles.resultsPanel}>
          {error && <div style={styles.errorBox}>⚠️ {error}</div>}

          {scanning && (
            <div style={styles.loadingBox}>
              <div style={styles.spinner} />
              <div style={styles.loadingText}>Executando Nmap no Kali Linux...</div>
              <div style={styles.loadingSubtext}>(Scans de UDP ou todas as portas podem demorar minutos)</div>
            </div>
          )}

          {!scanning && !results && (
            <div style={styles.emptyState}>
              <div style={{fontSize: '48px', marginBottom: '16px'}}>📡</div>
              <div style={{color: '#8b949e'}}>Configure as opções ao lado e inicie a varredura.</div>
            </div>
          )}

          {!scanning && results && (
            <div style={styles.resultsContainer}>
              <div style={styles.cmdBox}>
                <span style={{color: '#8b949e', marginRight: '8px'}}>CMD:</span>
                <code style={styles.cmdCode}>{results.rawCommand}</code>
              </div>
              
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
                      <div style={styles.noPorts}>Nenhuma porta aberta encontrada.</div>
                    )}
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

const styles = {
  container: { display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', fontFamily: 'sans-serif', color: '#c9d1d9' },
  topBar: { display: 'flex', gap: '16px', padding: '16px', background: '#161b22', borderBottom: '1px solid #30363d', alignItems: 'flex-end' },
  inputGroup: { flex: 1 },
  label: { display: 'block', color: '#8b949e', fontSize: '11px', marginBottom: '4px', fontWeight: 'bold' },
  targetInput: { width: '100%', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box' },
  btnScan: { padding: '10px 20px', background: '#238636', color: '#fff', border: '1px solid #2ea043', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontSize: '14px', whiteSpace: 'nowrap', height: '40px', fontFamily: 'sans-serif' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  
  mainArea: { display: 'flex', flex: 1, overflow: 'hidden' },
  
  optionsPanel: { width: '280px', background: '#0d1117', borderRight: '1px solid #30363d', padding: '16px', overflowY: 'auto' },
  optSection: { marginBottom: '24px', paddingBottom: '16px', borderBottom: '1px solid #21262d' },
  optTitle: { color: '#58a6ff', fontSize: '12px', fontWeight: 'bold', marginBottom: '10px', textTransform: 'uppercase' },
  btnGroup: { display: 'flex', flexWrap: 'wrap', gap: '6px' },
  toggleBtn: { padding: '6px 10px', background: '#161b22', border: '1px solid #30363d', borderRadius: '4px', color: '#8b949e', cursor: 'pointer', fontSize: '11px', fontFamily: 'sans-serif' },
  toggleBtnActive: { padding: '6px 10px', background: 'rgba(88, 166, 255, 0.2)', border: '1px solid #58a6ff', borderRadius: '4px', color: '#58a6ff', cursor: 'pointer', fontSize: '11px', fontWeight: 'bold', fontFamily: 'sans-serif' },
  checkGroup: { display: 'flex', flexDirection: 'column', gap: '8px' },
  checkLabel: { display: 'flex', alignItems: 'center', gap: '8px', color: '#c9d1d9', fontSize: '12px', cursor: 'pointer' },
  textInput: { width: '100%', padding: '6px', background: '#161b22', border: '1px solid #30363d', borderRadius: '4px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '12px', boxSizing: 'border-box', marginTop: '6px' },

  resultsPanel: { flex: 1, padding: '16px', overflowY: 'auto' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: '12px' },
  spinner: { width: '32px', height: '32px', border: '3px solid #30363d', borderTopColor: '#58a6ff', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#58a6ff', fontSize: '14px' },
  loadingSubtext: { color: '#8b949e', fontSize: '11px' },
  emptyState: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  resultsContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '16px' },
  cmdBox: { background: '#0d1117', border: '1px solid #30363d', padding: '8px 12px', borderRadius: '4px', marginBottom: '16px', display: 'flex', alignItems: 'center' },
  cmdCode: { color: '#3fb950', fontSize: '12px', wordBreak: 'break-all', fontFamily: 'monospace' },
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
  noPorts: { padding: '16px', color: '#8b949e', fontSize: '13px', textAlign: 'center' }
};

export default NmapScannerApp;
