import React from 'react';
import { Terminal, Folder, Clock, Bookmark, Cpu, Grid, X } from 'lucide-react';

const sections = [
  { id: 'sessions', icon: <Terminal size={16} />, label: 'Sessions' },
  { id: 'projects', icon: <Folder size={16} />, label: 'Projects' },
  { id: 'jobs', icon: <Cpu size={16} />, label: 'Jobs' },
  { id: 'snippets', icon: <Bookmark size={16} />, label: 'Snippets' },
  { id: 'history', icon: <Clock size={16} />, label: 'History' },
  { id: 'environment', icon: <Grid size={16} />, label: 'Environment' },
];

const TerminalSidebar = ({ open, onClose, tabs, activeTab, onSelectTab, onAddTab }) => {
  return (
    <>
      {open && <div className="terminal-sidebar-mobile-overlay" onClick={onClose} />}
      <div className={`terminal-sidebar ${open ? 'open' : 'collapsed'}`}>
        <div style={{ padding: '8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--theme-border)' }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--theme-muted)' }}>WORKSPACE</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--theme-text)', cursor: 'pointer' }}><X size={14} /></button>
        </div>
        <div style={{ padding: 4 }}>
          {sections.map(s => (
            <div key={s.id} style={sidebarItemStyle}>
              <span style={{ marginRight: 8 }}>{s.icon}</span>
              <span>{s.label}</span>
            </div>
          ))}
        </div>
        <div style={{ borderTop: '1px solid var(--theme-border)', padding: '8px', fontSize: 12, color: 'var(--theme-muted)' }}>
          SESSIONS
          {tabs.map(tab => (
            <div
              key={tab.id}
              onClick={() => onSelectTab(tab.id)}
              style={{ padding: '4px 8px', cursor: 'pointer', borderRadius: 4, background: tab.id === activeTab ? 'var(--theme-border)' : 'transparent' }}
            >
              💻 {tab.title}
            </div>
          ))}
        </div>
      </div>
    </>
  );
};

const sidebarItemStyle = {
  display: 'flex',
  alignItems: 'center',
  padding: '6px 8px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
  color: 'var(--theme-text)',
  marginBottom: 2,
};

export default TerminalSidebar;
