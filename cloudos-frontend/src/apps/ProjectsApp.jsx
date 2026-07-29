import { useState, useEffect } from 'react';
import { FolderPlus, Folder, Check } from 'lucide-react';
import { useCloudOS } from '../store/CloudOSContext';

export const ProjectsApp = () => {
  const { activeProject, setActiveProject } = useCloudOS();
  const [projects, setProjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [name, setName] = useState('');
  const [scope, setScope] = useState('');

  const fetchProjects = async () => {
    setLoading(true);
    try {
      const token = localStorage.getItem('cloudos_token');
      const res = await fetch('http://localhost:8080/api/projects', {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token ? `Bearer ${token}` : ''
        }
      });
      if (!res.ok) {
        setProjects([]);
        return;
      }
      const data = await res.json();
      setProjects(Array.isArray(data) ? data : []);
    } catch (e) {
      setProjects([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchProjects(); }, []);

  const handleCreate = async () => {
    if (!name) return;
    try {
      const token = localStorage.getItem('cloudos_token');
      await fetch('http://localhost:8080/api/projects', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token ? `Bearer ${token}` : ''
        },
        body: JSON.stringify({ name, scope })
      });
      setName('');
      setScope('');
      fetchProjects();
    } catch (e) {}
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300 p-6" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9', padding: '24px' }}>
      <h2 className="text-lg font-bold text-white mb-6" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', marginBottom: '24px' }}>Gestão de Projetos (Scope)</h2>
      
      <div className="flex gap-4 mb-8" style={{ display: 'flex', gap: '16px', marginBottom: '32px' }}>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Nome do Cliente (ex: Acme Corp)" className="flex-1 bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm outline-none text-white" style={{ flex: 1, background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
        <input value={scope} onChange={(e) => setScope(e.target.value)} placeholder="Escopo (ex: *.acme.com)" className="flex-1 bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm outline-none text-white" style={{ flex: 1, background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
        <button onClick={handleCreate} className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded text-sm font-bold flex items-center gap-1 text-white" style={{ background: '#2563eb', color: 'white', padding: '8px 16px', borderRadius: '6px', fontSize: '13px', fontWeight: 'bold', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '4px' }}><FolderPlus size={16} /> Criar</button>
      </div>

      <div className="flex-1 overflow-y-auto space-y-2" style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {Array.isArray(projects) && projects.map(p => (
          <div key={p.id} onClick={() => setActiveProject(p)} 
               className={`flex items-center justify-between p-4 rounded-lg border cursor-pointer ${activeProject?.id === p.id ? 'bg-blue-600/20 border-blue-500' : 'bg-[#161b22] border-gray-800'}`}
               style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px', borderRadius: '8px', border: activeProject?.id === p.id ? '1px solid #3b82f6' : '1px solid #30363d', background: activeProject?.id === p.id ? 'rgba(59, 130, 246, 0.15)' : '#161b22', cursor: 'pointer' }}>
            <div className="flex items-center gap-3" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Folder size={20} className={activeProject?.id === p.id ? 'text-blue-400' : 'text-gray-500'} style={{ color: activeProject?.id === p.id ? '#60a5fa' : '#8b949e' }} />
              <div>
                <h3 className="font-bold text-white text-sm" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: 0 }}>{p.name}</h3>
                <p className="text-xs text-gray-500" style={{ fontSize: '12px', color: '#8b949e', margin: '2px 0 0 0' }}>{p.scope || 'Sem escopo definido'}</p>
              </div>
            </div>
            {activeProject?.id === p.id && <Check size={20} className="text-blue-400" style={{ color: '#60a5fa' }} />}
          </div>
        ))}
        {(!Array.isArray(projects) || projects.length === 0) && !loading && (
          <div className="text-center text-gray-600 mt-10" style={{ textAlign: 'center', color: '#6e7681', marginTop: '40px' }}>Nenhum projeto cadastrado ou acesso negado.</div>
        )}
      </div>
    </div>
  );
};
