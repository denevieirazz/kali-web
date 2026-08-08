import { useState, useEffect, useRef } from 'react';
import { Play, Square, Terminal, Settings2, Crosshair, ArrowLeft, Box, AlertTriangle } from 'lucide-react';
import { useCloudOS } from '../store/CloudOSContext';

export function ToolRunnerApp({ payload, setPayload, openApp, setBg }) {
  const { activeProject } = useCloudOS();
  const [toolSchema, setToolSchema] = useState(null);
  const [allTools, setAllTools] = useState([]);
  const [fields, setFields] = useState({});
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const readerRef = useRef(null);
  const outputEndRef = useRef(null);

  const token = localStorage.getItem('cloudos_token');
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` };

  // 1. Lógica de Inicialização
  useEffect(() => {
    if (payload?.toolId) {
      fetchSchema(payload.toolId);
    } else {
      fetchAllTools();
    }
  }, [payload]);

  // Busca todas as ferramentas para o Catálogo
  const fetchAllTools = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('http://localhost:8080/api/kali/tools', { headers });
      if (!res.ok) throw new Error('Falha ao buscar ferramentas');
      const data = await res.json();
      setAllTools(Array.isArray(data) ? data : []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  // Busca o schema de uma ferramenta específica
  const fetchSchema = async (toolId) => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`http://localhost:8080/api/kali/tools/${toolId}/schema`, { headers });
      if (!res.ok) throw new Error(`Ferramenta '${toolId}' não encontrada no backend.`);
      
      const data = await res.json();
      
      // Adaptação Dinâmica de Schema (API -> React)
      const adaptedFields = (data.fields || []).map(f => ({
        name: f.id || f.name,
        label: f.label || f.name,
        type: f.type === 'boolean' ? 'checkbox' : f.type,
        default: f.default !== undefined ? f.default : (f.type === 'checkbox' ? false : ''),
        options: f.options || [],
        placeholder: f.placeholder || '',
        description: f.description || ''
      }));

      // CORREÇÃO: Força a inclusão do id no schema
      setToolSchema({ ...data, id: toolId, fields: adaptedFields });

      const initial = {};
      adaptedFields.forEach(f => { initial[f.name] = f.default; });
      setFields(initial);
      setOutput(`[+] ${data.name} carregado. Configure as opções e clique em Executar.\n`);
    } catch (err) {
      setError(err.message);
      setOutput(`[✗] Erro: ${err.message}\n`);
    } finally {
      setLoading(false);
    }
  };

  // Volta para o catálogo
  const backToCatalog = () => {
    setToolSchema(null);
    setOutput('');
    setError(null);
    if (setPayload) setPayload({ toolId: null });
    fetchAllTools();
  };

  useEffect(() => {
    outputEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [output]);

  const commandPreview = () => {
    if (!toolSchema?.buildCmd) return toolSchema ? toolSchema.name : '';
    try {
      const { cmd, args } = toolSchema.buildCmd(fields);
      return `${cmd} ${args.join(' ')}`;
    } catch {
      return toolSchema.name;
    }
  };

  const handleChange = (name, value) => setFields(prev => ({ ...prev, [name]: value }));

  const runTool = async () => {
    if (running || !toolSchema) return;
    setRunning(true);
    setOutput(prev => prev + `\n[▶] Iniciando execução...\n`);
    
    try {
      const response = await fetch(`http://localhost:8080/api/kali/tools/${toolSchema.id}/run`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ 
          options: fields,
          projectId: activeProject?.id || null 
        })
      });

      if (!response.ok) throw new Error('Falha na requisição de execução');

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
      setRunning(false);
      setOutput(prev => prev + `\n[⛔] Execução interrompida pelo usuário.\n`);
    }
  };

  // VIEW 1: CATÁLOGO DE FERRAMENTAS
  if (!payload?.toolId && !loading) {
    return (
      <div style={{ position: 'absolute', inset: 0, padding: '24px', background: '#0d1117', color: '#c9d1d9', overflowY: 'auto' }}>
        <h2 style={{ fontSize: '18px', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Crosshair size={18} color="#58a6ff" /> Central de Ferramentas
        </h2>
        <p style={{ color: '#8b949e', marginBottom: '24px', fontSize: '13px' }}>Selecione uma ferramenta para configurar e executar.</p>
        
        {error && <div style={{ color: '#f85149', marginBottom: 16 }}>{error}</div>}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '12px' }}>
          {allTools.map(tool => (
            <div 
              key={tool.id} 
              onClick={() => setPayload ? setPayload({ toolId: tool.id }) : fetchSchema(tool.id)}
              style={{
                background: '#161b22',
                border: '1px solid #30363d',
                borderRadius: '8px',
                padding: '16px',
                cursor: 'pointer',
                transition: 'all 0.2s',
              }}
              onMouseEnter={(e) => e.currentTarget.style.borderColor = '#58a6ff'}
              onMouseLeave={(e) => e.currentTarget.style.borderColor = '#30363d'}
            >
              <Box size={24} color="#58a6ff" />
              <div style={{ marginTop: '12px', fontWeight: '600', fontSize: '14px' }}>{tool.name}</div>
              <div style={{ fontSize: '11px', color: '#8b949e', marginTop: '4px' }}>{tool.category || 'Kali Tool'}</div>
            </div>
          ))}
          {allTools.length === 0 && !error && <div style={{ color: '#8b949e' }}>Nenhuma ferramenta instalada.</div>}
        </div>
      </div>
    );
  }

  if (loading) {
    return <div style={{ position: 'absolute', inset: 0, display: 'flex', background: '#0d1117', color: '#8b949e', alignItems: 'center', justifyContent: 'center' }}>Carregando ferramenta...</div>;
  }

  if (error && !toolSchema) {
    return (
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', gap: '16px', background: '#0d1117', color: '#f85149', alignItems: 'center', justifyContent: 'center', padding: 24, textAlign: 'center' }}>
        <AlertTriangle size={32} />
        <div style={{ fontWeight: 600 }}>{error}</div>
        <button onClick={backToCatalog} style={{ background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '8px 16px', borderRadius: 6, cursor: 'pointer' }}>
          Voltar ao Catálogo
        </button>
      </div>
    );
  }

  if (!toolSchema) {
    return <div style={{ position: 'absolute', inset: 0, display: 'flex', background: '#0d1117', color: '#f85149', alignItems: 'center', justifyContent: 'center' }}>Erro ao carregar ferramenta.</div>;
  }

  // VIEW 2: INTERFACE DA FERRAMENTA
  return (
    <div style={styles.container}>
      {/* HEADER */}
      <div className="tool-runner-header" style={styles.header}>
        <button style={styles.backBtn} onClick={backToCatalog} title="Voltar ao catálogo">
          <ArrowLeft size={16} />
        </button>
        <div style={styles.cmdBox}>
          <span style={styles.cmdPrefix}>$</span>
          <code style={styles.cmdText}>{commandPreview()}</code>
        </div>
        <div style={styles.actionBtns}>
          {running ? (
            <button style={{...styles.btn, ...styles.btnDanger}} onClick={stopTool}>
              <Square size={14} fill="#fff" /> Parar
            </button>
          ) : (
            <button style={{...styles.btn, ...styles.btnSuccess}} onClick={runTool}>
              <Play size={14} fill="#fff" /> Executar
            </button>
          )}
        </div>
      </div>

      {/* CONTEÚDO DIVIDIDO */}
      <div className="tool-runner-content" style={styles.contentWrapper}>
        
        {/* PAINEL ESQUERDA - CONFIG */}
        <div className="tool-runner-config" style={styles.configPanel}>
          <div style={styles.panelHeader}>
            <Settings2 size={14} /> Configurações
          </div>
          <div style={styles.fieldsContainer}>
            {toolSchema.fields.map(field => (
              <FieldRenderer key={field.name} field={field} value={fields[field.name]} onChange={handleChange} />
            ))}
          </div>
          
          {toolSchema.presets && toolSchema.presets.length > 0 && (
            <div style={styles.presetsContainer}>
              <div style={styles.presetsTitle}>Presets Rápidos</div>
              {toolSchema.presets.map(preset => (
                <button 
                  key={preset.name} 
                  style={styles.presetBtn}
                  onClick={() => setFields(prev => ({ ...prev, ...preset.args }))}
                >
                  {preset.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* PAINEL DIREITA - OUTPUT */}
        <div className="tool-runner-output" style={styles.outputPanel}>
          <div style={styles.outputHeader}>
            <Terminal size={14} color="#3fb950" /> Output
            {running && <span style={styles.runningBadge}>● Rodando</span>}
          </div>
          <pre style={styles.terminal}>
            {output}
            <div ref={outputEndRef} />
          </pre>
        </div>
      </div>

      {/* CSS RESPONSIVO */}
      <style>{`
        .tool-runner-content { flex-direction: row; }
        @media (max-width: 768px) {
          .tool-runner-content { flex-direction: column !important; }
          .tool-runner-config { width: 100% !important; max-height: 40vh; border-right: none !important; border-bottom: 1px solid #30363d !important; }
          .tool-runner-output { width: 100% !important; }
          .tool-runner-header { flex-wrap: wrap; }
        }
      `}</style>
    </div>
  );
}

// Renderer de Campos
function FieldRenderer({ field, value, onChange }) {
  if (field.type === 'checkbox') {
    return (
      <div style={styles.fieldRow} onClick={() => onChange(field.name, !value)}>
        <label style={styles.checkboxLabel}>
          <input type="checkbox" checked={!!value} onChange={(e) => onChange(field.name, e.target.checked)} style={{ display: 'none' }} />
          <div style={value ? styles.checkboxBoxChecked : styles.checkboxBox}>
            {value && <span style={{ color: '#fff', fontSize: 10 }}>✔</span>}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span>{field.label}</span>
            {field.description && <span style={styles.fieldDesc}>{field.description}</span>}
          </div>
        </label>
      </div>
    );
  }

  if (field.type === 'select') {
    return (
      <div style={styles.fieldRow}>
        <label style={styles.label}>{field.label}</label>
        {field.description && <span style={styles.fieldDescBlock}>{field.description}</span>}
        <select style={styles.select} value={value || ''} onChange={(e) => onChange(field.name, e.target.value)}>
          {field.options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
        </select>
      </div>
    );
  }

  if (field.type === 'range') {
    return (
      <div style={styles.fieldRow}>
        <label style={styles.label}>{field.label}: <span style={{color: '#58a6ff'}}>{value}</span></label>
        {field.description && <span style={styles.fieldDescBlock}>{field.description}</span>}
        <input type="range" min={field.min || 0} max={field.max || 5} value={value || 0} onChange={(e) => onChange(field.name, e.target.value)} style={styles.rangeInput} />
      </div>
    );
  }

  return (
    <div style={styles.fieldRow}>
      <label style={styles.label}>{field.label}</label>
      {field.description && <span style={styles.fieldDescBlock}>{field.description}</span>}
      <input type="text" style={styles.textInput} placeholder={field.placeholder || ''} value={value || ''} onChange={(e) => onChange(field.name, e.target.value)} />
    </div>
  );
}

export default ToolRunnerApp;

// ESTILOS
const styles = {
  container: { position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', background: '#0d1117', color: '#c9d1d9', fontFamily: 'Inter, sans-serif' },
  header: { padding: '12px 16px', borderBottom: '1px solid #30363d', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '12px', background: '#161b22', flexShrink: 0 },
  backBtn: { background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '8px', borderRadius: '6px', cursor: 'pointer', display: 'flex', alignItems: 'center' },
  cmdBox: { flex: 1, background: '#010409', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px', display: 'flex', alignItems: 'center', gap: '8px', fontFamily: 'JetBrains Mono, monospace', fontSize: '13px', overflowX: 'auto', whiteSpace: 'nowrap', minWidth: 0 },
  cmdPrefix: { color: '#3fb950', fontWeight: 'bold' },
  cmdText: { color: '#58a6ff' },
  actionBtns: { display: 'flex', gap: '8px', flexShrink: 0 },
  btn: { display: 'flex', alignItems: 'center', gap: '6px', padding: '8px 16px', border: '1px solid transparent', borderRadius: '6px', color: '#fff', fontSize: '13px', fontWeight: '600', cursor: 'pointer' },
  btnSuccess: { background: '#238636', borderColor: '#2ea043' },
  btnDanger: { background: '#da3633', borderColor: '#f85149' },
  contentWrapper: { flex: 1, display: 'flex', overflow: 'hidden', minWidth: 0, minHeight: 0 },
  configPanel: { width: '280px', borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column', background: '#0d1117', flexShrink: 0 },
  panelHeader: { padding: '10px 16px', fontSize: '12px', fontWeight: '600', color: '#8b949e', borderBottom: '1px solid #21262d', textTransform: 'uppercase', letterSpacing: '0.5px', display: 'flex', alignItems: 'center', gap: '6px' },
  fieldsContainer: { padding: '16px', overflowY: 'auto', flex: 1 },
  fieldRow: { marginBottom: '16px' },
  label: { display: 'block', fontSize: '12px', color: '#c9d1d9', marginBottom: '6px', fontWeight: '500' },
  textInput: { width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 10px', color: '#c9d1d9', fontSize: '13px', outline: 'none', boxSizing: 'border-box' },
  select: { width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 10px', color: '#c9d1d9', fontSize: '13px', outline: 'none', cursor: 'pointer' },
  checkboxLabel: { display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '13px' },
  checkboxBox: { width: '16px', height: '16px', borderRadius: '4px', border: '1px solid #30363d', background: '#161b22', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  checkboxBoxChecked: { width: '16px', height: '16px', borderRadius: '4px', border: '1px solid #2ea043', background: '#238636', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  rangeInput: { width: '100%', accentColor: '#58a6ff', cursor: 'pointer' },
  presetsContainer: { padding: '16px', borderTop: '1px solid #21262d' },
  presetsTitle: { fontSize: '12px', color: '#8b949e', marginBottom: '8px', fontWeight: '600' },
  presetBtn: { background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '6px 10px', borderRadius: '6px', fontSize: '12px', cursor: 'pointer', marginRight: '8px', marginBottom: '8px' },
  outputPanel: { flex: 1, display: 'flex', flexDirection: 'column', background: '#010409', minWidth: 0, minHeight: 0 },
  outputHeader: { padding: '8px 16px', background: '#0d1117', borderBottom: '1px solid #21262d', display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: '#8b949e' },
  runningBadge: { color: '#3fb950', fontWeight: '600' },
  terminal: { flex: 1, margin: '0', padding: '16px', color: '#c9d1d9', fontFamily: 'JetBrains Mono, monospace', fontSize: '13px', lineHeight: '1.5', overflowY: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word' },
  fieldDesc: { fontSize: '11px', color: '#8b949e', marginTop: '2px', display: 'block' },
  fieldDescBlock: { fontSize: '11px', color: '#8b949e', marginBottom: '6px', display: 'block' }
};
