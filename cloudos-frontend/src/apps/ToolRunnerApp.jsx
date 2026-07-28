import { useState, useEffect, useRef } from 'react';
import { Play, Loader, Terminal, Zap, LayoutGrid, ArrowLeft, AlertCircle } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

// Lista local das ferramentas que têm GUI
const AVAILABLE_TOOLS = [
  { id: 'nmap', name: 'Nmap', desc: 'Scanner de rede e portas' },
  { id: 'gobuster', name: 'Gobuster', desc: 'Brute-force de diretórios web' },
  { id: 'nikto', name: 'Nikto', desc: 'Scanner de vulnerabilidades Web' },
  { id: 'sqlmap', name: 'SQLMap', desc: 'Injeção de SQL e auditoria de BD' }
];

export const ToolRunnerApp = ({ payload, setPayload }) => {
  const [schema, setSchema] = useState(null);
  const [loading, setLoading] = useState(true);
  const [formValues, setFormValues] = useState({});
  const [output, setOutput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [validationError, setValidationError] = useState('');
  const outputRef = useRef(null);
  const currentToolId = payload?.toolId;

  useEffect(() => {
    if (currentToolId) {
      setLoading(true);
      setSchema(null);
      setValidationError('');
      fetch(`${API_BASE}/api/kali/tools/${currentToolId}/schema`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      })
        .then(res => res.json())
        .then(data => {
          if (data.error) { setSchema(null); } 
          else {
            setSchema(data);
            const initialValues = {};
            if (data.fields) {
              data.fields.forEach(f => {
                initialValues[f.id] = f.default !== undefined ? f.default : (f.type === 'boolean' ? false : '');
              });
            }
            setFormValues(initialValues);
          }
          setLoading(false);
        })
        .catch(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, [currentToolId]);

  useEffect(() => {
    if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight;
  }, [output]);

  const handleInputChange = (fieldId, value, type) => {
    setValidationError('');
    setFormValues(prev => ({ ...prev, [fieldId]: type === 'boolean' ? !prev[fieldId] : value }));
  };

  const applyPreset = (presetVars) => {
    setValidationError('');
    setFormValues(prev => ({ ...prev, ...presetVars }));
  };

  const buildCommandPreview = () => {
    if (!schema) return '';
    let cmd = schema.command;
    if (schema.fields) {
      schema.fields.forEach(field => {
        const val = formValues[field.id];
        if (val === undefined || val === '' || val === false) return;
        if (field.type === 'boolean' && val === true) cmd += ` ${field.flag}`;
        else if ((field.type === 'text' || field.type === 'select') && val) {
          cmd += field.flag ? ` ${field.flag} ${val}` : ` ${val}`;
        }
      });
    }
    return cmd;
  };

  const handleRun = async () => {
    // Validar campos obrigatórios
    if (schema && schema.fields) {
      const missing = schema.fields.filter(f => f.required && (!formValues[f.id] || formValues[f.id] === ''));
      if (missing.length > 0) {
        setValidationError(`Por favor, preencha o campo obrigatório: ${missing.map(m => m.label).join(', ')}`);
        return;
      }
    }

    setValidationError('');
    setOutput('');
    setIsRunning(true);
    try {
      const response = await fetch(`${API_BASE}/api/kali/tools/${currentToolId}/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
        body: JSON.stringify({ options: formValues })
      });
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setOutput(prev => prev + decoder.decode(value));
      }
    } catch (e) { setOutput("Erro ao conectar com o backend."); }
    setIsRunning(false);
  };

  // TELA DE SELEÇÃO (Se abrir sem payload)
  if (!currentToolId) {
    return (
      <div className="flex flex-col h-full bg-[#0d1117] text-gray-300 p-6" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9', padding: '24px' }}>
        <h2 className="text-lg font-bold text-white flex items-center gap-2 mb-6" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '24px' }}>
          <LayoutGrid size={18} /> Selecione uma Ferramenta
        </h2>
        <div className="grid grid-cols-2 gap-4" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '16px' }}>
          {AVAILABLE_TOOLS.map(tool => (
            <div key={tool.id} onClick={() => setPayload && setPayload({ toolId: tool.id })} 
                 className="bg-[#161b22] border border-gray-800 rounded-lg p-4 cursor-pointer hover:border-blue-500 transition-colors"
                 style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '16px', cursor: 'pointer' }}>
              <h3 className="font-bold text-white" style={{ fontSize: '15px', fontWeight: 'bold', color: 'white', margin: 0 }}>{tool.name}</h3>
              <p className="text-xs text-gray-500 mt-1" style={{ fontSize: '12px', color: '#8b949e', marginTop: '4px', margin: 0 }}>{tool.desc}</p>
            </div>
          ))}
        </div>
      </div>
    );
  }

  // TELA DE CARREGAMENTO
  if (loading) return <div className="flex items-center justify-center h-full bg-[#0d1117] text-gray-400" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#8b949e' }}><Loader className="animate-spin mr-2" size={16} /> Carregando...</div>;
  
  // TELA DE ERRO (Se o schema não existir)
  if (!schema) return (
    <div className="flex flex-col items-center justify-center h-full bg-[#0d1117] text-red-400 p-6" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#f87171', padding: '24px' }}>
      <p className="mb-4" style={{ marginBottom: '16px' }}>Schema não encontrado para esta ferramenta.</p>
      <button onClick={() => setPayload && setPayload(null)} className="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm" style={{ background: '#30363d', color: 'white', padding: '8px 16px', borderRadius: '6px', fontSize: '14px', border: 'none', cursor: 'pointer' }}>Voltar</button>
    </div>
  );

  // TELA PRINCIPAL DA GUI
  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div className="p-4 border-b border-gray-800 bg-[#161b22] flex justify-between items-center" style={{ padding: '16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div className="flex items-center gap-3" style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <button onClick={() => setPayload && setPayload(null)} className="text-gray-500 hover:text-white" style={{ background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center' }}><ArrowLeft size={18} /></button>
          <div>
            <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
              <Zap size={18} className="text-purple-400" color="#a78bfa" /> {schema.name} - Auto Runner
            </h2>
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
          {validationError && (
            <div style={{ background: 'rgba(239, 68, 68, 0.15)', border: '1px solid rgba(239, 68, 68, 0.4)', color: '#f87171', padding: '10px', borderRadius: '6px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <AlertCircle size={16} style={{ flexShrink: 0 }} />
              <span>{validationError}</span>
            </div>
          )}

          {schema.fields && schema.fields.map(field => (
            <div key={field.id} className="flex flex-col gap-2" style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label className="text-sm font-medium text-gray-400 flex items-center gap-2" style={{ fontSize: '13px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '6px' }}>
                {field.label} {field.required && <span className="text-red-400" style={{ color: '#f87171' }}>*</span>}
              </label>
              {field.type === 'text' && (
                <input type="text" placeholder={field.placeholder || ''} value={formValues[field.id] || ''} onChange={(e) => handleInputChange(field.id, e.target.value, 'text')}
                  className="bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white"
                  style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }} />
              )}
              {field.type === 'select' && (
                <select value={formValues[field.id] || ''} onChange={(e) => handleInputChange(field.id, e.target.value, 'select')}
                  className="bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white"
                  style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '13px', color: 'white', outline: 'none' }}>
                  <option value="">Selecione...</option>
                  {field.options && field.options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
                </select>
              )}
              {field.type === 'boolean' && (
                <label className="inline-flex items-center cursor-pointer" style={{ display: 'inline-flex', alignItems: 'center', cursor: 'pointer' }}>
                  <input type="checkbox" checked={formValues[field.id] || false} onChange={(e) => handleInputChange(field.id, e.target.value, 'boolean')} style={{ width: '18px', height: '18px', cursor: 'pointer' }} />
                  <span style={{ marginLeft: '8px', fontSize: '13px', color: '#c9d1d9' }}>{field.label}</span>
                </label>
              )}
            </div>
          ))}
        </div>

        <div className="flex-1 flex flex-col bg-black/50" style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'rgba(0,0,0,0.5)' }}>
          <div className="p-2 border-b border-gray-800 flex justify-between items-center bg-[#161b22]" style={{ padding: '10px 16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="text-xs text-gray-500 font-mono flex items-center gap-1 truncate" style={{ fontSize: '12px', color: '#8b949e', fontFamily: 'monospace', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Terminal size={12} /> {buildCommandPreview()}
            </span>
            <button onClick={handleRun} disabled={isRunning} className="bg-green-600 hover:bg-green-700 text-white px-4 py-1 rounded text-xs font-bold flex items-center gap-1 disabled:bg-gray-700 ml-2"
                    style={{ background: isRunning ? '#374151' : '#238636', color: 'white', padding: '6px 16px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: isRunning ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: '6px', marginLeft: '8px' }}>
              {isRunning ? <Loader size={12} className="animate-spin" /> : <Play size={12} />} {isRunning ? 'Escaneando...' : 'Executar'}
            </button>
          </div>
          <div ref={outputRef} className="flex-1 p-4 overflow-y-auto font-mono text-xs text-green-400 whitespace-pre-wrap" style={{ flex: 1, padding: '16px', overflowY: 'auto', fontFamily: 'monospace', fontSize: '12px', color: '#4ade80', whiteSpace: 'pre-wrap' }}>
            {output || <span style={{ color: '#6e7681' }}>Clique em "Executar" para iniciar o scan em segundo plano...</span>}
          </div>
        </div>
      </div>
    </div>
  );
};
