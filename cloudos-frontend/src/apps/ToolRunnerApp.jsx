import { useState, useEffect, useRef } from 'react';
import { Play, Square, Terminal, Settings2, ArrowLeft, Search, Radar, Globe, Bug, KeyRound, LayoutGrid, Loader } from 'lucide-react';

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

export function ToolRunnerApp({ payload, setPayload, toolSchema, activeProject }) {
  const [schema, setSchema] = useState(null);
  const [loading, setLoading] = useState(false);
  const [fields, setFields] = useState({});
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [activeCat, setActiveCat] = useState('all');
  const [search, setSearch] = useState('');
  const readerRef = useRef(null);
  const outputEndRef = useRef(null);

  const currentToolId = payload?.toolId || toolSchema?.id;

  // Carrega o schema da API se toolSchema não foi passado diretamente
  useEffect(() => {
    if (toolSchema) {
      setSchema(toolSchema);
      initFieldsFromSchema(toolSchema);
    } else if (currentToolId) {
      setLoading(true);
      fetch(`${API_BASE}/api/kali/tools/${currentToolId}/schema`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      })
        .then(res => res.json())
        .then(data => {
          if (data.error) {
            setSchema(null);
          } else {
            // Adapta schema da API se necessário para garantir compatibilidade
            const adapted = {
              id: data.id,
              name: data.name,
              description: data.description,
              presets: data.presets?.map(p => ({ name: p.name, args: p.vars })) || [],
              fields: data.fields.map(f => ({
                name: f.id,
                label: f.label,
                type: f.type === 'boolean' ? 'checkbox' : f.type,
                default: f.default,
                options: f.options,
                placeholder: f.placeholder,
                flag: f.flag,
                required: f.required
              })),
              buildCmd: (fieldsVal) => {
                let cmd = data.command;
                const args = [];
                data.fields.forEach(field => {
                  const val = fieldsVal[field.id];
                  if (!val) return;
                  if (field.type === 'boolean' && val === true) {
                    if (field.flag) args.push(field.flag);
                  } else if (val) {
                    if (field.flag) args.push(`${field.flag} ${val}`);
                    else args.push(val);
                  }
                });
                return { cmd, args };
              }
            };
            setSchema(adapted);
            initFieldsFromSchema(adapted);
          }
          setLoading(false);
        })
        .catch(() => setLoading(false));
    } else {
      setSchema(null);
    }
  }, [currentToolId, toolSchema]);

  const initFieldsFromSchema = (s) => {
    const initial = {};
    if (s && s.fields) {
      s.fields.forEach(f => {
        initial[f.name] = f.default !== undefined ? f.default : (f.type === 'checkbox' ? false : '');
      });
    }
    setFields(initial);
    setOutput(`[+] ${s.name} carregado. Configure as opções e clique em Executar.\n`);
  };

  useEffect(() => {
    outputEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [output]);

  // Constrói o comando em tempo real para preview
  const commandPreview = () => {
    if (!schema) return '';
    if (schema.buildCmd) {
      try {
        const { cmd, args } = schema.buildCmd(fields);
        return `${cmd} ${(args || []).join(' ')}`;
      } catch (e) {
        return '';
      }
    }
    return '';
  };

  const handleChange = (name, value) => {
    setFields(prev => ({ ...prev, [name]: value }));
  };

  const runTool = async () => {
    if (running || !schema) return;
    setRunning(true);
    setOutput(prev => prev + `\n[▶] Iniciando execução de ${schema.name}...\n`);

    try {
      const response = await fetch(`${API_BASE}/api/kali/tools/${schema.id}/run`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token()}`
        },
        body: JSON.stringify({ options: fields, fields })
      });

      if (!response.ok) {
        if (response.status === 400) {
          const errData = await response.json();
          setOutput(prev => prev + `\n[✗] Erro: ${errData.error}\n[DICA] Instale executando: ${errData.installCmd}\n`);
          setRunning(false);
          return;
        }
        throw new Error('Falha na requisição HTTP (' + response.status + ')');
      }

      const reader = response.body.getReader();
      readerRef.current = reader;
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setOutput(prev => prev + decoder.decode(value, { stream: true }));
      }
      setOutput(prev => prev + `\n[✓] Execução finalizada com sucesso.\n`);
    } catch (err) {
      setOutput(prev => prev + `\n[✗] Erro ao executar ferramenta: ${err.message}\n`);
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

  const backToSelection = () => {
    if (setPayload) setPayload(null);
    setSchema(null);
  };

  // TELA DE SELEÇÃO DE FERRAMENTAS (Se não houver ferramenta aberta)
  if (!currentToolId && !schema) {
    const filteredTools = AVAILABLE_TOOLS.filter(t => 
      (activeCat === 'all' || t.category === activeCat) &&
      (t.name.toLowerCase().includes(search.toLowerCase()) || t.desc.toLowerCase().includes(search.toLowerCase()))
    );

    return (
      <div style={styles.container}>
        <div style={{ display: 'flex', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
          {/* Sidebar de Categorias */}
          <div style={{ width: '200px', background: '#161b22', borderRight: '1px solid #30363d', padding: '12px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
            <h2 style={{ fontSize: '11px', textTransform: 'uppercase', color: '#8b949e', padding: '0 8px', marginBottom: '8px', letterSpacing: '0.5px' }}>Categorias</h2>
            {CATEGORIES.map(cat => (
              <div 
                key={cat.id} 
                onClick={() => setActiveCat(cat.id)} 
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  padding: '8px 10px', 
                  borderRadius: '6px', 
                  cursor: 'pointer', 
                  fontSize: '13px', 
                  background: activeCat === cat.id ? 'rgba(56, 139, 253, 0.15)' : 'transparent', 
                  color: activeCat === cat.id ? '#58a6ff' : '#c9d1d9',
                  border: activeCat === cat.id ? '1px solid rgba(56, 139, 253, 0.3)' : '1px solid transparent'
                }}
              >
                <cat.icon size={14} /> {cat.name}
              </div>
            ))}
          </div>

          {/* Lista de Ferramentas */}
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '20px' }}>
            <div style={{ position: 'relative', marginBottom: '16px' }}>
              <Search size={14} style={{ position: 'absolute', left: '12px', top: '11px', color: '#8b949e' }} />
              <input 
                value={search} 
                onChange={(e) => setSearch(e.target.value)} 
                placeholder="Buscar ferramenta no arsenal..." 
                style={{ width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '8px 12px 8px 34px', fontSize: '13px', color: 'white', outline: 'none', boxSizing: 'border-box' }} 
              />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '12px', flex: 1, overflowY: 'auto' }}>
              {filteredTools.map(tool => (
                <div 
                  key={tool.id} 
                  onClick={() => setPayload ? setPayload({ toolId: tool.id }) : setSchema({ id: tool.id, name: tool.name, fields: [] })} 
                  style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: '8px', padding: '14px', cursor: 'pointer', display: 'flex', flexDirection: 'column', transition: 'border-color 0.2s' }}
                >
                  <h3 style={{ fontSize: '14px', fontWeight: '600', color: '#f0f6fc', margin: 0 }}>{tool.name}</h3>
                  <p style={{ fontSize: '12px', color: '#8b949e', marginTop: '6px', flex: 1, margin: '6px 0 0 0' }}>{tool.desc}</p>
                  <span style={{ marginTop: '12px', fontSize: '10px', textTransform: 'uppercase', color: '#8b949e', background: '#21262d', padding: '2px 8px', borderRadius: '12px', width: 'fit-content' }}>{tool.category}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    );
  }

  // TELA DE CARREGAMENTO DE SCHEMA
  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', background: '#0d1117', color: '#8b949e', gap: '8px', fontSize: '14px' }}>
        <Loader size={18} style={{ animation: 'spin 1s linear infinite' }} /> Carregando módulo...
      </div>
    );
  }

  // TELA PRINCIPAL (IDE / BURP SUITE STYLE)
  return (
    <div style={styles.container}>
      {/* HEADER COM BOTÃO VOLTAR, COMANDO E AÇÕES */}
      <div style={styles.header}>
        {setPayload && (
          <button onClick={backToSelection} style={{ background: 'transparent', border: 'none', color: '#8b949e', cursor: 'pointer', display: 'flex', alignItems: 'center', padding: '4px' }}>
            <ArrowLeft size={16} />
          </button>
        )}
        <div style={styles.cmdBox}>
          <span style={styles.cmdPrefix}>$</span>
          <code style={styles.cmdText}>{commandPreview() || (schema ? schema.name : 'Configurando...')}</code>
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
      <div style={styles.contentWrapper}>
        {/* PAINEL ESQUERDA - CONFIG */}
        <div style={styles.configPanel}>
          <div style={styles.panelHeader}>
            <Settings2 size={14} /> Opções - {schema?.name}
          </div>
          <div style={styles.fieldsContainer}>
            {schema?.fields && schema.fields.map(field => (
              <FieldRenderer key={field.name} field={field} value={fields[field.name]} onChange={handleChange} />
            ))}
          </div>
          
          {schema?.presets && schema.presets.length > 0 && (
            <div style={styles.presetsContainer}>
              <div style={styles.presetsTitle}>Presets Rápidos</div>
              {schema.presets.map(preset => (
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
        <div style={styles.outputPanel}>
          <div style={styles.outputHeader}>
            <Terminal size={14} color="#3fb950" /> Terminal Virtual Output
            {running && <span style={styles.runningBadge}>● Executando</span>}
          </div>
          <pre style={styles.terminal}>
            {output}
            <div ref={outputEndRef} />
          </pre>
        </div>
      </div>

      <style>{`
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        @media (max-width: 768px) {
          .tool-runner-content { flex-direction: column !important; }
          .tool-runner-config { width: 100% !important; max-height: 40vh; border-right: none !important; border-bottom: 1px solid #30363d !important; }
          .tool-runner-output { width: 100% !important; }
        }
      `}</style>
    </div>
  );
}

function FieldRenderer({ field, value, onChange }) {
  if (field.type === 'checkbox') {
    return (
      <div style={styles.fieldRow} onClick={() => onChange(field.name, !value)}>
        <label style={styles.checkboxLabel}>
          <input 
            type="checkbox" 
            checked={!!value} 
            onChange={(e) => onChange(field.name, e.target.checked)}
            style={{ display: 'none' }}
          />
          <div style={value ? styles.checkboxBoxChecked : styles.checkboxBox}>
            {value && <span style={{ color: '#fff', fontSize: 10 }}>✔</span>}
          </div>
          {field.label}
        </label>
      </div>
    );
  }

  if (field.type === 'select') {
    return (
      <div style={styles.fieldRow}>
        <label style={styles.label}>{field.label}</label>
        <select 
          style={styles.select} 
          value={value || ''} 
          onChange={(e) => onChange(field.name, e.target.value)}
        >
          {(field.options || []).map(opt => <option key={opt} value={opt}>{opt}</option>)}
        </select>
      </div>
    );
  }

  if (field.type === 'range') {
    return (
      <div style={styles.fieldRow}>
        <label style={styles.label}>{field.label}: <span style={{color: '#58a6ff'}}>{value}</span></label>
        <input 
          type="range" 
          min={field.min || 0} 
          max={field.max || 5} 
          value={value || 0} 
          onChange={(e) => onChange(field.name, e.target.value)}
          style={styles.rangeInput}
        />
      </div>
    );
  }

  return (
    <div style={styles.fieldRow}>
      <label style={styles.label}>{field.label}</label>
      <input 
        type="text" 
        style={styles.textInput} 
        placeholder={field.placeholder || ''} 
        value={value || ''} 
        onChange={(e) => onChange(field.name, e.target.value)}
      />
    </div>
  );
}

const styles = {
  container: { display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9', fontFamily: 'Inter, -apple-system, sans-serif' },
  header: { padding: '10px 14px', borderBottom: '1px solid #30363d', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '12px', background: '#161b22' },
  cmdBox: { flex: 1, background: '#010409', border: '1px solid #30363d', borderRadius: '6px', padding: '6px 12px', display: 'flex', alignItems: 'center', gap: '8px', fontFamily: 'monospace', fontSize: '13px', overflowX: 'auto', whiteSpace: 'nowrap' },
  cmdPrefix: { color: '#3fb950', fontWeight: 'bold' },
  cmdText: { color: '#58a6ff' },
  actionBtns: { display: 'flex', gap: '8px' },
  btn: { display: 'flex', alignItems: 'center', gap: '6px', padding: '6px 14px', border: '1px solid transparent', borderRadius: '6px', color: '#fff', fontSize: '13px', fontWeight: '600', cursor: 'pointer' },
  btnSuccess: { background: '#238636', borderColor: '#2ea043' },
  btnDanger: { background: '#da3633', borderColor: '#f85149' },
  contentWrapper: { flex: 1, display: 'flex', overflow: 'hidden' },
  configPanel: { width: '300px', borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column', background: '#0d1117' },
  panelHeader: { padding: '10px 14px', fontSize: '12px', fontWeight: '600', color: '#8b949e', borderBottom: '1px solid #21262d', textTransform: 'uppercase', letterSpacing: '0.5px', display: 'flex', alignItems: 'center', gap: '6px' },
  fieldsContainer: { padding: '14px', overflowY: 'auto', flex: 1 },
  fieldRow: { marginBottom: '14px' },
  label: { display: 'block', fontSize: '12px', color: '#c9d1d9', marginBottom: '6px', fontWeight: '500' },
  textInput: { width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '7px 10px', color: '#c9d1d9', fontSize: '13px', outline: 'none', boxSizing: 'border-box' },
  select: { width: '100%', background: '#161b22', border: '1px solid #30363d', borderRadius: '6px', padding: '7px 10px', color: '#c9d1d9', fontSize: '13px', outline: 'none', cursor: 'pointer' },
  checkboxLabel: { display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '13px' },
  checkboxBox: { width: '16px', height: '16px', borderRadius: '4px', border: '1px solid #30363d', background: '#161b22', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  checkboxBoxChecked: { width: '16px', height: '16px', borderRadius: '4px', border: '1px solid #2ea043', background: '#238636', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  rangeInput: { width: '100%', accentColor: '#58a6ff', cursor: 'pointer' },
  presetsContainer: { padding: '14px', borderTop: '1px solid #21262d' },
  presetsTitle: { fontSize: '12px', color: '#8b949e', marginBottom: '8px', fontWeight: '600' },
  presetBtn: { background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '5px 10px', borderRadius: '6px', fontSize: '12px', cursor: 'pointer', marginRight: '6px', marginBottom: '6px' },
  outputPanel: { flex: 1, display: 'flex', flexDirection: 'column', background: '#010409' },
  outputHeader: { padding: '8px 14px', background: '#0d1117', borderBottom: '1px solid #21262d', display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: '#8b949e' },
  runningBadge: { color: '#3fb950', fontWeight: '600' },
  terminal: { flex: 1, margin: '0', padding: '14px', color: '#c9d1d9', fontFamily: 'monospace', fontSize: '13px', lineHeight: '1.5', overflowY: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }
};

export default ToolRunnerApp;
