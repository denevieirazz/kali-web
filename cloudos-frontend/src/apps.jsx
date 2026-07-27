import { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';
import { Wifi, Folder, FileCode, FileText, ChevronRight, Home, HardDrive, ArrowLeft, FolderPlus, Trash2, Pencil, FileArchive, Image as ImageIcon, File, Upload, LayoutGrid, List, ArrowUp, Clock, Star, Search, Usb, AlertTriangle, Shield, Eye, Key, Code2, Save, File as FileIcon } from 'lucide-react';
import Editor from '@monaco-editor/react';

const getAuthHeaders = (extraHeaders = {}) => {
  const token = localStorage.getItem('cloudos_token');
  return {
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    ...extraHeaders
  };
};

export const TerminalApp = () => {
  const termRef = useRef(null);

  useEffect(() => {
    if (!termRef.current) return;

    let term;
    let fit;
    let ws;
    let ro;
    let resizeTimeout;

    const initTimer = setTimeout(() => {
      if (!termRef.current) return;

      try {
        term = new Terminal({
          cursorBlink: true,
          fontSize: 14,
          fontFamily: 'Consolas, "Courier New", monospace',
          theme: { background: '#0a0a0a', foreground: '#e0e0e0', cursor: '#ffffff' }
        });
        
        fit = new FitAddon();
        term.loadAddon(fit);
        term.open(termRef.current);

        try { fit.fit(); } catch (e) {}
        if (term.textarea) term.textarea.focus();

        term.onResize(({ cols, rows }) => {
          if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'resize', cols, rows }));
          }
        });

        ro = new ResizeObserver(() => {
          clearTimeout(resizeTimeout);
          resizeTimeout = setTimeout(() => {
            try { if (term && term.element) fit.fit(); } catch (e) {}
          }, 100);
        });
        if (termRef.current) ro.observe(termRef.current);

        if (termRef.current) {
          termRef.current.addEventListener('mousedown', () => {
            if (term && term.textarea) term.textarea.focus();
          });
        }

        const token = localStorage.getItem('cloudos_token');
        ws = new WebSocket(`ws://localhost:8080?userId=user_001&token=${token}`);
        ws.binaryType = 'arraybuffer';

        ws.onopen = () => {
          if (term) term.write('\x1b[32mConectado ao CloudOS Kali Linux...\r\n\x1b[0m');
          try { fit.fit(); } catch(e) {}
        };

        ws.onmessage = (e) => {
          if (!term) return;
          if (e.data instanceof ArrayBuffer) term.write(new Uint8Array(e.data));
          else term.write(e.data);
        };

        ws.onerror = () => term && term.write('\r\n\x1b[31m[ERRO] Backend offline.\x1b[0m\r\n');
        ws.onclose = () => term && term.write('\r\n\x1b[33m[DESCONECTADO]\x1b[0m\r\n');

        term.onData((d) => {
          if (ws && ws.readyState === WebSocket.OPEN) ws.send(d);
        });
      } catch (err) {
        console.error("Erro ao inicializar terminal:", err);
      }
    }, 150);

    return () => {
      clearTimeout(initTimer);
      clearTimeout(resizeTimeout);
      if (ws) ws.close();
      if (term) term.dispose();
      if (ro) ro.disconnect();
    };
  }, []);

  return <div ref={termRef} style={{ height: '100%', width: '100%', padding: '5px', overflow: 'hidden', cursor: 'text' }} />;
};

export const NotepadApp = () => {
  const [text, setText] = useState('Bem-vindo ao CloudOS Notepad!\n\nSalvamento automático local.');
  return <textarea className="notepad-area" value={text} onChange={(e) => setText(e.target.value)}></textarea>;
};

export const SettingsApp = ({ setBg }) => {
  const [tab, setTab] = useState('appearance');
  const [devices, setDevices] = useState([]);
  const [loadingDev, setLoadingDev] = useState(false);
  const [errorDev, setErrorDev] = useState('');
  const [anonStatus, setAnonStatus] = useState('');
  const [osintKeys, setOsintKeys] = useState({ shodan: '', hunterio: '', virustotal: '' });

  const fetchDevices = () => {
    setLoadingDev(true);
    fetch('http://localhost:8080/api/devices', { headers: getAuthHeaders() })
      .then(res => res.json())
      .then(data => { if (data.error) setErrorDev(data.error); else setDevices(data.devices || []); })
      .catch(() => setErrorDev('Erro de conexão.'))
      .finally(() => setLoadingDev(false));
  };

  useEffect(() => { if (tab === 'hardware') fetchDevices(); }, [tab]);

  const handleAttach = (busid, name) => {
    if (window.confirm(`Conectar "${name}" ao Kali Linux?`)) {
      fetch('http://localhost:8080/api/devices/attach', { method: 'POST', headers: getAuthHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ busid }) })
        .then(res => res.json()).then(data => { if (data.error) alert(data.error); else { alert('Conectado!'); fetchDevices(); } });
    }
  };

  const handleAnon = (action) => {
    setAnonStatus('Processando...');
    fetch('http://localhost:8080/api/tactical/anon', { method: 'POST', headers: getAuthHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ action }) })
      .then(res => res.json()).then(data => {
        if (data.error) { setAnonStatus(`Erro: ${data.error}`); alert(data.error); }
        else { setAnonStatus(action === 'tor_on' ? 'Tor Ativado! Use proxychains no terminal.' : 'Comando executado com sucesso.'); }
      });
  };

  const saveOsintKeys = () => {
    fetch('http://localhost:8080/api/tactical/osint', { method: 'POST', headers: getAuthHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ keys: osintKeys }) })
      .then(() => alert('Chaves de OSINT salvas no Kali Linux!'));
  };

  return (
    <div className="settings-container">
      <h2>Centro de Controle Tático</h2>
      
      <div className="settings-tabs">
        <div className={`settings-tab ${tab === 'appearance' ? 'active' : ''}`} onClick={() => setTab('appearance')}><ImageIcon size={16} /> Aparência</div>
        <div className={`settings-tab ${tab === 'anon' ? 'active' : ''}`} onClick={() => setTab('anon')}><Shield size={16} /> Anonimato</div>
        <div className={`settings-tab ${tab === 'osint' ? 'active' : ''}`} onClick={() => setTab('osint')}><Eye size={16} /> OSINT APIs</div>
        <div className={`settings-tab ${tab === 'hardware' ? 'active' : ''}`} onClick={() => setTab('hardware')}><Usb size={16} /> Hardware</div>
      </div>

      {/* ABA APARÊNCIA */}
      {tab === 'appearance' && (
        <div className="settings-content">
          <h3>Papel de Parede</h3>
          <div style={{ display: 'flex', gap: '10px' }}>
            <div onClick={() => setBg('https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
            <div onClick={() => setBg('https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
            <div onClick={() => setBg('linear-gradient(135deg, #0f0c29, #302b63, #24243e)')} style={{ width: 80, height: 50, background: 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)', borderRadius: 4, cursor: 'pointer' }}></div>
          </div>
        </div>
      )}

      {/* ABA ANONIMATO (OpSec) */}
      {tab === 'anon' && (
        <div className="settings-content">
          <h3>Operational Security (OpSec)</h3>
          <p style={{ fontSize: '12px', color: '#888', marginBottom: '15px' }}>Configure o roteamento de tráfego e mascaramento de rede.</p>
          
          <div className="tactical-card">
            <div className="tactical-info"><Shield size={20} color="#a78bfa" /><div><div className="device-name">Roteamento Tor (Proxychains)</div><div className="device-id">Força todo o tráfego do terminal pela rede Onion.</div></div></div>
            <button className="device-btn" onClick={() => handleAnon('tor_on')}>Ativar</button>
          </div>
          <div className="tactical-card">
            <div className="tactical-info"><Shield size={20} color="#f87171" /><div><div className="device-name">Desligar Tor</div><div className="device-id">Restaura a conexão padrão do WSL.</div></div></div>
            <button className="device-btn-danger" onClick={() => handleAnon('tor_off')}>Desativar</button>
          </div>
          <div className="tactical-card">
            <div className="tactical-info"><Wifi size={20} color="#4ade80" /><div><div className="device-name">Spoofar Endereço MAC</div><div className="device-id">Gera um MAC aleatório para a interface de rede.</div></div></div>
            <button className="device-btn" onClick={() => handleAnon('mac_spoof')}>Spoofar</button>
          </div>

          {anonStatus && <div style={{ marginTop: '15px', fontSize: '12px', color: '#60a5fa' }}>{anonStatus}</div>}
        </div>
      )}

      {/* ABA OSINT */}
      {tab === 'osint' && (
        <div className="settings-content">
          <h3>Chaves de API de Inteligência</h3>
          <p style={{ fontSize: '12px', color: '#888', marginBottom: '15px' }}>Salve suas chaves de forma segura no sistema de arquivos do Kali. As ferramentas internas usarão estas chaves.</p>
          
          <div className="osint-input-group">
            <label>Shodan API Key</label>
            <input type="text" value={osintKeys.shodan} onChange={(e) => setOsintKeys({...osintKeys, shodan: e.target.value})} placeholder="SH-XXXXXXX..." />
          </div>
          <div className="osint-input-group">
            <label>Hunter.io API Key</label>
            <input type="text" value={osintKeys.hunterio} onChange={(e) => setOsintKeys({...osintKeys, hunterio: e.target.value})} placeholder="XXXXXXX..." />
          </div>
          <div className="osint-input-group">
            <label>VirusTotal API Key</label>
            <input type="text" value={osintKeys.virustotal} onChange={(e) => setOsintKeys({...osintKeys, virustotal: e.target.value})} placeholder="XXXXXXX..." />
          </div>
          
          <button className="device-btn" style={{ marginTop: '10px', width: '100%' }} onClick={saveOsintKeys}>Salvar Chaves no Kali</button>
        </div>
      )}

      {/* ABA HARDWARE */}
      {tab === 'hardware' && (
        <div className="settings-content">
          <h3>Pass-through de Dispositivos (USB)</h3>
          {errorDev && <div style={{ color: '#f87171', fontSize: '12px' }}>{errorDev}</div>}
          {loadingDev ? <div className="settings-loading">Procurando...</div> : (
            <div className="device-list">
              {devices.map((dev, i) => (
                <div key={i} className={`device-card ${dev.state === 'Attached' ? 'attached' : ''}`}>
                  <div className="device-info"><Usb size={20} color={dev.state === 'Attached' ? '#4ade80' : '#94a3b8'} /><div><div className="device-name">{dev.name}</div><div className="device-id">BUSID: {dev.busid}</div></div></div>
                  {dev.state !== 'Attached' && <button className="device-btn" onClick={() => handleAttach(dev.busid, dev.name)}>Plugar</button>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export const CodeEditorApp = ({ fileToOpen }) => {
  const [currentFile, setCurrentFile] = useState(null);
  const [content, setContent] = useState('');
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState(true);

  const openFile = (filePath) => {
    if (!filePath) return;
    setLoading(true);
    setSaved(true);
    fetch(`http://localhost:8080/api/files/read?path=${encodeURIComponent(filePath)}`, { headers: getAuthHeaders() })
      .then(res => res.json())
      .then(data => {
        if (data.error) { alert(data.error); return; }
        setCurrentFile(filePath);
        setContent(data.content || '');
      })
      .catch(() => alert('Erro de conexão ao carregar arquivo.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (fileToOpen) {
      openFile(fileToOpen);
    }
  }, [fileToOpen]);

  const saveFile = () => {
    if (!currentFile) return;
    setLoading(true);
    fetch('http://localhost:8080/api/files/save', {
      method: 'POST',
      headers: getAuthHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ path: currentFile, content })
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) alert(data.error);
        else setSaved(true);
      })
      .catch(() => alert('Erro de conexão ao salvar arquivo.'))
      .finally(() => setLoading(false));
  };

  const handleEditorChange = (value) => {
    setContent(value || '');
    setSaved(false);
  };

  return (
    <div className="code-editor-app">
      <div className="ce-toolbar">
        <div className="ce-tab">
          <FileIcon size={14} />
          {currentFile ? currentFile.split('/').pop() : 'Nenhum arquivo'}
          {!saved && <span className="ce-dot">*</span>}
        </div>
        <button className="ce-btn" onClick={saveFile} disabled={!currentFile || saved || loading}>
          <Save size={14} /> {loading ? 'Salvando...' : 'Salvar (Ctrl+S)'}
        </button>
      </div>
      
      <div className="ce-main">
        {currentFile ? (
          <Editor
            height="100%"
            theme="vs-dark"
            language={currentFile.split('.').pop() === 'sh' ? 'shell' : (currentFile.split('.').pop() === 'py' ? 'python' : (currentFile.split('.').pop() === 'js' ? 'javascript' : 'plaintext'))}
            value={content}
            onChange={handleEditorChange}
            onMount={(editor, monaco) => {
              editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, saveFile);
            }}
          />
        ) : (
          <div className="ce-empty">
            <Code2 size={48} color="#3b82f6" />
            <p>Nenhum arquivo aberto.</p>
            <span>Use o Gerenciador de Arquivos e clique em "Editar Código" para abrir um arquivo aqui.</span>
          </div>
        )}
      </div>
    </div>
  );
};

export const FileManagerApp = () => {
  const [path, setPath] = useState('/root');
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState([]);
  const [view, setView] = useState('grid');
  const [contextMenu, setContextMenu] = useState({ visible: false, x: 0, y: 0, item: null });
  const [search, setSearch] = useState('');
  const fileInputRef = useRef(null);

  const fetchFiles = (newPath) => {
    setLoading(true);
    setPath(newPath);
    setSelected([]);
    fetch(`http://localhost:8080/api/files?path=${encodeURIComponent(newPath)}`, { headers: getAuthHeaders() })
      .then(res => res.json())
      .then(data => {
          let fetchedItems = data.items || [];
          fetchedItems.sort((a, b) => {
              if (a.type !== b.type) return a.type === 'folder' ? -1 : 1;
              return a.name.localeCompare(b.name);
          });
          setItems(fetchedItems);
          setLoading(false);
      })
      .catch(() => setLoading(false));
  };

  useEffect(() => { fetchFiles('/root'); }, []);

  const goBack = () => {
    const parts = path.split('/').filter(Boolean);
    if (parts.length > 0) { parts.pop(); fetchFiles('/' + parts.join('/')); }
  };
  
  const goUp = () => goBack();

  const handleAction = (action, item = null) => {
    setContextMenu({ ...contextMenu, visible: false });

    let targets = item ? [item.path] : selected;
    if (targets.length === 0 && action !== 'mkdir') return;

    let name = '';
    let newPathStr = '';

    if (action === 'mkdir') {
        name = prompt('Nome da nova pasta:');
        if (!name) return;
    }
    if (action === 'rename') {
        name = prompt('Novo nome:', item ? item.name : '');
        if (!name) return;
        newPathStr = path + '/' + name;
    }

    fetch('http://localhost:8080/api/files/action', {
        method: 'POST',
        headers: getAuthHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify({ 
            action, 
            paths: targets, 
            path: targets[0], 
            name, 
            newPath: newPathStr,
            currentPath: path
        })
    }).then(() => fetchFiles(path));
  };

  const handleUploadClick = () => {
    setContextMenu({ ...contextMenu, visible: false });
    fileInputRef.current.click();
  };

  const handleFileUpload = (e) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    const formData = new FormData();
    for (let i = 0; i < files.length; i++) formData.append('files', files[i]);
    formData.append('path', path);

    fetch('http://localhost:8080/api/files/upload', { method: 'POST', headers: getAuthHeaders(), body: formData })
      .then(() => fetchFiles(path));
  };

  // 🚨 LÓGICA DE POSICIONAMENTO PERFEITA
  const handleContextMenu = (e, item = null) => {
    e.preventDefault();
    e.stopPropagation();
    
    const menuWidth = 180;
    const menuHeight = item ? 120 : 80;
    
    let x = e.clientX;
    let y = e.clientY;
    
    // Ajusta se sair da tela
    if (x + menuWidth > window.innerWidth) x = window.innerWidth - menuWidth - 10;
    if (y + menuHeight > window.innerHeight) y = window.innerHeight - menuHeight - 10;
    
    x = Math.max(10, x);
    y = Math.max(10, y);

    if (item && !selected.includes(item.path)) {
        setSelected([item.path]);
    } else if (!item) {
        setSelected([]);
    }
    setContextMenu({ visible: true, x, y, item });
  };

  const handleItemClick = (e, item) => {
      e.stopPropagation();
      if (e.ctrlKey || e.metaKey) {
          setSelected(prev => prev.includes(item.path) ? prev.filter(p => p !== item.path) : [...prev, item.path]);
      } else {
          setSelected([item.path]);
      }
  };

  const getIcon = (item) => {
    if (item.type === 'folder') return <Folder size={view === 'grid' ? 48 : 18} color="#60a5fa" fill="#3b82f6" />;
    const ext = item.name.split('.').pop().toLowerCase();
    if (['jpg', 'png', 'jpeg', 'gif'].includes(ext)) return <ImageIcon size={view === 'grid' ? 48 : 18} color="#a78bfa" />;
    if (['sh', 'py', 'js', 'c', 'cpp'].includes(ext)) return <FileCode size={view === 'grid' ? 48 : 18} color="#4ade80" />;
    if (['zip', 'tar', 'gz'].includes(ext)) return <FileArchive size={view === 'grid' ? 48 : 18} color="#fbbf24" />;
    return <File size={view === 'grid' ? 48 : 18} color="#94a3b8" />;
  };

  const pathParts = path.split('/').filter(Boolean);
  const filteredItems = items.filter(item => item.name.toLowerCase().includes(search.toLowerCase()));

  return (
    <div className="file-manager-pro" onClick={() => contextMenu.visible && setContextMenu({ ...contextMenu, visible: false })}>
      <input type="file" multiple ref={fileInputRef} style={{ display: 'none' }} onChange={handleFileUpload} />
      
      {/* SIDEBAR */}
      <div className="fmp-sidebar">
        <div className="fmp-sidebar-section">
          <div className="fmp-sidebar-title">Quick Access</div>
          <div className={`fmp-sidebar-item ${path === '/root' ? 'active' : ''}`} onClick={() => fetchFiles('/root')}><Home size={16} /> Início</div>
          <div className="fmp-sidebar-item"><Clock size={16} /> Recentes</div>
          <div className="fmp-sidebar-item"><Star size={16} /> Favoritos</div>
        </div>
        <div className="fmp-sidebar-section">
          <div className="fmp-sidebar-title">Locais</div>
          <div className={`fmp-sidebar-item ${path === '/root' ? 'active' : ''}`} onClick={() => fetchFiles('/root')}><HardDrive size={16} /> Kali Linux</div>
          <div className="fmp-sidebar-item" onClick={() => fetchFiles('/usr/share/wordlists')}><FileText size={16} /> Wordlists</div>
          <div className="fmp-sidebar-item" onClick={() => fetchFiles('/root/.trash')}><Trash2 size={16} /> Lixeira</div>
        </div>
      </div>

      {/* ÁREA PRINCIPAL */}
      <div className="fmp-main">
        {/* TOOLBAR */}
        <div className="fmp-toolbar">
          <button className="fmp-btn-icon" onClick={goBack} title="Voltar"><ArrowLeft size={16} /></button>
          <button className="fmp-btn-icon" onClick={goUp} title="Subir nível"><ArrowUp size={16} /></button>
          
          <div className="fmp-breadcrumb">
            <span onClick={() => fetchFiles('/root')}>root</span>
            {pathParts.map((p, i) => (
              <span key={i} className="fmp-crumb">
                <ChevronRight size={14} />
                <span onClick={() => fetchFiles('/' + pathParts.slice(0, i + 1).join('/'))}>{p}</span>
              </span>
            ))}
          </div>

          <div className="fmp-search">
            <Search size={14} />
            <input placeholder="Buscar..." value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>

          <button className="fmp-btn-icon" onClick={() => setView(view === 'grid' ? 'list' : 'grid')}>
            {view === 'grid' ? <List size={16} /> : <LayoutGrid size={16} />}
          </button>
        </div>

        {/* ACTION BAR */}
        <div className="fmp-action-bar">
          <button className="fmp-btn" onClick={() => handleAction('mkdir')}><FolderPlus size={14} /> Nova Pasta</button>
          <button className="fmp-btn" onClick={handleUploadClick}><Upload size={14} /> Upload</button>
          {selected.length > 0 && (
            <button className="fmp-btn-danger" onClick={() => handleAction('delete')}>
              <Trash2 size={14} /> Deletar ({selected.length})
            </button>
          )}
        </div>

        {/* CONTEÚDO */}
        <div className={`fmp-content ${view === 'list' ? 'list-view' : 'grid-view'}`} onContextMenu={(e) => handleContextMenu(e)}>
          {loading ? (
            <div className="fmp-loading">Lendo estrutura de diretórios...</div>
          ) : filteredItems.length === 0 ? (
            <div className="fmp-empty">Pasta vazia. Arraste arquivos ou clique em Upload.</div>
          ) : view === 'grid' ? (
            filteredItems.map((item, i) => (
              <div 
                key={i} 
                className={`fmp-item-grid ${selected.includes(item.path) ? 'selected' : ''}`}
                onClick={(e) => handleItemClick(e, item)}
                onDoubleClick={() => item.type === 'folder' && fetchFiles(item.path)}
                onContextMenu={(e) => handleContextMenu(e, item)}
              >
                {getIcon(item)}
                <span>{item.name}</span>
              </div>
            ))
          ) : (
            <div className="fmp-list-wrapper">
              {filteredItems.map((item, i) => (
                <div 
                  key={i} 
                  className={`fmp-item-list ${selected.includes(item.path) ? 'selected' : ''}`}
                  onClick={(e) => handleItemClick(e, item)}
                  onDoubleClick={() => item.type === 'folder' && fetchFiles(item.path)}
                  onContextMenu={(e) => handleContextMenu(e, item)}
                >
                  {getIcon(item)}
                  <span className="fmp-name">{item.name}</span>
                  <span className="fmp-type">{item.type === 'folder' ? 'Pasta' : 'Arquivo'}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* STATUS BAR */}
        <div className="fmp-statusbar">
          <span>{filteredItems.length} itens</span>
          {selected.length > 0 && <span> | {selected.length} selecionado(s)</span>}
          <span className="fmp-spacer"></span>
          <span>WSL Kali Linux</span>
        </div>
      </div>

      {/* 🚨 REACT PORTAL: Teletransporta o menu para fora da janela arrastável */}
      {contextMenu.visible && createPortal(
        <div 
            className="fmp-context-menu" 
            style={{ position: 'fixed', top: contextMenu.y, left: contextMenu.x, zIndex: 999999 }}
            onClick={(e) => e.stopPropagation()}
        >
          {contextMenu.item ? (
            <>
              <div className="fmp-ctx-item" onClick={() => { contextMenu.item.type === 'folder' && fetchFiles(contextMenu.item.path); setContextMenu({...contextMenu, visible: false}); }}>Abrir</div>
              {contextMenu.item.type === 'file' && (
                <div className="fmp-ctx-item" onClick={() => { 
                  window.dispatchEvent(new CustomEvent('openCodeEditor', { detail: { path: contextMenu.item.path } })); 
                  setContextMenu({...contextMenu, visible: false});
                }}>
                  <Code2 size={14} /> Editar Código
                </div>
              )}
              <div className="fmp-ctx-item" onClick={() => handleAction('rename', contextMenu.item)}><Pencil size={14} /> Renomear</div>
              <div className="fmp-ctx-divider"></div>
              <div className="fmp-ctx-item danger" onClick={() => handleAction('delete', contextMenu.item)}><Trash2 size={14} /> Mover para Lixeira</div>
            </>
          ) : (
            <>
              <div className="fmp-ctx-item" onClick={() => handleAction('mkdir')}><FolderPlus size={14} /> Nova Pasta</div>
              <div className="fmp-ctx-item" onClick={handleUploadClick}><Upload size={14} /> Upload aqui</div>
            </>
          )}
        </div>,
        document.body
      )}
    </div>
  );
};
