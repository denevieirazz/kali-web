import { useState, useEffect } from 'react';
import { Activity, HardDrive, AlertTriangle, Server } from 'lucide-react';

export const SystemMonitorApp = () => {
  const [status, setStatus] = useState(null);

  const fetchStatus = () => {
    fetch('http://localhost:8080/api/system/status', {
      headers: { 'Authorization': `Bearer ${localStorage.getItem('cloudos_token')}` }
    })
      .then(res => res.json())
      .then(setStatus)
      .catch(console.error);
  };

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 5000);
    return () => clearInterval(interval);
  }, []);

  if (!status) return <div className="p-4 text-white">Carregando métricas do WSL...</div>;

  return (
    <div className="p-4 text-white h-full overflow-y-auto bg-gray-900">
      <h2 className="text-xl font-bold mb-4 flex items-center gap-2"><Server size={20} /> Backend & WSL Status</h2>
      
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="bg-gray-800 p-4 rounded-lg border border-gray-700">
          <div className="text-xs text-gray-400 mb-1">Backend Status</div>
          <div className="text-lg text-green-400 font-bold flex items-center gap-2">
            <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span> Online
          </div>
        </div>
        <div className="bg-gray-800 p-4 rounded-lg border border-gray-700">
          <div className="text-xs text-gray-400 mb-1">Active WS Sessions</div>
          <div className="text-lg text-blue-400 font-bold">{status.activeSessions}</div>
        </div>
      </div>

      <div className="bg-gray-800 p-4 rounded-lg border border-gray-700 mb-6">
        <div className="text-xs text-gray-400 mb-2 flex items-center gap-2"><HardDrive size={14} /> Disk Usage (WSL)</div>
        <div className="w-full bg-gray-700 rounded-full h-2.5 mb-2">
          <div className="bg-blue-600 h-2.5 rounded-full" style={{ width: '45%' }}></div>
        </div>
        <div className="text-sm text-gray-300">{status.diskUsage} Usado</div>
      </div>

      <div className="bg-gray-800 p-4 rounded-lg border border-gray-700">
        <div className="text-xs text-gray-400 mb-2 flex items-center gap-2"><AlertTriangle size={14} /> Recent Errors</div>
        {status.recentErrors.length === 0 ? (
          <div className="text-sm text-gray-500">Nenhum erro recente.</div>
        ) : (
          <div className="space-y-2">
            {status.recentErrors.map((err, i) => (
              <div key={i} className="text-xs bg-red-900/20 border border-red-800/40 p-2 rounded text-red-300">
                <span className="text-red-500">{new Date(err.time).toLocaleTimeString()}</span>: {err.msg}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
