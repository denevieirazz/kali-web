import React, { useState } from 'react';

export default function PythonRunnerApp() {
  const [code, setCode] = useState('import socket\nprint(f"Meu IP no WSL: {socket.gethostbyname(socket.gethostname())}")\nprint("Teste de extensibilidade Python no CloudOS Enterprise!")');
  const [output, setOutput] = useState('');
  const [loading, setLoading] = useState(false);

  const runScript = async () => {
    setLoading(true);
    setOutput('⚡ Executando script no WSL2 Kali Linux...');
    try {
      const res = await fetch('/api/python/execute', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
        },
        body: JSON.stringify({ script: code })
      });
      if (res.ok) {
        const data = await res.json();
        let formatted = data.output || '';
        if (data.error) {
          formatted += `\n[STDERR / ERRO]\n${data.error}`;
        }
        setOutput(formatted || '[Script concluído sem saída]');
      } else {
        setOutput('❌ Erro na requisição ao servidor backend.');
      }
    } catch (err) {
      setOutput(`❌ Erro de execução: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', height: '100%', width: '100%', color: '#fff', fontFamily: 'Consolas, monospace', background: '#0d1117', overflow: 'hidden' }}>
      {/* Code Editor Panel */}
      <div style={{ flex: 1, borderRight: '1px solid #30363d', display: 'flex', flexDirection: 'column' }}>
        <div style={{ background: '#161b22', padding: '12px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #30363d' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '18px' }}>🐍</span>
            <span style={{ color: '#58a6ff', fontWeight: 'bold', fontSize: '14px' }}>Python Exploit & Automation Runner</span>
          </div>
          <button
            onClick={runScript}
            disabled={loading}
            style={{
              background: loading ? '#21262d' : '#238636',
              border: '1px solid #30363d',
              color: '#fff',
              padding: '6px 16px',
              borderRadius: '6px',
              cursor: loading ? 'not-allowed' : 'pointer',
              fontWeight: 'bold',
              fontSize: '13px'
            }}
          >
            {loading ? '⏳ Rodando...' : '▶️ Executar Script'}
          </button>
        </div>
        <textarea
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="Digite seu código Python aqui..."
          style={{
            flex: 1,
            background: '#0d1117',
            color: '#7ee787',
            border: 'none',
            padding: '16px',
            resize: 'none',
            outline: 'none',
            fontFamily: 'Consolas, "Fira Code", monospace',
            fontSize: '14px',
            lineHeight: '1.5'
          }}
        />
      </div>

      {/* Output Terminal Log Panel */}
      <div style={{ flex: 1, background: '#090d13', display: 'flex', flexDirection: 'column' }}>
        <div style={{ background: '#161b22', padding: '12px 16px', borderBottom: '1px solid #30363d', color: '#8b949e', fontSize: '13px', fontWeight: 'bold' }}>
          📺 Console de Saída (STDOUT / STDERR)
        </div>
        <div style={{ flex: 1, padding: '16px', overflowY: 'auto', whiteSpace: 'pre-wrap', color: '#58a6ff', fontSize: '13px', lineHeight: '1.5' }}>
          {output || <span style={{ color: '#8b949e' }}>A saída do script Python aparecerá aqui após a execução...</span>}
        </div>
      </div>
    </div>
  );
}
