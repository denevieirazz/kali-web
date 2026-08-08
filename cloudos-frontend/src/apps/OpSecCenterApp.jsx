import { useState, useEffect } from 'react';
import { Shield, Wifi, HardDrive, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const OpSecCenterApp = () => {
  const [status, setStatus] = useState(null);

  const fetchStatus = () => {
    fetch(`${API_BASE}/api/system/status`, { headers: { 'Authorization': `Bearer ${token()}` } })
      .then(res => res.json())
      .then(setStatus).catch(console.error);
  };

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 5000);
    return () => clearInterval(interval);
  }, []);

  const toggleTor = async (action) => {
    await fetch(`${API_BASE}/api/tactical/anon`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
      body: JSON.stringify({ action })
    });
    fetchStatus();
  };

  if (!status) return <div className="p-4 text-white">Carregando OpSec...</div>;

  return (
    <div className="p-6 text-white h-full overflow-y-auto bg-gray-900">
      <h2 className="text-xl font-bold mb-6 flex items-center gap-2"><Shield size={24} /> Operational Security Center</h2>
      
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className={`p-4 rounded-lg border ${status.torActive ? 'bg-green-900/20 border-green-800' : 'bg-red-900/20 border-red-800'}`}>
          <div className="flex items-center gap-2 mb-2">
            {status.torActive ? <CheckCircle className="text-green-400" /> : <XCircle className="text-red-400" />}
            <span className="font-bold">Tor Routing</span>
          </div>
          <div className="text-sm text-gray-400 mb-4">Status: {status.torActive ? 'ATIVO' : 'INATIVO'}</div>
          <button onClick={() => toggleTor(status.torActive ? 'tor_off' : 'tor_on')} className={`w-full py-2 rounded text-sm font-bold ${status.torActive ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'}`}>
            {status.torActive ? 'Desativar Tor' : 'Ativar Tor'}
          </button>
        </div>

        <div className="p-4 rounded-lg border border-gray-700 bg-gray-800">
          <div className="flex items-center gap-2 mb-2"><Wifi className="text-blue-400" /><span className="font-bold">Network Interface</span></div>
          <div className="text-sm text-gray-400">MAC Address (Mascarado):</div>
          <div className="text-lg text-gray-200 font-mono">{status.currentMac}</div>
        </div>
      </div>

      <div className="p-4 rounded-lg border border-gray-700 bg-gray-800 mb-6">
        <div className="flex items-center gap-2 mb-2"><HardDrive className="text-purple-400" /><span className="font-bold">Disk & Backend</span></div>
        <div className="text-sm text-gray-400">WSL Disk Usage: {status.diskUsage}</div>
        <div className="text-sm text-gray-400">Active Sessions: {status.activeSessions}</div>
      </div>

      <div className="p-4 rounded-lg border border-gray-700 bg-gray-800">
        <div className="flex items-center gap-2 mb-2"><AlertTriangle className="text-yellow-400" /><span className="font-bold">Recent Errors</span></div>
        {(!status?.recentErrors || status.recentErrors.length === 0) ? <div className="text-sm text-gray-500">Nenhum erro recente. Sistema saudável!</div> : 
          status.recentErrors.map((err, i) => (
            <div key={i} className="text-xs bg-red-900/20 border border-red-800/40 p-2 rounded mt-2 text-red-300">
              {new Date(err.time).toLocaleTimeString()}: {err.msg}
            </div>
          ))
        }
      </div>
    </div>
  );
};
