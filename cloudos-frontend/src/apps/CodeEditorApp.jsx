import { useState, useEffect } from 'react';
import Editor from '@monaco-editor/react';
import { Code2, Save, Eye } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const CodeEditorApp = ({ payload }) => {
  const [currentFile, setCurrentFile] = useState(null);
  const [content, setContent] = useState('');
  const [saved, setSaved] = useState(true);
  const [showPreview, setShowPreview] = useState(false);

  useEffect(() => {
    if (payload?.path) openFile(payload.path);
  }, [payload]);

  const openFile = (filePath) => {
    fetch(`${API_BASE}/api/files/read?path=${encodeURIComponent(filePath)}`, {
      headers: { 'Authorization': `Bearer ${token()}` }
    })
      .then(res => res.json())
      .then(data => { setCurrentFile(filePath); setContent(data.content || ''); setSaved(true); });
  };

  const saveFile = () => {
    if (!currentFile) return;
    fetch(`${API_BASE}/api/files/save`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
      body: JSON.stringify({ path: currentFile, content })
    }).then(() => setSaved(true));
  };

  const isHtml = currentFile?.endsWith('.html');

  return (
    <div className="flex flex-col h-full bg-gray-900">
      <div className="flex items-center justify-between p-2 bg-gray-800 border-b border-gray-700">
        <div className="flex items-center gap-2 text-white text-sm">
          <Code2 size={16} /> {currentFile ? currentFile.split('/').pop() : 'Sem arquivo'}
          {!saved && <span className="text-blue-400">*</span>}
        </div>
        <div className="flex gap-2">
          {isHtml && (
            <button onClick={() => setShowPreview(!showPreview)} className="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1 rounded text-xs flex items-center gap-1">
              <Eye size={14} /> {showPreview ? 'Ver Código' : 'Ver Preview'}
            </button>
          )}
          <button onClick={saveFile} disabled={saved} className="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 text-white px-3 py-1 rounded text-xs flex items-center gap-1">
            <Save size={14} /> Salvar
          </button>
        </div>
      </div>
      
      <div className="flex-1" style={{ minHeight: '300px' }}>
        {showPreview && isHtml ? (
          <iframe srcDoc={content} title="preview" sandbox="allow-scripts" className="w-full h-full bg-white" style={{ width: '100%', height: '100%', border: 'none' }} />
        ) : (
          <Editor height="100%" theme="vs-dark" language={currentFile?.split('.').pop() || 'plaintext'} value={content} onChange={(v) => { setContent(v); setSaved(false); }} />
        )}
      </div>
    </div>
  );
};
