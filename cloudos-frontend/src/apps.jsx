import { useState, useRef, useEffect } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export const TerminalApp = () => {
  const termRef = useRef(null);

  useEffect(() => {
    if (!termRef.current) return;

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      theme: { background: '#000000', foreground: '#ffffff' }
    });
    
    const fit = new FitAddon();
    term.loadAddon(fit);
    
    term.open(termRef.current);

    // 🚨 ATRASO CRÍTICO: Espera 100ms para garantir que a janela tem tamanho real
    const initTimer = setTimeout(() => {
      try { fit.fit(); } catch (e) {}
    }, 100);

    const ro = new ResizeObserver(() => {
      try { 
        if (term.element) fit.fit(); 
      } catch (e) {}
    });
    ro.observe(termRef.current);

    const ws = new WebSocket('ws://localhost:8080?userId=user_001');
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      term.write('\x1b[32mConectado ao CloudOS Kali Linux...\r\n\x1b[0m');
    };

    ws.onmessage = (e) => {
      if (e.data instanceof ArrayBuffer) {
        term.write(new Uint8Array(e.data));
      } else {
        term.write(e.data);
      }
    };

    ws.onerror = () => {
      term.write('\r\n\x1b[31m[ERRO] Falha na conexão com o backend. O servidor está rodando?\x1b[0m\r\n');
    };

    ws.onclose = () => {
      term.write('\r\n\x1b[33m[DESCONECTADO] O container foi encerrado.\x1b[0m\r\n');
    };

    term.onData((d) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(d);
      }
    });

    return () => {
      clearTimeout(initTimer);
      ws.close();
      term.dispose();
      ro.disconnect();
    };
  }, []);

  return <div ref={termRef} style={{ height: '100%', width: '100%', padding: '5px', overflow: 'hidden' }} />;
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
