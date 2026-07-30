import { useState, useRef } from 'react';
import { Play, Plus, Trash2, Workflow } from 'lucide-react';

export function PipelineBuilderApp({ activeProject }) {
  const [steps, setSteps] = useState([
    { tool: 'subfinder', args: ['-d', 'example.com'] },
    { tool: 'httpx', args: ['-silent'] }
  ]);
  const [output, setOutput] = useState('');
  const [running, setRunning] = useState(false);
  const readerRef = useRef(null);

  const token = localStorage.getItem('cloudos_token');

  const updateStep = (i, field, value) => {
    const newSteps = [...steps];
    newSteps[i] = { ...newSteps[i], [field]: field === 'args' ? value.split(' ') : value };
    setSteps(newSteps);
  };

  const addStep = () => setSteps([...steps, { tool: 'nmap', args: ['-sV'] }]);
  const removeStep = (i) => setSteps(steps.filter((_, idx) => idx !== i));

  const run = async () => {
    setRunning(true);
    setOutput('');
    try {
      const res = await fetch('http://localhost:8080/api/v3/pipeline/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ steps, projectId: activeProject?.id })
      });

      const reader = res.body.getReader();
      readerRef.current = reader;
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const lines = decoder.decode(value).split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const evt = JSON.parse(line);
            if (evt.type === 'start') setOutput(o => o + `\n▶ [${evt.step}] Iniciando...\n`);
            else if (evt.type === 'stdout') setOutput(o => o + evt.data);
            else if (evt.type === 'error') setOutput(o => o + `\n✗ [${evt.step}] ERRO: ${evt.msg}\n`);
          } catch {}
        }
      }
      setOutput(o => o + '\n[✓] Pipeline finalizado.\n');
    } catch (e) {
      setOutput(o => o + `\n[✗] Falha: ${e.message}\n`);
    } finally {
      setRunning(false);
    }
  };

  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', background: '#0d1117', color: '#c9d1d9', fontFamily: 'Inter, sans-serif' }}>
      <div style={{ padding: 12, borderBottom: '1px solid #30363d', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#161b22', flexShrink: 0 }}>
        <h2 style={{ margin: 0, fontSize: 14, display: 'flex', alignItems: 'center', gap: 8 }}><Workflow size={16} color="#58a6ff" /> Visual Pipeline</h2>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={addStep} style={styles.btnGhost}><Plus size={14} /> Step</button>
          <button onClick={run} disabled={running} style={{...styles.btn, background: running ? '#21262d' : '#238636'}}>
            <Play size={14} fill="#fff" /> {running ? 'Rodando...' : 'Executar'}
          </button>
        </div>
      </div>

      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Painel Edição */}
        <div style={{ width: 320, borderRight: '1px solid #30363d', padding: 16, overflowY: 'auto', flexShrink: 0 }}>
          {steps.map((s, i) => (
            <div key={i} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 12, marginBottom: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, fontSize: 12, color: '#8b949e' }}>
                <strong>Step {i + 1}</strong>
                <button onClick={() => removeStep(i)} style={{ background: 'transparent', border: 'none', color: '#f85149', cursor: 'pointer', display: 'flex', alignItems: 'center' }}><Trash2 size={14} /></button>
              </div>
              <input value={s.tool} onChange={e => updateStep(i, 'tool', e.target.value)} placeholder="ferramenta (ex: nmap)" style={styles.input} />
              <input value={Array.isArray(s.args) ? s.args.join(' ') : s.args} onChange={e => updateStep(i, 'args', e.target.value)} placeholder="argumentos (ex: -sV -p 80)" style={{...styles.input, marginTop: 8}} />
              {i < steps.length - 1 && <div style={{ textAlign: 'center', color: '#30363d', margin: '8px 0', fontSize: 16 }}>↓</div>}
            </div>
          ))}
        </div>

        {/* Painel Output */}
        <div style={{ flex: 1, background: '#010409', display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          <div style={{ padding: 8, borderBottom: '1px solid #21262d', fontSize: 12, color: '#8b949e', flexShrink: 0 }}>Console Output</div>
          <pre style={{ flex: 1, margin: 0, padding: 16, color: '#c9d1d9', fontFamily: 'JetBrains Mono, monospace', fontSize: 13, overflowY: 'auto', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
            {output || 'Monte seu pipeline e clique em Executar.'}
          </pre>
        </div>
      </div>
    </div>
  );
}

const styles = {
  input: { width: '100%', background: '#0d1117', border: '1px solid #30363d', borderRadius: 6, padding: '8px 10px', color: '#c9d1d9', fontSize: 13, outline: 'none', boxSizing: 'border-box' },
  btn: { display: 'flex', alignItems: 'center', gap: 6, padding: '6px 12px', border: '1px solid transparent', borderRadius: 6, color: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer' },
  btnGhost: { background: '#21262d', border: '1px solid #30363d', color: '#c9d1d9', padding: '6px 12px', borderRadius: 6, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }
};

export default PipelineBuilderApp;
