import React from 'react';
import { Terminal, Folder, Cpu, Bookmark, FileText, Grid } from 'lucide-react';

const quickActions = [
  { icon: <Terminal size={20} />, label: 'New Shell', onClick: 'newTab' },
  { icon: <Folder size={20} />, label: 'Open Project', onClick: 'project' },
  { icon: <Cpu size={20} />, label: 'Run Doctor', onClick: 'doctor' },
  { icon: <Bookmark size={20} />, label: 'Snippets', onClick: 'snippets' },
  { icon: <FileText size={20} />, label: 'Open Editor', onClick: 'editor' },
  { icon: <Grid size={20} />, label: 'Kali Hub', onClick: 'kalihub' },
];

const TerminalDashboard = ({ onNewTab, theme }) => (
  <div style={{
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    gap: 24,
    background: 'var(--theme-bg)',
    padding: 20,
  }}>
    <h2 style={{ color: 'var(--theme-text)', margin: 0 }}>CloudOS Terminal Pro</h2>
    <p style={{ color: 'var(--theme-muted)', margin: 0 }}>Select an action or start a new shell</p>
    <div style={{
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
      gap: 16,
      width: '100%',
      maxWidth: 500,
    }}>
      {quickActions.map((action, i) => (
        <button
          key={i}
          onClick={() => { if (action.onClick === 'newTab') onNewTab(); }}
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 8,
            padding: 16,
            background: 'var(--theme-panel)',
            border: '1px solid var(--theme-border)',
            borderRadius: 8,
            color: 'var(--theme-text)',
            cursor: 'pointer',
            transition: 'background 0.2s',
          }}
        >
          {action.icon}
          <span style={{ fontSize: 13 }}>{action.label}</span>
        </button>
      ))}
    </div>
  </div>
);

export default TerminalDashboard;
