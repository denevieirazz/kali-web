// ============================================
// ObsidianOS Recovery Environment
// ============================================
import { useCallback, useEffect, useRef, useState } from 'react';
import kernel from '../../core/kernel';
import { useFileSystem } from '../../stores/fileSystem';
import './RecoveryMode.css';

// ── Floating Terminal Window ──────────────────────────────────────────────────

interface TermLine {
  type: 'input' | 'output' | 'error' | 'system';
  content: string;
}

function RecoveryTerminal({ onClose }: { onClose: () => void }) {
  const [lines, setLines] = useState<TermLine[]>([
    { type: 'system', content: 'ObsidianOS Recovery Terminal' },
    { type: 'system', content: 'Digite "help" para ver os comandos disponíveis.' },
    { type: 'system', content: '' },
  ]);
  const [input, setInput] = useState('');
  const [currentPath, setCurrentPath] = useState('X:\\Recovery');
  const [history, setHistory] = useState<string[]>([]);
  const [histIdx, setHistIdx] = useState(-1);

  const inputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // drag state
  const [pos, setPos] = useState({ x: 80, y: 80 });
  const [size, setSize] = useState({ w: 620, h: 400 });
  const dragging = useRef(false);
  const resizing = useRef(false);
  const dragStart = useRef({ mx: 0, my: 0, ox: 0, oy: 0 });
  const resizeStart = useRef({ mx: 0, my: 0, ow: 0, oh: 0 });

  const { getNode, getChildren, createFile, createDirectory, deleteNode } = useFileSystem();

  useEffect(() => {
    scrollRef.current?.scrollTo(0, scrollRef.current.scrollHeight);
  }, [lines]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const addLine = useCallback((content: string, type: TermLine['type'] = 'output') => {
    setLines(prev => [...prev, { type, content }]);
  }, []);

  // ── drag ──
  const onTitleMouseDown = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('button')) return;
    dragging.current = true;
    dragStart.current = { mx: e.clientX, my: e.clientY, ox: pos.x, oy: pos.y };
    e.preventDefault();
  };
  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (dragging.current) {
        setPos({ x: dragStart.current.ox + e.clientX - dragStart.current.mx, y: dragStart.current.oy + e.clientY - dragStart.current.my });
      }
      if (resizing.current) {
        setSize({ w: Math.max(400, resizeStart.current.ow + e.clientX - resizeStart.current.mx), h: Math.max(260, resizeStart.current.oh + e.clientY - resizeStart.current.my) });
      }
    };
    const onUp = () => { dragging.current = false; resizing.current = false; };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  }, []);

  const onResizeMouseDown = (e: React.MouseEvent) => {
    resizing.current = true;
    resizeStart.current = { mx: e.clientX, my: e.clientY, ow: size.w, oh: size.h };
    e.preventDefault();
    e.stopPropagation();
  };

  // ── commands ──
  const executeCommand = useCallback((cmd: string) => {
    const trimmed = cmd.trim();
    if (!trimmed) return;
    setHistory(prev => [...prev, trimmed]);
    setHistIdx(-1);
    addLine(`${currentPath}> ${trimmed}`, 'input');

    const parts = trimmed.split(/\s+/);
    const command = parts[0].toLowerCase();
    const args = parts.slice(1);

    switch (command) {
      case 'help':
        addLine('Comandos disponíveis:');
        addLine('  dir / ls          - Listar conteúdo do diretório');
        addLine('  cd <caminho>      - Mudar diretório');
        addLine('  cls / clear       - Limpar tela');
        addLine('  echo <texto>      - Exibir texto');
        addLine('  type <arquivo>    - Mostrar conteúdo de arquivo');
        addLine('  mkdir <nome>      - Criar diretório');
        addLine('  touch <nome>      - Criar arquivo');
        addLine('  del <nome>        - Deletar arquivo/pasta');
        addLine('  pwd               - Mostra diretório atual');
        addLine('  whoami            - Mostra usuário atual');
        addLine('  hostname          - Mostra nome do computador');
        addLine('  date              - Mostra data e hora');
        addLine('  ver               - Versão do sistema');
        addLine('  tree              - Árvore de diretórios');
        addLine('  ipconfig          - Configuração de rede');
        addLine('  ping <host>       - Ping');
        addLine('  repair            - Executa Startup Repair');
        addLine('  format            - Formata o disco virtual');
        addLine('  restart           - Reinicia o sistema');
        addLine('  exit              - Fecha o terminal');
        break;

      case 'dir':
      case 'ls': {
        const target = args[0] ? (args[0].includes(':') ? args[0] : `${currentPath}\\${args[0]}`) : currentPath;
        const children = getChildren(target);
        if (children.length === 0) {
          addLine('  O diretório está vazio.');
        } else {
          addLine(` Diretório de ${target}`);
          addLine('');
          children.forEach(c => {
            const date = new Date(c.modifiedAt).toLocaleDateString('pt-BR');
            const time = new Date(c.modifiedAt).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
            const sizeStr = c.type === 'directory' ? '<DIR>    ' : c.size.toString().padStart(9);
            addLine(`${date}  ${time}    ${sizeStr}  ${c.name}`);
          });
        }
        break;
      }

      case 'cd': {
        if (!args[0] || args[0] === '.') break;
        if (args[0] === '..') {
          const parent = currentPath.split('\\').slice(0, -1).join('\\');
          if (parent) setCurrentPath(parent);
          break;
        }
        let newPath = '';
        let target = args[0].replace(/\//g, '\\');
        if (target.endsWith('\\') && target.length > 1) target = target.slice(0, -1);
        if (target.includes(':')) newPath = target;
        else if (target.startsWith('\\')) newPath = `C:${target}`;
        else newPath = currentPath === 'C:' ? `C:\\${target}` : `${currentPath}\\${target}`;
        const node = getNode(newPath);
        if (node && node.type === 'directory') setCurrentPath(newPath);
        else addLine(`O sistema não pode encontrar o caminho: ${args[0]}`, 'error');
        break;
      }

      case 'cls':
      case 'clear':
        setLines([]);
        break;

      case 'echo':
        addLine(args.join(' '));
        break;

      case 'type':
      case 'cat': {
        if (!args[0]) { addLine('Uso: type <arquivo>', 'error'); break; }
        const filePath = args[0].includes(':') ? args[0] : `${currentPath}\\${args[0]}`;
        const file = getNode(filePath);
        if (!file) addLine(`Arquivo não encontrado: ${args[0]}`, 'error');
        else if (file.type === 'directory') addLine('Acesso negado: é um diretório.', 'error');
        else addLine(file.content || '(arquivo vazio)');
        break;
      }

      case 'mkdir':
      case 'md':
        if (!args[0]) { addLine('Uso: mkdir <nome>', 'error'); break; }
        createDirectory(currentPath, args[0]);
        addLine(`Diretório criado: ${args[0]}`);
        break;

      case 'touch':
        if (!args[0]) { addLine('Uso: touch <nome>', 'error'); break; }
        createFile(currentPath, args[0], '', args[0].split('.').pop() || 'txt');
        addLine(`Arquivo criado: ${args[0]}`);
        break;

      case 'del':
      case 'rm': {
        if (!args[0]) { addLine('Uso: del <nome>', 'error'); break; }
        const delPath = `${currentPath}\\${args[0]}`;
        if (!getNode(delPath)) addLine(`Não encontrado: ${args[0]}`, 'error');
        else { deleteNode(delPath); addLine(`Deletado: ${args[0]}`); }
        break;
      }

      case 'pwd':
        addLine(currentPath);
        break;

      case 'whoami':
        addLine('OBSIDIAN\\Recovery');
        break;

      case 'hostname':
        addLine('DESKTOP-OBSIDIAN');
        break;

      case 'date':
        addLine(new Date().toLocaleString('pt-BR', { dateStyle: 'full', timeStyle: 'medium' }));
        break;

      case 'ver':
        addLine('ObsidianOS [Version 24H2 Build 26100] — Recovery Mode');
        break;

      case 'tree': {
        const printTree = (path: string, prefix: string) => {
          getChildren(path).forEach((child, i, arr) => {
            const isLast = i === arr.length - 1;
            addLine(`${prefix}${isLast ? '└── ' : '├── '}${child.name}${child.type === 'directory' ? '/' : ''}`);
            if (child.type === 'directory') printTree(child.path, prefix + (isLast ? '    ' : '│   '));
          });
        };
        addLine(currentPath);
        printTree(currentPath, '');
        break;
      }

      case 'ipconfig':
        addLine('Adaptador Ethernet:');
        addLine('   Endereço IPv4. . . : 192.168.1.100');
        addLine('   Máscara . . . . .  : 255.255.255.0');
        addLine('   Gateway . . . . .  : 192.168.1.1');
        break;

      case 'ping': {
        if (!args[0]) { addLine('Uso: ping <host>', 'error'); break; }
        addLine(`Disparando ${args[0]} com 32 bytes de dados:`);
        for (let i = 0; i < 4; i++) {
          addLine(`Resposta de ${args[0]}: bytes=32 tempo=${Math.floor(Math.random() * 20) + 5}ms TTL=128`);
        }
        break;
      }

      case 'repair':
        addLine('Iniciando Startup Repair...', 'system');
        kernel.fsStartupRepair().then(r => {
          if (r.fixed > 0) {
            addLine(`Reparado: ${r.fixed} arquivo(s) restaurado(s).`, 'system');
            addLine('Reiniciando em 3 segundos...', 'system');
            setTimeout(() => { localStorage.removeItem('obsidianos_crash_count'); window.location.reload(); }, 3000);
          } else {
            addLine('Nenhum arquivo corrompido encontrado.', 'system');
          }
        }).catch(() => addLine('Falha no reparo.', 'error'));
        break;

      case 'format':
        addLine('AVISO: Isso apagará todos os dados. Use "format /confirm" para confirmar.', 'error');
        break;

      case 'format /confirm':
        addLine('Formatando disco...', 'system');
        (async () => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const driver = (kernel as any)._diskDriver;
          if (driver) await driver.formatDisk(kernel.getDefaultNodes());
          localStorage.clear();
          addLine('Disco formatado. Reiniciando...', 'system');
          setTimeout(() => window.location.reload(), 1500);
        })();
        break;

      case 'restart':
        addLine('Reiniciando...', 'system');
        setTimeout(() => { localStorage.removeItem('obsidianos_crash_count'); window.location.reload(); }, 800);
        break;

      case 'exit':
        onClose();
        break;

      default: {
        const binaryName = command.endsWith('.obx') ? command : `${command}.obx`;
        const isAbs = binaryName.startsWith('C:');
        const searchPaths = isAbs ? [binaryName] : [`${currentPath}\\${binaryName}`, `C:\\ObsidianOS\\System32\\${binaryName}`];
        let foundPath = '';
        for (const p of searchPaths) {
          if (getNode(p)?.type === 'file') { foundPath = p; break; }
        }
        if (foundPath) {
          addLine(`Running ${foundPath}...`, 'system');
          const pid = kernel.createProcess(command, command, '⚙️');
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (kernel.executeBinary(pid, foundPath, args) as Promise<any>)
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            .then((r: any) => { if (r?.output) String(r.output).split('\n').forEach((l: string) => addLine(l)); })
            .catch((e: unknown) => addLine(`Erro: ${e instanceof Error ? e.message : String(e)}`, 'error'));
        } else {
          addLine(`'${command}' não é reconhecido como um comando interno ou externo.`, 'error');
        }
        break;
      }
    }
  }, [currentPath, addLine, getNode, getChildren, createFile, createDirectory, deleteNode, onClose]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      executeCommand(input);
      setInput('');
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (history.length > 0) {
        const idx = histIdx === -1 ? history.length - 1 : Math.max(0, histIdx - 1);
        setHistIdx(idx);
        setInput(history[idx]);
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (histIdx >= 0) {
        const idx = histIdx + 1;
        if (idx >= history.length) { setHistIdx(-1); setInput(''); }
        else { setHistIdx(idx); setInput(history[idx]); }
      }
    } else if (e.key === 'Tab') {
      e.preventDefault();
      if (input) {
        const match = getChildren(currentPath).find(c => c.name.toLowerCase().startsWith(input.toLowerCase()));
        if (match) setInput(match.name);
      }
    }
  };

  return (
    <div
      className="recovery-term-window"
      style={{ left: pos.x, top: pos.y, width: size.w, height: size.h }}
      onClick={() => inputRef.current?.focus()}
    >
      <div className="recovery-term-titlebar" onMouseDown={onTitleMouseDown}>
        <span className="recovery-term-title">💻 Terminal de Recuperação</span>
        <button className="recovery-term-close" onClick={onClose}>✕</button>
      </div>
      <div className="recovery-term-output" ref={scrollRef}>
        {lines.map((l, i) => (
          <div key={i} className={`rterm-${l.type}`}>{l.content}</div>
        ))}
        <div className="recovery-term-input-row">
          <span className="recovery-term-prompt">{currentPath}&gt;&nbsp;</span>
          <input
            ref={inputRef}
            className="recovery-term-input"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            spellCheck={false}
            autoComplete="off"
          />
        </div>
      </div>
      <div className="recovery-term-resize" onMouseDown={onResizeMouseDown} />
    </div>
  );
}

// ── Main Recovery Screen ──────────────────────────────────────────────────────

export default function RecoveryMode() {
  const [status, setStatus] = useState('');
  const [statusType, setStatusType] = useState<'ok' | 'error' | 'busy' | ''>('');
  const [busy, setBusy] = useState(false);
  const [termOpen, setTermOpen] = useState(false);

  const handleStartupRepair = async () => {
    if (busy) return;
    setBusy(true);
    setStatus('Executando Startup Repair...');
    setStatusType('busy');
    try {
      const result = await kernel.fsStartupRepair();
      if (result.fixed > 0) {
        setStatus(`Reparado: ${result.fixed} arquivo(s) restaurado(s). Reiniciando...`);
        setStatusType('ok');
        setTimeout(() => { localStorage.removeItem('obsidianos_crash_count'); window.location.reload(); }, 2500);
      } else {
        setStatus('Nenhum arquivo corrompido encontrado.');
        setStatusType('error');
        setBusy(false);
      }
    } catch {
      setStatus('Falha no reparo.');
      setStatusType('error');
      setBusy(false);
    }
  };

  const handleFormat = async () => {
    if (busy) return;
    if (!window.confirm('Isso vai apagar TODOS os dados do disco virtual. Continuar?')) return;
    setBusy(true);
    setStatus('Formatando disco...');
    setStatusType('busy');
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const driver = (kernel as any)._diskDriver;
      if (driver) await driver.formatDisk(kernel.getDefaultNodes());
      localStorage.clear();
      setStatus('Disco formatado. Reiniciando...');
      setStatusType('ok');
      setTimeout(() => window.location.reload(), 1500);
    } catch {
      setStatus('Falha ao formatar disco.');
      setStatusType('error');
      setBusy(false);
    }
  };

  const handleRestart = () => {
    localStorage.removeItem('obsidianos_crash_count');
    window.location.reload();
  };

  return (
    <div className="recovery-root">
      <div className="recovery-header">
        <h1>ObsidianOS Recovery Environment</h1>
        <p>O sistema entrou em modo de recuperação após múltiplas falhas críticas.</p>
      </div>

      <div className="recovery-options">
        <button className="recovery-option" onClick={handleStartupRepair} disabled={busy}>
          <span className="recovery-option-icon">🔧</span>
          <div>
            <div className="recovery-option-label">Startup Repair</div>
            <div className="recovery-option-desc">Restaura arquivos de sistema corrompidos ou ausentes</div>
          </div>
        </button>

        <button className="recovery-option" onClick={() => setTermOpen(t => !t)} disabled={busy}>
          <span className="recovery-option-icon">💻</span>
          <div>
            <div className="recovery-option-label">Abrir Terminal</div>
            <div className="recovery-option-desc">Terminal de recuperação para diagnóstico manual</div>
          </div>
        </button>

        <button className="recovery-option" onClick={handleFormat} disabled={busy}>
          <span className="recovery-option-icon">💾</span>
          <div>
            <div className="recovery-option-label">Formatar Disco</div>
            <div className="recovery-option-desc">Apaga todos os dados e reinstala o sistema</div>
          </div>
        </button>

        <button className="recovery-option" onClick={handleRestart} disabled={busy}>
          <span className="recovery-option-icon">🔄</span>
          <div>
            <div className="recovery-option-label">Reiniciar</div>
            <div className="recovery-option-desc">Reinicia o sistema normalmente</div>
          </div>
        </button>
      </div>

      {status && (
        <div className={`recovery-status ${statusType}`}>{status}</div>
      )}

      {termOpen && <RecoveryTerminal onClose={() => setTermOpen(false)} />}
    </div>
  );
}
