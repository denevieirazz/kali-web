import React, { useState, useEffect, useCallback } from 'react';
import { 
  Network, Server, RefreshCw, Play, Square, RotateCcw, 
  Shield, Activity, AlertTriangle, Wifi
} from 'lucide-react';

const API_BASE = 'http://localhost:8080/api';

export default function NetworkApp({ payload, setPayload, openApp, setBg }) {
  const [services, setServices] = useState([]);
  const [ports, setPorts] = useState([]);
  const [loading, setLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState(null);
  const [error, setError] = useState(null);

  const getHeaders = () => {
    const token = localStorage.getItem('cloudos_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };
  };

  const fetchData = useCallback(async () => {
    try {
      const headers = getHeaders();
      const [svcRes, portsRes] = await Promise.all([
        fetch(`${API_BASE}/network/services`, { headers }),
        fetch(`${API_BASE}/network/ports`, { headers })
      ]);

      if (!svcRes.ok) throw new Error('Falha ao buscar serviços');
      
      const svcData = await svcRes.json();
      const portsData = await portsRes.json();

      if (svcData.success) setServices(svcData.services || []);
      if (portsData.success) setPorts(portsData.ports || []);
      
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [fetchData]);

  const handleServiceAction = async (name, action) => {
    setActionLoading(`${name}_${action}`);
    try {
      const res = await fetch(`${API_BASE}/network/services/${name}/${action}`, {
        method: 'POST',
        headers: getHeaders()
      });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      
      setServices(prev => prev.map(s => 
        s.name === name ? { ...s, status: data.newStatus } : s
      ));
    } catch (err) {
      setError(`Erro ao ${action} ${name}: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', height: '100%',
      background: '#0d1117', color: '#c9d1d9', fontFamily: 'sans-serif'
    }}>
      {/* Header */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: '12px',
        padding: '12px 16px', borderBottom: '1px solid #30363d', background: '#161b22'
      }}>
        <Network size={20} color="#58a6ff" />
        <h2 style={{ margin: 0, fontSize: '16px', fontWeight: 600 }}>
          Centro de Controle de Rede & Serviços
        </h2>
        <button
          onClick={fetchData}
          style={{ marginLeft: 'auto', background: '#21262d', border: '1px solid #30363d', borderRadius: '6px', padding: '6px 12px', color: '#c9d1d9', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '6px' }}
        >
          <RefreshCw size={14} className={loading ? 'spin' : ''} /> Atualizar
        </button>
      </div>

      {/* Error Banner */}
      {error && (
        <div style={{ margin: '8px 16px', padding: '8px 12px', background: 'rgba(248,81,73,0.1)', border: '1px solid #f85149', borderRadius: '6px', display: 'flex', alignItems: 'center', gap: '8px', color: '#f85149', fontSize: '12px' }}>
          <AlertTriangle size={14} /> {error}
        </div>
      )}

      {/* Services Grid */}
      <div style={{ padding: '16px', borderBottom: '1px solid #30363d' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px' }}>
          <Server size={16} color="#3fb950" />
          <h3 style={{ margin: 0, fontSize: '13px', textTransform: 'uppercase', color: '#8b949e' }}>Serviços Táticos</h3>
        </div>
        
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '12px' }}>
          {services.map(svc => {
            const isRunning = svc.status === 'running';
            return (
              <div key={svc.name} style={{
                background: '#161b22', border: '1px solid #30363d', borderRadius: '8px',
                padding: '12px', display: 'flex', flexDirection: 'column', gap: '8px'
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontWeight: 600, fontSize: '14px' }}>{svc.name}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: isRunning ? '#3fb950' : '#f85149', boxShadow: `0 0 8px ${isRunning ? '#3fb950' : '#f85149'}` }} />
                    <span style={{ fontSize: '10px', color: isRunning ? '#3fb950' : '#f85149' }}>
                      {isRunning ? 'ATIVO' : 'PARADO'}
                    </span>
                  </div>
                </div>
                
                <div style={{ display: 'flex', gap: '4px' }}>
                  <button
                    onClick={() => handleServiceAction(svc.name, 'start')}
                    disabled={isRunning || actionLoading === `${svc.name}_start`}
                    style={{ flex: 1, background: '#238636', border: 'none', borderRadius: '4px', padding: '4px', color: 'white', cursor: isRunning ? 'not-allowed' : 'pointer', opacity: isRunning ? 0.5 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px', fontSize: '11px' }}
                  >
                    <Play size={10} /> Iniciar
                  </button>
                  <button
                    onClick={() => handleServiceAction(svc.name, 'stop')}
                    disabled={!isRunning || actionLoading === `${svc.name}_stop`}
                    style={{ flex: 1, background: '#21262d', border: '1px solid #f85149', borderRadius: '4px', padding: '4px', color: '#f85149', cursor: !isRunning ? 'not-allowed' : 'pointer', opacity: !isRunning ? 0.5 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px', fontSize: '11px' }}
                  >
                    <Square size={10} /> Parar
                  </button>
                  <button
                    onClick={() => handleServiceAction(svc.name, 'restart')}
                    disabled={actionLoading === `${svc.name}_restart`}
                    style={{ flex: 1, background: '#21262d', border: '1px solid #30363d', borderRadius: '4px', padding: '4px', color: '#c9d1d9', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px', fontSize: '11px' }}
                  >
                    <RotateCcw size={10} /> Reiniciar
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Ports Table */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px' }}>
          <Shield size={16} color="#d29922" />
          <h3 style={{ margin: 0, fontSize: '13px', textTransform: 'uppercase', color: '#8b949e' }}>Portas em Escuta (Listening)</h3>
        </div>
        
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid #30363d', textAlign: 'left' }}>
              <th style={{ padding: '8px 6px', color: '#8b949e' }}>Protocolo</th>
              <th style={{ padding: '8px 6px', color: '#8b949e' }}>Endereço Local</th>
              <th style={{ padding: '8px 6px', color: '#8b949e' }}>Porta</th>
              <th style={{ padding: '8px 6px', color: '#8b949e' }}>Processo</th>
            </tr>
          </thead>
          <tbody>
            {ports.map((p, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #21262d' }}>
                <td style={{ padding: '6px' }}>
                  <span style={{ background: '#21262d', padding: '2px 6px', borderRadius: '4px', fontFamily: 'monospace' }}>
                    {p.state === 'LISTEN' ? 'TCP' : 'UDP'}
                  </span>
                </td>
                <td style={{ padding: '6px', fontFamily: 'monospace', color: '#58a6ff' }}>{p.localAddress}</td>
                <td style={{ padding: '6px', fontFamily: 'monospace', fontWeight: 600, color: '#d29922' }}>{p.port}</td>
                <td style={{ padding: '6px', fontFamily: 'monospace', color: '#3fb950' }}>{p.process}</td>
              </tr>
            ))}
            
            {ports.length === 0 && (
              <tr>
                <td colSpan="4" style={{ padding: '20px', textAlign: 'center', color: '#8b949e' }}>
                  <Wifi size={24} style={{ marginBottom: '8px', opacity: 0.5 }} />
                  <div>Nenhuma porta aberta detectada no momento.</div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <style>{`@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } } .spin { animation: spin 1s linear infinite; }`}</style>
    </div>
  );
}
