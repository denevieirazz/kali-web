import React, { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';

export function HashCrackerApp() {
  const [hash, setHash] = useState('');
  const [format, setFormat] = useState('md5');
  const [cracking, setCracking] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [showLogs, setShowLogs] = useState(false);

  const getToken = () => localStorage.getItem('cloudos_token');

  const handleCrack = useCallback(async () => {
    if (!hash) { setError('Cole um hash para quebrar!'); return; }
    
    setCracking(true);
    setError(null);
    setResult(null);

    try {
      const res = await fetch(`${API_BASE}/api/hashcracker/crack`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ hash, format })
      });
      
      const data = await res.json();
      if (data.success) {
        setResult(data);
      } else {
        setError(data.error || 'Erro desconhecido');
      }
    } catch (err) {
      setError('Falha de comunicação com o backend');
    } finally {
      setCracking(false);
    }
  }, [hash, format]);

  const formats = [
    { id: 'md5', name: 'MD5' },
    { id: 'sha1', name: 'SHA-1' },
    { id: 'sha256', name: 'SHA-256' },
    { id: 'ntlm', name: 'NTLM (Windows)' }
  ];

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h2 style={styles.title}>🔐 Hash Cracker</h2>
        <p style={styles.subtitle}>Quebra de senhas via John the Ripper (Wordlist: rockyou.txt)</p>
      </div>

      <div style={styles.panel}>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Cole o Hash:</label>
          <textarea
            style={styles.hashInput}
            placeholder="Ex: 21232f297a57a5a743894a0e4a801fc3"
            value={hash}
            onChange={(e) => setHash(e.target.value)}
            disabled={cracking}
          />
        </div>

        <div style={styles.formatGroup}>
          <label style={styles.label}>Formato do Hash:</label>
          <div style={styles.btnGroup}>
            {formats.map(f => (
              <button
                key={f.id}
                style={format === f.id ? styles.formatBtnActive : styles.formatBtn}
                onClick={() => setFormat(f.id)}
                disabled={cracking}
              >
                {f.name}
              </button>
            ))}
          </div>
        </div>

        <button 
          style={{ ...styles.btnCrack, ...(cracking ? styles.btnDisabled : {}) }}
          onClick={handleCrack}
          disabled={cracking}
        >
          {cracking ? '⏳ Quebrando...' : '🔨 Iniciar Quebra'}
        </button>
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {cracking && (
        <div style={styles.loadingBox}>
          <div style={styles.spinner} />
          <div style={styles.loadingText}>Processando dicionário no Kali Linux...</div>
          <div style={styles.loadingSubtext}>Isso pode levar de segundos a minutos, dependendo da complexidade.</div>
        </div>
      )}

      {!cracking && result && (
        <div style={styles.resultContainer}>
          <div style={{
            ...styles.statusCard,
            borderColor: result.cracked ? '#3fb950' : '#f85149',
            background: result.cracked ? 'rgba(63, 185, 80, 0.1)' : 'rgba(248, 81, 73, 0.1)'
          }}>
            <div style={{ fontSize: '32px', marginBottom: '8px' }}>
              {result.cracked ? '✅' : '❌'}
            </div>
            <div style={{
              fontSize: '18px', fontWeight: 'bold',
              color: result.cracked ? '#3fb950' : '#f85149'
            }}>
              {result.cracked ? 'SENHA ENCONTRADA!' : 'SENHA NÃO ENCONTRADA'}
            </div>
            
            {result.cracked && result.password && (
              <div style={styles.passwordBox}>
                <span style={{color: '#8b949e', fontSize: '12px'}}>Senha em texto claro:</span>
                <code style={styles.passwordText}>{result.password}</code>
              </div>
            )}
          </div>

          <div style={styles.logSection}>
            <button style={styles.btnLogs} onClick={() => setShowLogs(!showLogs)}>
              {showLogs ? '🙈 Ocultar Logs Técnicos' : '🕵️ Ver Logs Técnicos'}
            </button>
            {showLogs && (
              <pre style={styles.logBox}>{result.logs}</pre>
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
  panel: { background: '#161b22', padding: '20px', borderRadius: '8px', border: '1px solid #30363d', marginBottom: '20px' },
  inputGroup: { marginBottom: '16px' },
  label: { display: 'block', color: '#8b949e', fontSize: '12px', marginBottom: '6px', fontWeight: 'bold' },
  hashInput: { width: '100%', height: '80px', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box', resize: 'none' },
  formatGroup: { marginBottom: '20px' },
  btnGroup: { display: 'flex', gap: '8px', flexWrap: 'wrap' },
  formatBtn: { padding: '8px 16px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#8b949e', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px' },
  formatBtnActive: { padding: '8px 16px', background: 'rgba(88, 166, 255, 0.2)', border: '1px solid #58a6ff', borderRadius: '6px', color: '#58a6ff', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px', fontWeight: 'bold' },
  btnCrack: { width: '100%', padding: '12px', background: '#da3633', color: '#fff', border: '1px solid #f85149', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', gap: '12px' },
  spinner: { width: '32px', height: '32px', border: '3px solid #30363d', borderTopColor: '#f85149', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#f85149', fontSize: '14px', fontWeight: 'bold' },
  loadingSubtext: { color: '#8b949e', fontSize: '12px' },
  resultContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '20px' },
  statusCard: { border: '2px solid', borderRadius: '8px', padding: '20px', textAlign: 'center', marginBottom: '16px' },
  passwordBox: { marginTop: '16px', padding: '12px', background: '#0d1117', borderRadius: '6px', border: '1px solid #30363d' },
  passwordText: { display: 'block', color: '#3fb950', fontSize: '20px', fontWeight: 'bold', marginTop: '4px', wordBreak: 'break-all', fontFamily: 'monospace' },
  logSection: { marginTop: '20px', borderTop: '1px solid #30363d', paddingTop: '16px' },
  btnLogs: { background: 'transparent', color: '#8b949e', border: '1px solid #30363d', padding: '8px 16px', borderRadius: '6px', cursor: 'pointer', fontFamily: 'sans-serif', fontSize: '12px', marginBottom: '12px' },
  logBox: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', color: '#8b949e', fontSize: '11px', maxHeight: '200px', overflowY: 'auto', whiteSpace: 'pre-wrap', fontFamily: 'monospace' }
};

export default HashCrackerApp;
