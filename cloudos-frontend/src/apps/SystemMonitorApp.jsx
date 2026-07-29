import { useState, useEffect, useRef } from 'react';
import { Cpu, MemoryStick, Activity } from 'lucide-react';
import LineChart from '../components/LineChart';

export const SystemMonitorApp = () => {
  const [cpuHist, setCpuHist] = useState([]);
  const [memHist, setMemHist] = useState([]);
  const [snap, setSnap] = useState(null);
  const wsRef = useRef(null);

  useEffect(() => {
    const token = localStorage.getItem('cloudos_token');
    const ws = new WebSocket(`ws://localhost:8080?token=${token}`);
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'subscribe', channel: 'sysmon' }));
    };

    ws.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data);
        if (m.type === 'sysmon') {
          setSnap(m.payload);
          setCpuHist(h => [...h.slice(-49), m.payload.cpu]);
          setMemHist(h => [...h.slice(-49), m.payload.mem.percent]);
        }
      } catch {}
    };

    return () => {
      try { ws.send(JSON.stringify({ type: 'unsubscribe', channel: 'sysmon' })); } catch {}
      ws.close();
    };
  }, []);

  const fmtBytes = (b) => {
    if (!b) return '0 B/s';
    if (b > 1e6) return (b / 1e6).toFixed(1) + ' MB/s';
    if (b > 1e3) return (b / 1e3).toFixed(1) + ' KB/s';
    return b + ' B/s';
  };

  return (
    <div className="p-4 bg-[#0d1117] text-[#c9d1d9] h-full overflow-y-auto" style={{ padding: '16px', background: '#0d1117', color: '#c9d1d9', height: '100%', overflowY: 'auto' }}>
      <h2 className="text-sm font-bold flex items-center gap-2" style={{ fontSize: '14px', fontWeight: 'bold', margin: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
        <Activity size={14} /> System Monitor (WSL 2 / Kali Linux)
      </h2>

      <div className="grid grid-cols-2 gap-3 mt-4" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginTop: '16px' }}>
        <div className="bg-[#161b22] border border-gray-800 rounded-lg p-3" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '12px' }}>
          <div className="flex justify-between mb-2" style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
            <span className="text-xs text-gray-400 flex items-center gap-1" style={{ fontSize: '12px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '4px' }}><Cpu size={14} /> CPU</span>
            <span className="text-base font-bold text-blue-400" style={{ fontSize: '16px', fontWeight: 'bold', color: '#58a6ff' }}>{snap ? `${snap.cpu.toFixed(1)}%` : '--'}</span>
          </div>
          <LineChart data={cpuHist} color="#58a6ff" />
        </div>

        <div className="bg-[#161b22] border border-gray-800 rounded-lg p-3" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '12px' }}>
          <div className="flex justify-between mb-2" style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
            <span className="text-xs text-gray-400 flex items-center gap-1" style={{ fontSize: '12px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '4px' }}><MemoryStick size={14} /> Memória</span>
            <span className="text-base font-bold text-green-400" style={{ fontSize: '16px', fontWeight: 'bold', color: '#3fb950' }}>{snap ? `${snap.mem.percent.toFixed(1)}%` : '--'}</span>
          </div>
          <LineChart data={memHist} color="#3fb950" />
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3 mt-3" style={{ marginTop: '12px', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '12px' }}>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>RAM usada</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? `${(snap.mem.used / 1e9).toFixed(2)} GB` : '--'}</div>
        </div>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>RAM total</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? `${(snap.mem.total / 1e9).toFixed(2)} GB` : '--'}</div>
        </div>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>Uptime</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? `${Math.floor(snap.uptime / 3600)}h ${Math.floor((snap.uptime % 3600) / 60)}m` : '--'}</div>
        </div>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>Load (1m)</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? snap.loadavg[0].toFixed(2) : '--'}</div>
        </div>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>↓ RX</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? fmtBytes(snap.net.rxBytesPerSec) : '--'}</div>
        </div>
        <div className="bg-[#161b22] border border-gray-800 rounded-md p-2.5" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '10px' }}>
          <div className="text-xs text-gray-500" style={{ fontSize: '11px', color: '#8b949e' }}>↑ TX</div>
          <div className="text-sm font-bold text-white" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white' }}>{snap ? fmtBytes(snap.net.txBytesPerSec) : '--'}</div>
        </div>
      </div>

      <div className="mt-4 p-3 bg-[#161b22] border border-gray-800 rounded-md text-xs text-gray-500" style={{ marginTop: '16px', padding: '12px', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', fontSize: '11px', color: '#8b949e' }}>
        Métricas de telemetria coletadas via <code style={{ color: '#58a6ff' }}>/proc/stat</code>, <code style={{ color: '#58a6ff' }}>/proc/meminfo</code> e <code style={{ color: '#58a6ff' }}>/proc/net/dev</code> do WSL 2 via WebSocket em tempo real (1.5s).
      </div>
    </div>
  );
};
