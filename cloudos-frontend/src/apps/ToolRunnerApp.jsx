import { useState, useEffect, useRef } from 'react';
import { Play, Loader, Terminal, Zap, RotateCcw } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const ToolRunnerApp = ({ payload }) => {
  const [schema, setSchema] = useState(null);
  const [loading, setLoading] = useState(true);
  const [formValues, setFormValues] = useState({});
  const [output, setOutput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const outputRef = useRef(null);

  useEffect(() => {
    if (payload?.toolId) {
      fetch(`${API_BASE}/api/kali/tools/${payload.toolId}/schema`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      })
        .then(res => res.json())
        .then(data => {
          if (data && !data.error) {
            setSchema(data);
            const initialValues = {};
            if (data.fields) {
              data.fields.forEach(f => initialValues[f.id] = f.type === 'boolean' ? false : '');
            }
            setFormValues(initialValues);
          }
          setLoading(false);
        })
        .catch(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, [payload]);

  useEffect(() => {
    if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight;
  }, [output]);

  const handleInputChange = (fieldId, value, type) => {
    setFormValues(prev => ({ ...prev, [fieldId]: type === 'boolean' ? !prev[fieldId] : value }));
  };

  const applyPreset = (presetVars) => {
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
    setOutput('');
    setIsRunning(true);
    
    try {
      const response = await fetch(`${API_BASE}/api/kali/tools/${payload.toolId}/run`, {
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
    } catch (e) {
      setOutput("Erro ao conectar com o backend.");
    }
    setIsRunning(false);
  };

  if (loading) return <div className="flex items-center justify-center h-full bg-[#0d1117] text-gray-400" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#8b949e' }}><Loader className="animate-spin mr-2" size={16} /> Carregando...</div>;
  if (!schema) return <div className="p-4 text-red-400" style={{ padding: '16px', color: '#f87171' }}>Schema não encontrado.</div>;

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      {/* Header */}
      <div className="p-4 border-b border-gray-800 bg-[#161b22] flex justify-between items-center" style={{ padding: '16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
            <Zap size={18} className="text-purple-400" color="#a78bfa" /> {schema.name} - Auto Runner
          </h2>
          <p className="text-xs text-gray-500" style={{ fontSize: '12px', color: '#8b949e', marginTop: '4px', margin: 0 }}>{schema.description}</p>
        </div>
        {schema.presets?.length > 0 && (
          <div className="flex gap-2" style={{ display: 'flex', gap: '8px' }}>
            {schema.presets.map((p, i) => (
              <button key={i} onClick={() => applyPreset(p.vars)} 
                      className="px-3 py-1 bg-purple-600/20 text-purple-400 border border-purple-800 rounded text-xs hover:bg-purple-600/30"
                      style={{ padding: '4px 12px', background: 'rgba(167, 139, 250, 0.15)', color: '#a78bfa', border: '1px solid rgba(167, 139, 250, 0.3)', borderRadius: '4px', fontSize: '12px', cursor: 'pointer' }}>
                {p.name}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Form e Console Divididos */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden" style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Formulário (Lado Esquerdo) */}
        <div className="md:w-1/3 p-6 space-y-5 overflow-y-auto border-r border-gray-800" style={{ width: '320px', padding: '20px', overflowY: 'auto', borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column', gap: '16px' }}>
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

        {/* Console de Output (Lado Direito) */}
        <div className="flex-1 flex flex-col bg-black/50" style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'rgba(0,0,0,0.5)' }}>
          <div className="p-2 border-b border-gray-800 flex justify-between items-center bg-[#161b22]" style={{ padding: '10px 16px', borderBottom: '1px solid #30363d', background: '#161b22', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="text-xs text-gray-500 font-mono flex items-center gap-1" style={{ fontSize: '12px', color: '#8b949e', fontFamily: 'monospace', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Terminal size={12} /> {buildCommandPreview()}
            </span>
            <button onClick={handleRun} disabled={isRunning} 
                    className="bg-green-600 hover:bg-green-700 text-white px-4 py-1 rounded text-xs font-bold flex items-center gap-1 disabled:bg-gray-700"
                    style={{ background: isRunning ? '#374151' : '#238636', color: 'white', padding: '6px 16px', borderRadius: '6px', fontSize: '12px', fontWeight: 'bold', border: 'none', cursor: isRunning ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: '6px' }}>
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
