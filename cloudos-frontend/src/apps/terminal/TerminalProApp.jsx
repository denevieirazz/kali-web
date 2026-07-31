import React, { useState, useCallback, useRef, useEffect } from 'react';
import TerminalPane from './components/TerminalPane';
import { Plus, X, Terminal } from 'lucide-react';
import './TerminalProApp.css';

export function TerminalProApp({ payload, setPayload, openApp }) {
  const [tabs, setTabs] = useState([]);
  const [activeTab, setActiveTab] = useState(null);
  const tabCounter = useRef(1);

  // Criar nova aba
  const newTab = useCallback(() => {
    const newId = `tab_${Date.now()}_${tabCounter.current++}`;
    const token = localStorage.getItem('cloudos_token') || '';
    const tab = {
      id: newId,
      title: `Term ${tabCounter.current - 1}`,
      icon: '🐉',
      wsToken: encodeURIComponent(token),
    };
    setTabs(prev => [...prev, tab]);
    setActiveTab(newId);
  }, []);

  // Inicializa uma aba padrão se não houver nenhuma
  useEffect(() => {
    if (tabs.length === 0) {
      newTab();
    }
  }, [tabs.length, newTab]);

  // Fechar aba
  const closeTab = (id, e) => {
    if (e) e.stopPropagation();
    if (tabs.length <= 1) return; // manter ao menos uma
    setTabs(prev => {
      const filtered = prev.filter(t => t.id !== id);
      if (activeTab === id) {
        const idx = prev.findIndex(t => t.id === id);
        const newActive = filtered[Math.min(idx, filtered.length - 1)];
        setActiveTab(newActive?.id || null);
      }
      return filtered;
    });
  };

  // Navegação entre abas
  const navigateTabs = useCallback((direction) => {
    const currentIdx = tabs.findIndex(t => t.id === activeTab);
    if (currentIdx === -1) return;
    const newIdx = direction === 'next'
      ? (currentIdx + 1) % tabs.length
      : (currentIdx - 1 + tabs.length) % tabs.length;
    setActiveTab(tabs[newIdx].id);
  }, [tabs, activeTab]);

  // Atalhos de teclado (Ctrl+T, Ctrl+W, Ctrl+Tab)
  useEffect(() => {
    const handler = (e) => {
      if (e.ctrlKey && e.key === 't') {
        e.preventDefault();
        newTab();
      } else if (e.ctrlKey && e.key === 'w') {
        e.preventDefault();
        if (tabs.length > 1 && activeTab) {
          closeTab(activeTab);
        }
      } else if (e.ctrlKey && e.key === 'Tab') {
        e.preventDefault();
        navigateTabs(e.shiftKey ? 'prev' : 'next');
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [tabs, activeTab, navigateTabs, newTab]);

  return (
    <div className="terminal-pro-app" style={{
      display: 'flex', flexDirection: 'column', height: '100%',
      background: '#0d1117',
      borderRadius: '12px',
      border: '1px solid #30363d',
      boxShadow: '0 8px 32px rgba(0,0,0,0.5)',
      overflow: 'hidden',
    }}>
      {/* Barra de título customizada */}
      <div style={{
        display: 'flex', alignItems: 'center', background: '#161b22',
        padding: '0 8px', height: '40px', borderBottom: '1px solid #30363d',
        userSelect: 'none',
      }}>
        {/* Abas */}
        <div style={{ display: 'flex', flex: 1, overflowX: 'auto', gap: '4px' }}>
          {tabs.map(tab => (
            <div
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              style={{
                display: 'flex', alignItems: 'center', padding: '0 12px',
                height: '32px', borderRadius: '6px 6px 0 0',
                background: activeTab === tab.id ? '#0d1117' : 'transparent',
                border: activeTab === tab.id ? '1px solid #30363d' : '1px solid transparent',
                borderBottom: 'none',
                color: activeTab === tab.id ? '#58a6ff' : '#8b949e',
                fontSize: '13px', fontWeight: 600,
                cursor: 'pointer', transition: 'all 0.2s',
                backdropFilter: activeTab === tab.id ? 'blur(12px)' : 'none',
                textShadow: activeTab === tab.id ? '0 0 10px #58a6ff' : 'none',
              }}
            >
              <span style={{ marginRight: 6 }}>{tab.icon}</span>
              {tab.title}
              {tabs.length > 1 && (
                <span
                  onClick={(e) => closeTab(tab.id, e)}
                  style={{ marginLeft: 8, cursor: 'pointer', opacity: 0.7, display: 'flex', alignItems: 'center' }}
                >
                  <X size={14} />
                </span>
              )}
            </div>
          ))}
        </div>
        {/* Botão + */}
        <button
          onClick={newTab}
          style={{
            background: 'none', border: 'none', color: '#58a6ff',
            cursor: 'pointer', padding: '6px', borderRadius: '4px',
            marginLeft: '4px', transition: '0.2s',
            display: 'flex', alignItems: 'center', justifyContent: 'center'
          }}
          title="Nova Aba (Ctrl+T)"
        >
          <Plus size={18} />
        </button>
      </div>

      {/* Conteúdo da aba ativa */}
      <div style={{ flex: 1, position: 'relative' }}>
        {tabs.map(tab => (
          <div
            key={tab.id}
            style={{
              display: activeTab === tab.id ? 'block' : 'none',
              height: '100%',
              width: '100%',
            }}
          >
            <TerminalPane
              wsUrl={`ws://localhost:8080?token=${tab.wsToken}`}
              isActive={activeTab === tab.id}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

export default TerminalProApp;
