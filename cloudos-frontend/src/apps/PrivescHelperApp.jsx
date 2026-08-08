import React, { useState, useEffect } from 'react';

export default function PrivescHelperApp({ websocket }) {
    const [payloads, setPayloads] = useState(null);
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (!websocket) return;
        const handleMsg = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.type === 'log') {
                    setLogs(prev => [...prev, data.message]);
                } else if (data.type === 'privesc_ready') {
                    setPayloads(data.payloads);
                    setLogs(prev => [...prev, '✅ LinPEAS baixado e Servidor HTTP ativo! Comandos prontos para cópia.']);
                    setLoading(false);
                }
            } catch (e) {}
        };
        websocket.addEventListener('message', handleMsg);
        return () => websocket.removeEventListener('message', handleMsg);
    }, [websocket]);

    const handleSetup = async () => {
        setPayloads(null);
        setLoading(true);
        setLogs(['⏳ Baixando LinPEAS e iniciando servidor HTTP no WSL2...']);
        try {
            const res = await fetch('/api/privesc/setup', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
                }
            });
            if (res.ok) {
                const data = await res.json();
                if (data.payloads) {
                    setPayloads(data.payloads);
                    setLogs(prev => [...prev, '✅ Servidor HTTP rodando e LinPEAS disponível!']);
                } else {
                    setLogs(prev => [...prev, `🟢 ${data.message || 'Configuração em andamento...'}`]);
                }
            } else {
                setLogs(prev => [...prev, '❌ Erro ao configurar ambiente de elevação de privilégios.']);
            }
        } catch (err) {
            setLogs(prev => [...prev, `❌ Erro de conexão: ${err.message}`]);
        } finally {
            setLoading(false);
        }
    };

    const copyToClipboard = (text) => {
        if (navigator.clipboard) {
            navigator.clipboard.writeText(text);
        }
        setLogs(prev => [...prev, '📋 Comando copiado para a área de transferência!']);
    };

    const containerStyle = {
        padding: '20px', background: '#0d1117', color: '#c9d1d9',
        fontFamily: 'Consolas, "Fira Code", monospace', height: '100%',
        boxSizing: 'border-box', overflowY: 'auto'
    };
    const btnStyle = {
        background: '#238636', color: '#fff', border: '1px solid #30363d',
        padding: '10px 20px', borderRadius: '6px', cursor: loading ? 'not-allowed' : 'pointer',
        fontWeight: 'bold', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '8px'
    };
    const payloadBox = {
        background: '#161b22', border: '1px solid #30363d', padding: '14px',
        margin: '10px 0', borderRadius: '6px', display: 'flex',
        justify: 'space-between', alignItems: 'center', gap: '12px'
    };
    const codeStyle = { color: '#3fb950', margin: 0, fontSize: '13px', wordBreak: 'break-all' };
    const copyBtn = {
        background: '#21262d', color: '#fff', border: '1px solid #30363d',
        padding: '6px 12px', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold', fontSize: '12px'
    };

    return (
        <div style={containerStyle}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', borderBottom: '1px solid #30363d', paddingBottom: '12px', marginBottom: '16px' }}>
                <span style={{ fontSize: '24px' }}>👑</span>
                <div>
                    <h2 style={{ margin: 0, color: '#58a6ff', fontSize: '18px' }}>1-Click Privesc (LinPEAS & Post-Exploitation)</h2>
                    <span style={{ color: '#8b949e', fontSize: '12px' }}>Baixe o LinPEAS, suba o servidor HTTP no WSL2 e copie os comandos de execução direta.</span>
                </div>
            </div>

            <button style={btnStyle} disabled={loading} onClick={handleSetup}>
                {loading ? '⏳ Preparando...' : '🚀 Preparar Ambiente LinPEAS'}
            </button>

            {payloads && (
                <div style={{ marginTop: '20px' }}>
                    <h3 style={{ color: '#58a6ff', fontSize: '14px', marginBottom: '10px' }}>Comandos de Transferência e Execução Direta:</h3>
                    
                    <div style={payloadBox}>
                        <pre style={codeStyle}>{payloads.curl}</pre>
                        <button style={copyBtn} onClick={() => copyToClipboard(payloads.curl)}>📋 Copiar cURL</button>
                    </div>

                    <div style={payloadBox}>
                        <pre style={codeStyle}>{payloads.wget}</pre>
                        <button style={copyBtn} onClick={() => copyToClipboard(payloads.wget)}>📋 Copiar Wget</button>
                    </div>

                    <div style={payloadBox}>
                        <pre style={codeStyle}>{payloads.sudo}</pre>
                        <button style={copyBtn} onClick={() => copyToClipboard(payloads.sudo)}>📋 Copiar Sudo cURL</button>
                    </div>
                </div>
            )}

            <div style={{ background: '#010409', border: '1px solid #30363d', padding: '14px', marginTop: '20px', borderRadius: '6px', height: '140px', overflowY: 'auto', fontSize: '13px', lineHeight: '1.5' }}>
                {logs.length === 0 ? (
                    <div style={{ color: '#8b949e' }}>Clique em "Preparar Ambiente LinPEAS" para iniciar o servidor de transferência...</div>
                ) : (
                    logs.map((log, i) => <div key={i} style={{ marginBottom: '4px' }}>{log}</div>)
                )}
            </div>
        </div>
    );
}
