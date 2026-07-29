import { useState, useEffect, useRef } from 'react';
import { Play, Loader, Terminal, Zap, LayoutGrid, ArrowLeft, Square, Search, Radar, Globe, Bug, KeyRound } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

const CATEGORIES = [
  { id: 'all', name: 'Todas', icon: LayoutGrid },
  { id: 'recon', name: 'Recon & OSINT', icon: Radar },
  { id: 'web', name: 'Web Scanning', icon: Globe },
  { id: 'exploit', name: 'Exploits', icon: Bug },
  { id: 'cracking', name: 'Cracking', icon: KeyRound }
];

const AVAILABLE_TOOLS = [
  { id: 'nmap', name: 'Nmap', desc: 'Scanner de rede ativo', category: 'recon' },
  { id: 'subfinder', name: 'Subfinder', desc: 'Subdomínios passivos', category: 'recon' },
  { id: 'httpx', name: 'Httpx', desc: 'Validador HTTP em massa', category: 'recon' },
  { id: 'gobuster', name: 'Gobuster', desc: 'Brute-force de diretórios', category: 'web' },
  { id: 'nikto', name: 'Nikto', desc: 'Scanner de vulns Web', category: 'web' },
  { id: 'sqlmap', name: 'SQLMap', desc: 'Injeção de SQL', category: 'web' },
  { id: 'searchsploit', name: 'SearchSploit', desc: 'Busca de Exploits', category: 'exploit' },
  { id: 'hashcat', name: 'Hashcat', desc: 'Quebra de hashes (GPU)', category: 'cracking' }
];

export const ToolRunnerApp = ({ payload, setPayload }) => {
  const [schema, setSchema] = useState(null);
  const [loading, setLoading] = useState(true);
  const [formValues, setFormValues] = useState({});
  const [output, setOutput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [runId, setRunId] = useState(null);
  const [activeCat, setActiveCat] = useState('all');
  const [search, setSearch] = useState('');
  const outputRef = useRef(null);
  const currentToolId = payload?.toolId;

  useEffect(() => {
    if (currentToolId) {
      setLoading(true);
      fetch(`${API_BASE}/api/kali/tools/${currentToolId}/schema`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      })
        .then(res => res.json())
        .then(data => {
          if (data.error) { setSchema(null); } 
          else {
            setSchema(data);
            const initialValues = {};
            data.fields.forEach(f => {
              if (f.type === 'boolean') initialValues[f.id] = f.default !== undefined ? f.default : false;
              else initialValues[f.id] = f.default !== undefined ? f.default : '';
            });
            setFormValues(initialValues);
          }
          setLoading(false);
        });
    } else { setLoading(false); }
  }, [currentToolId]);

  useEffect(() => {
    if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight;
  }, [output]);

  const handleInputChange = (fieldId, value, type) => {
    setFormValues(prev => ({ ...prev, [fieldId]: type === 'boolean' ? !prev[fieldId] : value }));
  };

  const applyPreset = (presetVars) => setFormValues(prev => ({ ...prev, ...presetVars }));

  const isFormValid = () => {
    if (!schema) return false;
    return schema.fields.every(f => !f.required || (formValues[f.id] !== '' && formValues[f.id] !== undefined));
  };

  const buildCommandPreview = () => {
    if (!schema) return '';
    let cmd = schema.command;
    schema.fields.forEach(field => {
      const val = formValues[field.id];
      if (!val) return;
      if (field.type === 'boolean' && val === true) cmd += ` ${field.flag}`;
      else if ((field.type === 'text' || field.type === 'select') && val) {
        cmd += field.flag ? ` ${field.flag} ${val}` : ` ${val}`;
      }
    });
    return cmd;
  };

  const handleRun = async () => {
    if (!isFormValid()) return;
    setOutput('');
    setIsRunning(true);
    try {
      const response = await fetch(`${API_BASE}/api/kali/tools/${currentToolId}/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
        body: JSON.stringify({ options: formValues })
      });

      if (response.status === 400) {
        const errData = await response.json();
        setOutput(`[ERRO] ${errData.error}\n[DICA] Instale rodando no terminal: ${errData.installCmd}`);
        setIsRunning(false);
        return;
      }

      const id = response.headers.get('X-Run-Id');
      if (id) setRunId(id);

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setOutput(prev => prev + decoder.decode(value));
      }
    } catch (e) { setOutput("Erro ao conectar com o backend."); }
    setIsRunning(false);
    setRunId(null);
  };

  const handleStop = async () => {
    if (!runId) return;
    await fetch(`${API_BASE}/api/kali/tools/stop`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
      body: JSON.stringify({ runId })
    });
    setOutput(prev => prev + "\n\n[SCAN INTERROMPIDO PELO USUÁRIO]");
    setIsRunning(false);
    setRunId(null);
  };

  // TELA DE SELEÇÃO COM CATEGORIAS
  if (!currentToolId) {
    const filteredTools = AVAILABLE_TOOLS.filter(t => 
      (activeCat === 'all' || t.category === activeCat) &&
      (t.name.toLowerCase().includes(search.toLowerCase()) || t.desc.toLowerCase().includes(search.toLowerCase()))
    );

    return (
      <div className="flex h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
        {/* Sidebar de Categorias */}
        <div className="w-56 bg-[#161b22] border-r border-gray-800 p-3 space-y-1" style={{ width: '200px', background: '#161b22', borderRight: '1px solid #30363d', padding: '12px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <h2 className="text-xs uppercase text-gray-500 px-2 mb-2" style={{ fontSize: '11px', textTransform: 'uppercase', color: '#8b949e', padding: '0 8px', marginBottom: '8px' }}>Categorias</h2>
          {CATEGORIES.map(cat => (
            <div key={cat.id} onClick={() => setActiveCat(cat.id)} 
                 className={`flex items-center gap-2 px-2 py-1.5 rounded-md cursor-pointer text-sm ${activeCat === cat.id ? 'bg-blue-600/20 text-blue-400' : 'hover:bg-gray-800'}`}
                 style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '6px 8px', borderRadius: '6px', cursor: 'pointer', fontSize: '13px', background: activeCat === cat.id ? 'rgba(59, 130, 246, 0.15)' : 'transparent', color: activeCat === cat.id ? '#60a5fa' : '#c9d1d9' }}>
              <cat.icon size={14} /> {cat.name}
            </div>
          ))}
        </div>

        {/* Área Principal de Seleção */}
        <div className="flex-1 flex flex-col p-6" style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '24px' }}>
          <div className="relative mb-6" style={{ position: 'relative', marginBottom: '24px' }}>
            <Search size={16} className="absolute left-3 top-2.5 text-gray-500" style={{ position: 'absolute', left: '12px', top: '10px', color: '#8b949e' }} />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar ferramenta..." 
                   className="w-full bg-[#161b22] border border-gray-700 rounded-md pl-9 pr-3 py-2 text-sm focus:border-blue-500 outline-none"
                   style={{ width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px 8px 36px', fontSize: '13px', color: 'white', outline: 'none' }} />
          </div>
          
          <div className="grid grid-cols-3 gap-4 flex-1 overflow-y-auto" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '16px', flex: 1, overflowY: 'auto' }}>
            {filteredTools.map(tool => (
              <div key={tool.id} onClick={() => setPayload({ toolId: tool.id })} 
                   className="bg-[#161b22] border border-gray-800 rounded-lg p-4 cursor-pointer hover:border-blue-500 transition-colors flex flex-col"
                   style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '16px', cursor: 'pointer', display: 'flex', flexDirection: 'column' }}>
                <h3 className="font-bold text-white text-sm" style={{ fontSize: '14px', fontWeight: 'bold', color: 'white', margin: 0 }}>{tool.name}</h3>
                <p className="text-xs text-gray-500 mt-1 flex-1" style={{ fontSize: '12px', color: '#8b949e', marginTop: '4px', flex: 1, margin: '4px 0 0 0' }}>{tool.desc}</p>
                <span className="mt-3 text-[10px] uppercase text-gray-600 bg-gray-800 w-fit px-2 py-0.5 rounded-full" style={{ marginTop: '12px', fontSize: '10px', textTransform: 'uppercase', color: '#8b949e', background: '#21262d', padding: '2px 8px', borderRadius: '12px', width: 'fit-content' }}>{tool.category}</span>
              </div>
            ))}
            {filteredTools.length === 0 && <div className="col-span-3 text-center text-gray-600 mt-10" style={{ gridColumn: 'span 3', textAlign: 'center', color: '#6e7681', marginTop: '40px' }}>Nenhuma ferramenta encontrada.</div>}
          </div>
        </div>
      </div>
    );
  }

  // TELA DE CARREGAMENTO
  if (loading) return <div className="flex items-center justify-center h-full bg-[#0d1117] text-gray-400" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#8b949e' }}><Loader className="animate-spin mr-2" size={16} /> Carregando...</div>;
  
  // TELA DE ERRO
  if (!schema) return (
    <div className="flex flex-col items-center justify-center h-full bg-[#0d1117] text-red-400 p-6" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#f87171', padding: '24px' }}>
      <p className="mb-4" style={{ marginBottom: '16px' }}>Schema não encontrado para esta ferramenta.</p>
      <button onClick={() => setPayload(null)} className="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm" style={{ background: '#30363d', color: 'white', padding: '8px 16px', borderRadius: '6px', fontSize: '14px', border: 'none', cursor: 'pointer' }}>Voltar</button>
    </div>
  );

  // TELA PRINCIPAL DA GUI
  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div className="p-4 border-b border-gray-800 bg-[#161b22] flex justify-between items-center" style={{ padding: '16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div className="flex items-center gap-3" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <button onClick={() => setPayload(null)} className="text-gray-500 hover:text-white" style={{ background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center' }}><ArrowLeft size={18} /></button>
          <div>
            <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}><Zap size={18} className="text-purple-400" color="#a78bfa" /> {schema.name}</h2>
            <p className="text-xs text-gray-500" style={{ fontSize: '12px', color: '#8b949e', marginTop: '2px', margin: 0 }}>{schema.description}</p>
          </div>
        </div>
        {schema.presets?.length > 0 && (
          <div className="flex gap-2" style={{ display: 'flex', gap: '8px' }}>
            {schema.presets.map((p, i) => (
              <button key={i} onClick={() => applyPreset(p.vars)} className="px-3 py-1 bg-purple-600/20 text-purple-400 border border-purple-800 rounded text-xs hover:bg-purple-600/30"
                      style={{ padding: '4px 12px', background: 'rgba(167, 139, 250, 0.15)', color: '#a78bfa', border: '1px solid rgba(167, 139, 250, 0.3)', borderRadius: '4px', fontSize: '12px', cursor: 'pointer' }}>
                {p.name}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="flex-1 flex flex-col md:flex-row overflow-hidden" style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        <div className="md:w-1/3 p-6 space-y-5 overflow-y-auto border-r border-gray-800" style={{ width: '320px', padding: '20px', overflowY: 'auto', borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {schema.fields.map(field => {
            const isInvalid = field.required && !formValues[field.id];
            return (
              <div key={field.id} className="flex flex-col gap-2" style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                <label className="text-sm font-medium text-gray-400 flex items-center gap-2" style={{ fontSize: '13px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  {field.label} {field.required && <span className="text-red-400" style={{ color: '#f87171' }}>*</span>}
                </label>
                {field.type === 'text' && (
                  <input type="text" placeholder={field.placeholder || ''} value={formValues[field.id] || ''} onChange={(e) => handleInputChange(field.id, e.target.value, 'text')}
                    className={`bg-[#161b22] border rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white ${isInvalid ? 'border-red-500' : 'border-gray-700'}`}
                    style={{ background: '#161b22', border: isInvalid ? '1px solid #f87171' : '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
                )}
                {field.type === 'textarea' && (
                  <textarea 
                    rows="6" 
                    placeholder={field.placeholder || 'Cole um item por linha...'} 
                    value={formValues[field.id] || ''} 
                    onChange={(e) => handleInputChange(field.id, e.target.value, 'text')}
                    className={`bg-[#161b22] border rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white font-mono ${isInvalid ? 'border-red-500' : 'border-gray-700'}`} 
                    style={{ background: '#161b22', border: isInvalid ? '1px solid #f87171' : '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none', fontFamily: 'monospace' }}
                  />
                )}
                {field.type === 'select' && (
                  <select value={formValues[field.id] || ''} onChange={(e) => handleInputChange(field.id, e.target.value, 'select')}
                    className={`bg-[#161b22] border rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white ${isInvalid ? 'border-red-500' : 'border-gray-700'}`}
                    style={{ background: '#161b22', border: isInvalid ? '1px solid #f87171' : '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }}>
                    <option value="">Selecione...</option>
                    {field.options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                )}
                {field.type === 'boolean' && (
                  <label className="inline-flex items-center cursor-pointer" style={{ display: 'inline-flex', alignItems: 'center', cursor: 'pointer' }}>
                    <input type="checkbox" checked={formValues[field.id] || false} onChange={(e) => handleInputChange(field.id, e.target.value, 'boolean')} style={{ width: '18px', height: '18px', cursor: 'pointer' }} />
                    <span style={{ marginLeft: '8px', fontSize: '13px', color: '#c9d1d9' }}>{field.label}</span>
                  </label>
                )}
              </div>
            );
          })}
        </div>

        <div className="flex-1 flex flex-col bg-black/50" style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'rgba(0,0,0,0.5)' }}>
          <div className="p-2 border-b border-gray-800 flex justify-between items-center bg-[#161b22]" style={{ padding: '10px 16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="text-xs text-gray-500 font-mono flex items-center gap-1 truncate" style={{ fontSize: '12px', color: '#8b949e', fontFamily: 'monospace', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Terminal size={12} /> {buildCommandPreview()}
            </span>
            
            <div className="flex gap-2 ml-2" style={{ display: 'flex', gap: '8px', marginLeft: '8px' }}>
              {isRunning && (
                <button onClick={handleStop} className="bg-red-600 hover:bg-red-700 text-white px-4 py-1 rounded text-xs font-bold flex items-center gap-1"
                        style={{ background: '#da3633', color: 'white', padding: '6px 16px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <Square size={12} fill="white" /> Interromper
                </button>
              )}
              <button onClick={handleRun} disabled={isRunning || !isFormValid()} 
                      className="bg-green-600 hover:bg-green-700 text-white px-4 py-1 rounded text-xs font-bold flex items-center gap-1 disabled:bg-gray-700 disabled:cursor-not-allowed"
                      style={{ background: (isRunning || !isFormValid()) ? '#374151' : '#238636', color: 'white', padding: '6px 16px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: (isRunning || !isFormValid()) ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: '6px' }}>
                {isRunning ? <Loader size={12} className="animate-spin" /> : <Play size={12} />} {isRunning ? 'Escaneando...' : 'Executar'}
              </button>
            </div>
          </div>
          
          <div ref={outputRef} className="flex-1 p-4 overflow-y-auto font-mono text-xs text-green-400 whitespace-pre-wrap" style={{ flex: 1, padding: '16px', overflowY: 'auto', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', whiteSpace: 'pre-wrap' }}>
            {output || <span style={{ color: '#6e7681' }}>Clique em "Executar" para iniciar o scan em segundo plano...</span>}
          </div>
        </div>
      </div>
    </div>
  );
};
