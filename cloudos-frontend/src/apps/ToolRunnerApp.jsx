import { useState, useEffect, useRef } from 'react';
import { Play, Square, Terminal, Settings2, Crosshair, ArrowLeft, Box } from 'lucide-react';

export function ToolRunnerApp({ payload, setPayload, openApp, setBg }) {
  const [toolSchema, setToolSchema] = useState(null);
  const [allTools, setAllTools] = useState([]);
  const [fields, setFields] = useState({});
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [loading, setLoading] = useState(true);
  const readerRef = useRef(null);
  const outputRef = useRef(null);

  const token = localStorage.getItem('cloudos_token');
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` };

  useEffect(() => {
    if (payload?.toolId) {
      fetchSchema(payload.toolId);
    } else {
      fetchAllTools();
    }
  }, [payload]);

  const fetchAllTools = async () => {
    setLoading(true);
    try {
      const res = await fetch('http://localhost:8080/api/kali/tools', { headers });
      if (!res.ok) throw new Error('Falha ao buscar ferramentas');
      const data = await res.json();
      setAllTools(Array.isArray(data) ? data : []);
    } catch (err) {
      console.error(err);
      setAllTools([]);
    } finally {
      setLoading(false);
    }
  };

  const fetchSchema = async (toolId) => {
    setLoading(true);
    try {
      const res = await fetch(`http://localhost:8080/api/kali/tools/${toolId}/schema`, { headers });
      if (!res.ok) throw new Error('Falha ao buscar schema');
      const data = await res.json();
      
      const adaptedFields = (data.fields || []).map(f => ({
        name: f.id || f.name,
        label: f.label || f.name,
        type: f.type === 'boolean' ? 'checkbox' : f.type,
        default: f.default !== undefined ? f.default : (f.type === 'checkbox' ? false : ''),
        options: f.options || [],
        placeholder: f.placeholder || ''
      }));

      setToolSchema({ ...data, fields: adaptedFields });

      const initial = {};
      adaptedFields.forEach(f => { initial[f.name] = f.default; });
      setFields(initial);
      setOutput(`[+] ${data.name} carregado. Configure as opções e clique em Executar.\n`);
    } catch (err) {
      setOutput(`[✗] Erro ao carregar schema: ${err.message}\n`);
    } finally {
      setLoading(false);
    }
  };

  const backToCatalog = () => {
    setToolSchema(null);
    setOutput('');
    if (setPayload) setPayload(null);
    fetchAllTools();
  };

  useEffect(() => {
    if (outputRef.current) outputRef.current.scrollTop = outputRef.current.scrollHeight;
  }, [output]);

  const commandPreview = () => {
    if (!toolSchema?.buildCmd) return toolSchema ? toolSchema.name : '';
    try {
      const { cmd, args } = toolSchema.buildCmd(fields);
      return `${cmd} ${args.join(' ')}`;
    } catch { return toolSchema.name; }
  };

  const handleChange = (name, value) => setFields(prev => ({ ...prev, [name]: value }));

  const runTool = async () => {
    if (running || !toolSchema) return;
    setRunning(true);
    setOutput(prev => prev + `\n[▶] Iniciando execução...\n`);
    
    try {
      const response = await fetch(`http://localhost:8080/api/kali/tools/${toolSchema.id}/run`, {
        method: 'POST', headers,
        body: JSON.stringify({ options: fields })
      });

      if (response.status === 400) {
        const errData = await response.json();
        setOutput(prev => prev + `\n[✗] ${errData.error}\n[DICA] ${errData.installCmd}\n`);
        setRunning(false);
        return;
      }

      if (!response.ok) throw new Error('Falha na requisição');

      const reader = response.body.getReader();
      readerRef.current = reader;
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setOutput(prev => prev + decoder.decode(value, { stream: true }));
      }
      setOutput(prev => prev + `\n[✓] Execução finalizada.\n`);
    } catch (err) {
      setOutput(prev => prev + `\n[✗] Erro: ${err.message}\n`);
    } finally {
      setRunning(false);
      readerRef.current = null;
    }
  };

  const stopTool = async () => {
    if (readerRef.current) {
      await readerRef.current.cancel();
      readerRef.current = null;
    }
    setRunning(false);
    setOutput(prev => prev + `\n[⛔] Execução interrompida pelo usuário.\n`);
  };

  // ──────── VIEW 1: CATÁLOGO DE FERRAMENTAS ────────
  if (!payload?.toolId && !loading) {
    return (
      <div style={{ position: 'absolute', inset: 0, background: '#0d1117', color: '#c9d1d9', overflow: 'auto', padding: '20px' }}>
        <h2 style={{ fontSize: '16px', marginBottom: '6px', display: 'flex', alignItems: 'center', gap: '8px', color: '#f0f6fc' }}>
          <Crosshair size={16} color="#58a6ff" /> Arsenal de Ferramentas
        </h2>
        <p style={{ color: '#8b949e', marginBottom: '20px', fontSize: '12px' }}>Selecione uma ferramenta para configurar e executar.</p>
        
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: '10px' }}>
          {allTools.map(tool => (
            <div 
              key={tool.id} 
              onClick={() => setPayload({ toolId: tool.id })}
              style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '14px', cursor: 'pointer', transition: 'border-color 0.2s' }}
              onMouseEnter={e => e.currentTarget.style.borderColor = '#58a6ff'}
              onMouseLeave={e => e.currentTarget.style.borderColor = '#30363d'}
            >
              <Box size={20} color="#58a6ff" />
              <div style={{ marginTop: '10px', fontWeight: '600', fontSize: '13px', color: '#f0f6fc' }}>{tool.name}</div>
              <div style={{ fontSize: '10px', color: '#8b949e', marginTop: '3px' }}>{tool.category || 'Kali'}</div>
            </div>
          ))}
          {allTools.length === 0 && <div style={{ color: '#8b949e', fontSize: '13px' }}>Nenhuma ferramenta encontrada.</div>}
        </div>
      </div>
    );
  }

  if (loading) {
    return <div style={{ position: 'absolute', inset: 0, display: 'flex', background: '#0d1117', color: '#8b949e', alignItems: 'center', justifyContent: 'center', fontSize: '13px' }}>Carregando...</div>;
  }

  if (!toolSchema) {
    return <div style={{ position: 'absolute', inset: 0, display: 'flex', background: '#0d1117', color: '#f85149', alignItems: 'center', justifyContent: 'center', fontSize: '13px' }}>Erro ao carregar ferramenta.</div>;
  }

  // ──────── VIEW 2: INTERFACE DA FERRAMENTA ────────
  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', background: '#0d1117', color: '#c9d1d9', fontFamily: 'Inter, -apple-system, sans-serif' }}>
      
      {/* HEADER - Fixo no topo */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 12px', background: '#161b22', borderBottom: '1px solid #30363d', flexShrink: 0 }}>
        <button onClick={backToCatalog} style={{ background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '6px', borderRadius: '6px', cursor: 'pointer', display: 'flex', alignItems: 'center' }} title="Voltar">
          <ArrowLeft size={14} />
        </button>
        <div style={{ flex: 1, background: '#010409', border: '1px solid #30363d', borderRadius: '6px', padding: '6px 10px', display: 'flex', alignItems: 'center', gap: '6px', fontFamily: 'monospace', fontSize: '12px', overflow: 'hidden', whiteSpace: 'nowrap', minWidth: 0 }}>
          <span style={{ color: '#3fb950', fontWeight: 'bold' }}>$</span>
          <code style={{ color: '#58a6ff' }}>{commandPreview()}</code>
        </div>
        <div style={{ display: 'flex', gap: '6px', flexShrink: 0 }}>
          {running ? (
            <button onClick={stopTool} style={{ display: 'flex', alignItems: 'center', gap: '5px', padding: '6px 12px', background: '#da3633', border: '1px solid #f85149', borderRadius: '6px', color: '#fff', fontSize: '12px', fontWeight: '600', cursor: 'pointer' }}>
              <Square size={12} fill="#fff" /> Parar
            </button>
          ) : (
            <button onClick={runTool} style={{ display: 'flex', alignItems: 'center', gap: '5px', padding: '6px 12px', background: '#238636', border: '1px solid #2ea043', borderRadius: '6px', color: '#fff', fontSize: '12px', fontWeight: '600', cursor: 'pointer' }}>
              <Play size={12} fill="#fff" /> Executar
            </button>
          )}
        </div>
      </div>

      {/* CORPO - Ocupa todo o espaço restante */}
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        
        {/* PAINEL ESQUERDO - CONFIG */}
        <div style={{ width: '260px', flexShrink: 0, borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column', background: '#0d1117' }}>
          <div style={{ padding: '8px 12px', fontSize: '11px', fontWeight: '600', color: '#8b949e', borderBottom: '1px solid #21262d', textTransform: 'uppercase', letterSpacing: '0.5px', display: 'flex', alignItems: 'center', gap: '5px', flexShrink: 0 }}>
            <Settings2 size={12} /> Opções
          </div>
          <div style={{ padding: '12px', overflowY: 'auto', flex: 1 }}>
            {toolSchema.fields.map(field => (
              <FieldRenderer key={field.name} field={field} value={fields[field.name]} onChange={handleChange} />
            ))}
          </div>
          
          {toolSchema.presets && toolSchema.presets.length > 0 && (
            <div style={{ padding: '10px 12px', borderTop: '1px solid #21262d', flexShrink: 0 }}>
              <div style={{ fontSize: '11px', color: '#8b949e', marginBottom: '6px', fontWeight: '600' }}>Presets</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                {toolSchema.presets.map(preset => (
                  <button 
                    key={preset.name} 
                    style={{ background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '4px 8px', borderRadius: '4px', fontSize: '11px', cursor: 'pointer' }}
                    onClick={() => setFields(prev => ({ ...prev, ...(preset.vars || preset.args) }))}
                  >
                    {preset.name}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* PAINEL DIREITO - TERMINAL OUTPUT */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: '#010409', minWidth: 0 }}>
          <div style={{ padding: '6px 12px', background: '#0d1117', borderBottom: '1px solid #21262d', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: '#8b949e', flexShrink: 0 }}>
            <Terminal size={12} color="#3fb950" /> Output
            {running && <span style={{ color: '#3fb950', fontWeight: '600', marginLeft: '4px' }}>● Executando</span>}
          </div>
          <pre ref={outputRef} style={{ flex: 1, margin: 0, padding: '12px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '12px', lineHeight: '1.5', overflowY: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
            {output || <span style={{ color: '#6e7681' }}>Aguardando execução...</span>}
          </pre>
        </div>
      </div>

      {/* RESPONSIVIDADE */}
      <style>{`
        @media (max-width: 768px) {
          .tool-runner-body { flex-direction: column !important; }
        }
      `}</style>
    </div>
  );
}

// ──────── RENDERER DE CAMPOS ────────
function FieldRenderer({ field, value, onChange }) {
  const labelStyle = { display: 'block', fontSize: '11px', color: '#c9d1d9', marginBottom: '4px', fontWeight: '500' };
  const inputStyle = { width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '5px', padding: '6px 8px', color: '#c9d1d9', fontSize: '12px', outline: 'none', boxSizing: 'border-box' };
  const rowStyle = { marginBottom: '12px' };

  if (field.type === 'checkbox') {
    return (
      <div style={rowStyle}>
        <label style={{ display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', fontSize: '12px' }} onClick={() => onChange(field.name, !value)}>
          <div style={{
            width: '14px', height: '14px', borderRadius: '3px',
            border: value ? '1px solid #2ea043' : '1px solid #30363d',
            background: value ? '#238636' : '#161b22',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0
          }}>
            {value && <span style={{ color: '#fff', fontSize: 9 }}>✔</span>}
          </div>
          {field.label}
        </label>
      </div>
    );
  }

  if (field.type === 'select') {
    return (
      <div style={rowStyle}>
        <label style={labelStyle}>{field.label}</label>
        <select style={{ ...inputStyle, cursor: 'pointer' }} value={value || ''} onChange={e => onChange(field.name, e.target.value)}>
          {(field.options || []).map(opt => <option key={opt} value={opt}>{opt}</option>)}
        </select>
      </div>
    );
  }

  if (field.type === 'textarea') {
    return (
      <div style={rowStyle}>
        <label style={labelStyle}>{field.label}</label>
        <textarea style={{ ...inputStyle, fontFamily: 'monospace', minHeight: '60px', resize: 'vertical' }} placeholder={field.placeholder || ''} value={value || ''} onChange={e => onChange(field.name, e.target.value)} />
      </div>
    );
  }

  return (
    <div style={rowStyle}>
      <label style={labelStyle}>{field.label}</label>
      <input type="text" style={inputStyle} placeholder={field.placeholder || ''} value={value || ''} onChange={e => onChange(field.name, e.target.value)} />
    </div>
  );
}

export default ToolRunnerApp;
