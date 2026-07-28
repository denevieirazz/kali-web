import { useState } from 'react';
import { Check, Download, Pin, Search } from 'lucide-react';
import { AppList } from '../registry';
import { useCloudOS } from '../store/CloudOSContext';

export const AppStoreApp = ({ openApp }) => {
  const { pinnedApps, togglePin } = useCloudOS();
  const [searchTerm, setSearchTerm] = useState('');

  const filteredApps = AppList.filter(app => 
    app.title.toLowerCase().includes(searchTerm.toLowerCase()) || 
    app.id.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div style={{ padding: '15px', borderBottom: '1px solid #30363d', background: '#161b22' }}>
        <h2 style={{ fontSize: '16px', fontWeight: 'bold', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
          <Download size={20} color="#58a6ff" /> CloudOS App Store
        </h2>
        <div style={{ marginTop: '12px', position: 'relative' }}>
          <Search size={14} style={{ position: 'absolute', left: '12px', top: '10px', color: '#6e7681' }} />
          <input 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Buscar ferramentas..." 
            style={{ width: '100%', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', paddingLeft: '36px', paddingRight: '12px', paddingTop: '8px', paddingBottom: '8px', fontSize: '13px', color: '#c9d1d9', outline: 'none' }}
          />
        </div>
      </div>
      
      <div className="appstore-grid" style={{ flex: 1, overflowY: 'auto', padding: '15px', display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '15px' }}>
        {filteredApps.map(app => {
          const isPinned = pinnedApps && pinnedApps.includes(app.id);
          const Icon = app.icon;
          return (
            <div key={app.id} className="appstore-card" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '15px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '8px', background: '#21262d', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '12px' }}>
                <Icon size={24} color="#58a6ff" />
              </div>
              <h3 style={{ fontSize: '14px', fontWeight: '600', margin: '0 0 4px 0', color: '#c9d1d9' }}>{app.title}</h3>
              <p style={{ fontSize: '11px', color: '#8b949e', margin: '0 0 12px 0', flex: 1 }}>Ferramenta do sistema CloudOS para análise e controle.</p>
              
              <div style={{ display: 'flex', gap: '8px', width: '100%' }}>
                <button onClick={() => openApp && openApp(app.id)} style={{ flex: 1, background: '#1f6feb', color: 'white', border: 'none', borderRadius: '4px', fontSize: '12px', padding: '6px 0', cursor: 'pointer', fontWeight: 'bold' }}>Abrir</button>
                <button onClick={() => togglePin(app.id, !isPinned)} style={{ padding: '6px 12px', borderRadius: '4px', border: 'none', background: isPinned ? '#30363d' : '#21262d', color: isPinned ? '#e3b341' : '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {isPinned ? <Check size={14} /> : <Pin size={14} />}
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
