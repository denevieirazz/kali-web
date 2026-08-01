import React, { useState, useEffect, useCallback } from 'react';
import { API_BASE } from '../config';

export function MetasploitApp() {
  const [rpcStatus, setRpcStatus] = useState({ running: false, loading: true });
  const [modules, setModules] = useState([]);
  const [search, setSearch] = useState('');
  const [selectedModule, setSelectedModule] = useState(null);
  const [options, setOptions] = useState({});
  const [optValues, setOptValues] = useState({});
  const [sessions, setSessions] = useState([]);
  const [execLog, setExecLog] = useState('');
  const [loadingOpts, setLoadingOpts] = useState(false);

  const getToken = () => localStorage.getItem('cloudos_token');

  const checkStatus = useCallback(async () => {
    try {
      const res = await fetch(`${API_BASE}/api/metasploit/status`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const data = await res.json();
      setRpcStatus({ running: data.running, loading: false });
    } catch {
      setRpcStatus({ running: false, loading: false });
    }
  }, []);

  const startRpc = async () => {
    setRpcStatus(prev => ({ ...prev, loading: true }));
    try {
      await fetch(`${API_BASE}/api/metasploit/start`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      await checkStatus();
    } catch (err) {
      console.error(err);
    }
  };

  const loadModules = useCallback(async () => {
    if (!rpcStatus.running) return;
    try {
      const res = await fetch(`${API_BASE}/api/metasploit/modules/exploits`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const data = await res.json();
      setModules(data.modules || []);
    } catch (err) {
      console.error(err);
    }
  }, [rpcStatus.running]);

  const loadSessions = useCallback(async () => {
    if (!rpcStatus.running) return;
    try {
      const res = await fetch(`${API_BASE}/api/metasploit/sessions`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const data = await res.json();
      setSessions(data.sessions || []);
    } catch (err) {
      console.error(err);
    }
  }, [rpcStatus.running]);

  useEffect(() => {
    checkStatus();
  }, [checkStatus]);

  useEffect(() => {
    if (rpcStatus.running) {
      loadModules();
      const interval = setInterval(loadSessions, 5000);
      return () => clearInterval(interval);
    }
  }, [rpcStatus.running, loadModules, loadSessions]);

  const handleSelectModule = async (modName) => {
    setSelectedModule(modName);
    setOptions({});
    setOptValues({});
    setLoadingOpts(true);
    try {
      const res = await fetch(`${API_BASE}/api/metasploit/options/exploits/${encodeURIComponent(modName)}`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      const data = await res.json();
      const opts = data.options || {};
      setOptions(opts);
      
      const defaultVals = {};
      Object.keys(opts).forEach(k => {
        if (opts[k].default) defaultVals[k] = opts[k].default;
      });
      setOptValues(defaultVals);
    } catch (err) {
      console.error(err);
    } finally {
      setLoadingOpts(false);
    }
  };

  const handleExecute = async () => {
    if (!selectedModule) return;
    setExecLog('🚀 Disparando exploit...');
    try {
      const res = await fetch(`${API_BASE}/api/metasploit/execute`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${getToken()}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          type: 'exploits',
          name: selectedModule,
          options: optValues
        })
      });
      const data = await res.json();
      if (data.result) {
        setExecLog(`✅ Exploit executado! Job ID: ${data.result.job_id}, Module: ${data.result.module}`);
      } else {
        setExecLog(`❌ Erro: ${data.error}`);
      }
      setTimeout(loadSessions, 2000);
    } catch (err) {
      setExecLog(`❌ Falha de comunicação: ${err.message}`);
    }
  };

  const filteredModules = (modules || []).filter(m => 
    m.toLowerCase().includes(search.toLowerCase())
  ).slice(0, 200);

  if (rpcStatus.loading) {
    return <div style={styles.loading}>Verificando status do MSF RPC...</div>;
  }

  return (
    <div style={styles.container}>
      {/* HEADER */}
      <div style={styles.header}>
        <h2 style={styles.title}>⚡ Metasploit Framework</h2>
        {rpcStatus.running ? (
          <div style={styles.statusOk}>● RPC ONLINE</div>
        ) : (
          <button style={styles.btnStart} onClick={startRpc}>Iniciar MSF RPC Daemon</button>
        )}
      </div>

      {!rpcStatus.running ? (
        <div style={styles.warning}>
          <p>O Daemon RPC do Metasploit não está rodando.</p>
          <p>Clique em "Iniciar MSF RPC Daemon" para subir o serviço no WSL2.</p>
        </div>
      ) : (
        <div style={styles.workspace}>
          {/* ESQUERDA: Lista de Módulos */}
          <div style={styles.panelLeft}>
            <h3 style={styles.panelTitle}>Exploits ({modules.length})</h3>
            <input 
              style={styles.searchInput}
              placeholder="Buscar exploit... (ex: apache, ssh)"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <div style={styles.moduleList}>
              {filteredModules.map(mod => (
                <div 
                  key={mod} 
                  style={{
                    ...styles.moduleItem,
                    backgroundColor: selectedModule === mod ? 'rgba(88, 166, 255, 0.2)' : 'transparent'
                  }}
                  onClick={() => handleSelectModule(mod)}
                >
                  {mod}
                </div>
              ))}
            </div>
          </div>

          {/* CENTRO: Opções e Execução */}
          <div style={styles.panelCenter}>
            <h3 style={styles.panelTitle}>
              {selectedModule ? `Configuração: ${selectedModule}` : 'Selecione um exploit'}
            </h3>
            
            {loadingOpts && <div style={styles.loadingOpts}>Carregando opções...</div>}

            {!loadingOpts && selectedModule && (
              <>
                <div style={styles.optionsGrid}>
                  {Object.entries(options).map(([key, opt]) => {
                    if (['RHOSTS', 'LHOST', 'LPORT', 'RHOST', 'SSL', 'VERBOSE'].includes(key) || opt.required) {
                      return (
                        <div key={key} style={styles.optionItem}>
                          <label style={styles.optLabel}>
                            {key} {opt.required && <span style={styles.required}>*</span>}
                          </label>
                          <input
                            style={styles.optInput}
                            type="text"
                            placeholder={opt.desc || ''}
                            value={optValues[key] || ''}
                            onChange={(e) => setOptValues(prev => ({ ...prev, [key]: e.target.value }))}
                          />
                        </div>
                      );
                    }
                    return null;
                  })}
                </div>

                <button style={styles.btnExecute} onClick={handleExecute}>
                  💥 EXECUTAR EXPLOIT
                </button>

                <div style={styles.logBox}>
                  <pre style={styles.logText}>{execLog}</pre>
                </div>
              </>
            )}
          </div>

          {/* DIREITA: Sessões Ativas */}
          <div style={styles.panelRight}>
            <h3 style={styles.panelTitle}>Sessões Ativas ({sessions.length})</h3>
            <div style={styles.sessionList}>
              {sessions.length === 0 ? (
                <div style={styles.noSessions}>Nenhuma sessão aberta.</div>
              ) : (
                sessions.map(s => (
                  <div key={s.id} style={styles.sessionCard}>
                    <div style={styles.sessionId}>ID: {s.id}</div>
                    <div style={styles.sessionType}>{s.type}</div>
                    <div style={styles.sessionInfo}>{s.info || 'N/A'}</div>
                    <div style={styles.sessionPeer}>{s.tunnel_peer || 'N/A'}</div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    background: '#0d1117',
    color: '#c9d1d9',
    fontFamily: 'sans-serif',
    padding: '16px',
  },
  loading: {
    display: 'flex',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#58a6ff',
    background: '#0d1117'
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '20px',
    borderBottom: '1px solid #30363d',
    paddingBottom: '16px'
  },
  title: {
    color: '#58a6ff',
    fontSize: '20px',
    margin: 0
  },
  statusOk: {
    color: '#3fb950',
    fontWeight: 'bold',
    fontSize: '14px'
  },
  btnStart: {
    background: '#238636',
    color: '#fff',
    border: '1px solid #2ea043',
    padding: '8px 16px',
    borderRadius: '6px',
    cursor: 'pointer',
    fontFamily: 'sans-serif',
    fontWeight: 'bold'
  },
  warning: {
    padding: '40px',
    textAlign: 'center',
    color: '#8b949e'
  },
  workspace: {
    display: 'flex',
    flex: 1,
    gap: '16px',
    minHeight: 0
  },
  panelLeft: {
    width: '300px',
    background: '#161b22',
    borderRadius: '8px',
    border: '1px solid #30363d',
    display: 'flex',
    flexDirection: 'column',
    padding: '12px'
  },
  panelCenter: {
    flex: 1,
    background: '#161b22',
    borderRadius: '8px',
    border: '1px solid #30363d',
    padding: '16px',
    overflowY: 'auto'
  },
  panelRight: {
    width: '280px',
    background: '#161b22',
    borderRadius: '8px',
    border: '1px solid #30363d',
    padding: '12px',
    display: 'flex',
    flexDirection: 'column'
  },
  panelTitle: {
    fontSize: '14px',
    color: '#8b949e',
    marginTop: 0,
    marginBottom: '12px',
    borderBottom: '1px solid #30363d',
    paddingBottom: '8px'
  },
  searchInput: {
    width: '100%',
    boxSizing: 'border-box',
    padding: '8px',
    background: '#0d1117',
    border: '1px solid #30363d',
    borderRadius: '4px',
    color: '#c9d1d9',
    fontFamily: 'sans-serif',
    marginBottom: '12px'
  },
  moduleList: {
    flex: 1,
    overflowY: 'auto',
    paddingRight: '4px'
  },
  moduleItem: {
    padding: '8px',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
    marginBottom: '4px',
    border: '1px solid transparent',
    transition: 'all 0.2s'
  },
  optionsGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '16px',
    marginBottom: '20px'
  },
  optionItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: '6px'
  },
  optLabel: {
    fontSize: '12px',
    color: '#58a6ff',
    fontWeight: 'bold'
  },
  required: {
    color: '#f85149'
  },
  optInput: {
    padding: '8px',
    background: '#0d1117',
    border: '1px solid #30363d',
    borderRadius: '4px',
    color: '#c9d1d9',
    fontFamily: 'monospace',
    fontSize: '12px'
  },
  btnExecute: {
    background: '#da3633',
    color: '#fff',
    border: '1px solid #f85149',
    padding: '12px',
    borderRadius: '6px',
    cursor: 'pointer',
    fontFamily: 'sans-serif',
    fontWeight: 'bold',
    fontSize: '14px',
    width: '100%',
    marginBottom: '20px'
  },
  logBox: {
    background: '#0d1117',
    border: '1px solid #30363d',
    borderRadius: '4px',
    padding: '12px',
    minHeight: '100px'
  },
  logText: {
    color: '#3fb950',
    margin: 0,
    fontSize: '12px',
    whiteSpace: 'pre-wrap'
  },
  sessionList: {
    flex: 1,
    overflowY: 'auto'
  },
  noSessions: {
    color: '#484f58',
    fontSize: '12px',
    textAlign: 'center',
    marginTop: '20px'
  },
  sessionCard: {
    background: '#0d1117',
    border: '1px solid #238636',
    borderRadius: '4px',
    padding: '10px',
    marginBottom: '8px'
  },
  sessionId: {
    color: '#3fb950',
    fontWeight: 'bold',
    fontSize: '14px'
  },
  sessionType: {
    color: '#58a6ff',
    fontSize: '12px'
  },
  sessionInfo: {
    color: '#c9d1d9',
    fontSize: '11px',
    marginTop: '4px'
  },
  sessionPeer: {
    color: '#8b949e',
    fontSize: '10px',
    marginTop: '4px'
  }
};

export default MetasploitApp;
