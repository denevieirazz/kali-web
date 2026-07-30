import React, { useState, useEffect, useRef } from 'react';
import TerminalSidebar from './components/TerminalSidebar';
import TerminalPane from './components/TerminalPane';
import { Terminal, Plus, ChevronLeft, ChevronRight, X } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp }) {
  const [tabs, setTabs] = useState([]);
  const [activeTabId, setActiveTabId] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const tabCounter = useRef(0);

  // Cria a primeira aba automaticamente ao abrir o app
  useEffect(() => {
    createTab();
  }, []);

  const createTab = () => {
    // Gerador de ID à prova de duplicação (Strict Mode safe)
    tabCounter.current += 1;
    const newId = `tab_${Date.now()}_${tabCounter.current}`;
    
    setTabs(prev => [...prev, { id: newId, title: 'bash' }]);
    setActiveTabId(newId);
  };

  const closeTab = (id) => {
    setTabs(prev => {
      const filtered = prev.filter(t => t.id !== id);
      if (activeTabId === id && filtered.length > 0) {
        const closedIndex = prev.findIndex(t => t.id === id);
        const newActive = prev[closedIndex - 1] || prev[closedIndex + 1];
        if (newActive) setActiveTabId(newActive.id);
      } else if (filtered.length === 0) {
        setActiveTabId(null);
      }
      return filtered;
    });
  };

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
            <button className="terminal-tab-add" onClick={createTab}><Plus size={16} /></button>
          </div>
          <div className="terminal-status-info">
            <span className="status-dot online"></span> WSL Connected
          </div>
        </div>

        <div className="terminal-content-area">
          {tabs.length > 0 ? (
            tabs.map(tab => (
              <TerminalPane 
                key={tab.id} 
                tabId={tab.id} 
                isActive={activeTabId === tab.id} 
              />
            ))
          ) : (
            <div className="terminal-empty-state">
              <Terminal size={64} style={{ opacity: 0.2, marginBottom: '16px' }} />
              <h3>CloudOS Terminal Pro</h3>
              <p>Todas as sessões foram fechadas.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} style={{ marginRight: '8px' }} /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span>Projeto: <b style={{ color: '#58a6ff' }}>Default</b></span>
          <span style={{ marginLeft: 'auto' }}>UTF-8 | Bash</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
