import { useEffect, useRef, useState } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { apiClient, getStoredToken } from '../../services/apiClient';
import 'xterm/css/xterm.css';

interface WslInfo {
  available: boolean;
  default: string | null;
  preferred: string | null;
  distributions: Array<{ name: string; version: number | null; state: string }>;
}

export default function CloudOSTerminal({ windowId }: { windowId?: string }) {
  const terminalRef = useRef<HTMLDivElement>(null);
  const [wslInfo, setWslInfo] = useState<WslInfo | null>(null);
  const [selectedProfile, setSelectedProfile] = useState<'wsl' | 'powershell'>('wsl');
  const [selectedDistro, setSelectedDistro] = useState<string>('');
  const [status, setStatus] = useState<string>('Carregando distribuições...');
  const [sessionActive, setSessionActive] = useState<boolean>(false);

  const termInstance = useRef<Terminal | null>(null);
  const wsInstance = useRef<WebSocket | null>(null);
  const isConnectingRef = useRef<boolean>(false);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);

  // 1. Carregar distribuições WSL reais via API
  useEffect(() => {
    async function loadDistros() {
      try {
        const info = await apiClient<WslInfo>('/api/wsl/distributions');
        setWslInfo(info);
        if (info && info.available && info.distributions.length > 0) {
          const pref = info.preferred || info.default || info.distributions[0].name;
          setSelectedDistro(pref);
          setSelectedProfile('wsl');
          setStatus(`Pronto: WSL • ${pref}`);
        } else {
          setSelectedProfile('powershell');
          setStatus('Pronto: PowerShell do Windows (WSL não detectado)');
        }
      } catch (e) {
        setSelectedProfile('powershell');
        setStatus('Pronto: PowerShell do Windows (Erro ao listar WSL)');
      }
    }
    loadDistros();
  }, []);

  // 2. Iniciar PTY somente após seleção explícita e montagem
  const startSession = (profile: 'wsl' | 'powershell', distroName?: string) => {
    if (isConnectingRef.current || sessionActive) return;
    isConnectingRef.current = true;

    const targetDistro = distroName || selectedDistro;
    setSelectedProfile(profile);
    if (distroName) setSelectedDistro(distroName);

    if (!terminalRef.current) return;

    // Limpar terminal anterior se existir
    if (termInstance.current) {
      termInstance.current.dispose();
      termInstance.current = null;
    }
    if (wsInstance.current) {
      wsInstance.current.close();
      wsInstance.current = null;
    }

    const term = new Terminal({
      theme: {
        background: '#090713',
        foreground: '#ede9fe',
        cursor: '#c084fc',
        selectionBackground: '#6d28d9'
      },
      fontFamily: 'JetBrains Mono, Consolas, monospace',
      fontSize: 13,
      cursorBlink: true,
      cols: 100,
      rows: 28
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(terminalRef.current);

    const safeFit = () => {
      try {
        if (terminalRef.current && terminalRef.current.clientWidth > 0 && terminalRef.current.clientHeight > 0) {
          fitAddon.fit();
        }
      } catch (e) {}
    };

    requestAnimationFrame(() => setTimeout(safeFit, 100));
    termInstance.current = term;

    const token = getStoredToken();
    if (!token) {
      setStatus('🔴 Autenticação necessária — Faça login na LockScreen');
      term.writeln('\x1b[1;31m[Erro: Faça login na LockScreen para acessar o Terminal Real]\x1b[0m');
      isConnectingRef.current = false;
      return;
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/terminal`;

    let ws: WebSocket;
    try {
      ws = new WebSocket(wsUrl, [token]);
      wsInstance.current = ws;

      ws.onopen = () => {
        const cols = term.cols || 100;
        const rows = term.rows || 28;

        // Enviar mensagem inicial "start" estruturada
        ws.send(JSON.stringify({
          type: 'start',
          profile: profile,
          distribution: profile === 'wsl' ? targetDistro : undefined,
          cols,
          rows
        }));

        setSessionActive(true);
        isConnectingRef.current = false;
        setStatus(profile === 'wsl' ? `🟢 WSL • ${targetDistro}` : '🟢 PowerShell do Windows');
      };

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'output') {
            term.write(msg.data);
          } else if (msg.type === 'error') {
            term.writeln(`\r\n\x1b[1;31m[Erro PTY: ${msg.data}]\x1b[0m`);
          } else if (msg.type === 'exit') {
            term.writeln('\r\n\x1b[1;33m[Sessão encerrada]\x1b[0m');
            setSessionActive(false);
          }
        } catch (e) {
          term.write(event.data);
        }
      };

      term.onData((data) => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'input', data }));
        }
      });

      term.onResize(({ cols, rows }) => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', cols, rows }));
        }
      });

      ws.onerror = () => {
        setStatus('🔴 Erro de conexão no WebSocket');
        isConnectingRef.current = false;
        setSessionActive(false);
      };

      ws.onclose = () => {
        setStatus('🟡 Conexão PTY encerrada');
        isConnectingRef.current = false;
        setSessionActive(false);
      };

    } catch (err: any) {
      setStatus('🔴 Falha ao abrir WebSocket: ' + err.message);
      isConnectingRef.current = false;
    }

    if (resizeObserverRef.current) {
      resizeObserverRef.current.disconnect();
    }
    const resizeObserver = new ResizeObserver(() => safeFit());
    if (terminalRef.current) resizeObserver.observe(terminalRef.current);
    resizeObserverRef.current = resizeObserver;
  };

  // 3. Auto-iniciar com a distribuição preferida assim que carregada
  useEffect(() => {
    if (wslInfo && !sessionActive && !isConnectingRef.current) {
      if (wslInfo.available && selectedDistro) {
        startSession('wsl', selectedDistro);
      } else {
        startSession('powershell');
      }
    }
  }, [wslInfo]);

  // Limpeza ao desmontar componente (encerra wsl.exe e limpa observers)
  useEffect(() => {
    return () => {
      if (resizeObserverRef.current) {
        resizeObserverRef.current.disconnect();
        resizeObserverRef.current = null;
      }
      if (wsInstance.current) {
        try {
          wsInstance.current.send(JSON.stringify({ type: 'close' }));
          wsInstance.current.close();
        } catch (e) {}
        wsInstance.current = null;
      }
      if (termInstance.current) {
        termInstance.current.dispose();
        termInstance.current = null;
      }
    };
  }, []);

  return (
    <div style={{ height: '100%', width: '100%', display: 'flex', flexDirection: 'column', background: '#090713' }}>
      {/* Header com Seletor Seguro de Perfil e Distribuições Reais */}
      <div style={{ padding: '6px 12px', background: '#120d24', borderBottom: '1px solid #2d224d', fontSize: '12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#9d85c0' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span style={{ fontWeight: 600, color: '#c084fc' }}>
            {selectedProfile === 'wsl' ? `WSL • ${selectedDistro || 'Linux'}` : 'PowerShell do Windows'}
          </span>
          <span style={{ fontSize: '11px', opacity: 0.8 }}>({status})</span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          {wslInfo && wslInfo.available && wslInfo.distributions.length > 0 && (
            <select
              value={selectedDistro}
              onChange={(e) => {
                const newDistro = e.target.value;
                setSelectedDistro(newDistro);
                startSession('wsl', newDistro);
              }}
              style={{ background: '#1e1638', color: '#ede9fe', border: '1px solid #4c387b', borderRadius: '4px', padding: '2px 6px', fontSize: '11px', cursor: 'pointer' }}
            >
              {wslInfo.distributions.map(d => (
                <option key={d.name} value={d.name}>
                  🐧 {d.name} {d.version ? `(WSL ${d.version})` : ''} {d.state ? `[${d.state}]` : ''}
                </option>
              ))}
            </select>
          )}

          <button
            onClick={() => startSession('powershell')}
            style={{
              background: selectedProfile === 'powershell' ? '#4f46e5' : '#1e1638',
              color: '#fff',
              border: '1px solid #4c387b',
              borderRadius: '4px',
              padding: '2px 8px',
              fontSize: '11px',
              cursor: 'pointer'
            }}
          >
            💻 PowerShell do Windows
          </button>
        </div>
      </div>

      {/* Terminal View Container */}
      <div ref={terminalRef} style={{ flex: 1, padding: '8px', overflow: 'hidden' }} />
    </div>
  );
}
