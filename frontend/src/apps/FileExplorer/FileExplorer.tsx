// ============================================
// File Explorer App
// ============================================
import { useState, useCallback, useRef } from 'react';
import { useFileSystem } from '../../stores/fileSystem';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import { useRubberBand } from '../../hooks/useRubberBand';
import kernel from '../../core/kernel';
import './FileExplorer.css';

export default function FileExplorerApp({ windowId }: { windowId: string }) {
  const { currentUser } = useSystem();
  const userHome = `C:\\Users\\${currentUser.username}`;
  const [currentPath, setCurrentPath] = useState(userHome);
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set());
  const [viewMode, setViewMode] = useState<'list' | 'grid' | 'details'>('details');
  const [pathInput, setPathInput] = useState(currentPath);
  const [isEditingPath, setIsEditingPath] = useState(false);
  const itemRefs = useRef<Map<string, HTMLElement>>(new Map());

  const { getNode, getChildren, deleteNode } = useFileSystem();
  const { updateWindowTitle } = useWindowManager();
  const openWindow = useWindowManager(s => s.openWindow);
  const createProcess = useProcessManager(s => s.createProcess);
  const { openContextMenu } = useContextMenuStore();
  const apps = useAppRegistry((s: any) => s.apps);

  const getItemRects = useCallback(() => {
    const map = new Map<string, DOMRect>();
    itemRefs.current.forEach((el, key) => {
      if (el) map.set(key, el.getBoundingClientRect());
    });
    return map;
  }, []);

  const { selectionRect, onMouseDown, containerRef } = useRubberBand({
    onSelectionChange: (keys) => setSelectedItems(new Set(keys)),
    getItemRects,
  });

  const children = getChildren(currentPath);
  const dirs = children.filter(c => c.type === 'directory').sort((a, b) => a.name.localeCompare(b.name));
  const files = children.filter(c => c.type === 'file').sort((a, b) => a.name.localeCompare(b.name));
  const sortedChildren = [...dirs, ...files];

  const navigateTo = useCallback((path: string) => {
    const node = getNode(path);
    if (node && node.type === 'directory') {
      setCurrentPath(path);
      setPathInput(path);
      setSelectedItems(new Set());
      updateWindowTitle(windowId, `${node.name} - Explorador de Arquivos`);
    }
  }, [getNode, windowId, updateWindowTitle]);

  const goUp = useCallback(() => {
    const parts = currentPath.split('\\');
    if (parts.length > 1) {
      navigateTo(parts.slice(0, -1).join('\\'));
    }
  }, [currentPath, navigateTo]);

  const handleDoubleClick = (node: any) => {
    if (node.type === 'directory') {
      navigateTo(node.path);
    } else {
      // Open file with associated app
      const ext = node.extension;
      let targetAppId = '';
      let titlePrefix = `${node.name} - `;
      
      if (ext === 'exe') {
        const isApp = node.metadata?.type === 'app_executable' || (node.content && node.content.startsWith('{'));
        const isBinary = node.metadata?.type === 'binary_executable';

        if (isApp) {
          try {
            const manifest = JSON.parse(node.content);
            targetAppId = manifest.appId || 'notepad';
            titlePrefix = '';
          } catch (e) {
            kernel.log('WARN', 'Explorer', `Invalid executable manifest: ${node.name}`);
            return;
          }
        } else if (isBinary) {
          // Distinguish real system PE binaries from SDK (JS) executables.
          // makeSysExe content starts with "[name.obx]" — SDK code does not.
          const isSdkApp = node.content && !node.content.trimStart().startsWith('[');

          if (isSdkApp) {
            // SDK app: open with SdkAppRunner
            const pid = createProcess('sdk-app-runner', node.name, '⚡');
            openWindow({
              title: node.name,
              icon: '⚡',
              appId: 'sdk-app-runner',
              width: 600,
              height: 400,
              processId: pid,
              params: { binaryPath: node.path },
            });
            return;
          }

          // Real system binary (PE32+): run in Terminal
          const terminalApp = apps['terminal'];
          if (terminalApp) {
            const pid = createProcess(terminalApp.id, terminalApp.name, '💻');
            openWindow({
              title: `Executando ${node.name} - Terminal`,
              icon: '💻', appId: 'terminal',
              processId: pid,
              width: 700, height: 450,
              params: { command: node.path }
            });
            return;
          }
        } else {
           kernel.log('INFO', 'Explorer', `Cannot execute system driver or library: ${node.name}`);
           return;
        }
      } else {
        targetAppId = (ext === 'txt' || ext === 'ini' || ext === 'js' || ext === 'json') ? 'notepad' : 
                      (ext === 'html' || ext === 'htm') ? 'browser' :
                      (ext === 'webm' || ext === 'mp4') ? 'media-player' : '';
      }

      if (!targetAppId) {
        kernel.log('INFO', 'Explorer', `No application associated with .${ext} files.`);
        return;
      }

      const app = apps[targetAppId];
      if (app) {
        const pid = createProcess(app.id, app.name, app.icon);
        openWindow({
          title: `${titlePrefix}${app.name}`,
          icon: app.icon,
          appId: app.id,
          width: app.defaultWidth,
          height: app.defaultHeight,
          processId: pid,
          params: { filePath: node.path }
        });
      } else {
        kernel.log('ERROR', 'Explorer', `Application '${targetAppId}' not found in registry.`);
      }
    }
  };

  const getFileIcon = (node: any) => {
    if (node.type === 'directory') return '📁';
    const ext = node.extension;
    switch (ext) {
      case 'txt': return '📝';
      case 'js': return '📜';
      case 'html': return '🌐';
      case 'css': return '🎨';
      case 'json': return '📋';
      case 'ini': return '⚙️';
      case 'png': case 'jpg': case 'gif': return '🖼️';
      case 'mp3': case 'wav': return '🎵';
      case 'mp4': case 'avi': case 'webm': return '🎬';
      case 'exe': return '⚡';
      case 'obx': return '⚡';
      case 'osl': return '🔷';
      case 'zip': case 'rar': return '📦';
      default: return '📄';
    }
  };

  // ── Drag from FileExplorer to Desktop ─────────────────────────────────────
  const handleDragStart = useCallback((e: React.DragEvent, node: any) => {
    const icon = getFileIcon(node);
    // Determine appId for executables
    let appId = '';
    if (node.metadata?.type === 'app_executable' && node.content?.startsWith('{')) {
      try { appId = JSON.parse(node.content).appId || ''; } catch { /* ignore */ }
    } else if (node.metadata?.type === 'binary_executable') {
      appId = `sdk:${node.name}`;
    }

    const payload = JSON.stringify({
      path: node.path,
      name: node.name,
      icon,
      appId,
    });

    e.dataTransfer.setData('application/obsidianos-file', payload);
    e.dataTransfer.setData('text/plain', payload);
    e.dataTransfer.effectAllowed = 'copy';

    // Ghost image
    const ghost = document.createElement('div');
    ghost.style.cssText = 'position:fixed;top:-200px;left:-200px;background:rgba(99,102,241,0.2);border:1px solid rgba(99,102,241,0.6);border-radius:6px;padding:6px 10px;color:#fff;font-size:13px;white-space:nowrap;backdrop-filter:blur(4px);';
    ghost.textContent = `${icon} ${node.name}`;
    document.body.appendChild(ghost);
    e.dataTransfer.setDragImage(ghost, 0, 0);
    setTimeout(() => document.body.removeChild(ghost), 0);
  }, []);

  const pathParts = currentPath.split('\\').filter(Boolean);

  const quickAccess = [
    { name: 'Desktop', icon: '🖥️', path: `${userHome}\\Desktop` },
    { name: 'Documentos', icon: '📄', path: `${userHome}\\Documents` },
    { name: 'Downloads', icon: '⬇️', path: `${userHome}\\Downloads` },
    { name: 'Imagens', icon: '🖼️', path: `${userHome}\\Pictures` },
    { name: 'Música', icon: '🎵', path: `${userHome}\\Music` },
    { name: 'Vídeos', icon: '🎬', path: `${userHome}\\Videos` },
  ];

  const handleItemContextMenu = (e: React.MouseEvent, node: any) => {
    e.preventDefault();
    e.stopPropagation();
    setSelectedItems(prev => new Set([...prev, node.path]));
    openContextMenu(e.clientX, e.clientY, [
      { id: 'open', label: 'Abrir', icon: '📂', onClick: () => handleDoubleClick(node) },
      { id: 'sep1', label: '', separator: true },
      { id: 'cut', label: 'Recortar', icon: '✂️', onClick: () => {} },
      { id: 'copy', label: 'Copiar', icon: '📄', onClick: () => {} },
      { id: 'paste', label: 'Colar', disabled: true, icon: '📋', onClick: () => {} },
      { id: 'sep2', label: '', separator: true },
      { id: 'rename', label: 'Renomear', icon: '📝', onClick: () => {} },
      { id: 'delete', label: 'Excluir', icon: '🗑️', onClick: () => {
        if (confirm(`Tem certeza que deseja excluir ${node.name}?`)) {
          deleteNode(node.path);
        }
      }},
      { id: 'sep3', label: '', separator: true },
      { id: 'props', label: 'Propriedades', onClick: () => {} },
    ]);
  };

  const handleContentContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    openContextMenu(e.clientX, e.clientY, [
      { id: 'view', label: 'Exibir', children: [
        { id: 'details', label: 'Detalhes', onClick: () => setViewMode('details') },
        { id: 'grid', label: 'Ícones grandes', onClick: () => setViewMode('grid') },
      ]},
      { id: 'sort', label: 'Classificar por', children: [
        { id: 'name', label: 'Nome', onClick: () => {} },
        { id: 'size', label: 'Tamanho', onClick: () => {} },
      ]},
      { id: 'sep1', label: '', separator: true },
      { id: 'refresh', label: 'Atualizar', onClick: () => {} },
      { id: 'sep2', label: '', separator: true },
      { id: 'new', label: 'Novo', children: [
        { id: 'folder', label: 'Pasta', icon: '📁', onClick: () => {} },
        { id: 'txt', label: 'Documento de Texto', icon: '📄', onClick: () => {} },
      ]},
      { id: 'sep3', label: '', separator: true },
      { id: 'props', label: 'Propriedades', onClick: () => {} },
    ]);
  };

  return (
    <div className="file-explorer">
      {/* Toolbar */}
      <div className="explorer-toolbar">
        <div className="explorer-nav-buttons">
          <button className="explorer-nav-btn" onClick={goUp} title="Voltar">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><path d="M15 18l-6-6 6-6"/></svg>
          </button>
          <button className="explorer-nav-btn" title="Avançar">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><path d="M9 18l6-6-6-6"/></svg>
          </button>
          <button className="explorer-nav-btn" onClick={goUp} title="Pasta pai">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"><path d="M18 15l-6-6-6 6"/></svg>
          </button>
        </div>

        {/* Path Bar */}
        <div className="explorer-path-bar" onClick={() => setIsEditingPath(true)}>
          {isEditingPath ? (
            <input
              className="explorer-path-input"
              value={pathInput}
              onChange={(e) => setPathInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  navigateTo(pathInput);
                  setIsEditingPath(false);
                }
                if (e.key === 'Escape') {
                  setPathInput(currentPath);
                  setIsEditingPath(false);
                }
              }}
              onBlur={() => {
                setPathInput(currentPath);
                setIsEditingPath(false);
              }}
              autoFocus
            />
          ) : (
            <div className="explorer-breadcrumbs">
              {pathParts.map((part, i) => (
                <span key={i} className="breadcrumb-item">
                  <button
                    className="breadcrumb-btn"
                    onClick={(e) => {
                      e.stopPropagation();
                      navigateTo(pathParts.slice(0, i + 1).join('\\'));
                    }}
                  >
                    {part}
                  </button>
                  {i < pathParts.length - 1 && <span className="breadcrumb-sep">›</span>}
                </span>
              ))}
            </div>
          )}
        </div>

        {/* Search */}
        <div className="explorer-search">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="7"/><path d="M21 21l-4.35-4.35"/>
          </svg>
          <input type="text" placeholder="Pesquisar" className="explorer-search-input" />
        </div>
      </div>

      <div className="explorer-body">
        {/* Sidebar */}
        <div className="explorer-sidebar">
          <div className="sidebar-section">
            <div className="sidebar-title">Acesso Rápido</div>
            {quickAccess.map(item => (
              <button
                key={item.path}
                className={`sidebar-item ${currentPath === item.path ? 'active' : ''}`}
                onClick={() => navigateTo(item.path)}
              >
                <span>{item.icon}</span>
                <span>{item.name}</span>
              </button>
            ))}
          </div>
          <div className="sidebar-section">
            <div className="sidebar-title">Este Computador</div>
            <button className="sidebar-item" onClick={() => navigateTo('C:')}>
              <span>💻</span>
              <span>Disco Local (C:)</span>
            </button>
          </div>
        </div>

        {/* Main Content */}
        <div
          className="explorer-content"
          ref={el => { containerRef.current = el; }}
          onMouseDown={onMouseDown}
          onContextMenu={handleContentContextMenu}
        >
          {viewMode === 'details' ? (
            <table className="explorer-table">
              <thead>
                <tr>
                  <th>Nome</th>
                  <th>Data de modificação</th>
                  <th>Tipo</th>
                  <th>Tamanho</th>
                </tr>
              </thead>
              <tbody>
                {sortedChildren.map(node => (
                  <tr
                    key={node.path}
                    ref={el => { if (el) itemRefs.current.set(node.path, el); else itemRefs.current.delete(node.path); }}
                    className={`explorer-row ${selectedItems.has(node.path) ? 'selected' : ''}`}
                    draggable
                    onDragStart={(e) => handleDragStart(e, node)}
                    onClick={() => setSelectedItems(new Set([node.path]))}
                    onDoubleClick={() => handleDoubleClick(node)}
                    onContextMenu={(e) => handleItemContextMenu(e, node)}
                  >
                    <td>
                      <span className="file-item-icon">{getFileIcon(node)}</span>
                      {node.name}
                    </td>
                    <td>{new Date(node.modifiedAt).toLocaleString('pt-BR')}</td>
                    <td>{node.type === 'directory' ? 'Pasta de arquivos' : `Arquivo ${node.extension?.toUpperCase()}`}</td>
                    <td>{node.type === 'file' ? `${node.size} B` : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="explorer-grid">
              {sortedChildren.map(node => (
                <div
                  key={node.path}
                  ref={el => { if (el) itemRefs.current.set(node.path, el); else itemRefs.current.delete(node.path); }}
                  className={`explorer-grid-item ${selectedItems.has(node.path) ? 'selected' : ''}`}
                  draggable
                  onDragStart={(e) => handleDragStart(e, node)}
                  onClick={() => setSelectedItems(new Set([node.path]))}
                  onDoubleClick={() => handleDoubleClick(node)}
                  onContextMenu={(e) => handleItemContextMenu(e, node)}
                >
                  <span className="grid-item-icon">{getFileIcon(node)}</span>
                  <span className="grid-item-name">{node.name}</span>
                </div>
              ))}
            </div>
          )}

          {sortedChildren.length === 0 && (
            <div className="explorer-empty">
              Esta pasta está vazia.
            </div>
          )}

          {/* Rubber band selection box */}
          {selectionRect && (
            <div
              className="explorer-selection-box"
              style={{
                left: selectionRect.x,
                top: selectionRect.y,
                width: selectionRect.width,
                height: selectionRect.height,
              }}
            />
          )}
        </div>
      </div>

      {/* Status Bar */}
      <div className="explorer-statusbar">
        <span>{sortedChildren.length} itens</span>
        {selectedItems.size > 0 && <span>{selectedItems.size} {selectedItems.size === 1 ? 'item selecionado' : 'itens selecionados'}</span>}
        <div className="explorer-view-toggle">
          <button
            className={viewMode === 'details' ? 'active' : ''}
            onClick={() => setViewMode('details')}
            title="Detalhes"
          >≡</button>
          <button
            className={viewMode === 'grid' ? 'active' : ''}
            onClick={() => setViewMode('grid')}
            title="Grade"
          >⊞</button>
        </div>
      </div>
    </div>
  );
}
