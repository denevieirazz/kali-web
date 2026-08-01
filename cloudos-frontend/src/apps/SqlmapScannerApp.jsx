import React, { useState, useCallback, useRef, useEffect } from 'react';

const API_BASE = 'http://localhost:8080';

export function SqlmapScannerApp() {
  const [url, setUrl] = useState('');
  const [lang, setLang] = useState('pt'); // pt ou en
  const [scanning, setScanning] = useState(false);
  const [logs, setLogs] = useState([]);
  const [question, setQuestion] = useState(null);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);
  const eventSourceRef = useRef(null);
  const logEndRef = useRef(null);

  const getToken = () => localStorage.getItem('cloudos_token');

  useEffect(() => {
    return () => {
      if (eventSourceRef.current) eventSourceRef.current.close();
    };
  }, []);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  const handleAnswer = async (ans) => {
    if (!eventSourceRef.current?.scanId) return;
    setQuestion(null);
    
    await fetch(`${API_BASE}/api/sqlmap/answer/${eventSourceRef.current.scanId}`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${getToken()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ answer: ans })
    });
  };

  const handleScan = useCallback(async () => {
    if (!url) { setError('Digite uma URL alvo!'); return; }
    
    setScanning(true);
    setError(null);
    setResults(null);
    setLogs([]);
    setQuestion(null);

    try {
      const startRes = await fetch(`${API_BASE}/api/sqlmap/scan`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ url, lang })
      });
      const { scanId } = await startRes.json();

      const sse = new EventSource(`${API_BASE}/api/sqlmap/events/${scanId}?token=${getToken()}`);
      eventSourceRef.current = sse;
      eventSourceRef.current.scanId = scanId;

      sse.addEventListener('message', (e) => {
        const data = JSON.parse(e.data);
        setLogs(prev => [...prev, data.text]);
      });

      sse.addEventListener('question', (e) => {
        const data = JSON.parse(e.data);
        setQuestion(data);
      });

      sse.addEventListener('done', (e) => {
        const data = JSON.parse(e.data);
        setResults(data);
        setScanning(false);
        sse.close();
      });

      sse.onerror = () => {
        setScanning(false);
        sse.close();
      };

    } catch (err) {
      setError('Falha de comunicação com o backend');
      setScanning(false);
    }
  }, [url, lang]);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h2 style={styles.title}>🕷️ SQLmap Web Exploiter</h2>
        <p style={styles.subtitle}>Controle total das decisões com interface visual e tradução</p>
      </div>

      <div style={styles.controlPanel}>
        <input
          style={styles.urlInput}
          placeholder="Ex: http://exemplo.com/pagina.php?id=1"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          disabled={scanning}
        />
        
        {/* SELETOR DE IDIOMA */}
        <div style={styles.langSelector}>
          <button 
            style={{ ...styles.langBtn, opacity: lang === 'pt' ? 1 : 0.5 }}
            onClick={() => setLang('pt')}
            title="Português"
          >🇧🇷</button>
          <button 
            style={{ ...styles.langBtn, opacity: lang === 'en' ? 1 : 0.5 }}
            onClick={() => setLang('en')}
            title="Inglês"
          >🇺🇸</button>
        </div>

        <button 
          style={{ ...styles.btnScan, ...(scanning ? styles.btnDisabled : {}) }}
          onClick={handleScan}
          disabled={scanning}
        >
          {scanning ? '⏳ Escaneando...' : '💥 Iniciar Ataque'}
        </button>
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {(scanning || logs.length > 0) && (
        <div style={styles.consoleArea}>
          <div style={styles.consoleHeader}>
            🔴 Terminal Interativo CloudOS {lang === 'pt' && <span style={{color: '#3fb950', marginLeft: '8px'}}>(Traduzido)</span>}
          </div>
          <div style={styles.consoleBody}>
            {logs.map((log, i) => (
              <pre key={i} style={styles.logLine}>{log}</pre>
            ))}
            
            {question && (
              <div style={styles.questionCard}>
                <div style={styles.questionIcon}>❓</div>
                <div style={styles.questionContent}>
                  <div style={styles.questionText}>{question.text}</div>
                  <div style={styles.btnGroup}>
                    <button style={styles.btnYes} onClick={() => handleAnswer('Y')}>
                      ✅ Sim (Y)
                    </button>
                    <button style={styles.btnNo} onClick={() => handleAnswer('N')}>
                      ❌ Não (N)
                    </button>
                  </div>
                </div>
              </div>
            )}
            <div ref={logEndRef} />
          </div>
        </div>
      )}

      {!scanning && results && (
        <div style={styles.resultsContainer}>
          <div style={{
            ...styles.statusCard,
            borderColor: results.vulnerable ? '#3fb950' : '#f85149',
            background: results.vulnerable ? 'rgba(63, 185, 80, 0.1)' : 'rgba(248, 81, 73, 0.1)'
          }}>
            <div style={{ fontSize: '32px', marginBottom: '8px' }}>
              {results.vulnerable ? '✅' : '❌'}
            </div>
            <div style={{
              fontSize: '18px', fontWeight: 'bold',
              color: results.vulnerable ? '#3fb950' : '#f85149'
            }}>
              {results.vulnerable ? 'ALVO VULNERÁVEL!' : 'ALVO SEGURO (Não vulnerável)'}
            </div>
            {results.dbms !== 'Desconhecido' && (
              <div style={{ marginTop: '8px', color: '#c9d1d9' }}>
                Banco de Dados: <strong style={{color: '#58a6ff'}}>{results.dbms}</strong>
              </div>
            )}
            {results.payload && (
              <div style={{ marginTop: '8px', color: '#8b949e', fontSize: '12px' }}>
                Payload: <code style={styles.codeBlock}>{results.payload}</code>
              </div>
            )}
          </div>

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
            </div>
          )}
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
  controlPanel: { display: 'flex', gap: '12px', marginBottom: '20px', background: '#161b22', padding: '16px', borderRadius: '8px', border: '1px solid #30363d', alignItems: 'center' },
  urlInput: { flex: 1, padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px' },
  langSelector: { display: 'flex', gap: '4px', background: '#0d1117', padding: '4px', borderRadius: '6px', border: '1px solid #30363d' },
  langBtn: { background: 'transparent', border: 'none', cursor: 'pointer', fontSize: '20px', padding: '4px 8px', borderRadius: '4px', transition: 'opacity 0.2s' },
  btnScan: { padding: '10px 20px', background: '#da3633', color: '#fff', border: '1px solid #f85149', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontFamily: 'sans-serif', fontSize: '14px' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  consoleArea: { border: '1px solid #30363d', borderRadius: '8px', overflow: 'hidden', marginBottom: '20px' },
  consoleHeader: { background: '#161b22', color: '#8b949e', padding: '8px 16px', fontSize: '12px', borderBottom: '1px solid #30363d' },
  consoleBody: { background: '#010409', padding: '16px', maxHeight: '300px', overflowY: 'auto' },
  logLine: { color: '#8b949e', fontSize: '11px', margin: '0 0 4px 0', whiteSpace: 'pre-wrap', wordBreak: 'break-all', fontFamily: 'monospace' },
  questionCard: { display: 'flex', gap: '12px', background: 'rgba(88, 166, 255, 0.1)', border: '1px solid #58a6ff', borderRadius: '8px', padding: '12px', margin: '12px 0' },
  questionIcon: { fontSize: '24px' },
  questionContent: { flex: 1 },
  questionText: { color: '#c9d1d9', fontSize: '13px', marginBottom: '10px' },
  btnGroup: { display: 'flex', gap: '8px' },
  btnYes: { padding: '8px 16px', background: 'rgba(63, 185, 80, 0.2)', color: '#3fb950', border: '1px solid #3fb950', borderRadius: '6px', cursor: 'pointer', fontFamily: 'sans-serif', fontWeight: 'bold', fontSize: '12px' },
  btnNo: { padding: '8px 16px', background: 'rgba(248, 81, 73, 0.2)', color: '#f85149', border: '1px solid #f85149', borderRadius: '6px', cursor: 'pointer', fontFamily: 'sans-serif', fontWeight: 'bold', fontSize: '12px' },
  resultsContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '20px' },
  statusCard: { border: '2px solid', borderRadius: '8px', padding: '20px', textAlign: 'center', marginBottom: '16px' },
  treeSection: { marginTop: '16px' },
  treeTitle: { color: '#58a6ff', fontSize: '16px', marginBottom: '12px' },
  treeGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '12px' },
  treeNode: { display: 'flex', alignItems: 'center', gap: '8px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px' },
  treeIcon: { fontSize: '18px' },
  treeLabel: { color: '#c9d1d9', fontSize: '14px', fontWeight: 'bold' },
  codeBlock: { display: 'inline-block', background: '#0d1117', padding: '2px 6px', borderRadius: '4px', color: '#3fb950', fontSize: '11px', fontFamily: 'monospace' }
};

export default SqlmapScannerApp;
