import React, { useState } from 'react';

export default function OsintTrackerApp() {
    const [mode, setMode] = useState('site');
    const [target, setTarget] = useState('');
    const [output, setOutput] = useState('');
    const [loading, setLoading] = useState(false);

    const handleTrack = async () => {
        if (!target) return;
        setLoading(true);
        setOutput('⏳ Rastreando, aguarde... (Isso pode levar alguns segundos)');

        try {
            const token = localStorage.getItem('cloudos_token') || '';
            const res = await fetch('/api/osint/track', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json', 
                    'Authorization': `Bearer ${token}` 
                },
                body: JSON.stringify({ mode, target })
            });
            const data = await res.json();
            setOutput(data.output || 'Nenhum resultado encontrado.');
        } catch (err) {
            setOutput('❌ Erro ao conectar com o backend.');
        }
        setLoading(false);
    };

    const containerStyle = { 
        display: 'flex', flexDirection: 'column', height: '100%', padding: '20px', 
        background: '#0d1117', color: '#c9d1d9', fontFamily: 'Consolas, "Fira Code", monospace',
        boxSizing: 'border-box', overflowY: 'auto'
    };
    const btnStyle = { 
        background: '#238636', color: '#fff', border: '1px solid #30363d', 
        padding: '10px 20px', borderRadius: '6px', cursor: 'pointer', fontWeight: 'bold', fontSize: '13px' 
    };
    const inputStyle = { 
        background: '#161b22', border: '1px solid #30363d', color: '#58a6ff', 
        padding: '10px 14px', borderRadius: '6px', fontSize: '14px', flex: 1, outline: 'none', fontWeight: 'bold' 
    };
    const consoleStyle = { 
        background: '#010409', border: '1px solid #30363d', marginTop: '20px', 
        padding: '15px', borderRadius: '8px', overflowY: 'auto', flex: 1, whiteSpace: 'pre-wrap', fontSize: '13px', lineHeight: '1.5' 
    };

    return (
        <div style={containerStyle}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', borderBottom: '1px solid #30363d', paddingBottom: '12px', marginBottom: '16px' }}>
                <span style={{ fontSize: '24px' }}>🎯</span>
                <div>
                    <h2 style={{ margin: 0, color: '#58a6ff', fontSize: '18px' }}>OSINT Auto-Tracker</h2>
                    <span style={{ color: '#8b949e', fontSize: '12px' }}>Rastreie pessoas em redes sociais (Sherlock) ou infraestrutura web (WhatWeb & Nmap).</span>
                </div>
            </div>
            
            <div style={{ display: 'flex', gap: '10px', marginBottom: '15px' }}>
                <button onClick={() => setMode('site')} style={{...btnStyle, background: mode === 'site' ? '#58a6ff' : '#21262d', color: mode === 'site' ? '#000' : '#fff'}}>🌐 Rastrear Site</button>
                <button onClick={() => setMode('person')} style={{...btnStyle, background: mode === 'person' ? '#58a6ff' : '#21262d', color: mode === 'person' ? '#000' : '#fff'}}>👤 Rastrear Pessoa</button>
            </div>

            <div style={{ display: 'flex', gap: '10px' }}>
                <input
                    style={inputStyle}
                    placeholder={mode === 'site' ? 'exemplo.com' : 'joao_silva'}
                    value={target}
                    onChange={(e) => setTarget(e.target.value)}
                    onKeyPress={(e) => e.key === 'Enter' && handleTrack()}
                    disabled={loading}
                />
                <button style={btnStyle} onClick={handleTrack} disabled={loading}>
                    {loading ? '⏳ Buscando...' : '🚀 Rastrear'}
                </button>
            </div>

            <div style={consoleStyle}>
                {output || 'Digite um alvo acima e clique em Rastrear para iniciar a varredura OSINT no WSL2...'}
            </div>
        </div>
    );
}
