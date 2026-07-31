import React from 'react';

const themes = [
  { name: 'GitHub Dark', xterm: { background: '#0d1117', foreground: '#c9d1d9', cursor: '#58a6ff', selection: '#58a6ff40', black: '#161b22', red: '#f85149', green: '#3fb950', yellow: '#d2991d', blue: '#58a6ff', magenta: '#bc8cff', cyan: '#39c5cf', white: '#b1bac4', brightBlack: '#6e7681', brightRed: '#ff7b72', brightGreen: '#56d364', brightYellow: '#e3b341', brightBlue: '#79c0ff', brightMagenta: '#d2a8ff', brightCyan: '#56d4dd', brightWhite: '#f0f6fc' }, colors: { bg: '#0d1117', panel: '#161b22', border: '#30363d', primary: '#58a6ff', text: '#c9d1d9', muted: '#8b949e' } },
  { name: 'Kali Neon', xterm: { background: '#0a0a0a', foreground: '#00ffcc', cursor: '#ff00ff', selection: '#ff00ff40', black: '#161b22', red: '#ff5555', green: '#50fa7b', yellow: '#f1fa8c', blue: '#bd93f9', magenta: '#ff79c6', cyan: '#8be9fd', white: '#f8f8f2', brightBlack: '#6272a4', brightRed: '#ff6e6e', brightGreen: '#69ff94', brightYellow: '#ffffa5', brightBlue: '#d6acff', brightMagenta: '#ff92d0', brightCyan: '#a4ffff', brightWhite: '#ffffff' }, colors: { bg: '#0a0a0a', panel: '#1a1a2e', border: '#00ffcc', primary: '#00ffcc', text: '#e0e0e0', muted: '#888888' } },
];

const TerminalThemePicker = ({ current, onChange }) => {
  return (
    <div style={{ position: 'absolute', bottom: 40, right: 10, zIndex: 999 }}>
      <select
        value={current.name}
        onChange={(e) => {
          const selected = themes.find(t => t.name === e.target.value);
          if (selected) onChange(selected);
        }}
        style={{
          background: 'var(--theme-panel)',
          color: 'var(--theme-text)',
          border: '1px solid var(--theme-border)',
          borderRadius: 4,
          padding: '4px 8px',
          fontSize: 12,
        }}
      >
        {themes.map(t => <option key={t.name} value={t.name}>{t.name}</option>)}
      </select>
    </div>
  );
};

export default TerminalThemePicker;
