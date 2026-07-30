import { useState, useRef, useEffect } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { Plus, X } from 'lucide-react';
import 'xterm/css/xterm.css';

export function TerminalApp({ payload }) {
  const [tabs, setTabs] = useState([{ id: Date.now(), title: 'bash' }]);
  const [activeTab, setActiveTab] = useState(tabs[0].id);
  const termContainersRef = useRef({});

  useEffect(() => {
    const currentTab = tabs.find(t => t.id === activeTab);
    if (currentTab && !termContainersRef.current[activeTab]?.term) {
      const container = termContainersRef.current[activeTab];
      if (container) {
        let term;
        let fit;
        let ws;

        try {
          term = new Terminal({
            cursorBlink: true,
            fontSize: 14,
            fontFamily: 'Consolas, "Courier New", monospace',
            theme: { background: '#0a0a0a', foreground: '#e0e0e0', cursor: '#ffffff' }
          });
          
          fit = new FitAddon();
          term.loadAddon(fit);
          term.open(container);
          setTimeout(() => { try { fit.fit(); } catch (e) {} }, 50);

          const token = localStorage.getItem('cloudos_token');
          const wsUrl = `ws://localhost:8080?token=${encodeURIComponent(token || '')}`;
          ws = new WebSocket(wsUrl);
          ws.binaryType = 'arraybuffer';

          ws.onopen = () => {
            try {
              fit.fit();
              ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
            } catch (e) {}
            if (payload?.cwd) {
              setTimeout(() => { if (ws.readyState === WebSocket.OPEN) ws.send(`cd "${payload.cwd}"\r`); }, 300);
            }
          };

          ws.onmessage = (event) => {
            if (term) {
              if (typeof event.data === 'string') term.write(event.data);
              else term.write(new Uint8Array(event.data));
            }
          };

          term.onData((data) => {
            if (ws && ws.readyState === WebSocket.OPEN) ws.send(data);
          });

          termContainersRef.current[activeTab] = { container, term, fit, ws };
        } catch (err) {
          console.error("Erro ao inicializar aba do Terminal:", err);
        }
      }
    }
  }, [activeTab, tabs, payload]);

  const addTab = () => {
    const newId = Date.now();
    setTabs(prev => [...prev, { id: newId, title: `bash (${prev.length + 1})` }]);
    setActiveTab(newId);
  };

  const closeTab = (id) => {
    const item = termContainersRef.current[id];
    if (item) {
      if (item.ws) item.ws.close();
      if (item.term) item.term.dispose();
      delete termContainersRef.current[id];
    }
    const newTabs = tabs.filter(t => t.id !== id);
    setTabs(newTabs);
    if (activeTab === id && newTabs.length > 0) {
      setActiveTab(newTabs[newTabs.length - 1].id);
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#0a0a0a]" style={{ display: 'flex', flexDirection: 'column', height: '100%', backgroundColor: '#0a0a0a' }}>
      {/* Tab Bar */}
      <div className="flex items-center bg-[#161b22] border-b border-[#30363d] px-2 h-9" style={{ display: 'flex', alignItems: 'center', backgroundColor: '#161b22', borderBottom: '1px solid #30363d', padding: '0 8px', height: '36px' }}>
        {tabs.map(tab => (
          <div 
            key={tab.id} 
            onClick={() => setActiveTab(tab.id)}
            style={{
              display: 'flex', alignItems: 'center', padding: '4px 10px', margin: '2px 4px 0 0',
              borderRadius: '4px 4px 0 0', cursor: 'pointer', fontSize: '12px',
              border: activeTab === tab.id ? '1px solid #30363d' : '1px solid transparent',
              borderBottom: activeTab === tab.id ? '1px solid #0a0a0a' : 'none',
              backgroundColor: activeTab === tab.id ? '#0a0a0a' : 'transparent',
              color: activeTab === tab.id ? '#ffffff' : '#8b949e'
            }}
          >
            <span>{tab.title}</span>
            {tabs.length > 1 && (
              <button onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }} style={{ marginLeft: '8px', background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center' }}>
                <X size={12} />
              </button>
            )}
          </div>
        ))}
        <button onClick={addTab} style={{ marginLeft: '8px', background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', padding: '4px', display: 'flex', alignItems: 'center' }} title="Nova Aba">
          <Plus size={16} />
        </button>
      </div>

      {/* Terminal Containers - Mantém todos montados */}
      <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        {tabs.map(tab => (
          <div 
            key={tab.id} 
            ref={el => {
              if (el && !termContainersRef.current[tab.id]) {
                termContainersRef.current[tab.id] = el;
              }
            }} 
            style={{ display: activeTab === tab.id ? 'block' : 'none', height: '100%', width: '100%' }}
          />
        ))}
      </div>
    </div>
  );
}

export default TerminalApp;
