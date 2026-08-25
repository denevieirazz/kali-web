// ============================================
// Notepad App
// ============================================
import { useState, useRef, useEffect } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useFileSystem } from '../../stores/fileSystem';
import { useProcess } from '../../contexts/ProcessContext';
import './Notepad.css';

import { readFile, writeTextFile, listDirectory } from '../CloudOSFiles/opfsFileService';

export default function NotepadApp({ windowId }: { windowId: string }) {
  const { pid } = useProcess();
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { getWindow, updateWindowTitle, closeWindow } = useWindowManager();
  const { getNode, updateFileContent } = useFileSystem();

  const [content, setContent] = useState('');
  const [fileName, setFileName] = useState('Sem título');
  const [filePath, setFilePath] = useState('');
  const [isModified, setIsModified] = useState(false);
  const [fontSize, setFontSize] = useState(14);
  const [showStatusBar] = useState(true);
  const [cursorLine, setCursorLine] = useState(1);
  const [cursorCol, setCursorCol] = useState(1);
  const [wordWrap, setWordWrap] = useState(true);
  const [showFileMenu, setShowFileMenu] = useState(false);

  // Initialize from window params (file path or content)
  useEffect(() => {
    const win = getWindow(windowId);
    if (win?.params?.content !== undefined || win?.params?.fileContent !== undefined) {
      setContent(win.params.fileContent ?? win.params.content ?? '');
      if (win.params.fileName) setFileName(win.params.fileName);
      if (win.params.filePath) setFilePath(win.params.filePath);
      setIsModified(false);
      return;
    }
    if (win?.params?.filePath) {
      const path = win.params.filePath;
      if (path.startsWith('~/')) {
        const parts = path.replace(/^~\//, '').split('/');
        const name = parts.pop() || 'Documento.txt';
        setFileName(name);
        setFilePath(path);
        void readFile(parts, name).then(file => file.text()).then(text => {
          setContent(text);
          setIsModified(false);
        }).catch(() => {
          setContent('');
          setIsModified(false);
        });
      } else {
        const node = getNode(path);
        if (node && node.type === 'file') {
          setContent(node.content || '');
          setFileName(node.name);
          setFilePath(path);
          setIsModified(false);
        }
      }
    }
  }, [windowId, getWindow, getNode]);

  useEffect(() => {
    updateWindowTitle(windowId, `${fileName}${isModified ? ' •' : ''} - Bloco de Notas`);
  }, [fileName, isModified, windowId, updateWindowTitle]);

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setContent(e.target.value);
    setIsModified(true);
    updateCursorPos(e.target);
  };

  const updateCursorPos = (textarea: HTMLTextAreaElement) => {
    const text = textarea.value.substring(0, textarea.selectionStart);
    const lines = text.split('\n');
    setCursorLine(lines.length);
    setCursorCol(lines[lines.length - 1].length + 1);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.ctrlKey && e.key === 's') {
      e.preventDefault();
      void handleSave();
    }
    if (e.key === 'Tab') {
      e.preventDefault();
      const textarea = textareaRef.current;
      if (!textarea) return;
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      const newContent = content.substring(0, start) + '    ' + content.substring(end);
      setContent(newContent);
      setTimeout(() => {
        textarea.selectionStart = textarea.selectionEnd = start + 4;
      }, 0);
    }
  };

  const handleSave = async () => {
    if (filePath && !filePath.startsWith('~/')) {
      updateFileContent(filePath, content);
      setIsModified(false);
    } else if (filePath && filePath.startsWith('~/')) {
      const parts = filePath.replace(/^~\//, '').split('/');
      const name = parts.pop() || fileName;
      await writeTextFile(parts, name, content);
      setIsModified(false);
    } else {
      await handleSaveAs();
    }
  };

  const handleSaveAs = async () => {
    const defaultVal = filePath || `~/Documents/${fileName.endsWith('.txt') ? fileName : `${fileName}.txt`}`;
    const input = window.prompt('Salvar arquivo em CloudOS Home:', defaultVal);
    if (!input) return;
    const normalized = input.trim().replace(/^~\//, '');
    const segments = normalized.split(/[\/\\]+/).filter(Boolean);
    const saveName = segments.pop() || 'documento.txt';
    const folderParts = segments.length > 0 ? segments : ['Documents'];
    try {
      await writeTextFile(folderParts, saveName, content);
      setFileName(saveName);
      setFilePath(`~/${[...folderParts, saveName].join('/')}`);
      setIsModified(false);
    } catch (err: any) {
      alert(`Erro ao salvar no CloudOS Home: ${err.message}`);
    }
  };

  const handleOpen = async () => {
    const input = window.prompt(
      'Abrir arquivo de CloudOS Home:\n(Ex: ~/Documents/nota.txt, ~/Desktop/teste.txt ou ~/Projects/App/readme.md)',
      filePath || '~/Documents/'
    );
    if (!input) return;
    const normalized = input.trim().replace(/^~\//, '');
    const segments = normalized.split(/[\/\\]+/).filter(Boolean);
    if (segments.length === 0) return;
    const targetName = segments.pop()!;
    const folderParts = segments;
    try {
      const file = await readFile(folderParts, targetName);
      const text = await file.text();
      setContent(text);
      setFileName(targetName);
      setFilePath(`~/${[...folderParts, targetName].join('/')}`);
      setIsModified(false);
    } catch (err: any) {
      alert(`Falha ao abrir arquivo: ${err.message}`);
    }
  };

  const handleNew = () => {
    if (isModified && !window.confirm('Descartar alterações não salvas?')) return;
    setContent('');
    setFileName('Sem título');
    setFilePath('');
    setIsModified(false);
  };

  const lineCount = content.split('\n').length;
  const charCount = content.length;

  return (
    <div className="notepad" onClick={() => setShowFileMenu(false)}>
      {/* Menu Bar */}
      <div className="notepad-menubar" style={{ position: 'relative' }}>
        <div style={{ position: 'relative', display: 'inline-block' }}>
          <button
            className="notepad-menu-item"
            onClick={(e) => { e.stopPropagation(); setShowFileMenu(v => !v); }}
          >
            Arquivo
          </button>
          {showFileMenu && (
            <div style={{
              position: 'absolute',
              top: '100%',
              left: 0,
              background: 'var(--surface-dropdown, #1f1f23)',
              border: '1px solid var(--border-subtle, #333)',
              borderRadius: 4,
              boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
              padding: 4,
              zIndex: 100,
              minWidth: 160,
              display: 'flex',
              flexDirection: 'column',
              gap: 2
            }}>
              <button
                style={{ background: 'transparent', border: 'none', color: '#eee', padding: '6px 12px', textAlign: 'left', cursor: 'pointer', borderRadius: 4 }}
                onClick={() => { setShowFileMenu(false); handleNew(); }}
              >
                📄 Novo
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#eee', padding: '6px 12px', textAlign: 'left', cursor: 'pointer', borderRadius: 4 }}
                onClick={() => { setShowFileMenu(false); void handleOpen(); }}
              >
                📂 Abrir...
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#eee', padding: '6px 12px', textAlign: 'left', cursor: 'pointer', borderRadius: 4 }}
                onClick={() => { setShowFileMenu(false); void handleSave(); }}
              >
                💾 Salvar (Ctrl+S)
              </button>
              <button
                style={{ background: 'transparent', border: 'none', color: '#eee', padding: '6px 12px', textAlign: 'left', cursor: 'pointer', borderRadius: 4 }}
                onClick={() => { setShowFileMenu(false); void handleSaveAs(); }}
              >
                💾 Salvar Como...
              </button>
              <div style={{ height: 1, background: '#333', margin: '4px 0' }} />
              <button
                style={{ background: 'transparent', border: 'none', color: '#eee', padding: '6px 12px', textAlign: 'left', cursor: 'pointer', borderRadius: 4 }}
                onClick={() => { setShowFileMenu(false); closeWindow(windowId); }}
              >
                ✕ Sair
              </button>
            </div>
          )}
        </div>
        <button className="notepad-menu-item" onClick={() => setWordWrap(w => !w)}>Quebra de Linha: {wordWrap ? 'Ligada' : 'Desligada'}</button>
        <button className="notepad-menu-item" onClick={() => setFontSize(s => s === 14 ? 18 : 14)}>Tamanho da Fonte</button>
      </div>

      {/* Editor */}
      <div className="notepad-editor">
        <textarea
          ref={textareaRef}
          className="notepad-textarea"
          value={content}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          onClick={(e) => updateCursorPos(e.target as HTMLTextAreaElement)}
          onKeyUp={(e) => updateCursorPos(e.target as HTMLTextAreaElement)}
          spellCheck={false}
          style={{ 
            whiteSpace: wordWrap ? 'pre-wrap' : 'pre',
            fontSize: `${fontSize}px`,
          }}
          placeholder="Comece a digitar..."
        />
      </div>

      {/* Status Bar */}
      {showStatusBar && (
        <div className="notepad-statusbar">
          <span className="pid-indicator" style={{ color: 'var(--accent)', fontWeight: 'bold' }}>PID: {pid}</span>
          <span>Ln {cursorLine}, Col {cursorCol}</span>
          <span>{charCount} caracteres</span>
          <span>{lineCount} linhas</span>
          <span>UTF-8</span>
          <span>CRLF</span>
          <span className="notepad-zoom">
            <button onClick={() => setFontSize(s => Math.max(8, s - 1))}>−</button>
            <span>{Math.round(fontSize / 14 * 100)}%</span>
            <button onClick={() => setFontSize(s => Math.min(32, s + 1))}>+</button>
          </span>
        </div>
      )}
    </div>
  );
}
