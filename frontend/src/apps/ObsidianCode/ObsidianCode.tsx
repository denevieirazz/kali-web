// ============================================
// Obsidian Code — IDE completa para SDK (.obx) e OSL (.osl)
// ============================================
import { useState, useRef, useEffect, useCallback } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useFileSystem } from '../../stores/fileSystem';
import { useProcess } from '../../contexts/ProcessContext';
import kernel from '../../core/kernel';
import './ObsidianCode.css';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Tab {
  id: string;
  fileName: string;
  filePath: string;   // '' = unsaved
  content: string;
  language: 'js' | 'osl';
  isModified: boolean;
}

interface ConsoleLine {
  msg: string;
  type: 'out' | 'err' | 'sys' | 'in';
}

// ── Syntax Highlighter ────────────────────────────────────────────────────────

const JS_KEYWORDS = new Set(['await','async','function','return','const','let','var','if','else','for','while','do','break','continue','new','typeof','instanceof','true','false','null','undefined','import','export','default','class','extends','try','catch','finally','throw','switch','case','of','in']);
const OSL_KEYWORDS = new Set(['let','fn','if','else','while','for','return','system','true','false','null']);
const SDK_GLOBALS  = new Set(['OS','StdIO','FS','Proc','Kernel','print']);

function highlight(code: string, lang: 'js' | 'osl'): string {
  const keywords = lang === 'osl' ? OSL_KEYWORDS : JS_KEYWORDS;

  // We tokenize line by line to avoid regex cross-contamination
  return code.split('\n').map(line => {
    // Escape HTML
    const esc = (s: string) =>
      s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    // Tokenize the line into segments: comment | string | word | other
    const segments: { text: string; kind: string }[] = [];
    let i = 0;

    while (i < line.length) {
      // Single-line comment
      if (line[i] === '/' && line[i + 1] === '/') {
        segments.push({ text: line.slice(i), kind: 'comment' });
        break;
      }
      // String: double quote
      if (line[i] === '"') {
        let j = i + 1;
        while (j < line.length && !(line[j] === '"' && line[j - 1] !== '\\')) j++;
        segments.push({ text: line.slice(i, j + 1), kind: 'string' });
        i = j + 1;
        continue;
      }
      // String: single quote
      if (line[i] === "'") {
        let j = i + 1;
        while (j < line.length && !(line[j] === "'" && line[j - 1] !== '\\')) j++;
        segments.push({ text: line.slice(i, j + 1), kind: 'string' });
        i = j + 1;
        continue;
      }
      // Template literal
      if (line[i] === '`') {
        let j = i + 1;
        while (j < line.length && line[j] !== '`') j++;
        segments.push({ text: line.slice(i, j + 1), kind: 'string' });
        i = j + 1;
        continue;
      }
      // Word (identifier / keyword)
      if (/[a-zA-Z_$]/.test(line[i])) {
        let j = i + 1;
        while (j < line.length && /[\w$]/.test(line[j])) j++;
        const word = line.slice(i, j);
        // Check for system:: (OSL syscall)
        if (word === 'system' && line[j] === ':' && line[j + 1] === ':') {
          segments.push({ text: 'system', kind: 'syscall' });
          segments.push({ text: '::', kind: 'plain' });
          i = j + 2;
          continue;
        }
        if (keywords.has(word))       segments.push({ text: word, kind: 'keyword' });
        else if (SDK_GLOBALS.has(word)) segments.push({ text: word, kind: 'global' });
        else                           segments.push({ text: word, kind: 'ident' });
        i = j;
        continue;
      }
      // Number
      if (/\d/.test(line[i])) {
        let j = i + 1;
        while (j < line.length && /[\d.]/.test(line[j])) j++;
        segments.push({ text: line.slice(i, j), kind: 'number' });
        i = j;
        continue;
      }
      // Plain character
      segments.push({ text: line[i], kind: 'plain' });
      i++;
    }

    return segments.map(seg => {
      const t = esc(seg.text);
      switch (seg.kind) {
        case 'keyword': return `<span class="hl-keyword">${t}</span>`;
        case 'string':  return `<span class="hl-string">${t}</span>`;
        case 'comment': return `<span class="hl-comment">${t}</span>`;
        case 'number':  return `<span class="hl-number">${t}</span>`;
        case 'syscall': return `<span class="hl-syscall">${t}</span>`;
        case 'global':  return `<span class="hl-global">${t}</span>`;
        default:        return t;
      }
    }).join('');
  }).join('\n');
}

// ── File Tree ─────────────────────────────────────────────────────────────────

const CODE_EXTS = new Set(['exe', 'osl', 'js', 'txt', 'json', 'ini', 'md']);

interface TreeNode { name: string; path: string; isDir: boolean; depth: number; }

function buildTree(rootPath: string, getChildren: (p: string) => any[]): TreeNode[] {
  const result: TreeNode[] = [];
  function walk(path: string, depth: number) {
    const children = getChildren(path).sort((a: any, b: any) => {
      if (a.type === 'directory' && b.type !== 'directory') return -1;
      if (a.type !== 'directory' && b.type === 'directory') return 1;
      return a.name.localeCompare(b.name);
    });
    for (const child of children) {
      const isDir = child.type === 'directory';
      const ext = child.name.split('.').pop()?.toLowerCase() || '';
      if (!isDir && !CODE_EXTS.has(ext)) continue;
      result.push({ name: child.name, path: child.path, isDir, depth });
      if (isDir) walk(child.path, depth + 1);
    }
  }
  walk(rootPath, 0);
  return result;
}

// ── Default templates ─────────────────────────────────────────────────────────

const DEFAULT_EXE = `// SDK Script — ObsidianOS
// Globals disponíveis: OS, StdIO, FS, Proc, Kernel, print

StdIO.print("🚀 Olá do ObsidianOS SDK!");
StdIO.print("PID: " + Proc.pid);

var res = OS.getResources();
StdIO.print("RAM: " + Math.round(res.usedMemory) + " / " + res.totalMemory + " MB");

await Proc.wait(500);
StdIO.print("Finalizando...");
Proc.exit(0);
`;

const DEFAULT_OSL = `// OSL Script — ObsidianOS Scripting Language
// Sintaxe: let, fn, if, else, while, return
// Syscalls: system::log(), system::fs_read(), system::fs_write(), system::reg_get()

let nome = "Developer";
system::log("Olá, " + nome + "!");

let ram = system::get_resource("ram");
system::log("RAM em uso: " + ram + " MB");

fn saudacao(usuario) {
    system::log("Bem-vindo ao ObsidianOS, " + usuario + "!");
}

saudacao(nome);
`;

// ── Main Component ────────────────────────────────────────────────────────────

let _tabCounter = 1;

export default function ObsidianCode({ windowId }: { windowId: string }) {
  const { pid } = useProcess();
  const { getWindow, updateWindowTitle } = useWindowManager();
  const { getNode, getChildren, updateFileContent, createFile } = useFileSystem();

  // ── Tabs ──────────────────────────────────────────────────────────────────
  const [tabs, setTabs] = useState<Tab[]>([{
    id: 'tab-1',
    fileName: 'script.obx',
    filePath: '',
    content: DEFAULT_EXE,
    language: 'js',
    isModified: false,
  }]);
  const [activeTabId, setActiveTabId] = useState('tab-1');

  // ── Sidebar ───────────────────────────────────────────────────────────────
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [sidebarTab, setSidebarTab] = useState<'files' | 'docs'>('files');
  const [expandedDirs, setExpandedDirs] = useState<Set<string>>(new Set([
    'C:\\Users\\User\\Documents',
    'C:\\ObsidianOS\\SDK\\examples',
    'C:\\ObsidianOS\\SDK\\docs',
  ]));

  // ── Console ───────────────────────────────────────────────────────────────
  const [consoleLines, setConsoleLines] = useState<ConsoleLine[]>([
    { msg: 'Obsidian Code IDE — pronto.', type: 'sys' },
    { msg: 'Ctrl+S salvar  |  F5 executar  |  Ctrl+W fechar aba', type: 'sys' },
  ]);
  const [consoleInput, setConsoleInput] = useState('');
  const [runnerPid, setRunnerPid] = useState<number | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const consoleEndRef = useRef<HTMLDivElement>(null);

  // ── Editor refs ───────────────────────────────────────────────────────────
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const highlightRef = useRef<HTMLPreElement>(null);
  const [cursorPos, setCursorPos] = useState({ line: 1, col: 1 });

  // ── Active tab helpers ────────────────────────────────────────────────────
  const activeTab = tabs.find(t => t.id === activeTabId) ?? tabs[0];

  const updateTab = useCallback((id: string, patch: Partial<Tab>) => {
    setTabs(prev => prev.map(t => t.id === id ? { ...t, ...patch } : t));
  }, []);

  // ── Window title ──────────────────────────────────────────────────────────
  useEffect(() => {
    if (!activeTab) return;
    const mod = activeTab.isModified ? ' ●' : '';
    updateWindowTitle(windowId, `Obsidian Code — ${activeTab.fileName}${mod}`);
  }, [activeTab, windowId, updateWindowTitle]);

  // ── Open file from params ─────────────────────────────────────────────────
  useEffect(() => {
    const win = getWindow(windowId);
    if (!win?.params?.filePath) return;
    const path = win.params.filePath as string;
    const node = getNode(path);
    if (!node || node.type !== 'file') return;
    openFileInTab(path, node.name, node.content || '');
  }, [windowId]);

  // ── Kernel output listeners ───────────────────────────────────────────────
  useEffect(() => {
    const addLine = (line: ConsoleLine) =>
      setConsoleLines(prev => [...prev.slice(-500), line]);

    const unOut = kernel.on('process:stdout', (d: { pid: number; message: string }) => {
      setRunnerPid(cur => {
        if (cur === d.pid) addLine({ msg: d.message, type: 'out' });
        return cur;
      });
    });
    const unErr = kernel.on('process:stderr', (d: { pid: number; message: string }) => {
      setRunnerPid(cur => {
        if (cur === d.pid) addLine({ msg: d.message, type: 'err' });
        return cur;
      });
    });
    const unExit = kernel.on('process:terminated', (exitPid: number) => {
      setRunnerPid(cur => {
        if (cur === exitPid) {
          setIsRunning(false);
          addLine({ msg: `[processo ${exitPid} finalizado]`, type: 'sys' });
          return null;
        }
        return cur;
      });
    });
    return () => { unOut(); unErr(); unExit(); };
  }, []);

  // ── Auto-scroll console ───────────────────────────────────────────────────
  useEffect(() => {
    consoleEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [consoleLines]);

  // ── Sync highlight scroll with textarea ──────────────────────────────────
  const syncScroll = () => {
    if (textareaRef.current && highlightRef.current) {
      highlightRef.current.scrollTop  = textareaRef.current.scrollTop;
      highlightRef.current.scrollLeft = textareaRef.current.scrollLeft;
    }
  };

  // ── File tree ─────────────────────────────────────────────────────────────
  const fileTree = buildTree('C:\\Users\\User', getChildren)
    .concat(buildTree('C:\\ObsidianOS\\SDK', getChildren));

  const toggleDir = (path: string) => {
    setExpandedDirs(prev => {
      const next = new Set(prev);
      next.has(path) ? next.delete(path) : next.add(path);
      return next;
    });
  };

  // ── Open file in tab ──────────────────────────────────────────────────────
  const openFileInTab = (path: string, name: string, content: string) => {
    const existing = tabs.find(t => t.filePath === path);
    if (existing) { setActiveTabId(existing.id); return; }
    const lang: 'js' | 'osl' = name.endsWith('.osl') ? 'osl' : 'js';
    const id = `tab-${++_tabCounter}`;
    setTabs(prev => [...prev, { id, fileName: name, filePath: path, content, language: lang, isModified: false }]);
    setActiveTabId(id);
  };

  const handleFileClick = (node: TreeNode) => {
    if (node.isDir) { toggleDir(node.path); return; }
    const fsNode = getNode(node.path);
    if (!fsNode || fsNode.type !== 'file') return;
    openFileInTab(node.path, node.name, fsNode.content || '');
  };

  // ── New file ──────────────────────────────────────────────────────────────
  const handleNewFile = (lang: 'js' | 'osl') => {
    const ext = lang === 'osl' ? 'osl' : 'exe';
    const name = `novo_${_tabCounter + 1}.${ext}`;
    const id = `tab-${++_tabCounter}`;
    setTabs(prev => [...prev, {
      id, fileName: name, filePath: '', language: lang,
      content: lang === 'osl' ? DEFAULT_OSL : DEFAULT_EXE,
      isModified: false,
    }]);
    setActiveTabId(id);
  };

  // ── Close tab ─────────────────────────────────────────────────────────────
  const closeTab = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    const idx = tabs.findIndex(t => t.id === id);
    const next = tabs.filter(t => t.id !== id);
    setTabs(next.length ? next : [{
      id: 'tab-1', fileName: 'script.obx', filePath: '', content: DEFAULT_EXE, language: 'js', isModified: false,
    }]);
    if (activeTabId === id) {
      setActiveTabId(next[Math.min(idx, next.length - 1)]?.id ?? 'tab-1');
    }
  };

  // ── Save ──────────────────────────────────────────────────────────────────
  const handleSave = useCallback(() => {
    if (!activeTab) return;
    let path = activeTab.filePath;
    if (!path) {
      path = `C:\\Users\\User\\Documents\\${activeTab.fileName}`;
      const ext = activeTab.fileName.split('.').pop() || 'exe';
      createFile('C:\\Users\\User\\Documents', activeTab.fileName, activeTab.content, ext);
    } else {
      updateFileContent(path, activeTab.content);
    }
    // Mark as binary_executable so kernel runs it correctly
    const nd = kernel.fsGetNode(path);
    if (nd) {
      if (!nd.metadata) nd.metadata = {};
      nd.metadata.type = activeTab.language === 'osl' ? 'osl_script' : 'binary_executable';
    }
    updateTab(activeTab.id, { filePath: path, isModified: false });
    setConsoleLines(prev => [...prev, { msg: `[salvo em ${path}]`, type: 'sys' }]);
  }, [activeTab, createFile, updateFileContent, updateTab]);

  // ── Run ───────────────────────────────────────────────────────────────────
  const handleRun = useCallback(() => {
    if (!activeTab || isRunning) return;
    handleSave();

    const path = activeTab.filePath || `C:\\Users\\User\\Documents\\${activeTab.fileName}`;
    if (!kernel.fsGetNode(path)) return;

    setConsoleLines(prev => [...prev, { msg: `\n▶ Executando ${activeTab.fileName} ...`, type: 'sys' }]);
    setIsRunning(true);

    const execPid = kernel.createProcess(
      activeTab.fileName, `Running ${activeTab.fileName}`, '⚡',
      undefined, path, []
    );
    setRunnerPid(execPid);
  }, [activeTab, isRunning, handleSave]);

  // ── Stop ──────────────────────────────────────────────────────────────────
  const handleStop = () => {
    if (runnerPid !== null) {
      kernel.terminateProcess(runnerPid);
      setIsRunning(false);
      setRunnerPid(null);
      setConsoleLines(prev => [...prev, { msg: '[processo interrompido]', type: 'sys' }]);
    }
  };

  // ── Clear console ─────────────────────────────────────────────────────────
  const clearConsole = () => setConsoleLines([]);

  // ── Editor change ─────────────────────────────────────────────────────────
  const handleEditorChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    updateTab(activeTab.id, { content: e.target.value, isModified: true });
  };

  // ── Cursor position ───────────────────────────────────────────────────────
  const updateCursor = () => {
    const ta = textareaRef.current;
    if (!ta) return;
    const text = ta.value.substring(0, ta.selectionStart);
    const lines = text.split('\n');
    setCursorPos({ line: lines.length, col: lines[lines.length - 1].length + 1 });
  };

  // ── Keyboard shortcuts ────────────────────────────────────────────────────
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Ctrl+S
    if (e.ctrlKey && e.key === 's') { e.preventDefault(); handleSave(); return; }
    // F5
    if (e.key === 'F5') { e.preventDefault(); handleRun(); return; }
    // Ctrl+W
    if (e.ctrlKey && e.key === 'w') { e.preventDefault(); closeTab(activeTab.id, e as any); return; }
    // Tab → 2 spaces
    if (e.key === 'Tab') {
      e.preventDefault();
      const ta = textareaRef.current!;
      const s = ta.selectionStart, end = ta.selectionEnd;
      const next = activeTab.content.substring(0, s) + '  ' + activeTab.content.substring(end);
      updateTab(activeTab.id, { content: next, isModified: true });
      requestAnimationFrame(() => { ta.selectionStart = ta.selectionEnd = s + 2; });
      return;
    }
    // Auto-close brackets
    const pairs: Record<string, string> = { '(': ')', '[': ']', '{': '}' };
    if (pairs[e.key]) {
      e.preventDefault();
      const ta = textareaRef.current!;
      const s = ta.selectionStart, end = ta.selectionEnd;
      const next = activeTab.content.substring(0, s) + e.key + pairs[e.key] + activeTab.content.substring(end);
      updateTab(activeTab.id, { content: next, isModified: true });
      requestAnimationFrame(() => { ta.selectionStart = ta.selectionEnd = s + 1; });
    }
  };

  // ── Console input ─────────────────────────────────────────────────────────
  const handleConsoleSubmit = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    const cmd = consoleInput.trim();
    if (!cmd) return;
    setConsoleLines(prev => [...prev, { msg: `> ${cmd}`, type: 'in' }]);
    setConsoleInput('');
    // eval in kernel context for quick testing
    try {
      // eslint-disable-next-line no-new-func
      const result = new Function('kernel', `"use strict"; return (${cmd})`)(kernel);
      if (result !== undefined) setConsoleLines(prev => [...prev, { msg: String(result), type: 'out' }]);
    } catch (err: any) {
      setConsoleLines(prev => [...prev, { msg: err.message, type: 'err' }]);
    }
  };

  // ── Docs content ─────────────────────────────────────────────────────────
  const docsNode = getNode('C:\\ObsidianOS\\SDK\\docs\\syscalls.txt');
  const docsContent = docsNode?.content || '';

  // ── Line numbers ─────────────────────────────────────────────────────────
  const lineCount = (activeTab?.content ?? '').split('\n').length;
  const lineNumbers = Array.from({ length: lineCount }, (_, i) => i + 1).join('\n');

  // ── Highlighted code ─────────────────────────────────────────────────────
  const highlighted = highlight(activeTab?.content ?? '', activeTab?.language ?? 'js');

  return (
    <div className="ocode-root">

      {/* ── Sidebar ── */}
      {sidebarOpen && (
        <div className="ocode-sidebar">
          <div className="ocode-sidebar-tabs">
            <button className={sidebarTab === 'files' ? 'active' : ''} onClick={() => setSidebarTab('files')}>📁 Arquivos</button>
            <button className={sidebarTab === 'docs'  ? 'active' : ''} onClick={() => setSidebarTab('docs')}>📖 SDK Docs</button>
          </div>

          {sidebarTab === 'files' && (
            <div className="ocode-filetree">
              <div className="ocode-filetree-actions">
                <button title="Novo .obx" onClick={() => handleNewFile('js')}>+ exe</button>
                <button title="Novo .osl" onClick={() => handleNewFile('osl')}>+ osl</button>
              </div>
              {fileTree.map(node => (
                <div
                  key={node.path}
                  className={`ocode-tree-item ${node.isDir ? 'dir' : 'file'}`}
                  style={{ paddingLeft: 8 + node.depth * 14 }}
                  onClick={() => handleFileClick(node)}
                  title={node.path}
                >
                  <span className="ocode-tree-icon">
                    {node.isDir
                      ? (expandedDirs.has(node.path) ? '▾' : '▸')
                      : node.name.endsWith('.osl') ? '🔷' : node.name.endsWith('.obx') ? '⚡' : '📄'}
                  </span>
                  <span className="ocode-tree-name">{node.name}</span>
                </div>
              ))}
            </div>
          )}

          {sidebarTab === 'docs' && (
            <pre className="ocode-docs">{docsContent}</pre>
          )}
        </div>
      )}

      {/* ── Main area ── */}
      <div className="ocode-main">

        {/* ── Toolbar ── */}
        <div className="ocode-toolbar">
          <button className="ocode-tb-btn" title="Toggle sidebar" onClick={() => setSidebarOpen(o => !o)}>☰</button>
          <div className="ocode-tb-sep" />
          <button className="ocode-tb-btn" title="Novo .obx (SDK)" onClick={() => handleNewFile('js')}>＋ exe</button>
          <button className="ocode-tb-btn" title="Novo .osl (OSL)" onClick={() => handleNewFile('osl')}>＋ osl</button>
          <div className="ocode-tb-sep" />
          <button className="ocode-tb-btn save" title="Salvar (Ctrl+S)" onClick={handleSave}>💾 Salvar</button>
          {!isRunning
            ? <button className="ocode-tb-btn run"  title="Executar (F5)"  onClick={handleRun}>▶ Executar</button>
            : <button className="ocode-tb-btn stop" title="Parar"          onClick={handleStop}>■ Parar</button>
          }
          <div className="ocode-tb-sep" />
          <span className="ocode-tb-lang">{activeTab?.language === 'osl' ? '🔷 OSL' : '⚡ SDK/JS'}</span>
        </div>

        {/* ── Tabs ── */}
        <div className="ocode-tabs">
          {tabs.map(tab => (
            <div
              key={tab.id}
              className={`ocode-tab ${tab.id === activeTabId ? 'active' : ''}`}
              onClick={() => setActiveTabId(tab.id)}
            >
              <span className="ocode-tab-icon">{tab.language === 'osl' ? '🔷' : '⚡'}</span>
              <span className="ocode-tab-name">{tab.fileName}{tab.isModified ? ' ●' : ''}</span>
              <span className="ocode-tab-close" onClick={e => closeTab(tab.id, e)}>×</span>
            </div>
          ))}
        </div>

        {/* ── Editor + Console ── */}
        <div className="ocode-workspace">

          {/* Editor */}
          <div className="ocode-editor-wrap">
            {/* Line numbers */}
            <pre className="ocode-line-numbers" aria-hidden="true">{lineNumbers}</pre>

            {/* Highlight layer */}
            <pre
              ref={highlightRef}
              className="ocode-highlight"
              aria-hidden="true"
              dangerouslySetInnerHTML={{ __html: highlighted + '\n' }}
            />

            {/* Editable textarea */}
            <textarea
              ref={textareaRef}
              className="ocode-textarea"
              value={activeTab?.content ?? ''}
              onChange={handleEditorChange}
              onKeyDown={handleKeyDown}
              onScroll={syncScroll}
              onClick={updateCursor}
              onKeyUp={updateCursor}
              spellCheck={false}
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
            />
          </div>

          {/* Console */}
          <div className="ocode-console-panel">
            <div className="ocode-console-header">
              <span>CONSOLE {isRunning && <span className="ocode-running-dot">●</span>}</span>
              {runnerPid && <span className="ocode-pid">PID {runnerPid}</span>}
              <button className="ocode-console-clear" onClick={clearConsole}>limpar</button>
            </div>
            <div className="ocode-console-output">
              {consoleLines.map((l, i) => (
                <div key={i} className={`ocode-console-line ${l.type}`}>{l.msg}</div>
              ))}
              <div ref={consoleEndRef} />
            </div>
            <div className="ocode-console-input-row">
              <span className="ocode-console-prompt">&gt;</span>
              <input
                className="ocode-console-input"
                value={consoleInput}
                onChange={e => setConsoleInput(e.target.value)}
                onKeyDown={handleConsoleSubmit}
                placeholder="expressão JS rápida..."
                spellCheck={false}
              />
            </div>
          </div>
        </div>

        {/* ── Status bar ── */}
        <div className="ocode-statusbar">
          <span>PID {pid}{runnerPid ? ` | sub-PID ${runnerPid}` : ''}</span>
          <span>{activeTab?.filePath || `não salvo`}</span>
          <span>Ln {cursorPos.line}, Col {cursorPos.col}</span>
          <span>{activeTab?.language === 'osl' ? 'OSL' : 'SDK/JS'}</span>
        </div>
      </div>
    </div>
  );
}
