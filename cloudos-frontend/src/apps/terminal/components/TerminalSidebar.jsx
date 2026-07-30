import React from 'react';
import { History, Terminal } from 'lucide-react';

export function TerminalSidebar({ isOpen }) {
  if (!isOpen) return null;
  
  return (
    <div className="terminal-sidebar">
      <div className="sidebar-header">
        <Terminal size={20} className="text-blue-400" color="#58a6ff" />
        <span>Pro</span>
      </div>
      
      <div className="sidebar-section">
        <p className="sidebar-title">Terminal</p>
        <button className="sidebar-btn">
          <History size={16} /> History
        </button>
      </div>
    </div>
  );
}

export default TerminalSidebar;
