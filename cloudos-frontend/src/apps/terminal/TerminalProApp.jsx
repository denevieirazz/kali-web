import React, { useState, useEffect, useRef } from 'react';
import TerminalTabs from './components/TerminalTabs';
import TerminalSidebar from './components/TerminalSidebar';
import TerminalPane from './components/TerminalPane';
import { Terminal, Plus, ChevronLeft, ChevronRight } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp }) {
  const [tabs, setTabs] = useState([]);
  const [activeTabId, setActiveTabId] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const wsRef = useRef(null);

  useEffect(() => {
    const token = localStorage.getItem('cloudos_token');
    const wsUrl = `ws://localhost:8080?token=${encodeURIComponent(token || '')}`;
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      // Cria a primeira sessão ao conectar
      ws.send(JSON.stringify({ type: 'create', cwd: payload?.cwd }));
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'session_created') {
          const newTab = { id: msg.sessionId, title: `bash (${tabs.length + 1})`, panes: [{ id: msg.sessionId, active: true }] };
          setTabs(prev => [...prev, newTab]);
          setActiveTabId(msg.sessionId);
        }
      } catch (e) {}
    };

    return () => {
      try { ws.close(); } catch (e) {}
    };
  }, []);

  const createTab = () => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'create' }));
    }
  };

  const closeTab = (id) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'kill', sessionId: id }));
    }
    const newTabs = tabs.filter(t => t.id !== id);
    setTabs(newTabs);
    if (activeTabId === id && newTabs.length > 0) {
      setActiveTabId(newTabs[newTabs.length - 1].id);
    }
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
          <TerminalTabs 
            tabs={tabs} 
            activeId={activeTabId} 
            onSelect={setActiveTabId} 
            onClose={closeTab} 
            onCreate={createTab} 
          />
          <div className="terminal-status-info">
            <span className="status-dot online"></span> WSL Connected
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
              <p style={{ fontSize: '13px', margin: 0 }}>Sessão pronta no WSL Kali Linux.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} style={{ marginRight: '8px' }} /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span>Projeto: <b style={{ color: '#58a6ff' }}>Default</b></span>
          <span>Escopo: <b style={{ color: '#3fb950' }}>Authorized</b></span>
          <span style={{ marginLeft: 'auto' }}>UTF-8 | Bash</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
