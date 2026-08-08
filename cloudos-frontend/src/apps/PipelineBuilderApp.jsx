// cloudos-frontend/src/apps/PipelineBuilderApp.jsx
import React, { useState, useCallback, useRef } from 'react';
import './PipelineBuilderApp.css';

const NODE_TYPES = [
  { id: 'tool', label: 'Ferramenta Kali', icon: '🛠️', color: '#58a6ff' },
  { id: 'script', label: 'Script Customizado', icon: '📜', color: '#3fb950' },
  { id: 'condition', label: 'Condição (If/Else)', icon: '🔀', color: '#d29922' },
  { id: 'parallel', label: 'Execução Paralela', icon: '⚡', color: '#a371f7' },
];

const PipelineBuilderApp = () => {
  const [nodes, setNodes] = useState([]);
  const [selectedNode, setSelectedNode] = useState(null);
  const [pipelineName, setPipelineName] = useState('Novo Pipeline');
  const [isRunning, setIsRunning] = useState(false);
  const [logs, setLogs] = useState('');
  const logRef = useRef(null);

  // Adicionar novo nó
  const addNode = useCallback((type) => {
    const newNode = {
      id: Date.now().toString(36),
      type,
      label: NODE_TYPES.find(n => n.id === type)?.label || type,
      config: {
        toolId: type === 'tool' ? 'nmap' : '',
        script: type === 'script' ? '# Python/Bash code\nprint("Hello")' : '',
        language: type === 'script' ? 'python' : '',
        condition: type === 'condition' ? 'success' : '',
        trueBranch: type === 'condition' ? [] : [],
        falseBranch: type === 'condition' ? [] : [],
        parallelNodes: type === 'parallel' ? [] : [],
      },
      x: 100 + nodes.length * 20,
      y: 100 + nodes.length * 30,
    };
    setNodes(prev => [...prev, newNode]);
    setSelectedNode(newNode.id);
  }, [nodes]);

  // Atualizar nó selecionado
  const updateNodeConfig = (nodeId, config) => {
    setNodes(prev => prev.map(n => n.id === nodeId ? { ...n, config: { ...n.config, ...config } } : n));
  };

  // Remover nó
  const removeNode = (nodeId) => {
    setNodes(prev => prev.filter(n => n.id !== nodeId));
    if (selectedNode === nodeId) setSelectedNode(null);
  };

  // Mover nó (drag)
  const moveNode = (nodeId, x, y) => {
    setNodes(prev => prev.map(n => n.id === nodeId ? { ...n, x, y } : n));
  };

  // Executar pipeline
  const runPipeline = async () => {
    setIsRunning(true);
    setLogs(prev => prev + `\n🚀 Iniciando pipeline: ${pipelineName}\n` + '═'.repeat(40));
    try {
      const res = await fetch('/api/pipeline/run', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        },
        body: JSON.stringify({ name: pipelineName, nodes }),
      });
      if (!res.ok) throw new Error(`Erro HTTP ${res.status}`);
      const data = await res.json();
      setLogs(prev => prev + '\n' + (data.log || 'Pipeline concluído.') + '\n✅ Sucesso!');
    } catch (err) {
      setLogs(prev => prev + `\n❌ Erro: ${err.message}`);
    } finally {
      setIsRunning(false);
    }
  };

  // Exportar Pipeline como JSON
  const exportJSON = () => {
    const data = JSON.stringify({ name: pipelineName, nodes }, null, 2);
    const blob = new Blob([data], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${pipelineName.toLowerCase().replace(/\s+/g, '_')}_pipeline.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Importar Pipeline via JSON
  const importJSON = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const parsed = JSON.parse(evt.target.result);
        if (parsed.nodes && Array.isArray(parsed.nodes)) {
          setNodes(parsed.nodes);
          if (parsed.name) setPipelineName(parsed.name);
          setLogs(prev => prev + '\n[PipelineBuilder] 📥 Pipeline carregado do arquivo JSON!');
        }
      } catch (err) {
        setLogs(prev => prev + '\n[PipelineBuilder Error] ❌ Erro ao ler arquivo JSON: ' + err.message);
      }
    };
    reader.readAsText(file);
  };

  const selected = (nodes || []).find(n => n.id === selectedNode);

  return (
    <div className="pipeline-container">
      {/* Header */}
      <div className="pipeline-header">
        <input
          type="text"
          value={pipelineName}
          onChange={e => setPipelineName(e.target.value)}
          className="pipeline-name-input"
          placeholder="Nome do Pipeline"
        />
        <div className="pipeline-actions">
          <button className="pp-btn pp-btn-add" onClick={() => addNode('tool')}>＋ Ferramenta</button>
          <button className="pp-btn pp-btn-script" onClick={() => addNode('script')}>📜 Script</button>
          <button className="pp-btn pp-btn-cond" onClick={() => addNode('condition')}>🔀 Condição</button>
          <button className="pp-btn pp-btn-parallel" onClick={() => addNode('parallel')}>⚡ Paralelo</button>
          <button className="pp-btn pp-btn-export" onClick={exportJSON} title="Exportar como .json">
            📥 JSON
          </button>
          <label className="pp-btn pp-btn-import" title="Importar arquivo .json">
            📤 Importar
            <input type="file" accept=".json" onChange={importJSON} style={{ display: 'none' }} />
          </label>
          <button
            className="pp-btn pp-btn-run"
            onClick={runPipeline}
            disabled={isRunning || nodes.length === 0}
          >
            {isRunning ? '⏳ Rodando...' : '▶️ Executar'}
          </button>
        </div>
      </div>

      {/* Área principal */}
      <div className="pipeline-body">
        {/* Canvas */}
        <div className="pipeline-canvas" onClick={() => setSelectedNode(null)}>
          {nodes.length === 0 && (
            <div className="pipeline-empty">
              <div className="empty-icon">🔗</div>
              <p>Adicione nós para construir seu pipeline de ataque automatizado.</p>
              <p className="empty-hint">Combine ferramentas, scripts customizados e lógica condicional.</p>
            </div>
          )}
          {nodes.map(node => (
            <div
              key={node.id}
              className={`pipeline-node ${node.type} ${selectedNode === node.id ? 'selected' : ''}`}
              style={{ left: node.x, top: node.y, borderColor: NODE_TYPES.find(t => t.id === node.type)?.color }}
              onClick={(e) => { e.stopPropagation(); setSelectedNode(node.id); }}
              draggable
              onDragEnd={(e) => moveNode(node.id, e.clientX - 50, e.clientY - 20)}
            >
              <span className="node-icon">{NODE_TYPES.find(t => t.id === node.type)?.icon}</span>
              <span className="node-label">{node.label}</span>
              <button className="node-remove" onClick={(e) => { e.stopPropagation(); removeNode(node.id); }}>✕</button>
            </div>
          ))}
        </div>

        {/* Painel de configuração */}
        {selected && (
          <div className="pipeline-config">
            <h4>⚙️ Configurar: {selected.label}</h4>
            {selected.type === 'tool' && (
              <div className="config-field">
                <label>Ferramenta Kali</label>
                <select
                  value={selected.config.toolId}
                  onChange={e => updateNodeConfig(selected.id, { toolId: e.target.value })}
                >
                  <option value="nmap">Nmap</option>
                  <option value="gobuster">Gobuster</option>
                  <option value="ffuf">FFuF</option>
                  <option value="sqlmap">SQLMap</option>
                  <option value="hydra">Hydra</option>
                </select>
              </div>
            )}
            {selected.type === 'script' && (
              <>
                <div className="config-field">
                  <label>Linguagem</label>
                  <select
                    value={selected.config.language}
                    onChange={e => updateNodeConfig(selected.id, { language: e.target.value })}
                  >
                    <option value="python">Python</option>
                    <option value="bash">Bash</option>
                    <option value="ruby">Ruby</option>
                  </select>
                </div>
                <div className="config-field">
                  <label>Código</label>
                  <textarea
                    value={selected.config.script}
                    onChange={e => updateNodeConfig(selected.id, { script: e.target.value })}
                    rows={6}
                    placeholder="Seu código aqui..."
                    style={{ fontFamily: 'monospace', fontSize: '12px' }}
                  />
                </div>
              </>
            )}
            {selected.type === 'condition' && (
              <div className="config-field">
                <label>Condição</label>
                <select
                  value={selected.config.condition}
                  onChange={e => updateNodeConfig(selected.id, { condition: e.target.value })}
                >
                  <option value="success">Se sucesso (exit 0)</option>
                  <option value="failure">Se falha (exit ≠ 0)</option>
                  <option value="contains">Se contiver texto</option>
                </select>
              </div>
            )}
            {selected.type === 'parallel' && (
              <div className="config-field">
                <label>Execução Paralela</label>
                <p className="hint">Todos os nós filhos serão executados simultaneamente.</p>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Logs */}
      <div className="pipeline-logs">
        <div className="logs-header">
          <span>📟 Logs de Execução</span>
          <button onClick={() => setLogs('')}>🧹 Limpar</button>
        </div>
        <pre className="logs-content" ref={logRef}>{logs || 'Aguardando execução...'}</pre>
      </div>
    </div>
  );
};

export default PipelineBuilderApp;
