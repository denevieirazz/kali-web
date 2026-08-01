import React, { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';

export function OsintApp() {
  const [target, setTarget] = useState('');
  const [module, setModule] = useState('whois');
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);
  const [activeTab, setActiveTab] = useState('structured');

  const getToken = () => localStorage.getItem('cloudos_token');

  const modules = [
    { id: 'whois', icon: '🌐', name: 'WHOIS Lookup', targetLabel: 'Domínio Alvo', desc: 'Registros de domínio, contatos e servidores de nome' },
    { id: 'theharvester', icon: '📧', name: 'theHarvester', targetLabel: 'Domínio Alvo', desc: 'Coleta de e-mails, nomes e subdomínios em fontes abertas' },
    { id: 'dnsenum', icon: '📡', name: 'DNSEnum', targetLabel: 'Domínio Alvo', desc: 'Enumeração completa de registros DNS e zonas' },
    { id: 'sherlock', icon: '🕵️', name: 'Sherlock', targetLabel: 'Username / Nick', desc: 'Rastreia contas de uma pessoa em 300+ redes sociais' }
  ];

  const activeModule = modules.find(m => m.id === module) || modules[0];

  const handleScan = useCallback(async () => {
    if (!target) { setError(`Digite um ${activeModule.targetLabel}!`); return; }
    
    setScanning(true);
    setError(null);
    setResults(null);

    try {
      const res = await fetch(`${API_BASE}/api/osint/scan`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ target, module })
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
  }, [target, module, activeModule]);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h2 style={styles.title}>🕵️‍♂️ OSINT Intelligence Hub</h2>
        <p style={styles.subtitle}>Reconhecimento de inteligência em fontes abertas (Domínios e Pessoas)</p>
      </div>

      <div style={styles.controlPanel}>
        <div style={styles.inputGroup}>
          <label style={styles.label}>🎯 {activeModule.targetLabel}</label>
          <input
            style={styles.input}
            placeholder={module === 'sherlock' ? "Ex: johndoe" : "Ex: exemplo.com.br"}
            value={target}
            onChange={(e) => setTarget(e.target.value)}
            disabled={scanning}
          />
        </div>
        
        <button 
          style={{ ...styles.btnScan, ...(scanning ? styles.btnDisabled : {}) }}
          onClick={handleScan}
          disabled={scanning}
        >
          {scanning ? '⏳ Coletando Dados...' : '🚀 Iniciar Coleta OSINT'}
        </button>
      </div>

      <div style={styles.moduleGrid}>
        {modules.map(m => (
          <div
            key={m.id}
            style={{
              ...styles.moduleCard,
              borderColor: module === m.id ? '#58a6ff' : '#30363d',
              background: module === m.id ? 'rgba(88, 166, 255, 0.1)' : 'transparent'
            }}
            onClick={() => setModule(m.id)}
          >
            <div style={{ fontSize: '24px', marginBottom: '6px' }}>{m.icon}</div>
            <div style={styles.moduleName}>{m.name}</div>
            <div style={styles.moduleDesc}>{m.desc}</div>
          </div>
        ))}
      </div>

      {error && <div style={styles.errorBox}>⚠️ {error}</div>}

      {scanning && (
        <div style={styles.loadingBox}>
          <div style={styles.spinner} />
          <div style={styles.loadingText}>Coletando informações de inteligência no Kali Linux...</div>
        </div>
      )}

      {!scanning && results && (
        <div style={styles.resultsContainer}>
          <div style={styles.resultsHeader}>
            <div style={styles.tabs}>
              <button 
                style={activeTab === 'structured' ? styles.tabActive : styles.tab}
                onClick={() => setActiveTab('structured')}
              >
                📊 Visão Estruturada
              </button>
              <button 
                style={activeTab === 'raw' ? styles.tabActive : styles.tab}
                onClick={() => setActiveTab('raw')}
              >
                📄 Output Bruto
              </button>
            </div>
            <div style={styles.cmdBadge}>
              <code style={styles.cmdText}>{results.rawCommand}</code>
            </div>
          </div>

          {activeTab === 'structured' ? (
            <div style={styles.structuredBody}>
              
              {/* RESUMO - DOMINIO */}
              {results.targetType === 'domain' && (
                <div style={styles.summaryGrid}>
                  <div style={styles.summaryCard}>
                    <div style={styles.summaryTitle}>📧 E-mails</div>
                    <div style={styles.summaryVal}>{results.data.emails.length}</div>
                  </div>
                  <div style={styles.summaryCard}>
                    <div style={styles.summaryTitle}>🌐 Subdomínios</div>
                    <div style={styles.summaryVal}>{results.data.subdomains.length}</div>
                  </div>
                  <div style={styles.summaryCard}>
                    <div style={styles.summaryTitle}>🖥️ IPs</div>
                    <div style={styles.summaryVal}>{results.data.ips.length}</div>
                  </div>
                </div>
              )}

              {/* RESUMO - PESSOA (SHERLOCK) */}
              {results.targetType === 'username' && (
                <div style={styles.summaryGrid}>
                  <div style={styles.summaryCard}>
                    <div style={styles.summaryTitle}>👤 Perfis Encontrados</div>
                    <div style={styles.summaryVal}>{results.data.profiles.length}</div>
                  </div>
                </div>
              )}

              {/* LISTAGEM */}
              {results.data.emails.length > 0 && (
                <div style={styles.section}>
                  <h3 style={styles.sectionTitle}>📧 E-mails Encontrados</h3>
                  <div style={styles.tagGrid}>
                    {results.data.emails.map((email, i) => (
                      <span key={i} style={styles.emailTag}>{email}</span>
                    ))}
                  </div>
                </div>
              )}

              {results.data.subdomains.length > 0 && (
                <div style={styles.section}>
                  <h3 style={styles.sectionTitle}>🌐 Subdomínios Mapeados</h3>
                  <div style={styles.tagGrid}>
                    {results.data.subdomains.map((sub, i) => (
                      <span key={i} style={styles.subdomainTag}>{sub}</span>
                    ))}
                  </div>
                </div>
              )}

              {results.data.ips.length > 0 && (
                <div style={styles.section}>
                  <h3 style={styles.sectionTitle}>🖥️ Endereços IP Identificados</h3>
                  <div style={styles.tagGrid}>
                    {results.data.ips.map((ip, i) => (
                      <span key={i} style={styles.ipTag}>{ip}</span>
                    ))}
                  </div>
                </div>
              )}

              {results.data.profiles.length > 0 && (
                <div style={styles.section}>
                  <h3 style={styles.sectionTitle}>🕵️ Perfis de Redes Sociais Encontrados</h3>
                  <div style={styles.tagGrid}>
                    {results.data.profiles.map((url, i) => (
                      <a 
                        key={i} 
                        href={url} 
                        target="_blank" 
                        rel="noreferrer" 
                        style={styles.profileLink}
                      >
                        🔗 {url.replace('https://', '').replace('http://', '')}
                      </a>
                    ))}
                  </div>
                </div>
              )}

            </div>
          ) : (
            <pre style={styles.rawOutput}>{results.data.rawText}</pre>
          )}
        </div>
      )}
    </div>
  );
}

const styles = {
  container: { padding: '20px', height: '100%', overflowY: 'auto', background: '#0d1117', fontFamily: 'sans-serif', color: '#c9d1d9' },
  header: { marginBottom: '20px', borderBottom: '1px solid #30363d', paddingBottom: '16px' },
  title: { color: '#58a6ff', fontSize: '20px', margin: '0 0 4px 0' },
  subtitle: { color: '#8b949e', fontSize: '12px', margin: 0 },
  controlPanel: { display: 'flex', gap: '16px', marginBottom: '16px', background: '#161b22', padding: '16px', borderRadius: '8px', border: '1px solid #30363d', alignItems: 'flex-end' },
  inputGroup: { flex: 1 },
  label: { display: 'block', color: '#8b949e', fontSize: '12px', marginBottom: '6px', fontWeight: 'bold' },
  input: { width: '100%', padding: '10px', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '14px', boxSizing: 'border-box' },
  btnScan: { padding: '10px 20px', background: '#238636', color: '#fff', border: '1px solid #2ea043', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontSize: '14px', whiteSpace: 'nowrap' },
  btnDisabled: { background: '#21262d', color: '#484f58', borderColor: '#30363d', cursor: 'not-allowed' },
  moduleGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '12px', marginBottom: '20px' },
  moduleCard: { padding: '16px', border: '1px solid', borderRadius: '8px', cursor: 'pointer', transition: 'all 0.2s' },
  moduleName: { color: '#c9d1d9', fontSize: '14px', fontWeight: 'bold', marginBottom: '4px' },
  moduleDesc: { color: '#8b949e', fontSize: '11px', lineHeight: '1.4' },
  errorBox: { background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', color: '#f85149', padding: '10px', borderRadius: '6px', marginBottom: '16px', fontSize: '13px' },
  loadingBox: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px', gap: '12px' },
  spinner: { width: '32px', height: '32px', border: '3px solid #30363d', borderTopColor: '#58a6ff', borderRadius: '50%', animation: 'spin 1s linear infinite' },
  loadingText: { color: '#58a6ff', fontSize: '14px' },
  resultsContainer: { background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '16px' },
  resultsHeader: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px', borderBottom: '1px solid #30363d', paddingBottom: '12px' },
  tabs: { display: 'flex', gap: '8px' },
  tab: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', color: '#8b949e', padding: '6px 12px', cursor: 'pointer', fontSize: '12px' },
  tabActive: { background: 'rgba(88, 166, 255, 0.2)', border: '1px solid #58a6ff', borderRadius: '6px', color: '#58a6ff', padding: '6px 12px', cursor: 'pointer', fontSize: '12px', fontWeight: 'bold' },
  cmdBadge: { background: '#0d1117', padding: '4px 8px', borderRadius: '4px', border: '1px solid #30363d' },
  cmdText: { color: '#3fb950', fontSize: '11px', fontFamily: 'monospace' },
  structuredBody: { display: 'flex', flexDirection: 'column', gap: '16px' },
  summaryGrid: { display: 'flex', gap: '12px' },
  summaryCard: { flex: 1, background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', textAlign: 'center' },
  summaryTitle: { color: '#8b949e', fontSize: '11px', marginBottom: '4px' },
  summaryVal: { color: '#58a6ff', fontSize: '24px', fontWeight: 'bold' },
  section: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px' },
  sectionTitle: { color: '#8b949e', fontSize: '12px', margin: '0 0 8px 0', textTransform: 'uppercase' },
  tagGrid: { display: 'flex', flexWrap: 'wrap', gap: '6px' },
  emailTag: { background: 'rgba(210, 153, 34, 0.2)', color: '#d29922', border: '1px solid #d29922', padding: '4px 8px', borderRadius: '4px', fontSize: '12px', fontFamily: 'monospace' },
  subdomainTag: { background: 'rgba(88, 166, 255, 0.2)', color: '#58a6ff', border: '1px solid #58a6ff', padding: '4px 8px', borderRadius: '4px', fontSize: '12px', fontFamily: 'monospace' },
  ipTag: { background: 'rgba(63, 185, 80, 0.2)', color: '#3fb950', border: '1px solid #3fb950', padding: '4px 8px', borderRadius: '4px', fontSize: '12px', fontFamily: 'monospace' },
  profileLink: { background: 'rgba(163, 113, 247, 0.2)', color: '#a371f7', border: '1px solid #a371f7', padding: '4px 8px', borderRadius: '4px', fontSize: '12px', fontFamily: 'monospace', textDecoration: 'none', cursor: 'pointer' },
  rawOutput: { background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '12px', color: '#8b949e', fontSize: '11px', maxHeight: '400px', overflowY: 'auto', whiteSpace: 'pre-wrap', fontFamily: 'monospace', margin: 0 }
};

export default OsintApp;
