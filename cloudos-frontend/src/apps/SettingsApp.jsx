import { useState } from 'react';
import { Palette, HardDrive, Info, Save, Database } from 'lucide-react';
import { useCloudOS } from '../store/CloudOSContext';

export const SettingsApp = () => {
  const [tab, setTab] = useState('appearance');
  const { settings, setSettings } = useCloudOS();

  const wallpapers = [
    'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070',
    'https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070',
    'linear-gradient(135deg, #0f0c29, #302b63, #24243e)'
  ];

  return (
    <div className="settings-container" style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      {/* Sidebar */}
      <div className="settings-sidebar" style={{ width: '210px', background: '#161b22', borderRight: '1px solid #30363d', padding: '15px 10px' }}>
        <div className={`settings-tab ${tab === 'appearance' ? 'active' : ''}`} onClick={() => setTab('appearance')}><Palette size={16} /> Aparência</div>
        <div className={`settings-tab ${tab === 'storage' ? 'active' : ''}`} onClick={() => setTab('storage')}><HardDrive size={16} /> Armazenamento</div>
        <div className={`settings-tab ${tab === 'backup' ? 'active' : ''}`} onClick={() => setTab('backup')}><Save size={16} /> Backups</div>
        <div className={`settings-tab ${tab === 'system' ? 'active' : ''}`} onClick={() => setTab('system')}><Database size={16} /> Sistema</div>
        <div className={`settings-tab ${tab === 'about' ? 'active' : ''}`} onClick={() => setTab('about')}><Info size={16} /> Sobre</div>
      </div>

      {/* Content */}
      <div className="settings-content-area" style={{ flex: 1, padding: '25px', overflowY: 'auto' }}>
        {tab === 'appearance' && (
          <div>
            <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '15px' }}>Personalização</h2>
            <div className="wallpaper-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '15px' }}>
              {wallpapers.map(wp => (
                <div key={wp} className={`wallpaper-thumb ${settings?.wallpaper === wp ? 'selected' : ''}`} 
                  style={{ height: '90px', borderRadius: '8px', cursor: 'pointer', border: settings?.wallpaper === wp ? '2px solid #58a6ff' : '2px solid transparent', background: wp.startsWith('http') ? `url(${wp}) center/cover` : wp }}
                  onClick={() => setSettings({ ...settings, wallpaper: wp })}
                />
              ))}
            </div>
          </div>
        )}
        
        {tab === 'storage' && (
          <div>
            <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '15px' }}>Armazenamento WSL</h2>
            <div style={{ background: '#161b22', padding: '20px', borderRadius: '8px', border: '1px solid #30363d' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '10px', fontSize: '13px' }}>
                <span>Disco Virtual (ext4)</span>
                <span style={{ color: '#8b949e' }}>45 GB usados de 100 GB</span>
              </div>
              <div style={{ width: '100%', background: '#21262d', borderRadius: '999px', height: '10px' }}>
                <div style={{ background: '#1f6feb', height: '100%', borderRadius: '999px', width: '45%' }}></div>
              </div>
            </div>
          </div>
        )}

        {tab === 'backup' && (
          <div>
            <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '15px' }}>Snapshots & Backups</h2>
            <button style={{ background: '#1f6feb', color: 'white', padding: '8px 16px', borderRadius: '6px', border: 'none', fontWeight: 'bold', cursor: 'pointer' }}
              onClick={() => {
                fetch('http://localhost:8080/api/snapshots/create', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${localStorage.getItem('cloudos_token')}` },
                  body: JSON.stringify({ name: `Backup ${new Date().toLocaleTimeString()}`, state: {} })
                }).then(r => r.json()).then(() => alert('Snapshot criado com sucesso!'));
              }}>
              Criar Snapshot do Ambiente
            </button>
            <p style={{ color: '#8b949e', fontSize: '13px', marginTop: '15px' }}>Restaure seu desktop para um estado anterior se algo der errado durante um pentest.</p>
          </div>
        )}

        {tab === 'system' && (
          <div>
            <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '15px' }}>Informações do Sistema</h2>
            <div style={{ background: '#161b22', padding: '20px', borderRadius: '8px', border: '1px solid #30363d', fontSize: '13px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span style={{ color: '#8b949e' }}>Backend:</span> <span>Node.js + WSL2 Kali</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span style={{ color: '#8b949e' }}>Database:</span> <span>SQLite (WAL Mode)</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span style={{ color: '#8b949e' }}>Security:</span> <span>JWT + Path Traversal Block</span></div>
            </div>
          </div>
        )}

        {tab === 'about' && (
          <div>
            <h2 style={{ fontSize: '20px', fontWeight: 'bold', marginBottom: '15px' }}>Sobre o CloudOS</h2>
            <div style={{ background: '#161b22', padding: '20px', borderRadius: '8px', border: '1px solid #30363d', fontSize: '13px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <h3 style={{ fontSize: '16px', color: '#58a6ff', margin: 0 }}>CloudOS Enterprise v2.5</h3>
              <p style={{ color: '#8b949e', margin: 0 }}>Plataforma SaaS de Pentest com subsistema Kali Linux isolado por usuário.</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
