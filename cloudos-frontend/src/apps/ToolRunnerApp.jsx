import { useState, useEffect, useRef } from 'react';
import { Play, Square, Terminal, Settings2, Crosshair } from 'lucide-react';

export default function ToolRunnerApp({ toolSchema, activeProject }) {
  // Estado inicial baseado no schema
  const [fields, setFields] = useState({});
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const [activeTab, setActiveTab] = useState('options'); // 'options' | 'output'
  const readerRef = useRef(null);
  const outputEndRef = useRef(null);

  useEffect(() => {
    // Inicializa fields com defaults do schema
    const initial = {};
    toolSchema.fields.forEach(f => {
      initial[f.name] = f.default !== undefined ? f.default : (f.type === 'checkbox' ? false : '');
    });
    setFields(initial);
    setOutput(`[+] ${toolSchema.name} carregado. Configure as opções e clique em Executar.\n`);
  }, [toolSchema]);

  useEffect(() => {
    // Auto-scroll terminal
    outputEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [output]);

  // Constrói o comando em tempo real para preview
  const commandPreview = () => {
    if (!toolSchema.buildCmd) return '';
    const { cmd, args } = toolSchema.buildCmd(fields);
    return `${cmd} ${args.join(' ')}`;
  };

  const handleChange = (name, value) => {
    setFields(prev => ({ ...prev, [name]: value }));
  };

  const runTool = async () => {
    if (running) return;
    setRunning(true);
    setOutput(prev => prev + `\n[▶] Iniciando execução...\n`);
    setActiveTab('output');

    const token = localStorage.getItem('cloudos_token');
    try {
      const response = await fetch('http://localhost:8080/api/tools/run', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ toolId: toolSchema.id, fields })
      });

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
      setRunning(false);
      setOutput(prev => prev + `\n[⛔] Execução interrompida pelo usuário.\n`);
    }
  };

  return (
    <div style={styles.container}>
      {/* HEADER COM COMANDO E BOTÕES */}
      <div style={styles.header}>
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
      <div style={styles.contentWrapper}>
        {/* PAINEL ESQUERDA - CONFIG */}
        <div style={styles.configPanel}>
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
        <div style={styles.outputPanel}>
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

      {/* CSS GLOBAL PARA RESPONSIVIDADE */}
      <style>{`
        @media (max-width: 768px) {
          .tool-runner-content { flex-direction: column !important; }
          .tool-runner-config { width: 100% !important; max-height: 40vh; border-right: none !important; border-bottom: 1px solid #30363d !important; }
          .tool-runner-output { width: 100% !important; }
          .tool-runner-header { flex-direction: column; gap: 8px; align-items: stretch !important; }
        }
      `}</style>
    </div>
  );
}

// Componente para renderizar cada tipo de campo do schema
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
          {field.options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
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

  // default: text ou textarea
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

// ESTILOS (GitHub Dark Theme)
const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    background: '#0d1117',
    color: '#c9d1d9',
    fontFamily: 'Inter, -apple-system, sans-serif',
  },
  header: {
    padding: '12px 16px',
    borderBottom: '1px solid #30363d',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: '16px',
    background: '#161b22',
  },
  cmdBox: {
    flex: 1,
    background: '#010409',
    border: '1px solid #30363d',
    borderRadius: '6px',
    padding: '8px 12px',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontFamily: 'JetBrains Mono, monospace',
    fontSize: '13px',
    overflowX: 'auto',
    whiteSpace: 'nowrap',
  },
  cmdPrefix: { color: '#3fb950', fontWeight: 'bold' },
  cmdText: { color: '#58a6ff' },
  actionBtns: { display: 'flex', gap: '8px' },
  btn: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    padding: '8px 16px',
    border: '1px solid transparent',
    borderRadius: '6px',
    color: '#fff',
    fontSize: '13px',
    fontWeight: '600',
    cursor: 'pointer',
    transition: 'opacity 0.2s',
  },
  btnSuccess: { background: '#238636', borderColor: '#2ea043' },
  btnDanger: { background: '#da3633', borderColor: '#f85149' },
  
  contentWrapper: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
    className: 'tool-runner-content',
  },
  configPanel: {
    width: '320px',
    borderRight: '1px solid #30363d',
    display: 'flex',
    flexDirection: 'column',
    background: '#0d1117',
    className: 'tool-runner-config',
  },
  panelHeader: {
    padding: '10px 16px',
    fontSize: '12px',
    fontWeight: '600',
    color: '#8b949e',
    borderBottom: '1px solid #21262d',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  fieldsContainer: {
    padding: '16px',
    overflowY: 'auto',
    flex: 1,
  },
  fieldRow: {
    marginBottom: '16px',
  },
  label: {
    display: 'block',
    fontSize: '12px',
    color: '#c9d1d9',
    marginBottom: '6px',
    fontWeight: '500',
  },
  textInput: {
    width: '100%',
    background: '#161b22',
    border: '1px solid #30363d',
    borderRadius: '6px',
    padding: '8px 10px',
    color: '#c9d1d9',
    fontSize: '13px',
    outline: 'none',
    boxSizing: 'border-box',
  },
  select: {
    width: '100%',
    background: '#161b22',
    border: '1px solid #30363d',
    borderRadius: '6px',
    padding: '8px 10px',
    color: '#c9d1d9',
    fontSize: '13px',
    outline: 'none',
    cursor: 'pointer',
  },
  checkboxLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    cursor: 'pointer',
    fontSize: '13px',
  },
  checkboxBox: {
    width: '16px',
    height: '16px',
    borderRadius: '4px',
    border: '1px solid #30363d',
    background: '#161b22',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxBoxChecked: {
    width: '16px',
    height: '16px',
    borderRadius: '4px',
    border: '1px solid #2ea043',
    background: '#238636',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rangeInput: {
    width: '100%',
    accentColor: '#58a6ff',
    cursor: 'pointer',
  },
  
  presetsContainer: {
    padding: '16px',
    borderTop: '1px solid #21262d',
  },
  presetsTitle: {
    fontSize: '12px',
    color: '#8b949e',
    marginBottom: '8px',
    fontWeight: '600',
  },
  presetBtn: {
    background: '#21262d',
    border: '1px solid #30363d',
    color: '#c9d1d9',
    padding: '6px 10px',
    borderRadius: '6px',
    fontSize: '12px',
    cursor: 'pointer',
    marginRight: '8px',
    marginBottom: '8px',
  },

  outputPanel: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    background: '#010409',
    className: 'tool-runner-output',
  },
  outputHeader: {
    padding: '8px 16px',
    background: '#0d1117',
    borderBottom: '1px solid #21262d',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '12px',
    color: '#8b949e',
  },
  runningBadge: {
    color: '#3fb950',
    fontWeight: '600',
    animation: 'pulse 1.5s infinite',
  },
  terminal: {
    flex: 1,
    margin: '0',
    padding: '16px',
    color: '#c9d1d9',
    fontFamily: 'JetBrains Mono, monospace',
    fontSize: '13px',
    lineHeight: '1.5',
    overflowY: 'auto',
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  },
};
