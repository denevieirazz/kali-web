import { useState, useEffect } from 'react';
import { Image as ImageIcon, Shield, Eye, Usb, Wifi } from 'lucide-react';

const getAuthHeaders = (extraHeaders = {}) => {
  const token = localStorage.getItem('cloudos_token');
  return {
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    ...extraHeaders
  };
};

export const SettingsApp = ({ setBg }) => {
  const [tab, setTab] = useState('appearance');
  const [devices, setDevices] = useState([]);
  const [loadingDev, setLoadingDev] = useState(false);
  const [errorDev, setErrorDev] = useState('');
  
  const [torActive, setTorActive] = useState(false);
  const [currentMac, setCurrentMac] = useState('Carregando...');
  const [anonStatus, setAnonStatus] = useState('');
  const [osintKeys, setOsintKeys] = useState({ shodan: '', hunterio: '', virustotal: '' });

  const fetchAnonStatus = () => {
    fetch('http://localhost:8080/api/system/status', { headers: getAuthHeaders() })
      .then(res => res.json())
      .then(data => {
        if (!data.error) {
          setTorActive(data.torActive);
          setCurrentMac(data.currentMac);
        } else {
          setCurrentMac('Erro ao ler');
        }
      })
      .catch(() => setCurrentMac('Backend offline'));
  };

  const fetchDevices = () => {
    setLoadingDev(true);
    fetch('http://localhost:8080/api/devices', { headers: getAuthHeaders() })
      .then(res => res.json())
      .then(data => { if (data.error) setErrorDev(data.error); else setDevices(data.devices || []); })
      .catch(() => setErrorDev('Erro de conexão.'))
      .finally(() => setLoadingDev(false));
  };

  useEffect(() => { 
    if (tab === 'hardware') fetchDevices(); 
    if (tab === 'anon') fetchAnonStatus();
  }, [tab]);

  const handleAttach = (busid, name) => {
    if (window.confirm(`Conectar "${name}" ao Kali Linux?`)) {
      fetch('http://localhost:8080/api/devices/attach', { method: 'POST', headers: getAuthHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ busid }) })
        .then(res => res.json()).then(data => { if (data.error) alert(data.error); else { alert('Conectado!'); fetchDevices(); } });
    }
  };

  const handleAnon = (action) => {
    setAnonStatus('Executando comando no Kali...');
    fetch('http://localhost:8080/api/tactical/anon', { method: 'POST', headers: getAuthHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ action }) })
      .then(res => res.json())
      .then(data => {
        if (data.error) {
          setAnonStatus(`Erro: ${data.error}`);
        } else {
          setAnonStatus('Comando finalizado. Atualizando status...');
          setTimeout(fetchAnonStatus, 1500);
        }
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
            <div onClick={() => setBg && setBg('https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
            <div onClick={() => setBg && setBg('https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070')} style={{ width: 80, height: 50, background: 'url(https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=2070) center/cover', borderRadius: 4, cursor: 'pointer' }}></div>
            <div onClick={() => setBg && setBg('linear-gradient(135deg, #0f0c29, #302b63, #24243e)')} style={{ width: 80, height: 50, background: 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)', borderRadius: 4, cursor: 'pointer' }}></div>
          </div>
        </div>
      )}

      {/* ABA ANONIMATO (AGORA EM TEMPO REAL) */}
      {tab === 'anon' && (
        <div className="settings-content">
          <h3>Operational Security (OpSec)</h3>
          <p style={{ fontSize: '12px', color: '#888', marginBottom: '15px' }}>Monitoramento em tempo real do Kali Linux.</p>
          
          {/* CARD DO TOR */}
          <div className={`tactical-card ${torActive ? 'tactical-active' : ''}`}>
            <div className="tactical-info">
              <Shield size={20} color={torActive ? "#4ade80" : "#f87171"} />
              <div>
                <div className="device-name">Roteamento Tor</div>
                <div className="device-id">
                  Status: {torActive ? <span style={{ color: '#4ade80', fontWeight: 'bold' }}>ATIVADO</span> : <span style={{ color: '#f87171', fontWeight: 'bold' }}>DESATIVADO</span>}
                </div>
              </div>
            </div>
            {torActive ? (
              <button className="device-btn-danger" onClick={() => handleAnon('tor_off')}>Desativar</button>
            ) : (
              <button className="device-btn" onClick={() => handleAnon('tor_on')}>Ativar</button>
            )}
          </div>

          {/* CARD DE MAC SPOOF */}
          <div className="tactical-card">
            <div className="tactical-info">
              <Wifi size={20} color="#60a5fa" />
              <div>
                <div className="device-name">Spoofar MAC Address</div>
                <div className="device-id" style={{ fontFamily: 'monospace' }}>
                  MAC Atual: {currentMac}
                </div>
              </div>
            </div>
            <button className="device-btn" onClick={() => handleAnon('mac_spoof')}>Spoofar</button>
          </div>

          {anonStatus && <div style={{ marginTop: '15px', fontSize: '12px', color: '#60a5fa' }}>{anonStatus}</div>}
        </div>
      )}

      {/* ABA OSINT */}
      {tab === 'osint' && (
        <div className="settings-content">
          <h3>Chaves de API de Inteligência</h3>
          <p style={{ fontSize: '12px', color: '#888', marginBottom: '15px' }}>Salve suas chaves de forma segura no sistema de arquivos do Kali.</p>
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
