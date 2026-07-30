import React from 'react';
import { History, Bookmark, Cpu, FileText, Terminal } from 'lucide-react';

export function TerminalSidebar({ isOpen, openApp }) {
  if (!isOpen) return null;
  return (
    <div className="terminal-sidebar">
      <div className="sidebar-header">
        <Terminal size={20} className="text-blue-400" color="#58a6ff" />
        <span>Pro</span>
      </div>
      <div className="sidebar-section">
        <p className="sidebar-title">Workspace</p>
        <button className="sidebar-btn" onClick={() => openApp && openApp('files')}><FileText size={16} /> Files</button>
        <button className="sidebar-btn" onClick={() => openApp && openApp('kalihub')}><Cpu size={16} /> Tools</button>
      </div>
      <div className="sidebar-section">
        <p className="sidebar-title">Terminal</p>
        <button className="sidebar-btn"><History size={16} /> History</button>
        <button className="sidebar-btn"><Bookmark size={16} /> Snippets</button>
      </div>
    </div>
  );
}

export default TerminalSidebar;
