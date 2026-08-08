import React, { useState, useRef, useEffect, useCallback } from 'react';
import Editor from '@monaco-editor/react';
import './ScriptLabApp.css';
import { SCRIPT_TEMPLATES } from './scriptLabTemplates';

const LANGUAGES = [
  { id: 'python', label: 'Python (.py)', ext: '.py', icon: '🐍' },
  { id: 'bash', label: 'Bash (.sh)', ext: '.sh', icon: '💻' },
  { id: 'ruby', label: 'Ruby (.rb)', ext: '.rb', icon: '💎' },
  { id: 'powershell', label: 'PowerShell (.ps1)', ext: '.ps1', icon: '⚡' }
];

const ScriptLabApp = () => {
  const [code, setCode] = useState('');
  const [language, setLanguage] = useState('python');
  const [fileName, setFileName] = useState('script1.py');
  const [output, setOutput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [savedScripts, setSavedScripts] = useState(() => {
    try {
      const saved = localStorage.getItem('cloudos_scripts');
      return saved ? JSON.parse(saved) : [];
    } catch { return []; }
  });
  const [showTemplates, setShowTemplates] = useState(false);
  const [showSaved, setShowSaved] = useState(false);
  const outputRef = useRef(null);
  const abortRef = useRef(null);

  // Auto-scroll output
  useEffect(() => {
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [output]);

  // Salvar scripts no localStorage
  const saveScripts = useCallback((scripts) => {
    setSavedScripts(scripts);
    localStorage.setItem('cloudos_scripts', JSON.stringify(scripts));
  }, []);

  // Novo script
  const handleNew = () => {
    if (code.trim() && !window.confirm('Tem certeza? O código atual será perdido.')) return;
    setCode('');
    setOutput('');
    const ext = LANGUAGES.find(l => l.id === language)?.ext || '.py';
    setFileName('script' + Date.now().toString(36) + ext);
  };

  // Salvar script localmente
  const handleSave = () => {
    if (!code.trim()) return;
    const existingIndex = savedScripts.findIndex(s => s.name === fileName);
    const newScript = { name: fileName, language, code, date: new Date().toISOString() };
    let updated;
    if (existingIndex >= 0) {
      updated = [...savedScripts];
      updated[existingIndex] = newScript;
    } else {
      updated = [...savedScripts, newScript];
    }
    saveScripts(updated);
    setOutput(prev => prev + '\n[ScriptLab] ✅ Script salvo localmente: ' + fileName);
  };

  // Salvar script no Kali / WSL2 para sobreviver à limpeza de cache
  const handleSaveWSL = async () => {
    if (!code.trim()) return;
    try {
      const res = await fetch('/api/scriptlab/save-to-wsl', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        },
        body: JSON.stringify({ name: fileName, code, language })
      });
      if (res.ok) {
        const data = await res.json();
        setOutput(prev => prev + `\n[ScriptLab] 🐧 Script persistido no WSL Kali (${data.name || fileName})!`);
      } else {
        throw new Error('Falha ao salvar no WSL');
      }
    } catch (err) {
      setOutput(prev => prev + `\n[ScriptLab Error] ❌ ${err.message}`);
    }
  };

  // Carregar script salvo
  const handleLoad = (script) => {
    setCode(script.code);
    setLanguage(script.language);
    setFileName(script.name);
    setShowSaved(false);
    setOutput(prev => prev + '\n[ScriptLab] 📂 Script carregado: ' + script.name);
  };

  // Deletar script salvo
  const handleDelete = (name, e) => {
    e.stopPropagation();
    const updated = savedScripts.filter(s => s.name !== name);
    saveScripts(updated);
    setOutput(prev => prev + '\n[ScriptLab] 🗑️ Script deletado: ' + name);
  };

  // Carregar template
  const handleTemplate = (template) => {
    if (code.trim() && !window.confirm('Carregar template? O código atual será perdido.')) return;
    setCode(template.code);
    setLanguage(template.language);
    const ext = LANGUAGES.find(l => l.id === template.language)?.ext || '.py';
    setFileName(template.name.toLowerCase().replace(/\s+/g, '_') + ext);
    setShowTemplates(false);
    setOutput(prev => prev + '\n[ScriptLab] 📋 Template carregado: ' + template.name);
  };

  // Mudar linguagem
  const handleLanguageChange = (langId) => {
    const ext = LANGUAGES.find(l => l.id === langId)?.ext || '.py';
    setLanguage(langId);
    setFileName(prev => prev.replace(/\.[^.]+$/, ext));
  };

  // Executar script
  const handleRun = async () => {
    if (!code.trim()) return;
    setIsRunning(true);
    setOutput(prev => prev + `\n\n🚀 [Executando ${fileName} como ${language}...]\n` + '─'.repeat(40) + '\n');

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const res = await fetch('/api/scriptlab/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}` },
        body: JSON.stringify({ code, language, fileName }),
        signal: controller.signal
      });

      if (!res.ok) {
        const errText = await res.text();
        throw new Error(errText || `HTTP ${res.status}`);
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          if (line.trim()) setOutput(prev => prev + line + '\n');
        }
      }
      if (buffer.trim()) setOutput(prev => prev + buffer + '\n');

      setOutput(prev => prev + '─'.repeat(40) + '\n✅ [Execução concluída]\n');
    } catch (err) {
      if (err.name === 'AbortError') {
        setOutput(prev => prev + '\n⏹️ [Execução interrompida pelo usuário]\n');
      } else {
        setOutput(prev => prev + '\n❌ [Erro] ' + err.message + '\n');
      }
    } finally {
      setIsRunning(false);
      abortRef.current = null;
    }
  };

  // Parar execução
  const handleStop = () => {
    if (abortRef.current) {
      abortRef.current.abort();
    }
    // Também tenta parar no backend
    fetch('/api/scriptlab/stop', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}` }
    }).catch(() => {});
  };

  // Download do script
  const handleDownload = () => {
    const blob = new Blob([code], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Atalhos de teclado
  const handleKeyDown = useCallback((e) => {
    if (e.ctrlKey && e.key === 's') {
      e.preventDefault();
      handleSave();
    }
    if (e.ctrlKey && e.key === 'Enter') {
      e.preventDefault();
      handleRun();
    }
  }, [code, fileName, language]);

  const currentLang = LANGUAGES.find(l => l.id === language);

  return (
    <div className="scriptlab-container" onKeyDown={handleKeyDown} tabIndex={-1}>
      {/* Header Toolbar */}
      <div className="scriptlab-toolbar">
        <div className="scriptlab-toolbar-left">
          <button className="sl-btn sl-btn-new" onClick={handleNew} title="Novo Script (Ctrl+N)">
            📄 Novo
          </button>
          <button className="sl-btn sl-btn-save" onClick={handleSave} title="Salvar (Ctrl+S)">
            💾 Salvar
          </button>
          <button className="sl-btn sl-btn-wsl" onClick={handleSaveWSL} title="Salvar no WSL Kali (Persistente)">
            🐧 Salvar WSL
          </button>
          <button className="sl-btn sl-btn-download" onClick={handleDownload} title="Download">
            📥 Baixar
          </button>
          <div className="sl-separator" />
          <button
            className={`sl-btn sl-btn-run ${isRunning ? 'running' : ''}`}
            onClick={handleRun}
            disabled={isRunning}
            title="Executar (Ctrl+Enter)"
          >
            ▶️ Executar
          </button>
          <button
            className="sl-btn sl-btn-stop"
            onClick={handleStop}
            disabled={!isRunning}
            title="Parar Execução"
          >
            ⏹️ Parar
          </button>
        </div>
        <div className="scriptlab-toolbar-right">
          <div className="sl-language-selector">
            <span className="sl-lang-icon">{currentLang?.icon}</span>
            <select
              value={language}
              onChange={(e) => handleLanguageChange(e.target.value)}
              className="sl-lang-select"
            >
              {LANGUAGES.map(lang => (
                <option key={lang.id} value={lang.id}>{lang.label}</option>
              ))}
            </select>
          </div>
          <input
            type="text"
            className="sl-filename-input"
            value={fileName}
            onChange={(e) => setFileName(e.target.value)}
            placeholder="nome_do_script.py"
          />
        </div>
      </div>

      {/* Main Content Area */}
      <div className="scriptlab-main">
        {/* Left Sidebar */}
        <div className="scriptlab-sidebar">
          <div className="sl-sidebar-section">
            <button
              className={`sl-sidebar-btn ${showTemplates ? 'active' : ''}`}
              onClick={() => { setShowTemplates(!showTemplates); setShowSaved(false); }}
            >
              📋 Templates
            </button>
            <button
              className={`sl-sidebar-btn ${showSaved ? 'active' : ''}`}
              onClick={() => { setShowSaved(!showSaved); setShowTemplates(false); }}
            >
              📂 Salvos ({savedScripts.length})
            </button>
          </div>

          {/* Templates Panel */}
          {showTemplates && (
            <div className="sl-sidebar-panel">
              <h4>Templates de Pentest</h4>
              {SCRIPT_TEMPLATES.map((tpl, i) => (
                <div key={i} className="sl-template-item" onClick={() => handleTemplate(tpl)}>
                  <span className="sl-template-icon">{LANGUAGES.find(l => l.id === tpl.language)?.icon || '📜'}</span>
                  <div className="sl-template-info">
                    <div className="sl-template-name">{tpl.name}</div>
                    <div className="sl-template-desc">{tpl.description}</div>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Saved Scripts Panel */}
          {showSaved && (
            <div className="sl-sidebar-panel">
              <h4>Scripts Salvos</h4>
              {savedScripts.length === 0 ? (
                <div className="sl-empty">Nenhum script salvo ainda.</div>
              ) : (
                savedScripts.map((script, i) => (
                  <div key={i} className="sl-saved-item" onClick={() => handleLoad(script)}>
                    <span className="sl-saved-icon">
                      {LANGUAGES.find(l => l.id === script.language)?.icon || '📜'}
                    </span>
                    <div className="sl-saved-info">
                      <div className="sl-saved-name">{script.name}</div>
                      <div className="sl-saved-date">{new Date(script.date).toLocaleString('pt-BR')}</div>
                    </div>
                    <button className="sl-saved-delete" onClick={(e) => handleDelete(script.name, e)} title="Deletar">
                      🗑️
                    </button>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        {/* Editor + Output */}
        <div className="scriptlab-content">
          {/* Editor Monaco */}
          <div className="scriptlab-editor">
            <Editor
              height="100%"
              language={language}
              value={code}
              onChange={(val) => setCode(val || '')}
              theme="vs-dark"
              options={{
                fontSize: 14,
                fontFamily: "'Fira Code', 'Cascadia Code', 'JetBrains Mono', 'Consolas', monospace",
                minimap: { enabled: true, scale: 1 },
                lineNumbers: 'on',
                scrollBeyondLastLine: false,
                wordWrap: 'on',
                tabSize: 4,
                insertSpaces: true,
                automaticLayout: true,
                bracketPairColorization: { enabled: true },
                padding: { top: 12 },
                suggestOnTriggerCharacters: true,
                quickSuggestions: true,
                renderWhitespace: 'selection',
                cursorBlinking: 'smooth',
                smoothScrolling: true,
              }}
              loading={
                <div className="sl-editor-loading">
                  <div className="sl-spinner" />
                  <span>Carregando Editor...</span>
                </div>
              }
            />
          </div>

          {/* Output Terminal */}
          <div className="scriptlab-output">
            <div className="sl-output-header">
              <span className="sl-output-title">📟 Saída do Terminal</span>
              <button
                className="sl-output-clear"
                onClick={() => setOutput('')}
                title="Limpar Saída"
              >
                🧹 Limpar
              </button>
            </div>
            <div className="sl-output-content" ref={outputRef}>
              {output ? (
                <pre className="sl-output-text">{output}</pre>
              ) : (
                <div className="sl-output-placeholder">
                  <div className="sl-placeholder-icon">▶️</div>
                  <div>Execute seu script com <strong>Ctrl+Enter</strong> ou clique em <strong>Executar</strong></div>
                  <div className="sl-placeholder-hint">
                    Dica: Selecione um template na barra lateral para começar rápido!
                  </div>
                </div>
              )}
              {isRunning && (
                <div className="sl-output-running">
                  <div className="sl-spinner-small" /> Executando...
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Status Bar */}
      <div className="scriptlab-statusbar">
        <span className="sl-status-item">📝 {fileName}</span>
        <span className="sl-status-item">{currentLang?.icon} {currentLang?.label}</span>
        <span className="sl-status-item">📏 {code.split('\n').length} linhas</span>
        <span className="sl-status-item">{code.length} caracteres</span>
        {isRunning && <span className="sl-status-running">🟢 Executando...</span>}
      </div>
    </div>
  );
};

export default ScriptLabApp;
