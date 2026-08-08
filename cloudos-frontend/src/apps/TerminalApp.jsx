import React, { useState, useRef, useEffect, useCallback } from 'react';

const API = '';

const ANSI_REGEX = /\x1B\[[0-9;]*m/g;
function stripAnsi(str) {
    return str ? str.replace(ANSI_REGEX, '') : '';
}

const COLORS = {
    bg: '#0d1117',
    surface: '#161b22',
    border: '#30363d',
    green: '#3fb950',
    cyan: '#79c0ff',
    yellow: '#e3b341',
    red: '#f85149',
    gray: '#8b949e',
    white: '#e6edf3',
    purple: '#d2a8ff',
};

export default function TerminalApp() {
    const [lines, setLines] = useState([
        { type: 'system', text: '╔══════════════════════════════════════════════╗' },
        { type: 'system', text: '║   CloudOS Terminal Pro  ●  WSL2 Kali Linux   ║' },
        { type: 'system', text: '╚══════════════════════════════════════════════╝' },
        { type: 'system', text: 'Digite um comando e pressione Enter.' },
        { type: 'empty',  text: '' },
    ]);
    const [input, setInput] = useState('');
    const [history, setHistory] = useState([]);
    const [histIdx, setHistIdx] = useState(-1);
    const [busy, setBusy] = useState(false);
    const [cwd, setCwd] = useState('~');
    const bottomRef = useRef(null);
    const inputRef = useRef(null);

    useEffect(() => {
        bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [lines]);

    useEffect(() => {
        inputRef.current?.focus();
    }, []);

    const addLines = useCallback((newLines) => {
        setLines(prev => [...prev, ...newLines]);
    }, []);

    const execCommand = useCallback(async (cmd) => {
        if (!cmd.trim()) return;

        const prompt = `root@kali:${cwd}# `;
        addLines([{ type: 'prompt', text: prompt + cmd }]);

        setBusy(true);
        try {
            const resp = await fetch(`${API}/api/terminal/exec`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ command: cmd }),
            });

            const data = await resp.json().catch(() => ({ status: 'error', output: '[Erro: resposta inválida do servidor]' }));

            if (data.status === 'success') {
                const raw = data.output || '';
                const stripped = stripAnsi(raw);
                if (stripped.trim()) {
                    const outputLines = stripped.split('\n').map(line => ({
                        type: 'output',
                        text: line,
                    }));
                    addLines(outputLines);

                    // update cwd if pwd was run
                    const pwdMatch = stripped.match(/^(\/[^\n]+)/);
                    if (cmd.trim() === 'pwd' && pwdMatch) {
                        setCwd(pwdMatch[1].trim());
                    }
                }
            } else {
                addLines([{ type: 'error', text: data.output || '[Erro desconhecido]' }]);
            }
        } catch (e) {
            addLines([{ type: 'error', text: `[Falha na conexão com o backend: ${e.message}]` }]);
        }

        addLines([{ type: 'empty', text: '' }]);
        setBusy(false);
    }, [cwd, addLines]);

    const handleKeyDown = useCallback((e) => {
        if (e.key === 'Enter') {
            const cmd = input.trim();
            if (cmd) {
                setHistory(prev => [cmd, ...prev.slice(0, 99)]);
                setHistIdx(-1);
            }
            setInput('');
            execCommand(cmd);
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setHistIdx(prev => {
                const next = Math.min(prev + 1, history.length - 1);
                setInput(history[next] || '');
                return next;
            });
        } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            setHistIdx(prev => {
                const next = Math.max(prev - 1, -1);
                setInput(next === -1 ? '' : history[next] || '');
                return next;
            });
        } else if (e.key === 'l' && e.ctrlKey) {
            e.preventDefault();
            setLines([]);
        }
    }, [input, history, execCommand]);

    const lineColor = (type) => {
        switch(type) {
            case 'system':  return COLORS.cyan;
            case 'prompt':  return COLORS.green;
            case 'error':   return COLORS.red;
            case 'empty':   return 'transparent';
            default:        return COLORS.white;
        }
    };

    return (
        <div
            style={{
                height: '100%', width: '100%', display: 'flex', flexDirection: 'column',
                background: COLORS.bg, fontFamily: "'Courier New', Courier, monospace",
                fontSize: '13px', boxSizing: 'border-box', overflow: 'hidden',
            }}
            onClick={() => inputRef.current?.focus()}
        >
            {/* Header */}
            <div style={{
                background: COLORS.surface, borderBottom: `1px solid ${COLORS.border}`,
                padding: '6px 14px', display: 'flex', alignItems: 'center', gap: '8px',
                flexShrink: 0,
            }}>
                <span style={{ color: COLORS.red, fontSize: '10px' }}>●</span>
                <span style={{ color: COLORS.yellow, fontSize: '10px' }}>●</span>
                <span style={{ color: COLORS.green, fontSize: '10px' }}>●</span>
                <span style={{ color: COLORS.gray, marginLeft: '8px', fontSize: '12px' }}>
                    Terminal Pro — WSL2 Kali Linux
                </span>
                {busy && (
                    <span style={{ color: COLORS.yellow, marginLeft: 'auto', fontSize: '11px' }}>
                        ⟳ executando...
                    </span>
                )}
                {!busy && (
                    <span style={{ color: COLORS.green, marginLeft: 'auto', fontSize: '11px' }}>
                        ● conectado
                    </span>
                )}
            </div>

            {/* Output Area */}
            <div style={{
                flex: 1, overflowY: 'auto', padding: '12px 16px',
                scrollbarWidth: 'thin', scrollbarColor: `${COLORS.border} transparent`,
            }}>
                {lines.map((line, i) => (
                    <div key={i} style={{
                        color: lineColor(line.type),
                        whiteSpace: 'pre-wrap', wordBreak: 'break-all',
                        lineHeight: '1.55',
                        minHeight: line.type === 'empty' ? '8px' : undefined,
                    }}>
                        {line.text}
                    </div>
                ))}
                <div ref={bottomRef} />
            </div>

            {/* Input Row */}
            <div style={{
                display: 'flex', alignItems: 'center',
                borderTop: `1px solid ${COLORS.border}`,
                background: COLORS.surface, padding: '8px 12px', flexShrink: 0,
            }}>
                <span style={{ color: COLORS.green, marginRight: '8px', whiteSpace: 'nowrap', userSelect: 'none' }}>
                    root@kali:<span style={{ color: COLORS.cyan }}>{cwd}</span>#
                </span>
                <input
                    ref={inputRef}
                    value={input}
                    onChange={e => setInput(e.target.value)}
                    onKeyDown={handleKeyDown}
                    disabled={busy}
                    placeholder={busy ? 'executando...' : 'comando...'}
                    style={{
                        flex: 1, background: 'transparent', border: 'none', outline: 'none',
                        color: COLORS.white, fontFamily: 'inherit', fontSize: '13px',
                        caretColor: COLORS.green,
                        opacity: busy ? 0.5 : 1,
                    }}
                    autoComplete="off"
                    spellCheck={false}
                />
                <button
                    onClick={() => { const cmd = input.trim(); setInput(''); execCommand(cmd); }}
                    disabled={busy || !input.trim()}
                    style={{
                        background: busy ? COLORS.gray : COLORS.green,
                        border: 'none', borderRadius: '4px', color: '#000',
                        padding: '4px 12px', cursor: busy ? 'not-allowed' : 'pointer',
                        fontFamily: 'inherit', fontSize: '12px', fontWeight: 700,
                        marginLeft: '8px', transition: 'all 0.2s',
                    }}
                >
                    ↵
                </button>
            </div>

            {/* Footer hint */}
            <div style={{
                background: COLORS.bg, padding: '3px 16px',
                fontSize: '10px', color: COLORS.gray, borderTop: `1px solid ${COLORS.border}`,
                display: 'flex', gap: '16px', flexShrink: 0,
            }}>
                <span>↑↓ histórico</span>
                <span>Ctrl+L limpar</span>
                <span>Enter executar</span>
            </div>
        </div>
    );
}
