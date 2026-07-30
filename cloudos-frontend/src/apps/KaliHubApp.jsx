import { useState, useEffect, useCallback } from 'react';
import {
  Search, RefreshCw, Star, Terminal, Cpu, AlertTriangle, X,
  CheckCircle, XCircle, Activity, Shield, ShieldAlert, ShieldX, Download
} from 'lucide-react';
import './KaliHubApp.css';

const API_BASE = 'http://localhost:8080';

const CATEGORIES = [
  { id: 'all', name: 'Todas', icon: Search },
  { id: 'favorites', name: 'Favoritas', icon: Star },
  { id: 'recent', name: 'Recentes', icon: Activity },
  { id: 'installed', name: 'Instaladas', icon: CheckCircle },
  { id: 'missing', name: 'Faltando', icon: XCircle },
  { id: 'recon', name: 'Recon', icon: Search },
  { id: 'web', name: 'Web', icon: Terminal },
  { id: 'exploitation', name: 'Exploitation', icon: Cpu },
  { id: 'cracking', name: 'Cracking', icon: Cpu },
  { id: 'wireless', name: 'Wireless', icon: Cpu },
];

const RISK_META = {
  safe: { label: 'Safe', cls: 'kali-risk-safe', icon: Shield },
  medium: { label: 'Caution', cls: 'kali-risk-medium', icon: ShieldAlert },
  restricted: { label: 'Restricted', cls: 'kali-risk-restricted', icon: ShieldX },
};

export function KaliHubApp({ payload, setPayload, openApp }) {
  const [tools, setTools] = useState([]);
  const [statuses, setStatuses] = useState({});
  const [favorites, setFavorites] = useState([]);
  const [recent, setRecent] = useState([]);
  const [activeCat, setActiveCat] = useState('all');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [selectedTool, setSelectedTool] = useState(null);

  const token = () => localStorage.getItem('cloudos_token');
  const headers = { 'Authorization': `Bearer ${token()}` };

  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const [toolsRes, favRes, recentRes] = await Promise.all([
        fetch(`${API_BASE}/api/kali/tools`, { headers }),
        fetch(`${API_BASE}/api/kali/tools/favorites`, { headers }),
        fetch(`${API_BASE}/api/kali/tools/recent`, { headers })
      ]);

      if (toolsRes.ok) setTools(await toolsRes.json());
      if (favRes.ok) setFavorites((await favRes.json()).map(t => t.id || t.tool_id));
      if (recentRes.ok) setRecent((await recentRes.json()).map(t => t.id || t.tool_id));
    } catch (e) {
      console.error("Erro ao carregar catálogo:", e);
    } finally {
      setLoading(false);
    }
  }, []);

  const refreshStatus = useCallback(async () => {
    setStatuses(prev => {
      const next = { ...prev };
      tools.forEach(t => { if (!next[t.id]) next[t.id] = 'checking'; });
      return next;
    });

    try {
      const res = await fetch(`${API_BASE}/api/kali/tools/status`, { headers });
      if (res.ok) setStatuses(await res.json());
    } catch (e) {
      console.error("Erro ao checar status:", e);
    }
  }, [tools]);

  useEffect(() => { fetchAll(); }, [fetchAll]);
  useEffect(() => { if (tools.length > 0) refreshStatus(); }, [tools, refreshStatus]);

  const filteredTools = tools.filter(t => {
    const q = search.toLowerCase();
    const matchSearch = !q || 
      t.name?.toLowerCase().includes(q) ||
      t.description?.toLowerCase().includes(q) ||
      t.command?.toLowerCase().includes(q) ||
      t.tags?.some(tag => tag.toLowerCase().includes(q));

    const matchCat = 
      activeCat === 'all' ? true :
      activeCat === 'favorites' ? favorites.includes(t.id) :
      activeCat === 'recent' ? recent.includes(t.id) :
      activeCat === 'installed' ? statuses[t.id] === 'installed' :
      activeCat === 'missing' ? statuses[t.id] === 'missing' :
      t.category === activeCat;

    return matchSearch && matchCat;
  });

  const handleSafeOpen = (tool, useGui = false) => {
    if (tool.riskLevel === 'restricted') {
      setSelectedTool(tool); // Força abrir o painel de detalhes
      return;
    }
    handleOpen(tool, useGui);
  };

  const handleOpen = async (tool, useGui = false) => {
    try {
      const res = await fetch(`${API_BASE}/api/kali/tools/${tool.id}/open`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers }
      });

      if (!res.ok) throw new Error('Falha ao preparar ferramenta no backend.');

      // Registra como recente
      setRecent(prev => [tool.id, ...prev.filter(id => id !== tool.id)].slice(0, 5));

      if (useGui) {
        openApp?.('toolrunner', { toolId: tool.id });
      } else {
        openApp?.('terminal', {
          tool: tool.command,
          initialText: `${tool.command} --help\n` // Segurança: não executa automático
        });
      }
      setSelectedTool(null);
    } catch (e) {
      console.error(e);
      alert(`Erro: ${e.message}`);
    }
  };

  const toggleFavorite = async (toolId) => {
    const isFav = favorites.includes(toolId);
    setFavorites(prev => isFav ? prev.filter(id => id !== toolId) : [...prev, toolId]); // Otimismo UI
    
    try {
      await fetch(`${API_BASE}/api/kali/tools/${toolId}/favorite`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: JSON.stringify({ isFavorite: !isFav })
      });
    } catch (e) {
      // Reverte se falhar
      setFavorites(prev => isFav ? [...prev, toolId] : prev.filter(id => id !== toolId));
    }
  };

  const handleInstall = async (tool) => {
    if (!confirm(`Instalar ${tool.name} no WSL/Kali? Isso pode levar alguns minutos.`)) return;
    setStatuses(prev => ({ ...prev, [tool.id]: 'checking' }));
    
    try {
      const res = await fetch(`${API_BASE}/api/kali/tools/${tool.id}/install`, {
        method: 'POST',
        headers
      });
      if (!res.ok) throw new Error('Falha na instalação');
      refreshStatus();
    } catch (e) {
      alert(`Erro: ${e.message}`);
      refreshStatus();
    }
  };

  const statusMeta = {
    installed: { cls: 'kali-status-installed', txt: 'Instalado' },
    missing: { cls: 'kali-status-missing', txt: 'Não Instalado' },
    checking: { cls: 'kali-status-checking', txt: 'Verificando...' }
  };

  return (
    <div className="kali-hub">
      {/* SIDEBAR */}
      <aside className="kali-sidebar">
        <div className="kali-sidebar-header">Categorias</div>
        <div className="kali-cat-list">
          {CATEGORIES.map(cat => {
            const Icon = cat.icon;
            const count = cat.id === 'all' ? tools.length : 
                          cat.id === 'favorites' ? favorites.length :
                          cat.id === 'recent' ? recent.length :
                          cat.id === 'installed' ? Object.values(statuses).filter(s => s === 'installed').length :
                          cat.id === 'missing' ? Object.values(statuses).filter(s => s === 'missing').length :
                          tools.filter(t => t.category === cat.id).length;
            
            return (
              <button 
                key={cat.id} 
                className={`kali-cat-btn ${activeCat === cat.id ? 'active' : ''}`}
                onClick={() => setActiveCat(cat.id)}
              >
                <Icon size={14} /> {cat.name}
                <span className="kali-cat-count">{count}</span>
              </button>
            );
          })}
        </div>
      </aside>

      {/* MAIN AREA */}
      <main className="kali-main">
        <div className="kali-topbar">
          <div style={{ position: 'relative', flex: 1 }}>
            <Search size={14} style={{ position: 'absolute', left: 12, top: 10, color: '#8b949e' }} />
            <input 
              className="kali-search" 
              style={{ paddingLeft: 32 }}
              placeholder="Buscar por nome, tag, comando..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <button className="kali-btn-icon" onClick={refreshStatus} title="Atualizar Status WSL">
            <RefreshCw size={14} />
          </button>
        </div>

        <div className="kali-grid">
          {loading ? (
            Array.from({ length: 6 }).map((_, i) => <div key={i} className="kali-skeleton" />)
          ) : filteredTools.length === 0 ? (
            <div className="kali-empty">Nenhuma ferramenta encontrada.</div>
          ) : (
            filteredTools.map(tool => {
              const status = statuses[tool.id] || 'checking';
              const risk = RISK_META[tool.riskLevel || 'safe'];
              const RiskIcon = risk.icon;
              const isFav = favorites.includes(tool.id);

              return (
                <div key={tool.id} className="kali-card">
                  <div className="kali-card-header">
                    <span className="kali-card-title">{tool.name}</span>
                    <button className={`kali-fav-btn ${isFav ? 'active' : ''}`} onClick={() => toggleFavorite(tool.id)}>
                      <Star size={14} fill={isFav ? '#d29922' : 'none'} />
                    </button>
                  </div>
                  <div className="kali-card-desc">{tool.description}</div>
                  
                  <div className="kali-card-footer">
                    <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                      <span className={`kali-badge ${statusMeta[status].cls}`}>{statusMeta[status].txt}</span>
                      <span className={`kali-badge ${risk.cls}`} style={{display: 'flex', alignItems: 'center', gap: 4}}>
                        <RiskIcon size={10} /> {risk.label}
                      </span>
                    </div>
                    
                    {status === 'missing' ? (
                      <button className="kali-action-btn install" onClick={() => handleInstall(tool)}>
                        <Download size={12} style={{marginRight: 4}} /> Instalar
                      </button>
                    ) : (
                      <div style={{ display: 'flex', gap: 4 }}>
                        <button className="kali-action-btn" onClick={() => handleSafeOpen(tool, false)} title="Abrir no Terminal">
                          <Terminal size={12} />
                        </button>
                        <button className="kali-action-btn gui" onClick={() => handleSafeOpen(tool, true)} title="Abrir na GUI">
                          <Cpu size={12} />
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>

        <div className="kali-statusbar">
          <span className="kali-status-item"><Activity size={12} /> {filteredTools.length} ferramentas</span>
          <span className="kali-status-item">Categoria: {CATEGORIES.find(c => c.id === activeCat)?.name}</span>
          <span className="kali-status-item" style={{ color: '#3fb950' }}>Instaladas: {Object.values(statuses).filter(s => s === 'installed').length}</span>
          <span className="kali-status-item" style={{ color: '#f85149' }}>Faltando: {Object.values(statuses).filter(s => s === 'missing').length}</span>
          <span className="kali-status-item" style={{ marginLeft: 'auto', color: '#58a6ff' }}>WSL: Connected</span>
        </div>
      </main>

      {/* DETAILS PANEL */}
      {selectedTool && (
        <aside className="kali-details-panel">
          <div className="kali-details-header">
            <h3 style={{ margin: 0, fontSize: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
              <AlertTriangle size={16} color="#f85149" /> {selectedTool.name}
            </h3>
            <button className="kali-btn-icon" onClick={() => setSelectedTool(null)}>
              <X size={14} />
            </button>
          </div>
          
          <div className="kali-details-body">
            <div className="kali-details-section">
              <h4>Descrição</h4>
              <p>{selectedTool.description}</p>
            </div>

            {selectedTool.riskLevel === 'restricted' && (
              <div className="kali-warning-box">
                <strong>Atenção:</strong> Esta ferramenta possui risco elevado e pode causar danos ao alvo se usada incorretamente. Confirme abaixo se você tem autorização explícita para usá-la no escopo do projeto.
              </div>
            )}

            <div className="kali-details-section">
              <h4>Parâmetros Base</h4>
              <code style={{ background: '#161b22', padding: 8, borderRadius: 6, display: 'block', color: '#58a6ff', fontSize: 12 }}>
                {selectedTool.command} {selectedTool.baseArgs || ''}
              </code>
            </div>

            <div style={{ marginTop: 'auto', display: 'flex', gap: 8 }}>
              <button 
                className="kali-action-btn" 
                style={{ flex: 1, justifyContent: 'center' }}
                onClick={() => handleOpen(selectedTool, false)}
              >
                <Terminal size={14} style={{marginRight: 6}} /> Terminal
              </button>
              <button 
                className="kali-action-btn gui" 
                style={{ flex: 1, justifyContent: 'center' }}
                onClick={() => handleOpen(selectedTool, true)}
              >
                <Cpu size={14} style={{marginRight: 6}} /> GUI
              </button>
            </div>
          </div>
        </aside>
      )}
    </div>
  );
}

export default KaliHubApp;
