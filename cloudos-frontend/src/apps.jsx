import { useState, useRef, useEffect } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';

export const TerminalApp = () => {
  const termRef = useRef(null);
  useEffect(() => {
    const term = new Terminal({ cursorBlink: true, theme: { background: 'rgba(0,0,0,0)', foreground: '#fff' } });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(termRef.current);
    fit.fit();
    const ro = new ResizeObserver(() => {
      try {
        fit.fit();
      } catch (e) {}
    });
    ro.observe(termRef.current);

    const ws = new WebSocket('ws://localhost:8080?userId=user_001');
    ws.onmessage = (e) => term.write(e.data);
    term.onData((d) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(d);
      }
    });

    return () => { ws.close(); term.dispose(); ro.disconnect(); };
  }, []);
  return <div ref={termRef} className="terminal-container"></div>;
};

export const NotepadApp = () => {
  const [text, setText] = useState('Bem-vindo ao CloudOS Notepad!\n\nSalvamento automático local.');
  return <textarea className="notepad-area" value={text} onChange={(e) => setText(e.target.value)}></textarea>;
};

export const SettingsApp = ({ setBg }) => (
  <div className="settings-container">
    <h2>Configurações</h2>
    <br />
    <h3>Papel de Parede</h3>
    <div style={{ display: 'flex', gap: '10px', marginTop: '10px' }}>
      <div onClick={() => setBg('https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
      <div onClick={() => setBg('https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
      <div onClick={() => setBg('linear-gradient(135deg, #0f0c29, #302b63, #24243e)')} style={{ width: 80, height: 50, background: 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)', borderRadius: 4, cursor: 'pointer' }}></div>
    </div>
  </div>
);
