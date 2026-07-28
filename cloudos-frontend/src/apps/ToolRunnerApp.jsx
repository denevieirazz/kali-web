import { useState, useEffect } from 'react';
import { Play, Terminal as TermIcon, Loader, AlertCircle } from 'lucide-react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const ToolRunnerApp = ({ payload, openApp }) => {
  const [schema, setSchema] = useState(null);
  const [loading, setLoading] = useState(true);
  const [formValues, setFormValues] = useState({});

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
              data.fields.forEach(f => {
                initialValues[f.id] = f.type === 'boolean' ? false : '';
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
  }, [payload]);

  const handleInputChange = (fieldId, value, type) => {
    setFormValues(prev => ({ ...prev, [fieldId]: type === 'boolean' ? !prev[fieldId] : value }));
  };

  const buildCommand = () => {
    if (!schema) return '';
    let cmd = schema.command;
    
    if (schema.fields) {
      schema.fields.forEach(field => {
        const val = formValues[field.id];
        if (val === undefined || val === '' || val === false) return;

        if (field.type === 'boolean' && val === true) {
          cmd += ` ${field.flag}`;
        } else if (field.type === 'text' || field.type === 'select') {
          if (field.flag) {
            cmd += ` ${field.flag} ${val}`;
          } else {
            cmd += ` ${val}`;
          }
        }
      });
    }
    
    return cmd;
  };

  const handleExecute = () => {
    const finalCmd = buildCommand();
    openApp('terminal', { tool: finalCmd });
  };

  if (loading) return <div className="flex items-center justify-center h-full bg-[#0d1117] text-gray-400"><Loader className="animate-spin mr-2" size={16} /> Carregando interface...</div>;
  if (!schema) return <div className="p-4 text-red-400">Erro: Schema não encontrado.</div>;

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300" style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      {/* Header da Ferramenta */}
      <div className="p-4 border-b border-gray-800 bg-[#161b22]" style={{ padding: '16px', borderBottom: '1px solid #30363d', background: '#161b22' }}>
        <h2 className="text-lg font-bold text-white flex items-center gap-2" style={{ fontSize: '18px', fontWeight: 'bold', color: 'white', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
          <TermIcon size={18} className="text-blue-400" color="#58a6ff" /> {schema.name} - GUI Interface
        </h2>
        <p className="text-xs text-gray-500 mt-1" style={{ fontSize: '12px', color: '#8b949e', marginTop: '4px' }}>{schema.description}</p>
      </div>

      {/* Formulário Dinâmico */}
      <div className="flex-1 overflow-y-auto p-6 space-y-5" style={{ flex: 1, overflowY: 'auto', padding: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
        {schema.fields && schema.fields.map(field => (
          <div key={field.id} className="flex flex-col gap-2" style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            <label className="text-sm font-medium text-gray-400 flex items-center gap-2" style={{ fontSize: '14px', color: '#8b949e', display: 'flex', alignItems: 'center', gap: '8px' }}>
              {field.label}
              {field.required && <span className="text-red-400 text-xs" style={{ color: '#f87171', fontSize: '12px' }}>*</span>}
            </label>
            
            {field.type === 'text' && (
              <input 
                type="text" 
                placeholder={field.placeholder || ''} 
                value={formValues[field.id] || ''} 
                onChange={(e) => handleInputChange(field.id, e.target.value, 'text')}
                className="bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white"
                style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '14px', color: 'white', outline: 'none' }}
              />
            )}
            
            {field.type === 'select' && (
              <select 
                value={formValues[field.id] || ''} 
                onChange={(e) => handleInputChange(field.id, e.target.value, 'select')}
                className="bg-[#161b22] border border-gray-700 rounded-md px-3 py-2 text-sm focus:border-blue-500 outline-none text-white"
                style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontSize: '14px', color: 'white', outline: 'none' }}
              >
                <option value="">Selecione...</option>
                {field.options && field.options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
              </select>
            )}
            
            {field.type === 'boolean' && (
              <label className="inline-flex items-center cursor-pointer" style={{ display: 'inline-flex', alignItems: 'center', cursor: 'pointer' }}>
                <input 
                  type="checkbox" 
                  checked={formValues[field.id] || false} 
                  onChange={(e) => handleInputChange(field.id, e.target.value, 'boolean')} 
                  style={{ width: '18px', height: '18px', cursor: 'pointer' }}
                />
                <span style={{ marginLeft: '8px', fontSize: '14px', color: '#c9d1d9' }}>{field.label}</span>
              </label>
            )}
          </div>
        ))}
      </div>

      {/* Footer de Execução (Visualizador de Comando) */}
      <div className="p-4 border-t border-gray-800 bg-[#161b22]" style={{ padding: '16px', borderTop: '1px solid #30363d', background: '#161b22' }}>
        <div className="mb-3" style={{ marginBottom: '12px' }}>
          <div className="text-xs text-gray-500 mb-1" style={{ fontSize: '12px', color: '#8b949e', marginBottom: '4px' }}>Comando gerado:</div>
          <div className="bg-black/50 border border-gray-800 rounded-md p-2 font-mono text-sm text-green-400 overflow-x-auto whitespace-nowrap" style={{ background: '#0a0a0a', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', fontFamily: 'monospace', fontSize: '14px', color: '#4ade80', overflowX: 'auto', whitespace: 'nowrap' }}>
            <span style={{ color: '#8b949e' }}>$</span> {buildCommand()}
          </div>
        </div>
        
        <div className="flex items-center gap-2 text-xs text-yellow-500 mb-3" style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: '#eab308', marginBottom: '12px' }}>
          <AlertCircle size={14} /> 
          <span>O comando será enviado ao terminal. Pressione Enter para executar.</span>
        </div>

        <button 
          onClick={handleExecute} 
          className="w-full bg-blue-600 hover:bg-blue-700 text-white py-2.5 rounded-md font-bold flex items-center justify-center gap-2 transition-colors"
          style={{ width: '100%', background: '#1f6feb', color: 'white', padding: '10px 0', borderRadius: '6px', fontWeight: 'bold', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
        >
          <Play size={16} /> Enviar para Terminal
        </button>
      </div>
    </div>
  );
};
