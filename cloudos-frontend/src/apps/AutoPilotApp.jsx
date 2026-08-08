import React, { useState, useEffect } from 'react';

export default function AutoPilotApp({ websocket }) {
    const [target, setTarget] = useState('');
    const [logs, setLogs] = useState([]);
    const [mode, setMode] = useState('web');
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (!websocket) return;

        const handleMsg = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.type === 'log' || data.type === 'done' || data.type === 'autopilot') {
                    setLogs((prev) => [...prev, data.message]);
                    if (data.type === 'done') setLoading(false);
                }
            } catch (e) {}
        };

        websocket.addEventListener('message', handleMsg);
        return () => websocket.removeEventListener('message', handleMsg);
    }, [websocket]);

    const handleRun = async () => {
        if (!target.trim()) return;
        setLoading(true);
        setLogs([`⏳ [AUTO-PILOT] Iniciando engenhos de busca para: ${target}...`]);
        const endpoint = mode === 'web' ? '/api/autopilot/web' : '/api/autopilot/person';
        const payload = mode === 'web' ? { target } : { username: target };

        try {
            const res = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${localStorage.getItem('cloudos_token') || ''}`
                },
                body: JSON.stringify(payload)
            });
            if (res.ok) {
                const data = await res.json();
                setLogs(prev => [...prev, `🟢 ${data.message || 'Pipeline em execução...'}`]);
            } else {
                setLogs(prev => [...prev, '❌ Erro ao iniciar pipeline no backend.']);
                setLoading(false);
            }
        } catch (err) {
            setLogs(prev => [...prev, `❌ Erro de conexão: ${err.message}`]);
            setLoading(false);
        }
    };

    const containerStyle = {
        display: 'flex', flexDirection: 'column', height: '100%', padding: '20px',
        background: 'rgba(13, 17, 23, 0.9)', color: '#c9d1d9', fontFamily: 'Consolas, "Fira Code", monospace',
        boxSizing: 'border-box'
    };
    const inputStyle = {
        background: '#0d1117', border: '1px solid #30363d', color: '#58a6ff',
        padding: '12px', borderRadius: '6px', fontSize: '15px', outline: 'none', flex: 1
    };
    const btnStyle = {
        background: '#238636', color: '#fff', border: 'none', padding: '12px 24px',
        borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', marginLeft: '10px',
        fontSize: '14px'
    };
    const consoleStyle = {
        background: '#010409', border: '1px solid #30363d', marginTop: '20px',
        padding: '16px', borderRadius: '8px', overflowY: 'auto', flex: 1, whiteSpace: 'pre-wrap',
        fontSize: '13px', lineHeight: '1.5'
    };

    return (
        <div style={containerStyle}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', borderBottom: '1px solid #30363d', paddingBottom: '12px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                    <span style={{ fontSize: '24px' }}>🚀</span>
                    <div>
                        <h2 style={{ margin: 0, color: '#58a6ff', fontSize: '18px' }}>Recon Autopilot (Engenho de Automação)</h2>
                        <span style={{ color: '#8b949e', fontSize: '12px' }}>Execução encadeada de WhatWeb, Nmap (AKB Integration), theHarvester e Sherlock.</span>
                    </div>
                </div>
                <div style={{ display: 'flex' }}>
                    <button onClick={() => setMode('web')} style={{ ...btnStyle, background: mode === 'web' ? '#58a6ff' : '#21262b', color: mode === 'web' ? '#000' : '#fff' }}>🌐 Rastrear Site</button>
                    <button onClick={() => setMode('person')} style={{ ...btnStyle, background: mode === 'person' ? '#58a6ff' : '#21262b', color: mode === 'person' ? '#000' : '#fff', marginLeft: '10px' }}>🕵️ Rastrear Pessoa</button>
                </div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center' }}>
                <input
                    style={inputStyle}
                    placeholder={mode === 'web' ? 'exemplo.com ou 192.168.0.1' : 'username_exemplo'}
                    value={target}
                    onChange={(e) => setTarget(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleRun()}
                />
                <button style={{ ...btnStyle, background: loading ? '#21262d' : '#238636' }} disabled={loading} onClick={handleRun}>
                    {loading ? '⏳ EXECUTANDO...' : '🚀 AUTO-PILOT'}
                </button>
            </div>

            <div style={consoleStyle}>
                {logs.length === 0 ? (
                    <div style={{ color: '#8b949e' }}>Digite o alvo e clique em AUTO-PILOT para iniciar o rastreio automático...</div>
                ) : (
                    logs.map((log, i) => (
                        <div key={i} style={{ marginBottom: '6px', color: log.includes('✅') ? '#3fb950' : log.includes('❌') ? '#f85149' : '#8b949e' }}>
                            {log}
                        </div>
                    ))
                )}
            </div>
        </div>
    );
}
