import React, { useState, useEffect } from 'react';

export default function PayloadForgeApp({ websocket }) {
    const [port, setPort] = useState(4444);
    const [payload, setPayload] = useState('');
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (!websocket) return;
        const handleMsg = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.type === 'log') {
                    setLogs(prev => [...prev, data.message]);
                } else if (data.type === 'payload_ready') {
                    setPayload(data.payload);
                    if (navigator.clipboard) {
                        navigator.clipboard.writeText(data.payload);
                    }
                    setLogs(prev => [...prev, '📋 Payload gerado e copiado para a área de transferência!']);
                    setLoading(false);
                }
            } catch (e) {}
        };
        websocket.addEventListener('message', handleMsg);
        return () => websocket.removeEventListener('message', handleMsg);
    }, [websocket]);

    const handleGenerate = async (type) => {
        setPayload('');
        setLoading(true);
        setLogs([`⚙️ Solicitando payload ${type.toUpperCase()} na porta ${port}...`]);
        try {
            const res = await fetch('/api/payloads/generate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
                },
                body: JSON.stringify({ type, port: parseInt(port) })
            });
            if (res.ok) {
                const data = await res.json();
                if (data.payload) {
                    setPayload(data.payload);
                    if (navigator.clipboard) {
                        navigator.clipboard.writeText(data.payload);
                    }
                    setLogs(prev => [
                        ...prev,
                        `🛠️ Payload ${type.toUpperCase()} gerado com sucesso!`,
                        `👂 Listener auto-iniciado na porta ${port}.`,
                        '📋 Payload copiado para a área de transferência!'
                    ]);
                } else {
                    setLogs(prev => [...prev, `🟢 ${data.message || 'Payload em geração no backend...'}`]);
                }
            } else {
                setLogs(prev => [...prev, '❌ Erro ao gerar payload no servidor.']);
            }
        } catch (err) {
            setLogs(prev => [...prev, `❌ Erro de conexão: ${err.message}`]);
        } finally {
            setLoading(false);
        }
    };

    const containerStyle = {
        display: 'flex', flexDirection: 'column', height: '100%', padding: '20px',
        background: '#0d1117', color: '#c9d1d9', fontFamily: 'Consolas, "Fira Code", monospace',
        boxSizing: 'border-box', overflowY: 'auto'
    };
    const btnStyle = {
        background: '#238636', color: '#fff', border: '1px solid #30363d',
        padding: '10px 18px', borderRadius: '6px', cursor: 'pointer', margin: '5px',
        fontWeight: 'bold', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '8px'
    };
    const inputStyle = {
        background: '#161b22', border: '1px solid #30363d', color: '#58a6ff',
        padding: '8px 14px', borderRadius: '6px', width: '120px', textAlign: 'center',
        fontSize: '14px', outline: 'none', fontWeight: 'bold'
    };
    const consoleStyle = {
        background: '#010409', border: '1px solid #30363d', marginTop: '20px',
        padding: '16px', borderRadius: '8px', overflowY: 'auto', flex: 1, minHeight: '120px',
        fontSize: '13px', lineHeight: '1.5'
    };
    const payloadBoxStyle = {
        background: '#161b22', border: '1px solid #58a6ff', padding: '16px',
        borderRadius: '8px', marginTop: '20px', color: '#3fb950', wordBreak: 'break-all',
        fontSize: '13px'
    };

    return (
        <div style={containerStyle}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', borderBottom: '1px solid #30363d', paddingBottom: '12px', marginBottom: '20px' }}>
                <span style={{ fontSize: '24px' }}>🛠️</span>
                <div>
                    <h2 style={{ margin: 0, color: '#58a6ff', fontSize: '18px' }}>Payload Forge & Auto-Listener</h2>
                    <span style={{ color: '#8b949e', fontSize: '12px' }}>Gere payloads de reverse shell com 1-clique e inicie listeners ncat no WSL2.</span>
                </div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '15px', marginBottom: '20px', background: '#161b22', border: '1px solid #30363d', padding: '14px 18px', borderRadius: '8px' }}>
                <label style={{ color: '#8b949e', fontSize: '13px', fontWeight: 'bold' }}>Porta do Listener:</label>
                <input type="number" style={inputStyle} value={port} onChange={(e) => setPort(e.target.value)} />
            </div>

            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                <button style={btnStyle} disabled={loading} onClick={() => handleGenerate('php')}>🐘 Reverse Shell PHP</button>
                <button style={btnStyle} disabled={loading} onClick={() => handleGenerate('python')}>🐍 Reverse Shell Python</button>
                <button style={btnStyle} disabled={loading} onClick={() => handleGenerate('bash')}>💥 Reverse Shell Bash</button>
                <button style={btnStyle} disabled={loading} onClick={() => handleGenerate('netcat')}>🐛 Reverse Shell Netcat</button>
                <button style={btnStyle} disabled={loading} onClick={() => handleGenerate('powershell')}>⚡ PowerShell One-Liner</button>
            </div>

            {payload && (
                <div style={payloadBoxStyle}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                        <strong style={{ color: '#58a6ff' }}>📋 Payload Gerado (Copiado Automaticamente):</strong>
                        <button
                            onClick={() => navigator.clipboard.writeText(payload)}
                            style={{ background: '#21262d', border: '1px solid #30363d', color: '#fff', padding: '4px 10px', borderRadius: '4px', cursor: 'pointer', fontSize: '11px' }}
                        >
                            📋 Re-copiar
                        </button>
                    </div>
                    <code style={{ background: '#0d1117', padding: '10px', borderRadius: '4px', display: 'block', border: '1px solid #30363d' }}>{payload}</code>
                </div>
            )}

            <div style={consoleStyle}>
                {logs.length === 0 ? (
                    <div style={{ color: '#8b949e' }}>Escolha o tipo de payload acima para gerar e auto-iniciar o listener...</div>
                ) : (
                    logs.map((log, i) => <div key={i} style={{ marginBottom: '4px' }}>{log}</div>)
                )}
            </div>
        </div>
    );
}
