import { useState, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Folder, FileCode, Home, ArrowLeft, FolderPlus, Trash2, Upload, Download, Terminal as TermIcon, Code2, HardDrive, Clock, Star, FileText } from 'lucide-react';
import { useCloudFS } from '../hooks/useCloudFS';

export const FileManagerApp = ({ openApp }) => {
  const { path, items, loading, fetchFiles, action } = useCloudFS();
  const [selected, setSelected] = useState([]);
  const [progress, setProgress] = useState(0);
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0, item: null });
  const fileInputRef = useRef(null);

  const handleUpload = (e) => {
    const files = e.target.files;
    if (!files.length) return;
    
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

  const goBack = () => {
    const parts = path.split('/').filter(Boolean);
    parts.pop();
    fetchFiles(parts.join('/'));
  };

  const triggerMkdir = () => {
    const name = prompt('Nome da nova pasta:');
    if (name) action('mkdir', { path, name }).then(() => fetchFiles(path));
  };

  const triggerDelete = (itemPath) => {
    action('delete', { path: itemPath }).then(() => fetchFiles(path));
  };

  const getFileIcon = (item) => {
    if (item.type === 'folder') return <Folder size={32} color="#60a5fa" fill="#3b82f6" />;
    const ext = item.name.split('.').pop().toLowerCase();
    if (['sh', 'py', 'js', 'c', 'cpp'].includes(ext)) return <FileCode size={32} color="#4ade80" />;
    if (['txt', 'md'].includes(ext)) return <FileText size={32} color="#9ca3af" />;
    return <FileCode size={32} color="#e5e7eb" />;
  };

  const emptyTrash = async () => {
    if (!window.confirm("Tem certeza? Isso vai apagar TODOS os arquivos da lixeira permanentemente.")) return;
    
    for (const item of items) {
      await action('delete', { path: item.path });
    }
    fetchFiles('.trash');
  };

  return (
    <div className="file-manager-pro" onClick={() => setContextMenu({ visible: false })}>
      <input type="file" multiple ref={fileInputRef} style={{ display: 'none' }} onChange={handleUpload} />
      
      {/* SIDEBAR */}
      <div className="fmp-sidebar">
        <div className="fmp-sidebar-section">
          <div className="fmp-sidebar-title">Navegação</div>
          <div className={`fmp-sidebar-item ${path === '' ? 'active' : ''}`} onClick={() => fetchFiles('')}>
            <Home size={14} /> Início
          </div>
          <div className="fmp-sidebar-item" onClick={() => fetchFiles('.trash')}>
            <Trash2 size={14} /> Lixeira
          </div>
        </div>
        <div className="fmp-sidebar-section">
          <div className="fmp-sidebar-title">Sistema</div>
          <div className="fmp-sidebar-item"><HardDrive size={14} /> Armazenamento</div>
          <div className="fmp-sidebar-item"><Clock size={14} /> Recentes</div>
          <div className="fmp-sidebar-item"><Star size={14} /> Favoritos</div>
        </div>
      </div>

      {/* ÁREA PRINCIPAL */}
      <div className="fmp-main">
        {/* TOOLBAR SUPERIOR */}
        <div className="fmp-toolbar">
          <button className="fmp-btn-icon" onClick={goBack} title="Voltar"><ArrowLeft size={16} /></button>
          <div className="fmp-breadcrumb">
            <Home size={14} onClick={() => fetchFiles('')} style={{ cursor: 'pointer' }} />
            <span>{path ? `/ ${path}` : '/ Home'}</span>
          </div>
        </div>

        {/* BARRA DE AÇÕES */}
        <div className="fmp-action-bar">
          <button className="fmp-btn" onClick={triggerMkdir}><FolderPlus size={14} /> Nova Pasta</button>
          <button className="fmp-btn" onClick={() => fileInputRef.current.click()}><Upload size={14} /> Upload</button>
          
          {path === '.trash' && items.length > 0 && (
            <button className="fmp-btn-danger" onClick={emptyTrash}>
              <Trash2 size={14} /> Esvaziar Lixeira
            </button>
          )}

          {progress > 0 && (
            <div className="fmp-progress-container">
              <div className="fmp-progress-bar" style={{ width: `${progress}%` }}></div>
              <span className="fmp-progress-text">{progress}%</span>
            </div>
          )}
        </div>

        {/* GRID DE ARQUIVOS */}
        <div className="fmp-content grid-view" onContextMenu={(e) => handleContext(e)}>
          {loading ? (
            <div className="fmp-state-message">
              <div className="fmp-spinner"></div>
              <span>Lendo estrutura de diretórios...</span>
            </div>
          ) : items.length === 0 ? (
            <div className="fmp-state-message">
              <Folder size={48} color="#333" />
              <span>Pasta vazia</span>
              <p>Arraste arquivos ou clique em Upload</p>
            </div>
          ) : (
            items.map((item, i) => (
              <div key={i} className={`fmp-item ${selected.includes(item.path) ? 'selected' : ''}`}
                onClick={(e) => { e.stopPropagation(); setSelected([item.path]); }}
                onDoubleClick={() => item.type === 'folder' ? fetchFiles(item.path) : (openApp && openApp('editor', { path: item.path }))}
                onContextMenu={(e) => handleContext(e, item)}>
                {getFileIcon(item)}
                <span className="fmp-item-name">{item.name}</span>
              </div>
            ))
          )}
        </div>

        {/* STATUS BAR INFERIOR */}
        <div className="fmp-statusbar">
          <span>{items.length} itens</span>
          {selected.length > 0 && <span className="fmp-status-selected">| {selected.length} selecionado(s)</span>}
          <div className="fmp-spacer"></div>
          <span className="fmp-status-badge">WSL Kali Linux (Isolado)</span>
        </div>
      </div>

      {/* MENU DE BOTÃO DIREITO */}
      {contextMenu.visible && createPortal(
        <div className="fmp-context-menu" style={{ position: 'fixed', top: contextMenu.y, left: contextMenu.x, zIndex: 9999 }}
             onClick={(e) => e.stopPropagation()}>
          {contextMenu.item ? (
            <>
              {contextMenu.item.type === 'file' && (
                <div className="fmp-ctx-item" onClick={() => { if (openApp) openApp('editor', { path: contextMenu.item.path }); setContextMenu({ visible: false }); }}>
                  <Code2 size={14} /> Editar Código
                </div>
              )}
              <div className="fmp-ctx-item" onClick={() => { if (openApp) openApp('terminal', { cwd: contextMenu.item.path }); setContextMenu({ visible: false }); }}>
                <TermIcon size={14} /> Abrir Terminal Aqui
              </div>
              <div className="fmp-ctx-item" onClick={() => { handleDownload(contextMenu.item); setContextMenu({ visible: false }); }}>
                <Download size={14} /> Baixar (ZIP)
              </div>
              <div className="fmp-ctx-divider"></div>
              <div className="fmp-ctx-item danger" onClick={() => { triggerDelete(contextMenu.item.path); setContextMenu({ visible: false }); }}>
                <Trash2 size={14} /> Deletar
              </div>
            </>
          ) : (
            <>
              <div className="fmp-ctx-item" onClick={() => { triggerMkdir(); setContextMenu({ visible: false }); }}>
                <FolderPlus size={14} /> Nova Pasta
              </div>
              <div className="fmp-ctx-item" onClick={() => { fileInputRef.current.click(); setContextMenu({ visible: false }); }}>
                <Upload size={14} /> Upload aqui
              </div>
            </>
          )}
        </div>, document.body
      )}
    </div>
  );
};
