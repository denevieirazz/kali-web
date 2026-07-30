import React, { useState, useEffect } from 'react';
import TerminalSidebar from './components/TerminalSidebar';
import TerminalPane from './components/TerminalPane';
import { Terminal, Plus, ChevronLeft, ChevronRight, X } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp }) {
  const [tabs, setTabs] = useState([]);
  const [activeTabId, setActiveTabId] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);

  // Cria a primeira aba automaticamente ao montar
  useEffect(() => {
    createTab();
  }, []);

  const createTab = () => {
    const id = `tab_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
    const newTab = { id, title: `bash (${tabs.length + 1})` };
    setTabs(prev => {
      const updated = [...prev, newTab];
      return updated;
    });
    setActiveTabId(id);
  };

  const closeTab = (id) => {
    setTabs(prev => {
      const updated = prev.filter(t => t.id !== id);
      if (activeTabId === id && updated.length > 0) {
        setActiveTabId(updated[updated.length - 1].id);
      } else if (updated.length === 0) {
        setActiveTabId(null);
      }
      return updated;
    });
  };

  const activeTab = tabs.find(t => t.id === activeTabId);

  return (
    <div className="terminal-pro-app">
      <TerminalSidebar isOpen={sidebarOpen} openApp={openApp} />
      <div className="terminal-pro-main">
        {/* TOP BAR COM TABS */}
        <div className="terminal-topbar">
          <button onClick={() => setSidebarOpen(!sidebarOpen)} className="t-icon-btn">
            {sidebarOpen ? <ChevronLeft size={16} /> : <ChevronRight size={16} />}
          </button>
          <div className="terminal-tabs-container">
            {tabs.map(tab => (
              <div 
                key={tab.id} 
                className={`terminal-tab ${activeTabId === tab.id ? 'active' : ''}`} 
                onClick={() => setActiveTabId(tab.id)}
              >
                <span className="dot"></span>
                <span>{tab.title}</span>
                <button className="close-btn" onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}>
                  <X size={12} />
                </button>
              </div>
            ))}
            <button className="terminal-tab-add" onClick={createTab} title="Nova Aba (Ctrl+Shift+T)">
              <Plus size={16} />
            </button>
          </div>
          <div className="terminal-status-info">
            <span className="status-dot online"></span> Kali Terminal
          </div>
        </div>

        {/* ÁREA DE CONTEÚDO: CADA ABA TEM SEU PRÓPRIO WEBSOCKET */}
        <div className="terminal-content-area">
          {tabs.length > 0 ? (
            tabs.map(tab => (
              <div 
                key={tab.id} 
                style={{ 
                  display: activeTabId === tab.id ? 'flex' : 'none', 
                  width: '100%', height: '100%' 
                }}
              >
                <TerminalPane 
                  tabId={tab.id} 
                  cwd={payload?.cwd} 
                  active={activeTabId === tab.id} 
                />
              </div>
            ))
          ) : (
            <div className="terminal-empty-state">
              <Terminal size={64} style={{ opacity: 0.2, marginBottom: '16px' }} />
              <h3 style={{ color: '#c9d1d9', margin: '0 0 8px 0' }}>CloudOS Terminal Pro</h3>
              <p style={{ fontSize: '13px', margin: 0 }}>Clique para iniciar uma sessão.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} style={{ marginRight: '8px' }} /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        {/* STATUS BAR */}
        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span>Projeto: <b style={{ color: '#58a6ff' }}>Default</b></span>
          <span style={{ marginLeft: 'auto' }}>UTF-8 | Bash | Abas: {tabs.length}</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
