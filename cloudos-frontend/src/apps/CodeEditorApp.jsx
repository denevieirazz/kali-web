import React, { useState, useEffect, useRef } from 'react';
import Editor from '@monaco-editor/react';
import { 
  FileCode, Play, X, FolderOpen, Loader, Circle, 
  CheckCircle
} from 'lucide-react';

const API_BASE = 'http://localhost:8080/api';

const getHeaders = () => {
  const token = localStorage.getItem('cloudos_token');
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  };
};

// Mapeamento de extensão para linguagem do Monaco
const getLanguageByExtension = (filename) => {
  if (!filename) return 'plaintext';
  const ext = filename.split('.').pop().toLowerCase();
  const map = {
    py: 'python', sh: 'shell', bash: 'shell',
    js: 'javascript', jsx: 'javascript', ts: 'typescript', tsx: 'typescript',
    html: 'html', css: 'css', json: 'json', xml: 'xml',
    c: 'c', cpp: 'cpp', java: 'java', rb: 'ruby', go: 'go',
    sql: 'sql', md: 'markdown', txt: 'plaintext'
  };
  return map[ext] || 'plaintext';
};

export function CodeEditorApp({ payload, setPayload, openApp, setBg }) {
  const [openTabs, setOpenTabs] = useState([]); // { path, name, content, originalContent, isDirty, language }
  const [activeTabPath, setActiveTabPath] = useState(null);
  const [saveStatus, setSaveStatus] = useState('idle'); // idle, saving, saved
  const [loading, setLoading] = useState(false);
  const saveTimers = useRef({});

  // Abre arquivo quando recebe payload do FileManager ou Desktop
  useEffect(() => {
    if (payload?.path && !openTabs.find(t => t.path === payload.path)) {
      openFile(payload.path);
    } else if (payload?.path) {
      setActiveTabPath(payload.path);
    }
  }, [payload?.path]);

  const openFile = async (filePath) => {
    setLoading(true);
    try {
      const res = await fetch(`${API_BASE}/files/read?path=${encodeURIComponent(filePath)}`, {
        headers: getHeaders()
      });
      const data = await res.json();
      
      const content = data.content !== undefined ? data.content : '';
      const filename = filePath.split('/').pop();
      const newTab = {
        path: filePath,
        name: filename,
        content: content,
        originalContent: content,
        isDirty: false,
        language: getLanguageByExtension(filename)
      };
      setOpenTabs(prev => [...prev, newTab]);
      setActiveTabPath(filePath);
    } catch (err) {
      console.error('Erro ao abrir arquivo:', err);
    } finally {
      setLoading(false);
    }
  };

  const closeTab = (path, e) => {
    e.stopPropagation();
    const tabIndex = openTabs.findIndex(t => t.path === path);
    const newTabs = openTabs.filter(t => t.path !== path);
    setOpenTabs(newTabs);

    if (activeTabPath === path) {
      if (newTabs.length > 0) {
        const newIndex = tabIndex > 0 ? tabIndex - 1 : 0;
        setActiveTabPath(newTabs[newIndex].path);
      } else {
        setActiveTabPath(null);
      }
    }
  };

  const handleEditorChange = (value) => {
    setOpenTabs(prev => prev.map(tab => 
      tab.path === activeTabPath 
        ? { ...tab, content: value, isDirty: value !== tab.originalContent }
        : tab
    ));

    if (saveTimers.current[activeTabPath]) {
      clearTimeout(saveTimers.current[activeTabPath]);
    }

    setSaveStatus('idle');
    saveTimers.current[activeTabPath] = setTimeout(() => {
      saveFile(activeTabPath, value);
    }, 1500);
  };

  const saveFile = async (path, content) => {
    setSaveStatus('saving');
    try {
      const res = await fetch(`${API_BASE}/files/save`, {
        method: 'POST',
        headers: getHeaders(),
        body: JSON.stringify({ path, content })
      });
      const data = await res.json();

      if (data.success) {
        setSaveStatus('saved');
        setOpenTabs(prev => prev.map(tab =>
          tab.path === path ? { ...tab, originalContent: content, isDirty: false } : tab
        ));
        
        setTimeout(() => setSaveStatus('idle'), 2000);
      }
    } catch (err) {
      console.error('Erro ao salvar:', err);
      setSaveStatus('idle');
    }
  };

  const handleRunInTerminal = () => {
    const activeTab = openTabs.find(t => t.path === activeTabPath);
    if (!activeTab) return;

    let command = '';
    if (activeTab.language === 'python') command = `python3 ${activeTab.path}`;
    else if (activeTab.language === 'shell') command = `bash ${activeTab.path}`;
    else {
      alert('Linguagem não suportada para execução direta. Abra o terminal manualmente.');
      return;
    }

    openApp?.('terminal', { initialText: `${command}\n` });
  };

  const handleBeforeMount = (monaco) => {
    monaco.editor.defineTheme('cloudosDark', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '8b949e', fontStyle: 'italic' },
        { token: 'keyword', foreground: 'ff7b72' },
        { token: 'string', foreground: 'a5d6ff' },
        { token: 'number', foreground: '79c0ff' },
        { token: 'type', foreground: 'ffa657' },
        { token: 'function', foreground: 'd2a8ff' },
      ],
      colors: {
        'editor.background': '#0d1117',
        'editor.foreground': '#c9d1d9',
        'editor.lineHighlightBackground': '#161b22',
        'editorLineNumber.foreground': '#484f58',
        'editorLineNumber.activeForeground': '#c9d1d9',
        'editor.selectionBackground': '#264f78',
        'editor.inactiveSelectionBackground': '#3a3d41',
        'editorCursor.foreground': '#58a6ff',
        'editorGutter.background': '#0d1117',
        'editorIndentGuide.background': '#21262d',
      }
    });
  };

  const activeTab = openTabs.find(t => t.path === activeTabPath);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117' }}>
      
      {/* ===== Header ===== */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: '8px',
        padding: '8px 12px', background: '#161b22', borderBottom: '1px solid #30363d'
      }}>
        <FileCode size={16} color="#58a6ff" />
        <span style={{ fontSize: '13px', fontWeight: 600, color: '#c9d1d9' }}>Editor de Código</span>
        
        <div style={{ flex: 1 }} />

        <button
          onClick={handleRunInTerminal}
          disabled={!activeTab}
          style={{
            display: 'flex', alignItems: 'center', gap: '6px',
            background: '#238636', border: 'none', borderRadius: '6px',
            padding: '5px 12px', color: 'white', cursor: activeTab ? 'pointer' : 'not-allowed',
            opacity: activeTab ? 1 : 0.5, fontSize: '12px', fontWeight: 500
          }}
        >
          <Play size={12} /> Rodar
        </button>
      </div>

      {/* ===== Abas (Tabs) ===== */}
      <div style={{
        display: 'flex', background: '#0d1117', borderBottom: '1px solid #30363d',
        overflowX: 'auto'
      }}>
        {openTabs.map(tab => (
          <div
            key={tab.path}
            onClick={() => setActiveTabPath(tab.path)}
            style={{
              display: 'flex', alignItems: 'center', gap: '8px',
              padding: '8px 16px', cursor: 'pointer',
              background: activeTabPath === tab.path ? '#0d1117' : 'transparent',
              borderBottom: activeTabPath === tab.path ? '1px solid #0d1117' : '1px solid transparent',
              borderRight: '1px solid #30363d',
              color: activeTabPath === tab.path ? '#c9d1d9' : '#8b949e',
              fontSize: '12px', whiteSpace: 'nowrap',
              marginBottom: '-1px'
            }}
          >
            <FileCode size={12} color={tab.language === 'python' ? '#3572A5' : '#89e051'} />
            <span>{tab.name}</span>
            {tab.isDirty && <Circle size={8} color="#58a6ff" fill="#58a6ff" />}
            <X 
              size={12} 
              onClick={(e) => closeTab(tab.path, e)}
              style={{ borderRadius: '4px', padding: '2px' }}
              className="hover-bg"
            />
          </div>
        ))}
      </div>

      {/* ===== Editor ===== */}
      <div style={{ flex: 1, position: 'relative' }}>
        {loading && (
          <div style={{
            position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: '#0d1117', color: '#8b949e', zIndex: 10
          }}>
            <Loader size={20} className="spin" /> <span style={{ marginLeft: '8px' }}>Carregando arquivo...</span>
          </div>
        )}
        
        {activeTab ? (
          <Editor
            height="100%"
            path={activeTab.path}
            defaultLanguage={activeTab.language}
            language={activeTab.language}
            value={activeTab.content}
            theme="cloudosDark"
            beforeMount={handleBeforeMount}
            onChange={(value) => handleEditorChange(value || '')}
            options={{
              fontSize: 14,
              fontFamily: 'Menlo, Consolas, "DejaVu Sans Mono", monospace',
              minimap: { enabled: true },
              scrollBeyondLastLine: false,
              automaticLayout: true,
              tabSize: 4,
              wordWrap: 'on',
              lineNumbers: 'on',
              renderWhitespace: 'selection',
              cursorBlinking: 'smooth',
              smoothScrolling: true,
            }}
          />
        ) : (
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
            height: '100%', color: '#484f58', gap: '12px'
          }}>
            <FolderOpen size={48} />
            <span style={{ fontSize: '14px' }}>Abra um arquivo pelo Explorador de Arquivos para começar a editar</span>
          </div>
        )}
      </div>

      {/* ===== Status Bar ===== */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '4px 12px', background: '#161b22', borderTop: '1px solid #30363d',
        fontSize: '11px', color: '#8b949e'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          {saveStatus === 'saving' && <><Loader size={10} className="spin" /> Salvando...</>}
          {saveStatus === 'saved' && <><CheckCircle size={10} color="#3fb950" /> Salvo no WSL</>}
          {saveStatus === 'idle' && activeTab?.isDirty && <Circle size={8} color="#58a6ff" fill="#58a6ff" />}
          {saveStatus === 'idle' && !activeTab?.isDirty && 'Pronto'}
        </div>
        
        {activeTab && (
          <div style={{ display: 'flex', gap: '12px' }}>
            <span>{activeTab.language.toUpperCase()}</span>
            <span>UTF-8</span>
            <span>LF</span>
          </div>
        )}
      </div>

      <style>{`
        .hover-bg:hover { background: rgba(255,255,255,0.1); }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        .spin { animation: spin 1s linear infinite; }
      `}</style>
    </div>
  );
}

export default CodeEditorApp;
