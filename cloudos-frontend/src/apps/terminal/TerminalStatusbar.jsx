import React from 'react';

const TerminalStatusbar = ({ user, cwd, project, shell, encoding, jobs }) => {
  return (
    <div className="terminal-statusbar">
      <span style={{ marginRight: 12 }}>👤 {user}</span>
      <span style={{ marginRight: 12 }}>📁 {cwd}</span>
      <span style={{ marginRight: 12 }}>📦 {project}</span>
      <span style={{ marginRight: 12, color: '#3fb950' }}>● WSL Online</span>
      <span style={{ marginRight: 12 }}>{shell}</span>
      <span style={{ marginRight: 12 }}>{encoding}</span>
      <span style={{ flex: 1 }} />
      <span style={{ marginRight: 12 }}>⚙️ Jobs: {jobs}</span>
      <span>{new Date().toLocaleTimeString()}</span>
    </div>
  );
};

export default TerminalStatusbar;
