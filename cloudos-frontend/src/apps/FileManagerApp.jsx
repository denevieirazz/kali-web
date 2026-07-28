import { useState, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Folder, FileCode, Home, ArrowLeft, FolderPlus, Trash2, Upload, Download, Terminal as TermIcon, Code2 } from 'lucide-react';
import { useCloudFS } from '../hooks/useCloudFS';

export const FileManagerApp = ({ openApp }) => {
  const { path, items, loading, fetchFiles, action } = useCloudFS();
  const [selected, setSelected] = useState([]);
  const [progress, setProgress] = useState(0);
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0, item: null });
  const fileInputRef = useRef(null);

  const handleUpload = (e) => {
    const files = e.target.files;
    if (!files || !files.length) return;
    
    const formData = new FormData();
    for (let file of files) formData.append('files', file);
    formData.append('path', path);

    const xhr = new XMLHttpRequest();
    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) setProgress(Math.round((e.loaded * 100) / e.total));
    });
    xhr.addEventListener('load', () => { setProgress(0); fetchFiles(path); });
    xhr.addEventListener('error', () => setProgress(0));
    
    xhr.open('POST', 'http://localhost:8080/api/files/upload');
    xhr.setRequestHeader('Authorization', `Bearer ${localStorage.getItem('cloudos_token')}`);
    xhr.send(formData);
  };

  const handleDownload = (item) => {
    window.location.href = `http://localhost:8080/api/files/download?path=${encodeURIComponent(item.path)}`;
  };

  const handleContext = (e, item = null) => {
    e.preventDefault(); e.stopPropagation();
    if (item) setSelected([item.path]);
    setContextMenu({ visible: true, x: e.clientX, y: e.clientY, item });
  };

  return (
    <div className="file-manager-pro" onClick={() => setContextMenu({ visible: false })}>
      <input type="file" multiple ref={fileInputRef} style={{ display: 'none' }} onChange={handleUpload} />
      
      {/* Toolbar */}
      <div className="fmp-toolbar">
        <button className="fmp-btn-icon" onClick={() => fetchFiles(path.split('/').slice(0, -1).join('/'))}><ArrowLeft size={16} /></button>
        <div className="fmp-breadcrumb">
          <Home size={14} onClick={() => fetchFiles('')} />
          <span>/ {path}</span>
        </div>
      </div>

      {/* Action Bar com Upload Progress */}
      <div className="fmp-action-bar">
        <button className="fmp-btn" onClick={() => { const name = prompt('Nome da pasta:'); if (name) action('mkdir', { path, name }).then(() => fetchFiles(path)); }}>
          <FolderPlus size={14} /> Nova Pasta
        </button>
        <button className="fmp-btn" onClick={() => fileInputRef.current.click()}>
          <Upload size={14} /> Upload
        </button>
        {progress > 0 && (
          <div className="fmp-progress-container">
            <div className="fmp-progress-bar" style={{ width: `${progress}%` }}></div>
            <span className="fmp-progress-text">{progress}%</span>
          </div>
        )}
      </div>

      {/* Grid de Arquivos */}
      <div className="fmp-content grid-view" onContextMenu={(e) => handleContext(e)}>
        {loading ? <div className="fmp-loading">Carregando...</div> : 
         items.length === 0 ? <div className="fmp-empty">Pasta vazia</div> :
          items.map((item, i) => (
            <div key={i} className={`fmp-item ${selected.includes(item.path) ? 'selected' : ''}`}
              onClick={(e) => { e.stopPropagation(); setSelected([item.path]); }}
              onDoubleClick={() => item.type === 'folder' ? fetchFiles(item.path) : (openApp && openApp('editor', { path: item.path }))}
              onContextMenu={(e) => handleContext(e, item)}>
              {item.type === 'folder' ? <Folder size={32} color="#60a5fa" /> : <FileCode size={32} color="#4ade80" />}
              <span>{item.name}</span>
            </div>
          ))
        }
      </div>

      {/* Context Menu Portal */}
      {contextMenu.visible && createPortal(
        <div className="fmp-context-menu" style={{ position: 'fixed', top: contextMenu.y, left: contextMenu.x, zIndex: 9999 }}>
          {contextMenu.item ? (
            <>
              {contextMenu.item.type === 'file' && (
                <div className="fmp-ctx-item" onClick={() => { if (openApp) openApp('editor', { path: contextMenu.item.path }); setContextMenu({ ...contextMenu, visible: false }); }}>
                  <Code2 size={14} /> Editar Código
                </div>
              )}
              <div className="fmp-ctx-item" onClick={() => { if (openApp) openApp('terminal', { cwd: contextMenu.item.path }); setContextMenu({ ...contextMenu, visible: false }); }}>
                <TermIcon size={14} /> Abrir Terminal Aqui
              </div>
              <div className="fmp-ctx-item" onClick={() => { handleDownload(contextMenu.item); setContextMenu({ ...contextMenu, visible: false }); }}>
                <Download size={14} /> Baixar (ZIP)
              </div>
              <div className="fmp-ctx-divider"></div>
              <div className="fmp-ctx-item danger" onClick={() => action('delete', { path: contextMenu.item.path }).then(() => fetchFiles(path))}>
                <Trash2 size={14} /> Deletar
              </div>
            </>
          ) : (
            <>
              <div className="fmp-ctx-item" onClick={() => { const name = prompt('Nome:'); if (name) action('mkdir', { path, name }).then(() => fetchFiles(path)); }}><FolderPlus size={14} /> Nova Pasta</div>
              <div className="fmp-ctx-item" onClick={() => fileInputRef.current.click()}><Upload size={14} /> Upload aqui</div>
            </>
          )}
        </div>, document.body
      )}
    </div>
  );
};
