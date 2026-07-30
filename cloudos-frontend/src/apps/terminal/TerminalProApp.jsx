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

  useEffect(() => {
    createTab();
  }, []);

  const createTab = () => {
    tabCounter.current += 1;
    const newId = `tab_${Date.now()}_${tabCounter.current}`;
    setTabs(prev => [...prev, { id: newId, title: 'bash' }]);
    setActiveTabId(newId);
  };

  const closeTab = (id) => {
    setTabs(prev => prev.filter(t => t.id !== id));
    if (activeTabId === id && tabs.length > 1) {
      const closedIndex = tabs.findIndex(t => t.id === id);
      const newActive = tabs[closedIndex - 1] || tabs[closedIndex + 1];
      if (newActive) setActiveTabId(newActive.id);
    } else if (tabs.length <= 1) {
      setActiveTabId(null);
    }
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
              <Terminal size={64} className="opacity-20 mb-4" />
              <h3>CloudOS Terminal Pro</h3>
              <p>Todas as sessões foram fechadas.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} className="mr-2" /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span>Projeto: <b className="text-blue-400">Default</b></span>
          <span className="ml-auto">UTF-8 | Bash</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
