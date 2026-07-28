import { useState } from 'react';
import { Palette, User, HardDrive, Info, Terminal as TermIcon } from 'lucide-react';
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
    <div className="settings-container">
      <div className="settings-sidebar">
        <div className={`settings-tab ${tab === 'appearance' ? 'active' : ''}`} onClick={() => setTab('appearance')}>
          <Palette size={16} /> Aparência
        </div>
        <div className={`settings-tab ${tab === 'account' ? 'active' : ''}`} onClick={() => setTab('account')}>
          <User size={16} /> Conta
        </div>
        <div className={`settings-tab ${tab === 'storage' ? 'active' : ''}`} onClick={() => setTab('storage')}>
          <HardDrive size={16} /> Armazenamento
        </div>
        <div className={`settings-tab ${tab === 'terminal' ? 'active' : ''}`} onClick={() => setTab('terminal')}>
          <TermIcon size={16} /> Terminal
        </div>
        <div className={`settings-tab ${tab === 'about' ? 'active' : ''}`} onClick={() => setTab('about')}>
          <Info size={16} /> Sobre
        </div>
      </div>

      <div className="settings-content-area">
        {tab === 'appearance' && (
          <div>
            <h2>Personalização</h2>
            <p className="text-gray-400 mb-4" style={{ color: '#9ca3af', marginBottom: '15px' }}>Escolha o papel de parede do seu desktop.</p>
            <div className="wallpaper-grid">
              {wallpapers.map(wp => (
                <div key={wp} className={`wallpaper-thumb ${settings?.wallpaper === wp ? 'selected' : ''}`} 
                  style={{ background: wp.startsWith('http') ? `url(${wp}) center/cover` : wp }}
                  onClick={() => setSettings({ ...settings, wallpaper: wp })}
                />
              ))}
            </div>
          </div>
        )}
        
        {tab === 'account' && (
          <div>
            <h2>Conta e Plano</h2>
            <div className="settings-card">
              <h3>Plano Atual: <span style={{ color: '#60a5fa' }}>Pro Tier</span></h3>
              <p style={{ fontSize: '13px', color: '#9ca3af', marginBottom: '15px' }}>Você tem acesso a armazenamento isolado no WSL2 com suporte a OpSec e Terminal Tmux.</p>
              <button className="settings-btn-primary">Gerenciar Assinatura</button>
            </div>
          </div>
        )}

        {tab === 'storage' && (
          <div>
            <h2>Armazenamento WSL</h2>
            <div className="settings-card">
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '10px' }}>
                <span>Disco Virtual (ext4)</span>
                <span style={{ color: '#9ca3af' }}>45 GB usados de 100 GB</span>
              </div>
              <div style={{ width: '100%', background: 'rgba(255,255,255,0.1)', borderRadius: '4px', height: '8px' }}>
                <div style={{ width: '45%', background: '#3b82f6', height: '100%', borderRadius: '4px' }}></div>
              </div>
            </div>
          </div>
        )}

        {tab === 'terminal' && (
          <div>
            <h2>Preferências do Terminal</h2>
            <div className="settings-card">
              <label style={{ display: 'block', fontSize: '13px', color: '#9ca3af', marginBottom: '10px' }}>Tamanho da Fonte</label>
              <input type="range" min="12" max="24" defaultValue="14" style={{ width: '100%' }} />
            </div>
          </div>
        )}

        {tab === 'about' && (
          <div>
            <h2>Sobre o CloudOS</h2>
            <div className="settings-card">
              <h3>CloudOS Enterprise v2.0</h3>
              <p style={{ fontSize: '13px', color: '#9ca3af' }}>Backend: Node.js + SQLite + WSL2 Kali Linux</p>
              <p style={{ fontSize: '13px', color: '#9ca3af' }}>Frontend: React 18 + Vite + Monaco</p>
              <p style={{ fontSize: '13px', color: '#9ca3af', marginTop: '10px' }}>Arquitetura SaaS isolada por usuário com Node FS Security, SQLite Persistence e JWT Authentication.</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
