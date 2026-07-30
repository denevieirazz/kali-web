import React from 'react';
import { X, Plus } from 'lucide-react';

export function TerminalTabs({ tabs, activeId, onSelect, onClose, onCreate }) {
  return (
    <div className="terminal-tabs-container">
      {(tabs || []).map(tab => (
        <div 
          key={tab.id} 
          className={`terminal-tab ${activeId === tab.id ? 'active' : ''}`}
          onClick={() => onSelect(tab.id)}
        >
          <span className="dot"></span>
          <span>{tab.title}</span>
          <button className="close-btn" onClick={(e) => { e.stopPropagation(); onClose(tab.id); }}>
            <X size={12} />
          </button>
        </div>
      ))}
      <button className="terminal-tab-add" onClick={onCreate} title="Nova Aba">
        <Plus size={16} />
      </button>
    </div>
  );
}

export default TerminalTabs;
