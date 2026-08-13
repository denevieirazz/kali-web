import { useCallback, useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { apiClient, getStoredToken, resolveWebSocketUrl } from '../../services/apiClient';
import { useWindowManager } from '../../stores/windowManager';
import 'xterm/css/xterm.css';

interface WslInfo {
  available: boolean;
  default: string | null;
  preferred: string | null;
  distributions: Array<{ name: string; version: number | null; state: string }>;
}

type TerminalProfile = 'wsl' | 'powershell';

export default function CloudOSTerminal({ windowId }: { windowId?: string }) {
  const [windowParams] = useState(() => {
    const win = windowId ? useWindowManager.getState().getWindow(windowId) : undefined;
    const profile: TerminalProfile = win?.params?.profile === 'powershell' ? 'powershell' : 'wsl';
    return { profile, distribution: typeof win?.params?.distribution === 'string' ? win.params.distribution : '' };
  });

  const terminalRef = useRef<HTMLDivElement>(null);
  const [wslInfo, setWslInfo] = useState<WslInfo | null>(null);
  const [selectedProfile, setSelectedProfile] = useState<TerminalProfile>(windowParams.profile);
  const [selectedDistro, setSelectedDistro] = useState(windowParams.distribution);
  const [status, setStatus] = useState('Carregando perfis do host…');
  const [sessionActive, setSessionActive] = useState(false);

  const termInstance = useRef<Terminal | null>(null);
  const wsInstance = useRef<WebSocket | null>(null);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);
  const connectionGeneration = useRef(0);
  const initialSessionStarted = useRef(false);

  const destroySession = useCallback((updateState = true) => {
    connectionGeneration.current += 1;
    resizeObserverRef.current?.disconnect();
    resizeObserverRef.current = null;
    const ws = wsInstance.current;
    wsInstance.current = null;
    if (ws) {
      try {
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'close' }));
        ws.close();
      } catch {}
    }
    termInstance.current?.dispose();
    termInstance.current = null;
    if (updateState) setSessionActive(false);
  }, []);

  const startSession = useCallback((profile: TerminalProfile, distroName = '') => {
    if (!terminalRef.current) return;
    destroySession();
    const generation = ++connectionGeneration.current;
    const targetDistro = distroName || selectedDistro;
    setSelectedProfile(profile);
    if (distroName) setSelectedDistro(distroName);
    setStatus('Conectando ao agente local…');

    const term = new Terminal({
      theme: { background: '#090713', foreground: '#ede9fe', cursor: '#67e8f9', selectionBackground: '#334a73' },
      fontFamily: 'Cascadia Code, JetBrains Mono, Consolas, monospace',
      fontSize: 13,
      cursorBlink: true,
      cols: 100,
      rows: 28
    });
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(terminalRef.current);
    termInstance.current = term;

    const safeFit = () => {
      try {
        if (terminalRef.current?.clientWidth && terminalRef.current?.clientHeight) fitAddon.fit();
      } catch {}
    };
    requestAnimationFrame(() => window.setTimeout(safeFit, 80));
    const observer = new ResizeObserver(safeFit);
    observer.observe(terminalRef.current);
    resizeObserverRef.current = observer;

    const token = getStoredToken();
    if (!token) {
      term.writeln('\x1b[1;31m[Faça login no CloudOS para acessar o terminal real.]\x1b[0m');
      setStatus('Autenticação necessária');
      return;
    }

    const ws = new WebSocket(resolveWebSocketUrl('/ws/terminal'), [token]);
    wsInstance.current = ws;

    ws.onopen = () => {
      if (generation !== connectionGeneration.current) return ws.close();
      ws.send(JSON.stringify({
        type: 'start',
        profile,
        distribution: profile === 'wsl' ? targetDistro : undefined,
        cols: term.cols || 100,
        rows: term.rows || 28
      }));
      setSessionActive(true);
      setStatus(profile === 'wsl' ? `WSL · ${targetDistro}` : 'PowerShell do Windows');
    };

    ws.onmessage = (event) => {
      if (generation !== connectionGeneration.current) return;
      try {
        const message = JSON.parse(event.data);
        if (message.type === 'output') term.write(message.data);
        else if (message.type === 'error') term.writeln(`\r\n\x1b[1;31m[${message.data}]\x1b[0m`);
        else if (message.type === 'exit') {
          term.writeln('\r\n\x1b[1;33m[Sessão encerrada]\x1b[0m');
          setSessionActive(false);
          setStatus('Sessão encerrada');
        }
      } catch {
        term.write(event.data);
      }
    };

    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'input', data }));
    });
    term.onResize(({ cols, rows }) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'resize', cols, rows }));
    });

    ws.onerror = () => {
      if (generation !== connectionGeneration.current) return;
      setSessionActive(false);
      setStatus('Falha na conexão com o terminal');
    };
    ws.onclose = () => {
      if (generation !== connectionGeneration.current) return;
      setSessionActive(false);
      setStatus('Conexão encerrada');
    };
  }, [destroySession, selectedDistro]);

  useEffect(() => {
    async function loadProfiles() {
      try {
        const info = await apiClient<WslInfo>('/api/wsl/distributions');
        setWslInfo(info);
        const requested = windowParams.distribution;
        const requestedExists = info.distributions.some((distro) => distro.name === requested);
        const distro = requestedExists ? requested : info.preferred || info.default || info.distributions[0]?.name || '';
        setSelectedDistro(distro);
        if (windowParams.profile === 'powershell' || !info.available) setSelectedProfile('powershell');
      } catch {
        setWslInfo({ available: false, default: null, preferred: null, distributions: [] });
        setSelectedProfile('powershell');
        setStatus('WSL indisponível; PowerShell pronto');
      }
    }
    loadProfiles();
  }, [windowParams.distribution, windowParams.profile]);

  useEffect(() => {
    if (!wslInfo || initialSessionStarted.current) return;
    initialSessionStarted.current = true;
    if (selectedProfile === 'wsl' && wslInfo.available && selectedDistro) startSession('wsl', selectedDistro);
    else startSession('powershell');
  }, [selectedDistro, selectedProfile, startSession, wslInfo]);

  useEffect(() => () => destroySession(false), [destroySession]);

  return (
    <div style={{ height: '100%', width: '100%', display: 'flex', flexDirection: 'column', background: '#090713' }}>
      <div style={{ minHeight: 39, padding: '6px 12px', background: '#101725', borderBottom: '1px solid #29354a', fontSize: 12, display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center', color: '#93a4bd' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
          <span style={{ width: 7, height: 7, flex: '0 0 auto', borderRadius: '50%', background: sessionActive ? '#35d098' : '#f5b955', boxShadow: sessionActive ? '0 0 10px #35d098' : 'none' }} />
          <strong style={{ color: '#dce8fa', whiteSpace: 'nowrap' }}>{selectedProfile === 'wsl' ? `Linux · ${selectedDistro || 'WSL'}` : 'Windows · PowerShell'}</strong>
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: 10 }}>{status}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          {wslInfo?.available && wslInfo.distributions.length > 0 && <select aria-label="Distribuição WSL" value={selectedDistro} onChange={(event) => startSession('wsl', event.target.value)} style={{ maxWidth: 190, background: '#162033', color: '#e6eefb', border: '1px solid #344662', borderRadius: 6, padding: '3px 6px', fontSize: 10 }}>
            {wslInfo.distributions.map((distro) => <option key={distro.name} value={distro.name}>{distro.name} · WSL {distro.version || '?'}</option>)}
          </select>}
          <button onClick={() => startSession('powershell')} style={{ background: selectedProfile === 'powershell' ? '#3e6fca' : '#162033', color: '#fff', border: '1px solid #344662', borderRadius: 6, padding: '4px 8px', fontSize: 10, cursor: 'pointer' }}>PowerShell</button>
          <button onClick={() => startSession(selectedProfile, selectedDistro)} title="Reconectar" style={{ background: '#162033', color: '#bcd0eb', border: '1px solid #344662', borderRadius: 6, padding: '4px 7px', fontSize: 10, cursor: 'pointer' }}>↻</button>
        </div>
      </div>
      <div ref={terminalRef} style={{ flex: 1, padding: 8, overflow: 'hidden' }} />
    </div>
  );
}
