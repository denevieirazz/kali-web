import { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Folder, FileCode, Home, ArrowLeft, FolderPlus, Trash2, Upload, List, LayoutGrid, Terminal as TermIcon, Code2 } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const FileManagerApp = ({ openApp }) => {
  const [path, setPath] = useState('');
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState([]);
  const [view, setView] = useState('grid');
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0, item: null });
  const fileInputRef = useRef(null);

  const fetchFiles = (newPath) => {
    setLoading(true);
    setPath(newPath);
    setSelected([]);
    fetch(`${API_BASE}/api/files?path=${encodeURIComponent(newPath)}`, {
      headers: { 'Authorization': `Bearer ${token()}` }
    })
      .then(res => res.json())
      .then(data => { setItems(data.items || []); setLoading(false); })
      .catch(() => setLoading(false));
  };

  useEffect(() => { fetchFiles(''); }, []);

  const handleAction = async (action, item = null) => {
    setContextMenu({ ...contextMenu, visible: false });
    const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` };
    
    if (action === 'mkdir') {
      const name = prompt('Nome da nova pasta:');
      if (!name) return;
      await fetch(`${API_BASE}/api/files/mkdir`, { method: 'POST', headers, body: JSON.stringify({ path, name }) });
    } else if (action === 'delete') {
      await fetch(`${API_BASE}/api/files/delete`, { method: 'POST', headers, body: JSON.stringify({ path: item ? item.path : selected[0] }) });
    }
    fetchFiles(path);
  };

  const handleUpload = async (e) => {
    const files = e.target.files;
    if (!files || !files.length) return;
    const formData = new FormData();
    for (let file of files) formData.append('files', file);
    formData.append('path', path);
    
    await fetch(`${API_BASE}/api/files/upload`, { 
      method: 'POST', 
      headers: { 'Authorization': `Bearer ${token()}` },
      body: formData 
    });
    fetchFiles(path);
  };

  const handleContextMenu = (e, item = null) => {
    e.preventDefault(); e.stopPropagation();
    if (item && !selected.includes(item.path)) setSelected([item.path]);
    setContextMenu({ visible: true, x: e.clientX, y: e.clientY, item });
  };

  return (
    <div className="file-manager-pro" onClick={() => setContextMenu({ ...contextMenu, visible: false })}>
      <input type="file" multiple ref={fileInputRef} style={{ display: 'none' }} onChange={handleUpload} />
      
      <div className="fmp-toolbar">
        <button className="fmp-btn-icon" onClick={() => fetchFiles(path.split('/').slice(0, -1).join('/'))}><ArrowLeft size={16} /></button>
        <div className="fmp-breadcrumb">
          <Home size={14} onClick={() => fetchFiles('')} />
          <span>{path || 'Home'}</span>
        </div>
        <button className="fmp-btn-icon" onClick={() => setView(view === 'grid' ? 'list' : 'grid')}>{view === 'grid' ? <List size={16} /> : <LayoutGrid size={16} />}</button>
      </div>

      <div className="fmp-action-bar">
        <button className="fmp-btn" onClick={() => handleAction('mkdir')}><FolderPlus size={14} /> Nova Pasta</button>
        <button className="fmp-btn" onClick={() => fileInputRef.current.click()}><Upload size={14} /> Upload</button>
      </div>

      <div className={`fmp-content ${view}-view`} onContextMenu={(e) => handleContextMenu(e)}>
        {loading ? <div>Carregando...</div> : items.length === 0 ? <div>Pasta vazia</div> : 
          items.map((item, i) => (
            <div key={i} className={`fmp-item ${selected.includes(item.path) ? 'selected' : ''}`}
              onClick={(e) => { e.stopPropagation(); setSelected([item.path]); }}
              onDoubleClick={() => item.type === 'folder' ? fetchFiles(item.path) : (openApp && openApp('editor', { path: item.path }))}
              onContextMenu={(e) => handleContextMenu(e, item)}>
              {item.type === 'folder' ? <Folder size={32} color="#60a5fa" /> : <FileCode size={32} color="#4ade80" />}
              <span>{item.name}</span>
            </div>
          ))
        }
      </div>

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
              <div className="fmp-ctx-divider"></div>
              <div className="fmp-ctx-item danger" onClick={() => handleAction('delete', contextMenu.item)}><Trash2 size={14} /> Deletar</div>
            </>
          ) : (
            <>
              <div className="fmp-ctx-item" onClick={() => handleAction('mkdir')}><FolderPlus size={14} /> Nova Pasta</div>
              <div className="fmp-ctx-item" onClick={() => fileInputRef.current.click()}><Upload size={14} /> Upload aqui</div>
            </>
          )}
        </div>, document.body
      )}
    </div>
  );
};
