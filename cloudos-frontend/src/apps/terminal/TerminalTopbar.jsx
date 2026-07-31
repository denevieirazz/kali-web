import React from 'react';
import { Menu, RefreshCw, Settings } from 'lucide-react';

const TerminalTopbar = ({ title, onToggleSidebar, sidebarOpen }) => (
  <div style={{
    display: 'flex',
    alignItems: 'center',
    height: 36,
    padding: '0 12px',
    background: 'var(--theme-panel)',
    borderBottom: '1px solid var(--theme-border)',
    gap: 8,
    userSelect: 'none',
  }}>
    <button onClick={onToggleSidebar} style={iconBtnStyle} title="Toggle Sidebar">
      <Menu size={16} />
    </button>
    <span style={{ fontWeight: 600, fontSize: 14 }}>{title}</span>
    <div style={{ flex: 1 }} />
    <span style={{ fontSize: 12, color: '#3fb950' }}>● WSL Online</span>
    <button style={iconBtnStyle} title="Refresh"><RefreshCw size={14} /></button>
    <button style={iconBtnStyle} title="Settings"><Settings size={14} /></button>
  </div>
);

const iconBtnStyle = {
  background: 'none',
  border: 'none',
  color: 'var(--theme-text)',
  cursor: 'pointer',
  padding: 4,
  display: 'flex',
  alignItems: 'center',
  borderRadius: 4,
};

export default TerminalTopbar;
