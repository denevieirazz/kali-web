import React, { useState, useEffect, useRef } from 'react';
import TerminalSidebar from './components/TerminalSidebar';
import TerminalPane from './components/TerminalPane';
import { Terminal, Plus, ChevronLeft, ChevronRight } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp }) {
  const [tabs, setTabs] = useState([]);
  const [activeTabId, setActiveTabId] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [wsStatus, setWsStatus] = useState('connecting'); // connecting, open, closed, error
  const wsRef = useRef(null);

  useEffect(() => {
    let ws = null;
    const token = localStorage.getItem('cloudos_token');
    
    // Se o Tracking Prevention bloqueou o localStorage, avisa
    if (!token) {
      console.error("Token JWT não encontrado no localStorage. Desative a proteção de rastreamento do navegador.");
      setWsStatus('error');
      return;
    }

    const wsUrl = `ws://localhost:8080?token=${encodeURIComponent(token)}`;
    ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setWsStatus('open');
      // Cria a primeira sessão ao conectar se a lista estiver vazia
      ws.send(JSON.stringify({ type: 'create', cwd: payload?.cwd }));
    };

    ws.onerror = () => setWsStatus('error');
    ws.onclose = () => setWsStatus('closed');

    ws.onmessage = (event) => {
      try {
        if (typeof event.data !== 'string' || !event.data.startsWith('{')) return;
        const msg = JSON.parse(event.data);
        if (msg.type === 'session_created') {
          setTabs(prev => [...prev, { id: msg.sessionId, title: `bash (${prev.length + 1})`, panes: [{ id: msg.sessionId, active: true }] }]);
          setActiveTabId(msg.sessionId);
        }
      } catch(e) {}
    };

    const handleKey = (e) => {
      if (e.ctrlKey && e.shiftKey && e.key === 'T') { e.preventDefault(); createTab(); }
    };
    window.addEventListener('keydown', handleKey);

    return () => {
      window.removeEventListener('keydown', handleKey);
      if (ws) {
        ws.onmessage = null;
        if (ws.readyState === WebSocket.OPEN) ws.close();
      }
    };
  }, []);

  const createTab = () => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'create' }));
    } else {
      alert('Não foi possível conectar ao Backend do Terminal. Verifique se o servidor Node.js está rodando na porta 8080 e se o JWT é válido.');
    }
  };

  const closeTab = (id) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'kill', sessionId: id }));
    }
    setTabs(prev => prev.filter(t => t.id !== id));
    if (activeTabId === id && tabs.length > 1) setActiveTabId(tabs[tabs.length - 1].id);
  };

  const activeTab = tabs.find(t => t.id === activeTabId);

  return (
    <div className="terminal-pro-app">
      <TerminalSidebar isOpen={sidebarOpen} openApp={openApp} />
      <div className="terminal-pro-main">
        <div className="terminal-topbar">
          <button onClick={() => setSidebarOpen(!sidebarOpen)} className="t-icon-btn">
            {sidebarOpen ? <ChevronLeft size={16} /> : <ChevronRight size={16} />}
          </button>
          <div className="terminal-tabs-container">
            {tabs.map(tab => (
              <div key={tab.id} className={`terminal-tab ${activeTabId === tab.id ? 'active' : ''}`} onClick={() => setActiveTabId(tab.id)}>
                <span className="dot"></span>
                <span>{tab.title}</span>
                <button className="close-btn" onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}>X</button>
              </div>
            ))}
            <button className="terminal-tab-add" onClick={createTab}><Plus size={16} /></button>
          </div>
          <div className="terminal-status-info">
            <span className={`status-dot ${wsStatus}`}></span> 
            {wsStatus === 'open' ? 'WSL Connected' : wsStatus === 'connecting' ? 'Connecting...' : 'Disconnected'}
          </div>
        </div>

        <div className="terminal-content-area">
          {activeTab ? (
            activeTab.panes.map(pane => (
              <TerminalPane key={pane.id} sessionId={pane.id} ws={wsRef.current} active={true} />
            ))
          ) : (
            <div className="terminal-empty-state">
              <Terminal size={64} style={{ opacity: 0.2, marginBottom: '16px' }} />
              <h3 style={{ color: '#c9d1d9', margin: '0 0 8px 0' }}>CloudOS Terminal Pro</h3>
              <p style={{ fontSize: '13px', margin: 0 }}>Sessão WSL Kali Linux pronta.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} style={{ marginRight: '8px' }} /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span>Projeto: <b style={{ color: '#58a6ff' }}>Default</b></span>
          <span style={{ marginLeft: 'auto' }}>UTF-8 | Bash | Status: {wsStatus}</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
