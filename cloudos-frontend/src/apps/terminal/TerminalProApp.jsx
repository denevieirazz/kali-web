import React, { useState, useEffect, useRef } from 'react';
import TerminalSidebar from './components/TerminalSidebar';
import TerminalTabs from './components/TerminalTabs';
import TerminalPane from './components/TerminalPane';
import { Terminal, Plus, ChevronLeft, ChevronRight, Menu } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp, setBg }) {
  const [tabs, setTabs] = useState([]);
  const [activeTabId, setActiveTabId] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [isMobile, setIsMobile] = useState(window.innerWidth < 768);
  const tabCounter = useRef(0);

  // Detecta resolução para ajustar mobile/desktop
  useEffect(() => {
    const handleResize = () => {
      const mobile = window.innerWidth < 768;
      setIsMobile(mobile);
      if (!mobile) setSidebarOpen(true);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  // Cria primeira aba ao montar
  useEffect(() => {
    createTab();
  }, []);

  const createTab = () => {
    tabCounter.current += 1;
    const newId = `tab_${Date.now()}_${tabCounter.current}`;
    setTabs(prev => Array.isArray(prev) ? [...prev, { id: newId, title: 'bash', status: 'online' }] : [{ id: newId, title: 'bash', status: 'online' }]);
    setActiveTabId(newId);
    if (isMobile) setSidebarOpen(false);
  };

  const closeTab = (id) => {
    setTabs(prev => (Array.isArray(prev) ? prev.filter(t => t.id !== id) : []));
    if (activeTabId === id && tabs.length > 1) {
      const closedIndex = tabs.findIndex(t => t.id === id);
      const newActive = tabs[closedIndex - 1] || tabs[closedIndex + 1];
      if (newActive) setActiveTabId(newActive.id);
    } else if (tabs.length <= 1) {
      setActiveTabId(null);
    }
  };

  return (
    <div className={`terminal-pro-app ${isMobile ? 'mobile' : 'desktop'}`}>
      {/* Overlay para fechar drawer no mobile */}
      {isMobile && sidebarOpen && <div className="sidebar-overlay" onClick={() => setSidebarOpen(false)} />}
      
      <TerminalSidebar isOpen={sidebarOpen} isMobile={isMobile} openApp={openApp} onClose={() => setSidebarOpen(false)} />
      
      <div className="terminal-pro-main">
        <div className="terminal-topbar">
          {isMobile && (
            <button onClick={() => setSidebarOpen(true)} className="t-icon-btn mobile-menu-btn">
              <Menu size={18} />
            </button>
          )}
          {!isMobile && (
            <button onClick={() => setSidebarOpen(!sidebarOpen)} className="t-icon-btn">
              {sidebarOpen ? <ChevronLeft size={16} /> : <ChevronRight size={16} />}
            </button>
          )}
          
          <TerminalTabs 
            tabs={tabs} 
            activeId={activeTabId} 
            onSelect={setActiveTabId} 
            onClose={closeTab} 
            onCreate={createTab} 
          />
          
          <div className="terminal-status-info">
            <span className="status-dot online"></span> WSL
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
              <p>Sessões encerradas.</p>
              <button onClick={createTab} className="t-btn-primary">
                <Plus size={16} style={{ marginRight: '8px' }} /> Nova Sessão
              </button>
            </div>
          )}
        </div>

        <div className="terminal-statusbar">
          <span><b>cloudos@kali</b></span>
          <span className="hide-mobile">Projeto: <b style={{ color: '#58a6ff' }}>Default</b></span>
          <span className="ml-auto hide-mobile">UTF-8 | Bash</span>
        </div>
      </div>
    </div>
  );
}

export default TerminalProApp;
