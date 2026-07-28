import { useState, useEffect } from 'react';
import { Search, Star, Activity, Bug, Database, Rocket, KeyRound, Hash, Wifi, Eye, FolderSearch, Terminal as TermIcon, AlertTriangle, CheckCircle, XCircle, Loader, ShieldAlert, LayoutGrid } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

const iconMap = { Radar: Search, Activity: Activity, Bug: Bug, Database: Database, Rocket: Rocket, KeyRound: KeyRound, Hash: Hash, Wifi: Wifi, Eye: Eye, FolderSearch: FolderSearch };

const categories = [
    { id: 'all', name: 'All Tools', icon: Search, color: '#58a6ff' },
    { id: 'favorites', name: 'Favorites', icon: Star, color: '#facc15' },
    { id: 'recon', name: 'Reconnaissance', icon: Search, color: '#58a6ff' },
    { id: 'web', name: 'Web Analysis', icon: Bug, color: '#a78bfa' },
    { id: 'vuln', name: 'Vulnerability', icon: ShieldAlert, color: '#f97316' },
    { id: 'password', name: 'Password Audit', icon: KeyRound, color: '#ef4444' },
    { id: 'wireless', name: 'Wireless', icon: Wifi, color: '#10b981' },
    { id: 'network', name: 'Network', icon: Activity, color: '#06b6d4' }
];

export const KaliHubApp = ({ openApp }) => {
  const [tools, setTools] = useState([]);
  const [statuses, setStatuses] = useState({});
  const [favorites, setFavorites] = useState([]);
  const [activeCat, setActiveCat] = useState('all');
  const [search, setSearch] = useState('');
  const [selectedTool, setSelectedTool] = useState(null);
  const [loadingStatus, setLoadingStatus] = useState(true);

  useEffect(() => {
    fetch(`${API_BASE}/api/kali/tools`, { headers: { 'Authorization': `Bearer ${token()}` } })
      .then(res => res.json()).then(data => setTools(Array.isArray(data) ? data : [])).catch(console.error);
    
    fetch(`${API_BASE}/api/kali/tools/favorites`, { headers: { 'Authorization': `Bearer ${token()}` } })
      .then(res => res.json()).then(data => setFavorites(Array.isArray(data) ? data : [])).catch(console.error);

    fetch(`${API_BASE}/api/kali/tools/status`, { headers: { 'Authorization': `Bearer ${token()}` } })
      .then(res => res.json()).then(data => { setStatuses(data || {}); setLoadingStatus(false); }).catch(() => setLoadingStatus(false));
  }, []);

  const handleFavorite = async (toolId) => {
    try {
      const res = await fetch(`${API_BASE}/api/kali/tools/${toolId}/favorite`, {
        method: 'POST', headers: { 'Authorization': `Bearer ${token()}` }
      });
      const data = await res.json();
      if (data.isFavorite) setFavorites(prev => [...prev, toolId]);
      else setFavorites(prev => prev.filter(id => id !== toolId));
    } catch (e) {}
  };

  const handleOpen = async (tool, useGui = false) => {
    try {
      fetch(`${API_BASE}/api/kali/tools/${tool.id}/open`, {
        method: 'POST', headers: { 'Authorization': `Bearer ${token()}` }
      });
      if (useGui) {
        if (openApp) openApp('toolrunner', { toolId: tool.id });
      } else {
        if (openApp) openApp('terminal', { tool: tool.command });
      }
      setSelectedTool(null);
    } catch (e) {}
  };

  const filteredTools = tools.filter(t => {
    const matchCat = activeCat === 'all' ? true : activeCat === 'favorites' ? favorites.includes(t.id) : t.category === activeCat;
    const matchSearch = t.name.toLowerCase().includes(search.toLowerCase()) || (t.tags && t.tags.some(tag => tag.includes(search.toLowerCase())));
    return matchCat && matchSearch;
  });

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      {/* Sidebar */}
      <div style={{ width: '210px', background: '#161b22', borderRight: '1px solid #30363d', padding: '15px 10px', display: 'flex', flexDirection: 'column', gap: '4px', overflowY: 'auto' }}>
        <h2 style={{ fontSize: '10px', textTransform: 'uppercase', color: '#6e7681', padding: '0 8px', marginBottom: '8px', letterSpacing: '0.5px' }}>Categorias</h2>
        {categories.map(cat => (
          <div key={cat.id} onClick={() => setActiveCat(cat.id)} 
               style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 10px', borderRadius: '6px', cursor: 'pointer', fontSize: '13px', background: activeCat === cat.id ? 'rgba(56, 139, 253, 0.15)' : 'transparent', color: activeCat === cat.id ? '#58a6ff' : '#8b949e' }}>
            <cat.icon size={14} color={cat.color} /> {cat.name}
          </div>
        ))}
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* Topbar */}
        <div style={{ padding: '15px', borderBottom: '1px solid #30363d', background: '#0d1117' }}>
          <div style={{ position: 'relative' }}>
            <Search size={16} style={{ position: 'absolute', left: '12px', top: '10px', color: '#6e7681' }} />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search tools..." 
                   style={{ width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', paddingLeft: '36px', paddingRight: '12px', paddingTop: '8px', paddingBottom: '8px', fontSize: '13px', color: '#c9d1d9', outline: 'none' }} />
          </div>
        </div>

        {/* Grid */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '15px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '15px' }}>
            {filteredTools.map(tool => {
              const status = loadingStatus ? 'checking' : (statuses[tool.id] || 'missing');
              const isFav = favorites.includes(tool.id);
              const Icon = iconMap[tool.icon] || Search;
              return (
                <div key={tool.id} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '15px', display: 'flex', flexDirection: 'column' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
                    <div style={{ width: '38px', height: '38px', borderRadius: '6px', background: '#21262d', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <Icon size={20} color="#58a6ff" />
                    </div>
                    <button onClick={() => handleFavorite(tool.id)} style={{ background: 'transparent', border: 'none', cursor: 'pointer' }}>
                      <Star size={16} color={isFav ? '#facc15' : '#6e7681'} fill={isFav ? '#facc15' : 'transparent'} />
                    </button>
                  </div>
                  <h3 style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: '0 0 4px 0' }}>{tool.name}</h3>
                  <p style={{ fontSize: '11px', color: '#8b949e', margin: '0 0 10px 0', height: '32px', overflow: 'hidden' }}>{tool.description}</p>
                  
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px' }}>
                    <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '999px', background: tool.riskLevel === 'restricted' ? 'rgba(239, 68, 68, 0.2)' : tool.riskLevel === 'medium' ? 'rgba(234, 179, 8, 0.2)' : 'rgba(34, 197, 94, 0.2)', color: tool.riskLevel === 'restricted' ? '#f87171' : tool.riskLevel === 'medium' ? '#facc15' : '#4ade80' }}>
                      {tool.riskLevel}
                    </span>
                    {status === 'installed' && <span style={{ fontSize: '10px', color: '#4ade80', display: 'flex', alignItems: 'center', gap: '4px' }}><CheckCircle size={10} /> Installed</span>}
                    {status === 'missing' && <span style={{ fontSize: '10px', color: '#f87171', display: 'flex', alignItems: 'center', gap: '4px' }}><XCircle size={10} /> Missing</span>}
                    {status === 'checking' && <span style={{ fontSize: '10px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '4px' }}><Loader size={10} /> Checking</span>}
                  </div>

                  <div style={{ marginTop: 'auto', display: 'flex', gap: '8px' }}>
                    <button onClick={() => handleOpen(tool)} style={{ flex: 1, background: '#1f6feb', color: 'white', border: 'none', borderRadius: '4px', fontSize: '12px', padding: '6px 0', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px', fontWeight: 'bold' }}>
                      <TermIcon size={12} /> Open
                    </button>
                    <button onClick={() => setSelectedTool(tool)} style={{ padding: '6px 12px', background: '#21262d', color: 'white', border: '1px solid #30363d', borderRadius: '4px', fontSize: '12px', cursor: 'pointer' }}>
                      Details
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* Details Modal */}
      {selectedTool && (
        <div style={{ position: 'fixed', top: 0, left: 0, width: '100vw', height: '100vh', background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(5px)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 99999, padding: '20px' }} onClick={() => setSelectedTool(null)}>
          <div style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', width: '100%', maxWidth: '420px', padding: '20px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '15px' }}>
              <h2 style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', margin: 0 }}>{selectedTool.name}</h2>
              <button onClick={() => setSelectedTool(null)} style={{ background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer' }}><XCircle size={20} /></button>
            </div>
            <p style={{ fontSize: '13px', color: '#8b949e', marginBottom: '15px' }}>{selectedTool.description}</p>
            
            <div style={{ fontSize: '13px', marginBottom: '15px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #30363d', paddingBottom: '6px' }}><span style={{ color: '#8b949e' }}>Category:</span> <span>{selectedTool.category}</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #30363d', paddingBottom: '6px' }}><span style={{ color: '#8b949e' }}>Command:</span> <code style={{ background: '#21262d', padding: '2px 6px', borderRadius: '4px', color: '#58a6ff' }}>{selectedTool.command}</code></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #30363d', paddingBottom: '6px' }}><span style={{ color: '#8b949e' }}>Risk Level:</span> <span style={{ color: '#f87171' }}>{selectedTool.riskLevel}</span></div>
            </div>

            {selectedTool.riskLevel === 'restricted' && (
              <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.3)', color: '#f87171', fontSize: '11px', padding: '10px', borderRadius: '6px', marginBottom: '15px', display: 'flex', gap: '8px' }}>
                <AlertTriangle size={24} style={{ flexShrink: 0 }} />
                <span>Esta ferramenta é voltada para laboratório, auditoria própria e ambientes autorizados. Não execute contra sistemas de terceiros sem permissão.</span>
              </div>
            )}

            <div style={{ display: 'flex', gap: '10px' }}>
              <button onClick={() => handleOpen(selectedTool, true)} style={{ flex: 1, background: '#8957e5', color: 'white', border: 'none', padding: '10px 0', borderRadius: '6px', fontWeight: 'bold', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
                <LayoutGrid size={16} /> Abrir GUI
              </button>
              <button onClick={() => handleOpen(selectedTool, false)} style={{ flex: 1, background: '#1f6feb', color: 'white', border: 'none', padding: '10px 0', borderRadius: '6px', fontWeight: 'bold', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
                <TermIcon size={16} /> Abrir Terminal
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
