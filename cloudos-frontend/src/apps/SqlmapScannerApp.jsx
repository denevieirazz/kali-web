import React, { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';

export function SqlmapScannerApp() {
  const [url, setUrl] = useState('');
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);
  const [showLogs, setShowLogs] = useState(false);

  const getToken = () => localStorage.getItem('cloudos_token');

  const handleScan = useCallback(async () => {
    if (!url) { setError('Digite uma URL alvo!'); return; }
    
    setScanning(true);
    setError(null);
    setResults(null);

    try {
      const res = await fetch(`${API_BASE}/api/sqlmap/scan`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ url })
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
  }, [url]);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h2 style={styles.title}>🕷️ SQLmap Web Exploiter</h2>
        <p style={styles.subtitle}>Teste automático de SQL Injection (Zero Terminal)</p>
      </div>

      {/* PAINEL DE CONTROLE */}
      <div style={styles.controlPanel}>
        <input
          style={styles.urlInput}
          placeholder="Ex: http://exemplo.com/pagina.php?id=1"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          disabled={scanning}
        />
        <button 
          style={{ ...styles.btnScan, ...(scanning ? styles.btnDisabled : {}) }}
          onClick={handleScan}
          disabled={scanning}
        >
          {scanning ? '⏳ Injetando...' : '💥 Testar SQL Injection'}
        </button>
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {/* ESTADO DE LOADING */}
      {scanning && (
        <div style={styles.loadingBox}>
          <div style={styles.spinner} />
          <div style={styles.loadingText}>Analisando alvo... Isso pode levar até 3 minutos.</div>
          <div style={styles.loadingSubtext}>O SQLmap está testando milhares de payloads no backend.</div>
        </div>
      )}

      {/* RESULTADOS */}
      {!scanning && results && (
        <div style={styles.resultsContainer}>
          
          {/* Cartão de Status Principal */}
          <div style={{
            ...styles.statusCard,
            borderColor: results.vulnerable ? '#3fb950' : '#f85149',
            background: results.vulnerable ? 'rgba(63, 185, 80, 0.1)' : 'rgba(248, 81, 73, 0.1)'
          }}>
            <div style={{ fontSize: '32px', marginBottom: '8px' }}>
              {results.vulnerable ? '✅' : '❌'}
            </div>
            <div style={{
              fontSize: '18px',
              fontWeight: 'bold',
              color: results.vulnerable ? '#3fb950' : '#f85149'
            }}>
              {results.vulnerable ? 'ALVO VULNERÁVEL!' : 'ALVO SEGURO (Não vulnerável)'}
            </div>
            
            {results.dbms !== 'Desconhecido' && (
              <div style={{ marginTop: '8px', color: '#c9d1d9' }}>
                Banco de Dados Detectado: <strong style={{color: '#58a6ff'}}>{results.dbms}</strong>
              </div>
            )}
            
            {results.payload && (
              <div style={{ marginTop: '8px', color: '#8b949e', fontSize: '12px' }}>
                Payload utilizado: <code style={styles.codeBlock}>{results.payload}</code>
              </div>
            )}
          </div>

          {/* Árvore Visual de Bancos de Dados */}
          {results.databases.length > 0 && (
            <div style={styles.treeSection}>
              <h3 style={styles.treeTitle}>🗄️ Bancos de Dados Encontrados ({results.databases.length})</h3>
              <div style={styles.treeGrid}>
                {results.databases.map((db, i) => (
                  <div key={i} style={styles.treeNode}>
                    <span style={styles.treeIcon}>📁</span>
                    <span style={styles.treeLabel}>{db}</span>
                  </div>
                ))}
              </div>
              
              <div style={styles.infoNote}>
                ℹ️ Para explorar as tabelas e colunas destes bancos em detalhe, use o Terminal Integrado com o comando: 
                <code style={styles.codeBlock}>sqlmap -u "{url}" --tables -D {results.databases[0]}</code>
              </div>
            </div>
          )}

          {/* Toggle de Logs Técnicos */}
          <div style={styles.logSection}>
            <button style={styles.btnLogs} onClick={() => setShowLogs(!showLogs)}>
              {showLogs ? '🙈 Ocultar Logs Técnicos' : '🕵️ Ver Logs Técnicos'}
            </button>
            {showLogs && (
              <pre style={styles.logBox}>{results.logs}</pre>
            )}
          </div>

        </div>
      )}
    </div>
  );
}

const styles = {
  container: { padding: '20px', height: '100%', overflowY: 'auto', background: '#0d1117', fontFamily: 'sans-serif' },
  header: { marginBottom: '20px', borderBottom: '1px solid #30363d', paddingBottom: '16px' },
  title: { color: '#58a6ff', fontSize: '20px', margin: '0 0 4px 0' },
  subtitle: { color: '#8b949e', fontSize: '12px', margin: 0 },
  controlPanel: { display: 'flex', gap: '12px', marginBottom: '24px', background: '#161b22', padding: '16px', borderRadius: '8px', border: '1px solid #30363d' },
  urlInput: { flex: 1, padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px' },
  btnScan: { padding: '10px 20px', background: '#da3633', color: '#fff', border: '1px solid #f85149', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px', whiteSpace: 'nowrap' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', gap: '12px' },
  spinner: { width: '40px', height: '40px', border: '4px solid #30363d', borderTopColor: '#f85149', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#f85149', fontSize: '16px', fontWeight: 'bold' },
  loadingSubtext: { color: '#8b949e', fontSize: '12px' },
  resultsContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '20px' },
  statusCard: { border: '2px solid', borderRadius: '8px', padding: '20px', textAlign: 'center', marginBottom: '24px' },
  treeSection: { marginTop: '16px' },
  treeTitle: { color: '#58a6ff', fontSize: '16px', marginBottom: '12px' },
  treeGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '12px', marginBottom: '16px' },
  treeNode: { display: 'flex', alignItems: 'center', gap: '8px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px' },
  treeIcon: { fontSize: '18px' },
  treeLabel: { color: '#c9d1d9', fontSize: '14px', fontWeight: 'bold' },
  infoNote: { background: 'rgba(88, 166, 255, 0.1)', border: '1px solid #58a6ff', borderRadius: '6px', padding: '12px', fontSize: '12px', color: '#8b949e' },
  codeBlock: { display: 'inline-block', background: '#0d1117', padding: '2px 6px', borderRadius: '4px', color: '#3fb950', marginTop: '4px', fontSize: '11px', fontFamily: 'monospace' },
  logSection: { marginTop: '24px', borderTop: '1px solid #30363d', paddingTop: '16px' },
  btnLogs: { background: 'transparent', color: '#8b949e', border: '1px solid #30363d', padding: '8px 16px', borderRadius: '6px', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px', marginBottom: '12px' },
  logBox: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', color: '#8b949e', fontSize: '11px', maxHeight: '300px', overflowY: 'auto', whiteSpace: 'pre-wrap', fontFamily: 'monospace' }
};

export default SqlmapScannerApp;
