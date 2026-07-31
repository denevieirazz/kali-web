import React, { useState, useCallback, useRef, useEffect } from 'react';
import TerminalTopbar from './TerminalTopbar';
import TerminalTabs from './TerminalTabs';
import TerminalSidebar from './TerminalSidebar';
import TerminalPane from './TerminalPane';
import TerminalStatusbar from './TerminalStatusbar';
import TerminalDashboard from './TerminalDashboard';
import TerminalThemePicker from './TerminalThemePicker';
import '../TerminalProApp.css';

const defaultTheme = {
  name: 'GitHub Dark',
  xterm: {
    background: '#0d1117',
    foreground: '#c9d1d9',
    cursor: '#58a6ff',
    selection: '#58a6ff40',
    black: '#161b22',
    red: '#f85149',
    green: '#3fb950',
    yellow: '#d2991d',
    blue: '#58a6ff',
    magenta: '#bc8cff',
    cyan: '#39c5cf',
    white: '#b1bac4',
    brightBlack: '#6e7681',
    brightRed: '#ff7b72',
    brightGreen: '#56d364',
    brightYellow: '#e3b341',
    brightBlue: '#79c0ff',
    brightMagenta: '#d2a8ff',
    brightCyan: '#56d4dd',
    brightWhite: '#f0f6fc',
  },
  colors: {
    bg: '#0d1117',
    panel: '#161b22',
    border: '#30363d',
    primary: '#58a6ff',
    text: '#c9d1d9',
    muted: '#8b949e',
  },
};

export function TerminalProApp({ payload, setPayload, openApp, setBg }) {
  const [tabs, setTabs] = useState(() => {
    try {
      const saved = localStorage.getItem('terminal_tabs');
      if (saved) return JSON.parse(saved);
    } catch {}
    return [{ id: 'tab_1', title: 'Shell 1', wsToken: 'default' }];
  });
  const [activeTab, setActiveTab] = useState(tabs[0]?.id || null);
  const [showDashboard, setShowDashboard] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [theme, setTheme] = useState(defaultTheme);
  const tabCounter = useRef(tabs.length + 1);

  useEffect(() => {
    localStorage.setItem('terminal_tabs', JSON.stringify(tabs));
  }, [tabs]);

  const addTab = useCallback(() => {
    const newId = `tab_${tabCounter.current++}`;
    const newTab = { id: newId, title: `Shell ${tabCounter.current - 1}`, wsToken: 'default' };
    setTabs(prev => [...prev, newTab]);
    setActiveTab(newId);
    setShowDashboard(false);
  }, []);

  const closeTab = useCallback((id) => {
    setTabs(prev => {
      if (prev.length <= 1) return prev;
      const filtered = prev.filter(t => t.id !== id);
      if (activeTab === id) {
        const idx = prev.findIndex(t => t.id === id);
        const newActive = filtered[Math.min(idx, filtered.length - 1)];
        setActiveTab(newActive?.id || null);
        if (filtered.length === 0) {
          setShowDashboard(true);
          setActiveTab(null);
        }
      }
      return filtered;
    });
  }, [activeTab]);

  const navigateTab = useCallback((direction) => {
    const currentIdx = tabs.findIndex(t => t.id === activeTab);
    if (currentIdx === -1) return;
    const newIdx = (currentIdx + direction + tabs.length) % tabs.length;
    setActiveTab(tabs[newIdx].id);
  }, [tabs, activeTab]);

  const renameTab = useCallback((id, newTitle) => {
    setTabs(prev => prev.map(t => t.id === id ? { ...t, title: newTitle } : t));
  }, []);

  useEffect(() => {
    const handler = (e) => {
      if (e.ctrlKey && e.shiftKey && e.key === 'T') {
        e.preventDefault();
        addTab();
      }
      if (e.ctrlKey && e.shiftKey && e.key === 'W') {
        e.preventDefault();
        if (tabs.length > 0 && activeTab) {
          closeTab(activeTab);
        }
      }
      if (e.ctrlKey && e.key === 'Tab') {
        e.preventDefault();
        navigateTab(e.shiftKey ? -1 : 1);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [tabs, activeTab, addTab, closeTab, navigateTab]);

  const toggleSidebar = () => setSidebarOpen(o => !o);

  return (
    <div className="terminal-pro" style={{ '--theme-bg': theme.colors.bg, '--theme-panel': theme.colors.panel, '--theme-border': theme.colors.border, '--theme-primary': theme.colors.primary, '--theme-text': theme.colors.text, '--theme-muted': theme.colors.muted }}>
      <TerminalTopbar
        title="Terminal Pro"
        onToggleSidebar={toggleSidebar}
        sidebarOpen={sidebarOpen}
      />
      <div className="terminal-body">
        <TerminalSidebar
          open={sidebarOpen}
          onClose={() => setSidebarOpen(false)}
          tabs={tabs}
          activeTab={activeTab}
          onSelectTab={setActiveTab}
          onAddTab={addTab}
        />
        <div className="terminal-main">
          <TerminalTabs
            tabs={tabs}
            activeTab={activeTab}
            onSelectTab={(id) => { setActiveTab(id); setShowDashboard(false); }}
            onCloseTab={closeTab}
            onNewTab={addTab}
            onRenameTab={renameTab}
          />
          <div className="terminal-workspace">
            {showDashboard || tabs.length === 0 ? (
              <TerminalDashboard onNewTab={addTab} theme={theme} />
            ) : (
              tabs.map(tab => (
                <div
                  key={tab.id}
                  className={`terminal-pane-container ${tab.id === activeTab ? 'active' : ''}`}
                  style={{ display: tab.id === activeTab ? 'flex' : 'none', height: '100%' }}
                >
                  <TerminalPane
                    wsUrl={`ws://localhost:8080?token=${tab.wsToken}`}
                    isActive={tab.id === activeTab}
                    theme={theme}
                  />
                </div>
              ))
            )}
          </div>
          <TerminalStatusbar
            user="cloudos"
            cwd="~"
            project="Default"
            shell="bash"
            encoding="UTF-8"
            jobs={0}
          />
        </div>
      </div>
      <TerminalThemePicker current={theme} onChange={setTheme} />
    </div>
  );
}

export default TerminalProApp;
