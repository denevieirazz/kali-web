// ============================================
// Notepad App
// ============================================
import { useState, useRef, useEffect } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useFileSystem } from '../../stores/fileSystem';
import { useProcess } from '../../contexts/ProcessContext';
import './Notepad.css';

export default function NotepadApp({ windowId }: { windowId: string }) {
  const { pid } = useProcess();
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const { getWindow, updateWindowTitle } = useWindowManager();
  const { getNode, updateFileContent } = useFileSystem();

  const [content, setContent] = useState('');
  const [fileName, setFileName] = useState('Sem título');
  const [filePath, setFilePath] = useState('');
  const [isModified, setIsModified] = useState(false);
  const [fontSize, setFontSize] = useState(14);
  const [showStatusBar] = useState(true);
  const [cursorLine, setCursorLine] = useState(1);
  const [cursorCol, setCursorCol] = useState(1);
  const [wordWrap] = useState(true);

  // Initialize from window params (file path)
  useEffect(() => {
    const win = getWindow(windowId);
    if (win?.params?.filePath) {
      const path = win.params.filePath;
      const node = getNode(path);
      if (node && node.type === 'file') {
        setContent(node.content || '');
        setFileName(node.name);
        setFilePath(path);
        setIsModified(false);
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
      handleSave();
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

  const handleSave = () => {
    if (filePath) {
      updateFileContent(filePath, content);
      setIsModified(false);
    }
  };

  const lineCount = content.split('\n').length;
  const charCount = content.length;

  return (
    <div className="notepad">
      {/* Menu Bar */}
      <div className="notepad-menubar">
        <button className="notepad-menu-item">Arquivo</button>
        <button className="notepad-menu-item">Editar</button>
        <button className="notepad-menu-item">Formatar</button>
        <button className="notepad-menu-item">Exibir</button>
        <button className="notepad-menu-item">Ajuda</button>
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
