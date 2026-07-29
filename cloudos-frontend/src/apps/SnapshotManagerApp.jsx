import { useState, useEffect } from 'react';
import { Camera, RotateCcw, Trash2, Plus, Clock } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const SnapshotManagerApp = () => {
  const [snaps, setSnaps] = useState([]);
  const [showCreate, setShowCreate] = useState(false);
  const [name, setName] = useState('');

  const loadSnaps = async () => {
    try {
      const r = await fetch(`${API_BASE}/api/snapshots`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      });
      if (r.ok) setSnaps(await r.json());
    } catch (e) {}
  };

  useEffect(() => { loadSnaps(); }, []);

  const handleCapture = async () => {
    if (!name) return;
    try {
      await fetch(`${API_BASE}/api/snapshots`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
        body: JSON.stringify({ name, data: JSON.stringify({ open_windows: [] }) })
      });
      setName('');
      setShowCreate(false);
      loadSnaps();
    } catch (e) {}
  };

  const handleRestore = async (id) => {
    try {
      const r = await fetch(`${API_BASE}/api/snapshots/${id}/restore`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token()}` }
      });
      if (r.ok) {
        alert('Snapshot restaurado com sucesso! Atualize a área de trabalho.');
      }
    } catch (e) {}
  };

  const handleDelete = async (id) => {
    try {
      await fetch(`${API_BASE}/api/snapshots/${id}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token()}` }
      });
      loadSnaps();
    } catch (e) {}
  };

  return (
    <div className="p-4 bg-[#0d1117] text-gray-300 h-full overflow-y-auto" style={{ padding: '16px', background: '#0d1117', color: '#c9d1d9', height: '100%', overflowY: 'auto' }}>
      <div className="flex justify-between items-center mb-4" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
        <h2 className="text-sm font-bold text-white flex items-center gap-2" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
          <Camera size={14} /> Snapshot Manager
        </h2>
        <button onClick={() => setShowCreate(!showCreate)} className="bg-green-600 hover:bg-green-700 px-3 py-1.5 rounded text-xs font-bold flex items-center gap-1 text-white" style={{ background: '#16a34a', color: 'white', padding: '6px 12px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}>
          <Plus size={14} /> Novo Snapshot
        </button>
      </div>

      {showCreate && (
        <div className="bg-[#161b22] border border-gray-800 rounded-lg p-3 mb-4" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '12px', marginBottom: '16px' }}>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Nome do Snapshot (ex: Layout Red Team)" className="w-full bg-[#0d1117] border border-gray-700 rounded px-3 py-2 text-sm outline-none text-white mb-2" style={{ width: '100%', background: '#0d1117', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none', marginBottom: '8px' }} />
          <div className="flex gap-2" style={{ display: 'flex', gap: '8px' }}>
            <button onClick={handleCapture} disabled={!name} className="bg-blue-600 hover:bg-blue-700 px-3 py-1.5 rounded text-xs font-bold text-white" style={{ background: '#2563eb', color: 'white', padding: '6px 12px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: name ? 'pointer' : 'not-allowed' }}>Capturar Estado</button>
            <button onClick={() => setShowCreate(false)} className="bg-gray-800 hover:bg-gray-700 px-3 py-1.5 rounded text-xs text-white" style={{ background: '#30363d', color: 'white', padding: '6px 12px', borderRadius: '6px', fontSize: '12px', border: 'none', cursor: 'pointer' }}>Cancelar</button>
          </div>
        </div>
      )}

      <div className="space-y-2" style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {snaps.map(s => (
          <div key={s.id} className="bg-[#161b22] border border-gray-800 rounded-lg p-3 flex justify-between items-center" style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h3 className="font-bold text-white text-sm" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: 0 }}>{s.name}</h3>
              <p className="text-xs text-gray-500 flex items-center gap-1 mt-1" style={{ fontSize: '11px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '4px', margin: '4px 0 0 0' }}>
                <Clock size={11} /> {new Date(s.created_at).toLocaleString()}
              </p>
            </div>
            <div className="flex gap-2" style={{ display: 'flex', gap: '8px' }}>
              <button onClick={() => handleRestore(s.id)} title="Restaurar" className="p-1.5 bg-gray-800 hover:bg-gray-700 rounded text-gray-300" style={{ background: '#30363d', border: 'none', borderRadius: '4px', padding: '6px', color: '#c9d1d9', cursor: 'pointer' }}><RotateCcw size={14} /></button>
              <button onClick={() => handleDelete(s.id)} title="Excluir" className="p-1.5 bg-red-900/30 hover:bg-red-900/50 rounded text-red-400" style={{ background: 'rgba(248, 113, 113, 0.15)', border: 'none', borderRadius: '4px', padding: '6px', color: '#f87171', cursor: 'pointer' }}><Trash2 size={14} /></button>
            </div>
          </div>
        ))}
        {snaps.length === 0 && <div className="text-center text-gray-600 mt-10" style={{ textAlign: 'center', color: '#6e7681', marginTop: '40px' }}>Nenhum snapshot salvo.</div>}
      </div>
    </div>
  );
};
